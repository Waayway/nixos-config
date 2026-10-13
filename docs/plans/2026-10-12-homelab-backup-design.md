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
3. **One backup host, reading the pools over NFS from ZFS snapshots.** TrueNAS
   stays an appliance: it takes the snapshots, a NixOS host does the backup.
   The backup host is **nixos-manager**: it's already NixOS, and as the fleet
   controller it can already change every host, so giving it read access to
   the data adds little risk. Can move to its own VM later without changing the
   module.
4. **Back up from snapshots, not live files.** A TrueNAS periodic snapshot task
   takes a recursive `backup-%Y-%m-%d_%H-%M` snapshot of both pools at 02:00.
   The datasets get `snapdir=visible`, so the backup host sees
   `<mount>/.zfs/snapshot/backup-…/`. Each dataset is consistent at one moment,
   and writes during the run don't matter.
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
7. **One Storage Box sub-account for the backup host**, key-only SSH, both repos
   under it. The SSH key comes from 1Password through opnix. The main Storage
   Box account stays in 1Password and is never on a server.
8. **Ransomware/mistake protection: Storage Box snapshots.** The backup host's
   key can delete its repos. Automatic Storage Box snapshots (set in Hetzner
   Robot, outside any server's reach) keep older states of the whole box.
   restic's append-only mode needs rest-server, which the Storage Box doesn't
   run.
9. **The Proxmox host and TrueNAS stay non-NixOS**, configured by hand once
   (snapshot task, `snapdir`, NFS exports, config export).

## Architecture

```
 ┌───────────────────────────── pve ─────────────────────────────────┐
 │                                                                    │
 │  main ──01:30 mariadb-dump──┐        media ──(postgres dump)──┐    │
 │                             ▼                                 ▼    │
 │  truenas  store/internal/db-dumps/…                                │
 │    02:00 recursive snapshot  store@backup-…, archive@backup-…      │
 │    NFS (ro, only to 10.0.10.170): store/internal, store/shares,    │
 │                                   archive/internal, archive/shares │
 │                             │                                      │
 │  nixos-manager ◄────────────┘        opnix ◄── 1Password "Homelab" │
 │    02:30 bind-mount newest .zfs/snapshot/backup-* → /run/backup/…  │
 │          restic backup (encrypted, zstd) → repo "store"            │
 │    Sun 03:00 same for archive/shares → repo "archive"              │
 │    Backrest (tailnet only, read/restore) ← backrest-browser        │
 └──────────────────────────────┬─────────────────────────────────────┘
                                │ SFTP over SSH :23, key-only
                                ▼
              Hetzner Storage Box  uXXXX-sub1: restic/store, restic/archive
              (+ automatic box snapshots, managed in Robot)
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

### Which datasets

The backup host mounts each dataset read-only (`fileSystems` with
`fsType = "nfs"`, `options = [ "ro" "noauto" "x-systemd.automount" ]`). The
list lives in the host file, so a new dataset is one line plus an NFS export on
TrueNAS. A check in `backupPrepareCommand` lists the pools' datasets over the
TrueNAS API and fails loudly when one isn't in the list (except
`store/proxmox-vms`). That keeps "everything on the pools" true without
silently missing a new share.

### NixOS module: `modules/backup/restic.nix`

Feature module per `docs/modules.md`:

```nix
options.backup.restic = {
  enable = lib.mkEnableOption "encrypted restic backups to the Storage Box";
  repos = lib.mkOption {
    type = lib.types.attrsOf (lib.types.submodule {
      options = {
        datasets = …;      # name → NFS source (host:/mnt/pool/dataset)
        paths = …;         # extra local paths
        sqlite = …;        # name → db path, dumped before the run
        timerConfig = …;   # OnCalendar etc.
        pruneOpts = …;
      };
    });
  };
};
```

Per repo the module:

- declares `services.restic.backups.<repo>` with
  `repository = "sftp:storagebox:restic/<repo>"`,
  `passwordFile = secretPaths.restic-<repo>`, `initialize = true`,
  `createWrapper = true`, `extraBackupArgs = [ "--compression" "auto"
  "--exclude-caches" ]`, `timerConfig` with `Persistent = true` and a
  randomized delay;
- an SSH alias `storagebox` for root (`programs.ssh.extraConfig`: host,
  port 23, sub-account user, `IdentityFile` = the opnix path) and the box's
  host key in `programs.ssh.knownHosts`;
- `backupPrepareCommand`: for each dataset, find the newest `backup-*` snapshot
  under the NFS mount and bind-mount it to `/run/backup/<repo>/<dataset>`
  (constant paths let restic find the parent snapshot and skip unchanged
  files), fail if it's older than 26 hours; dump the SQLite databases; run the
  dataset check;
- `backupCleanupCommand`: unmount the bind mounts, write
  `/var/lib/backup/<repo>.last-success` when the run succeeded;
- `pruneOpts` per repo, `runCheck = true` with `checkOpts = [
  "--read-data-subset=2%" ]` (a different 2% each run covers the whole repo
  over time);
- `OnFailure=` on the backup units → `notify@.service`.

If restic re-reads every file each night (inode numbers on snapshot mounts can
differ), add `--ignore-inode` to `extraBackupArgs`; dedup means nothing is
uploaded twice either way, it only costs read time.

### Encryption summary

| Where | How |
|---|---|
| Off-site data | restic: AES-256-CTR + Poly1305-AES, scrypt-derived key, client side |
| In transit to the box | SFTP over SSH (port 23), key-only sub-account |
| Restic passwords, SSH key, API keys, app secrets | 1Password vault Homelab → opnix → root-only files at runtime |
| Recovery | the 1Password account (repo passwords + Storage Box login) |
| On-site data (TrueNAS) | unencrypted today. ZFS native encryption needs new datasets and a copy (`zfs send` into an encrypted dataset); optional, later |
| LAN (NFS) | plaintext; exports limited per client IP, backup exports read-only |

### Monitoring

A `notify@.service` template triggered by `OnFailure=` posts the unit name and
the last journal lines to ntfy. A daily timer fails (and so notifies) when a
`last-success` stamp is older than 36 h (`store`) or 8 days (`archive`).
Backrest shows snapshot history; later the Lodestar dashboard can show the
backup age per repo.

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

1. **Storage Box size.** 3.9 TiB now: BX21 (5 TB) is tight once versions and box
   snapshots accumulate; BX31 (10 TB) leaves room.
2. **TrueNAS Apps** on `archive` (the pool has the Apps icon): which apps run,
   and does their state (the hidden `ix-apps` dataset) need a backup?
3. **`store/shares`** is SMB-only: fine to add a read-only NFS export to
   10.0.10.170 for the backup?
4. **VM 110 (vpn):** what does the container do? Needs the Proxmox console.
5. **Immich and the download stack:** revive them on the new `media` host, or drop?
6. **1Password plan:** service accounts must be available on it.
7. **Alert channel:** ntfy (self-hosted or ntfy.sh) or email? The design assumes ntfy.
