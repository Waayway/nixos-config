# Homelab: encrypted off-site backups and NixOS migration (design)

Current state: `docs/homelab.md` (inventory of 2026-10-12). This design extends
the "Migration of the homelab" section of
`2026-10-12-fleet-manager-design.md` with backups and the per-service target,
and corrects its table (the Garage LXC is gone).

## Goal

1. All data on the TrueNAS ZFS pools (`archive`, `store`) plus the application
   databases is backed up nightly to the Hetzner Storage Box, encrypted on the
   client, so Hetzner (or anyone with the box's credentials) only sees ciphertext.
2. VMs aren't backed up. Every service runs on a NixOS host defined in this repo,
   so a VM is rebuilt from the repo; only the data on ZFS matters.
3. Backups are verified, and a failed or missing backup is noticed.

## Scope

| In | Out |
|---|---|
| `store/internal` (300 GiB: Nextcloud, Immich, Jellyfin config) | `store/proxmox-vms` zvol (VM disks) |
| `store/shares` (300 GiB, SMB) | vzdumps of any VM |
| `archive/shares` (3.26 TiB, mostly Jellyfin media) | Archipelago (not needed) |
| `archive/internal` (empty today) | voice-memo (deprecated) |
| database dumps: Nextcloud MariaDB, Immich Postgres (if revived), Lodestar SQLite | Jenkins (retired) |
| TrueNAS config export | |

Total about 3.9 TiB. New datasets on either pool are picked up automatically
(see "Which datasets").

## Decisions

1. **Tool: BorgBackup** via the NixOS module `services.borgbackup.jobs`.
   - The Storage Box runs `borg serve` itself (SSH port 23), so deduplication
     and compression happen without pulling chunks back over the WAN. For
     3.9 TiB on a home uplink that matters more than restic's niceties.
   - Encryption `repokey-blake2` (AES-256 + BLAKE2b authentication), protected
     by a passphrase from sops.
   - Compression `auto,zstd` (skips already compressed media).
   - restic over SFTP was the alternative: equally good encryption, but slower
     against a Storage Box for multi-TB data and no server-side process.
2. **One backup host, reading the pools over NFS from ZFS snapshots.** TrueNAS
   stays an appliance: it takes the snapshots, a NixOS host does the backup.
   The backup host is **nixos-manager**: it's already NixOS, and as the fleet
   controller it can already change every host, so giving it read access to
   the data adds little risk. Can move to its own VM later without changing the
   module.
3. **Back up from snapshots, not live files.** A TrueNAS periodic snapshot task
   takes a recursive `backup-%Y-%m-%d` snapshot of both pools at 02:00. The
   datasets get `snapdir=visible`, so the backup host sees
   `<mount>/.zfs/snapshot/backup-<today>/`. Each dataset is consistent at one
   moment, and the backup can't be disturbed by writes during the run.
4. **Databases are dumped onto ZFS before the snapshot.** The dumps then travel
   with the rest of the data, and the backup host never needs access to the
   databases:
   - Nextcloud (Main): `mariadb-dump --single-transaction` at 01:30 to
     `store/internal/db-dumps/nextcloud/`. Today a root cron on the Rocky VM;
     after migration `services.mysqlBackup` with `location` on that NFS path.
   - Immich (media), if revived: `services.postgresqlBackup` the same way.
   - Lodestar runs on the backup host itself: `sqlite3 .backup` in the borg
     `preHook`, straight into the archive.
   The 30 minutes between the Nextcloud dump and the snapshot is acceptable:
   files newer than the DB get picked up by `occ files:scan` after a restore.
5. **Two repositories, matching how the data changes:**

   | Repo | Datasets | Schedule | Retention |
   |---|---|---|---|
   | `store` | `store/internal`, `store/shares`, `archive/internal`, Lodestar DB, TrueNAS config | daily 02:30 | 7 daily, 4 weekly, 12 monthly |
   | `archive` | `archive/shares` | weekly, Sunday 03:00 | 4 weekly, 6 monthly |

   The large, slow-changing media share doesn't slow down the nightly run, and
   a long initial upload of 3.26 TiB doesn't block the important data.
6. **One Storage Box sub-account for the backup host**, key-only SSH, both repos
   under it. The main account's credentials stay in 1Password and are never on
   a server.
7. **Ransomware/mistake protection: Storage Box snapshots.** The backup host's
   key can `borg delete` its repos. Automatic Storage Box snapshots (set in
   Hetzner Robot, outside any server's reach) keep older states of the whole
   box. Borg's `--append-only` would be better but needs control over the
   server's `authorized_keys` command, which the Storage Box doesn't offer.
8. **Secrets: sops-nix.** `secrets/nixos-manager.yaml` holds the borg passphrase
   and the Storage Box SSH key, encrypted to the host's age key **and** the
   workstation user keys. Host age keys come from host SSH keys, which die with
   the VM; without a workstation key, a lost pve means unreadable backups.
9. **Key escrow.** After creating each repo, `borg key export --paper` and the
   passphrase go into 1Password. That's the recovery path if both the servers
   and the laptops are gone.
10. **The Proxmox host and TrueNAS stay non-NixOS**, configured by hand once
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
 │  nixos-manager ◄────────────┘                                      │
 │    02:30 bind-mount newest .zfs/snapshot/backup-* → /run/backup/…  │
 │          borg create (encrypted, zstd) → repo "store"              │
 │    Sun 03:00 same for archive/shares → repo "archive"              │
 └──────────────────────────────┬─────────────────────────────────────┘
                                │ SSH :23, key-only
                                ▼
              Hetzner Storage Box  uXXXX-sub1/{store,archive}
              (+ automatic box snapshots, managed in Robot)
```

### Which datasets

The backup host mounts each dataset read-only (`fileSystems` with
`fsType = "nfs"`, `options = [ "ro" "noauto" "x-systemd.automount" ]`). The
list of datasets lives in the host file, so a new dataset is one line plus an
NFS export on TrueNAS. A check in the `preHook` lists the pools' datasets
over the TrueNAS API (read-only API key in sops) and fails loudly when one isn't
in the list. That way "everything on the pools" stays true without silently
missing a new share.

### NixOS module: `modules/backup/borg.nix`

Feature module per `docs/modules.md`:

```nix
options.backup.borg = {
  enable = lib.mkEnableOption "encrypted borg backups to the Storage Box";
  repoBase = lib.mkOption { type = lib.types.str; };   # ssh://uXXXX-sub1@uXXXX.your-storagebox.de:23/./
  repos = lib.mkOption {
    type = lib.types.attrsOf (lib.types.submodule {
      options = {
        datasets = …;   # name → NFS source (host:/mnt/pool/dataset)
        paths = …;      # extra local paths
        sqlite = …;     # name → db path, dumped in preHook
        startAt = …;
        keep = …;       # prune settings
      };
    });
  };
};
```

Per repo the module:

- declares `services.borgbackup.jobs.<repo>` with
  `encryption.mode = "repokey-blake2"`,
  `encryption.passCommand = "cat ${config.sops.secrets.borg-passphrase.path}"`,
  `environment.BORG_RSH = "ssh -p 23 -i ${storagebox key}"`,
  `extraArgs = "--remote-path=borg-1.4"` (pins the server version),
  `compression = "auto,zstd"`, `persistentTimer = true`;
- `preHook`: for each dataset, find the newest `backup-*` snapshot under the NFS
  mount and bind-mount it to `/run/backup/<repo>/<dataset>` (constant paths
  keep borg's files cache effective), fail if it's older than 26 hours; dump
  the SQLite databases; check the dataset list against the TrueNAS API;
- `postHook`: unmount the bind mounts, write `/var/lib/backup/<repo>.last-success`;
- prune per `keep`, then `borg compact`;
- adds a weekly `borg check --repository-only` and a monthly
  `borg check --verify-data` limited with `--max-duration`;
- `OnFailure=` on all backup units → `notify@.service`.

### Encryption summary

| Where | How |
|---|---|
| Off-site data | borg `repokey-blake2`: AES-256-CTR + BLAKE2b MAC, client side |
| In transit to the box | SSH (port 23), key-only sub-account |
| Borg passphrase, SSH key, TrueNAS API key | sops-nix (age), host key + workstation keys |
| Recovery | paper key export + passphrase in 1Password |
| On-site data (TrueNAS) | unencrypted today. ZFS native encryption needs new datasets and a copy (`zfs send` into an encrypted dataset); optional, later |
| LAN (NFS) | plaintext; exports limited per client IP, backup exports read-only |
| App secrets (Cloudflare, DB passwords) | moved from `.env` files into sops during migration |

### Monitoring

A `notify@.service` template triggered by `OnFailure=` posts the unit name and
the last journal lines to the alert channel. A daily timer fails (and so
notifies) when a `last-success` stamp is older than 36 h (`store`) or 8 days
(`archive`). Later: show the backup age in the Lodestar dashboard.

### Restore

Runbook in `docs/homelab.md`:

```sh
sudo borg-job-store list
sudo borg-job-store extract ::store-2026-… run/backup/store/internal/nextcloud
# Nextcloud DB
gunzip -c …/db-dumps/nextcloud/nextcloud.sql.gz | mysql nextcloud
```

Restore drill once per quarter: one dataset into a scratch directory, compare
with the live data; the Nextcloud dump into a scratch MariaDB.

## Target per VM (NixOS migration)

Independent of backups: the backup works the same before and after a VM moves,
because the data stays on ZFS. Only the Nextcloud dump job changes owner.

| VM | Becomes | Services, NixOS-native where possible | Notes |
|---|---|---|---|
| 170 nixos-manager | stays NixOS, + backup host | Lodestar, borg | drop Flatpak/interception-tools (server gating), clean `/var/lib/fleet-server`, grow disk (borg cache needs a few GB) |
| 110 vpn | NixOS or retire | unknown: look first | 1 container; maybe replaced by Tailscale entirely |
| 201 archipelago | NixOS `archipelago` | `virtualisation.oci-containers`, image built by Nix (`dockerTools`) from a pinned Archipelago source, native nginx | no backup needed; `onboot` |
| 120 media | NixOS `media` | `services.jellyfin` (VA-API, amdgpu), `services.immich` if revived (ML on CPU: ROCm doesn't support Polaris/WX7100), downloads via `oci-containers` (gluetun + qBittorrent) or VPN-Confinement | GPU passthrough stays |
| 100 Main | NixOS `main` | `services.traefik` (routes in Nix, Cloudflare DNS-01 from sops), `services.nextcloud` (current MariaDB via `services.mysql`, Redis via `configureRedis`, `datadir` on NFS), `services.collabora-online` instead of richdocumentscode, host Tailscale instead of the sidecar | largest; last |
| 200 minecraft | NixOS when needed | `nix-minecraft` flake or `services.minecraft-server`, BlueMap | world data: move onto ZFS when it's revived, then it's in the backup |
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
6. **Alert channel:** ntfy (self-hosted or ntfy.sh) or email?
