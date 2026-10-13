# Homelab: encrypted off-site backups and NixOS migration (design)

Current state: `docs/homelab.md` (inventory of 2026-10-12). This design extends
the "Migration of the homelab" section of
`2026-10-12-fleet-manager-design.md` with backups, secrets and the per-service
target, and corrects its table (the Garage LXC is gone).

## Goal

1. All data on the TrueNAS ZFS pools (`archive`, `store`) plus the application
   databases is backed up nightly to the Hetzner Storage Box, encrypted on the
   client, so Hetzner (or anyone with the box's credentials) only sees ciphertext.
2. VMs aren't backed up. Every service runs on a NixOS host defined in this repo,
   so a VM is rebuilt from the repo; only the data on ZFS matters.
3. Every secret lives in 1Password. Hosts fetch what they need at activation;
   nothing secret is in git, not even encrypted.
4. Backups are verified, and a failed or missing backup is noticed.

## Scope

| In | Out |
|---|---|
| `store/internal` (300 GiB: Nextcloud, Immich, Jellyfin config) | `store/proxmox-vms` zvol (VM disks) |
| `store/shares` (300 GiB, SMB) | vzdumps of any VM |
| `archive/shares` (3.26 TiB, mostly Jellyfin media) | Archipelago (not needed) |
| `archive/internal` (empty today) | voice-memo (deprecated) |
| database dumps: Nextcloud MariaDB, Immich Postgres (if revived), Lodestar SQLite | Jenkins (retired) |
| TrueNAS config export | |

Total about 3.9 TiB. New datasets on either pool are caught by a check
(see "Which datasets").

## Decisions

1. **Secrets: opnix, replacing sops-nix everywhere.**
   - `github:brizzbuzz/opnix`, module `services.onepassword-secrets`. Nix refers
     to secrets as `op://Homelab/<item>/<field>`; at activation (and on its own
     systemd service) opnix fetches them with a **1Password service account**
     and writes files with the owner and mode we set. It can restart the
     consuming services when a secret changes.
   - A vault **Homelab** holds every server secret. A service account with
     **read-only** access to that vault only is the one bootstrap secret per
     host, placed by hand at `/etc/opnix-token` (`sudo opnix token set`), never
     in git or the Nix store.
   - sops-nix today holds a single used secret (`tailscale_authkey`, servers
     only); workstations use none. Moving that one and removing sops-nix (input,
     module, `.sops.yaml`, `secrets/`) means one secret system instead of two,
     and no more age keys per host.
   - Recovery needs only the 1Password account: no laptop age key, no host
     key. If pve burns down, a fresh NixOS VM + a token + this repo restores
     everything.
   - Trade-off: a changed secret needs 1Password.com reachable. Already written
     files stay in place, and opnix runs as a systemd service that doesn't block
     boot. Verified in the spike (plan phase 1).
2. **Backup tool: restic** via the NixOS module `services.restic.backups`.
   - Encryption is always on: AES-256-CTR with a Poly1305-AES MAC, keys derived
     from the repository password with scrypt. The password (in 1Password) is
     all you need to restore; there's no separate key file to export.
   - Repository format v2 with `--compression auto` (zstd, skips already
     compressed media).
   - SFTP to the Storage Box (port 23). The initial upload is bound by the home
     uplink anyway (3.9 TiB at 50 Mbit/s ≈ a week); after that only changes go up.
   - The module gives `restic-<name>` wrappers (`createWrapper`), `runCheck`,
     `pruneOpts`, prepare/cleanup hooks and persistent timers.
   - **Backrest** (in nixpkgs, 1.10.x) on nixos-manager as a UI for browsing and
     restoring, with `backrest-browser` in front of it. Scheduling stays in the
     NixOS module so it's code; Backrest only reads the repos.
   - Borg was the alternative: server-side `borg serve` on the Storage Box, but
     no Backrest, one repo per host and a version pin on the server.
3. **Driven from one host, restic runs on TrueNAS (revised 2026-10-13).**
   The first idea was nixos-manager reading the pools over NFS. TrueNAS 26
   doesn't serve `.zfs/snapshot` over NFS without an Enterprise licence
   (`expose_snapshots`), so instead nixos-manager starts restic **on TrueNAS**
   over SSH: a static restic pinned by `flake.lock` (`pkgsStatic.restic`),
   copied there when its hash changes. The repo password goes over stdin and the
   Storage Box key through the forwarded SSH agent, so no secret is stored on
   TrueNAS. Data flows straight from TrueNAS's disks to the Storage Box.
   Everything (schedule, retention, restic version, secret references) stays in
   this repo; TrueNAS only provides `bash`, `ssh`, `unshare` and `sqlite3`.
4. **Back up from snapshots, not live files.** A TrueNAS periodic snapshot task
   takes a recursive `backup-%Y-%m-%d_%H-%M` snapshot of both pools at 02:00.
   The remote script bind-mounts the newest one of each dataset at
   `/run/restic-view/<dataset>` in a private mount namespace: consistent at one
   moment, and the same paths every run, so restic skips unchanged files. A
   snapshot older than 26 h fails the run.
4a. **TrueNAS as code.** Its snapshot tasks, dataset properties, cron jobs and
   NFS shares are declared in `modules/truenas/` and applied by
   `truenas-reconcile` (`midclt` over SSH as the TrueNAS user `automation`;
   on switch and daily). Resources it owns carry a `[nix] <name>` marker; only
   those are ever deleted. nixos-manager is effectively root on TrueNAS, as it
   already is on every host it deploys.
5. **Databases are dumped onto ZFS before the snapshot.** The dumps travel with
   the rest of the data, and the backup host never needs database access:
   - Nextcloud (Main): `mariadb-dump --single-transaction` at 01:30 to
     `store/internal/db-dumps/nextcloud/`. Today a root cron on the Rocky VM;
     after migration `services.mysqlBackup` with `location` on that NFS path.
   - Immich (media), if revived: `services.postgresqlBackup` the same way.
   - Lodestar runs on the backup host itself: `sqlite3 .backup` in
     `backupPrepareCommand`, straight into the snapshot.
   The 30 minutes between the Nextcloud dump and the snapshot is acceptable:
   files newer than the DB get picked up by `occ files:scan` after a restore.
6. **Two repositories, matching how the data changes:**

   | Repo | Datasets | Schedule | Retention |
   |---|---|---|---|
   | `store` | `store/internal`, `store/shares`, `archive/internal`, Lodestar DB, TrueNAS config | daily 02:30 | 7 daily, 4 weekly, 12 monthly |
   | `archive` | `archive/shares` | weekly, Sunday 03:00 | 4 weekly, 6 monthly |

   The large, slow-changing media share doesn't hold up the nightly run, and
   its multi-day initial upload doesn't block the important data. Each repo has
   its own password item in 1Password.
7. **One Storage Box sub-account (`u592252-sub2`, 10 TB box)**, key-only SSH,
   both repos under `restic/`. The key (Homelab/storagebox-backup) is the only
   one in its `authorized_keys`. The main Storage Box account stays in 1Password.
8. **Ransomware/mistake protection: Storage Box snapshots.** The backup host's
   key can delete its repos. Automatic Storage Box snapshots (set in Hetzner
   Robot, outside any server's reach) keep older states of the whole box.
   restic's append-only mode needs rest-server, which the Storage Box doesn't
   run.
9. **The Proxmox host and TrueNAS stay non-NixOS.** TrueNAS's settings come
   from Nix (decision 4a); its install, pools, datasets and the `automation`
   user are manual, like the opnix token on servers.

## Architecture

```
 ┌───────────────────────────── pve ─────────────────────────────────┐
 │  main ──01:30 mariadb-dump──► truenas store/internal/db-dumps/…    │
 │                                                                    │
 │  truenas   02:00 recursive snapshots store@backup-…, archive@backup-… │
 │     ▲                                                              │
 │     │ SSH as automation: copy pinned restic if needed, then        │
 │     │ `sudo restic backup` of /run/restic-view/<dataset>           │
 │     │ (snapshot bind mounts, private namespace); password on stdin,│
 │     │ Storage Box key via agent forwarding                         │
 │  nixos-manager  02:30 restic-store.service (Sun 03:00 restic-archive)│
 │     opnix ◄── 1Password Homelab   truenas-reconcile (on switch, daily)│
 │     local part: Lodestar DB; forget/prune and check from here      │
 └──────────────────────┬─────────────────────────────┬───────────────┘
                        │ SFTP over SSH :23           │ HTTPS
                        ▼                             ▼
      Hetzner Storage Box u592252-sub2:          healthchecks.io
      restic/store, restic/archive               (/start, /<exit code>)
```

### Secrets: `modules/secrets/opnix.nix`

Replaces `modules/secrets/sops.nix`. Always imported; on when a host has a token:

```nix
services.onepassword-secrets = {
  enable = true;
  tokenFile = "/etc/opnix-token";
};
```

Modules declare the secrets they need next to their use, for example the
Tailscale module:

```nix
services.onepassword-secrets.secrets.tailscaleAuthKey = {
  reference = "op://Homelab/tailscale-authkey/credential";
  services = [ "tailscaled" ];
};
services.tailscale.authKeyFile =
  config.services.onepassword-secrets.secretPaths.tailscaleAuthKey;
```

Items in the Homelab vault (names are the contract with the repo):

| Item | Used by |
|---|---|
| `tailscale-authkey` | servers' unattended Tailscale login |
| `restic-store`, `restic-archive` | repository passwords |
| `storagebox-backup` | SSH private key + host/user for sub-account `-sub1` |
| `truenas-api` | read-only API key for the dataset check |
| `ntfy` | alert topic/token |
| later: `cloudflare-dns`, `nextcloud-db`, `archipelago-secret`, `lodestar-deploy-key`, … | migrated services |

Workstations keep no opnix token; they need no server secrets. Darwin hosts
import the module with `enable = false`.

### Modules

- `modules/truenas/truenas.nix`: options `truenas.{enable, host, user, hostKey,
  snapshotTasks, datasets, cronJobs, nfsShares}` and the `truenas-reconcile`
  service; `reconcile.sh` does the work (`apply` / `check`).
  `modules/truenas/homelab.nix` holds this homelab's TrueNAS state.
- `modules/backup/restic.nix`: options `backup.restic.{enable, storageBox,
  healthchecksReference, repos.<name>.{truenas, local.{paths,sqlite},
  snapshotPrefix, maxSnapshotAgeHours, timerConfig, pruneOpts, checkOpts,
  healthchecks}}`; per repo `restic-<name>.service` + timer and a
  `restic-<name>` command for manual use. `restic-truenas.sh` is the part sent
  to TrueNAS. `modules/backup/homelab.nix` declares the two repos.
- Secrets via opnix: `truenasAutomationKey`, `storageBoxKey`, `resticStore`,
  `resticArchive`, `healthchecksUrl`.

Not covered by the snapshot path and declared as live paths instead: TrueNAS's
config database (`/data/freenas-v1.db`, copied with `sqlite3 .backup`) and
`/data/pwenc_secret`.

### Encryption summary

| Where | How |
|---|---|
| Off-site data | restic: AES-256-CTR + Poly1305-AES, scrypt-derived key, client side |
| In transit to the box | SFTP over SSH (port 23), key-only sub-account |
| Restic passwords, SSH key, API keys, app secrets | 1Password vault Homelab → opnix → root-only files at runtime |
| Recovery | the 1Password account (repo passwords + Storage Box login) |
| On-site data (TrueNAS) | unencrypted today. ZFS native encryption needs new datasets and a copy (`zfs send` into an encrypted dataset); optional, later |
| LAN (NFS) | plaintext; to be limited per client IP (plan phase 5); backups don't use NFS |

### Monitoring

Healthchecks.io, one check (Homelab/healthchecks.io). The daily `store` run
pings `/start` and then `/<exit code>` with the last 60 kB of its log
(`ExecStopPost`); `archive` only pings on failure. Missing or failed runs alert
through the integrations configured there. A failed ping never fails a backup.

### Restore

Runbook in `docs/homelab.md`:

```sh
sudo restic-store snapshots
sudo restic-store restore latest --target /tmp/restore --include /run/backup/store/store-internal/nextcloud
# Nextcloud DB
gunzip -c /tmp/restore/…/db-dumps/nextcloud/nextcloud-<date>.sql.gz | mysql nextcloud
```

Or browse and download single files in Backrest / backrest-browser.

From nothing (pve gone): any machine with restic, the Storage Box login and the
repo password from 1Password can `restic -r sftp:… restore`.

Restore drill once per quarter: one dataset into a scratch directory, compare
with the live data; the Nextcloud dump into a scratch MariaDB.

## Target per VM (NixOS migration)

Independent of backups: the backup works the same before and after a VM moves,
because the data stays on ZFS. Only the Nextcloud dump job changes owner.
Every migrated service gets its secrets from the Homelab vault through opnix.

| VM | Becomes | Services, NixOS-native where possible | Notes |
|---|---|---|---|
| 170 nixos-manager | stays NixOS, + backup host | Lodestar, restic, Backrest | drop Flatpak/interception-tools (server gating), clean `/var/lib/fleet-server`, grow disk (restic cache needs a few GB) |
| 110 vpn | NixOS or retire | unknown: look first | 1 container; maybe replaced by Tailscale entirely |
| 201 archipelago | NixOS `archipelago` | `virtualisation.oci-containers`, image built by Nix (`dockerTools`) from a pinned Archipelago source, native nginx | no backup needed; `onboot` |
| 120 media | NixOS `media` | `services.jellyfin` (VA-API, amdgpu), `services.immich` if revived (ML on CPU: ROCm doesn't support Polaris/WX7100), downloads via `oci-containers` (gluetun + qBittorrent) or VPN-Confinement | GPU passthrough stays |
| 100 Main | NixOS `main` | `services.traefik` (routes in Nix, Cloudflare DNS-01), `services.nextcloud` (current MariaDB via `services.mysql`, Redis via `configureRedis`, `datadir` on NFS), `services.collabora-online` instead of richdocumentscode, host Tailscale instead of the sidecar | largest; last |
| 200 minecraft | NixOS when needed | `nix-minecraft` flake or `services.minecraft-server`, BlueMap | world data on ZFS when revived, then it's in the backup |
| 105 deploy-box | **retire** | | |
| 101 router | **delete** | | frees 64 GB on `store-lvm` |
| 130 truenas | stays TrueNAS | | off the beta train; NFS exports per IP |

Data that today lives on a VM disk (Nextcloud's DB, Immich's Postgres, Traefik's
ACME state) is either dumped to ZFS (databases) or recreated (ACME certs). New
NixOS hosts keep no unique state outside ZFS.

## Open questions

Resolved 2026-10-13: Storage Box is 10 TB; no TrueNAS Apps exist; `store/shares`
needs no NFS export (restic reads it on TrueNAS); 1Password service accounts
work; alerts go to Healthchecks.io.

1. **VM 110 (vpn):** what does the container do? Needs the Proxmox console.
2. **Immich and the download stack:** revive them on the new `media` host, or drop?
