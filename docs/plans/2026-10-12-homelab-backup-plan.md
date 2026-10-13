# Homelab: encrypted off-site backups and NixOS migration (plan)

Design: `2026-10-12-homelab-backup-design.md`. Inventory: `docs/homelab.md`.
Steps marked **(user)** need Hetzner Robot, the Proxmox console, the TrueNAS UI
or 1Password; everything else can be done from the repo and over SSH.

Backups come first and don't depend on the migration: the backup host
(nixos-manager) is already NixOS, and the data stays on ZFS whichever VM uses it.

## Phase 0: answers and accounts

1. **(user)** Answer the open questions in the design (Storage Box size,
   TrueNAS Apps, NFS export of `store/shares`, VM 110, Immich/downloads, alert
   channel).
2. **(user)** Hetzner Robot, Storage Box:
   - enable SSH support (port 23);
   - create sub-account `-sub1` for the backup host;
   - enable automatic snapshots (for example daily, keep 7, plus weekly, keep 4).
3. **(user)** TrueNAS:
   - dataset `store/internal/db-dumps` (owner: the UID the dump job runs as);
   - `snapdir=visible` on `store/internal`, `store/shares`, `archive/internal`,
     `archive/shares` (Datasets → Edit → Advanced → Snapshot directory);
   - periodic snapshot tasks, recursive on `store` and on `archive`, daily at
     02:00, naming `backup-%Y-%m-%d_%H-%M`, keep 3 days. Exclude
     `store/proxmox-vms`;
   - NFS exports read-only for 10.0.10.170 on the four datasets (`store/shares`
     gets a new NFS share next to its SMB share);
   - a read-only API key for the dataset-list check;
   - add the `proxmox_vms_rsa` public key to `truenas_admin` so the remaining
     inventory (Apps, pool layout, scrub/SMART) can be done over SSH.
4. **(user)** VM 110: look at the container from the Proxmox console, note it
   in `docs/homelab.md`.

## Phase 1: backup module

Files: `modules/backup/borg.nix`, `modules/backup/notify.nix`.

1. `modules/backup/borg.nix` as in the design: options `enable`, `repoBase`,
   `repos.<name>.{datasets,paths,sqlite,startAt,keep}`; per repo a
   `services.borgbackup.jobs` entry, NFS `fileSystems` (ro, automount), the
   snapshot bind-mount `preHook`, the dataset check against the TrueNAS API,
   `postHook` stamp, prune/compact, weekly and monthly `borg check` units,
   `OnFailure`. Off by default.
2. `modules/backup/notify.nix`: `notify@.service` posting to the alert channel
   (token from sops), plus the stamp-age timer.
3. Format with the repo's nixfmt; evaluate all five hosts (the module is
   imported everywhere and must stay inert when disabled).

## Phase 2: enable on nixos-manager

Files: `hosts/servers/nixos-manager.nix`, `secrets/nixos-manager.yaml`,
`.sops.yaml`.

1. Generate the Storage Box key: `ssh-keygen -t ed25519 -N "" -f
   <scratch>/storagebox-backup`. **(user)** add the public key to `-sub1`
   (`ssh-copy-id -p 23 -s uXXXX-sub1@uXXXX.your-storagebox.de`).
2. `.sops.yaml`: rule for `secrets/nixos-manager.yaml` with nixos-manager's age
   key (`ssh-keyscan -t ed25519 10.0.10.170 | ssh-to-age`) plus the workstation
   keys. Check that this Mac can decrypt the file.
3. `secrets/nixos-manager.yaml`: `borg-passphrase` (`openssl rand -base64 48`),
   `storagebox-ssh-key`, `truenas-api-key`, notify token.
4. Host file:
   ```nix
   backup.borg = {
     enable = true;
     repoBase = "ssh://uXXXX-sub1@uXXXX.your-storagebox.de:23/./";
     repos.store = {
       datasets = {
         store-internal = "10.0.10.130:/mnt/store/internal";
         store-shares = "10.0.10.130:/mnt/store/shares";
         archive-internal = "10.0.10.130:/mnt/archive/internal";
       };
       sqlite.lodestar = "/var/lib/lodestar-server/lodestar.db";
       startAt = "*-*-* 02:30";
     };
     repos.archive = {
       datasets.archive-shares = "10.0.10.130:/mnt/archive/shares";
       startAt = "Sun 03:00";
       keep = { weekly = 4; monthly = 6; };
     };
   };
   ```
5. Grow nixos-manager's disk (**(user)** `qm resize 170 virtio0 +32G`, then
   grow the partition and filesystem), and fix the server gating so Flatpak and
   interception-tools leave it.
6. Evaluate all hosts, build on nixos-manager (scratch clone, see `AGENTS.md`),
   commit, push to `unstable`, promote to `stable`, apply via Lodestar.

## Phase 3: database dumps on the Rocky VMs (until they migrate)

1. Main: root cron at 01:30:
   `docker exec nextcloud-db sh -c 'mariadb-dump --single-transaction -u root
   -p"$MARIADB_ROOT_PASSWORD" nextcloud' | gzip >
   /store/db-dumps/nextcloud/nextcloud-$(date +%F).sql.gz`, plus deleting dumps
   older than 3 days. Temporary: replaced by `services.mysqlBackup` when Main
   moves to NixOS.
2. media: only if Immich is revived before media migrates (same, `pg_dumpall`).
3. **(user)** TrueNAS: schedule the config export into
   `store/internal/db-dumps/truenas-config/` (cron task calling the
   `config.save` API, or monthly by hand).

## Phase 4: first runs and restore test

1. `store` repo first: `sudo systemctl start borgbackup-job-store` (the
   initial 600 GiB takes hours; watch `journalctl -fu borgbackup-job-store`).
   `borg init` happens on first use.
2. `borg key export --paper` for the repo → **(user)** 1Password together with
   the passphrase.
3. Restore test: extract one Nextcloud file and the latest Nextcloud dump into
   `/tmp`; `gunzip -t` the dump, compare the file's checksum with the live copy.
4. `archive` repo: start by hand; the initial 3.26 TiB takes days on a home
   uplink. borg resumes from its last checkpoint if interrupted
   (`--checkpoint-interval`, default 30 min).
5. Trigger a failure on purpose (wrong repo path) and check that the
   notification arrives; revert.
6. Write the restore runbook in `docs/homelab.md`.

## Phase 5: cleanup and hardening

1. VM 101: check its disk read-only for anything worth keeping, then **(user)**
   delete it → 64 GB free on `store-lvm`.
2. Orphaned disks: list contents of `local-lvm:vm-105-disk-{0..3}`,
   `vm-120-disk-0`, `vm-170-disk-0`; **(user)** delete what's stale; remove the
   dangling `unused0` from VM 200.
3. VM 105 (Jenkins): **(user)** shut down, delete after two weeks.
4. media: delete `/opt/voice-memo` (deprecated).
5. Traefik: remove the dead `bluemap` route (and `immich` if not revived).
6. NFS exports per IP: `store/internal` → main, media, nixos-manager (ro);
   `archive/shares` → media (ro), nixos-manager (ro); `archive/internal` and
   `store/shares` → nixos-manager (ro) and whoever needs them.
7. pve: `apt full-upgrade` in a quiet window; `PermitRootLogin prohibit-password`.
8. **(user)** TrueNAS: move from 26.0.0-BETA.2 to the 26 stable release when it
   ships. Going back to 25.10 is likely impossible if the pools use 26's
   feature flags (`zpool get all | grep feature@`).

## Phase 6: migrate VMs to NixOS, one at a time

Order: vpn (or retire) → archipelago → media → Main. Per VM:

1. `hosts/servers/<name>.nix` (thin: identity, `netInterface` with a new
   temporary IP, enabled options) and service modules (feature modules with
   `enable`). Secrets in `secrets/<name>.yaml`.
2. Evaluate all hosts, build on nixos-manager.
3. **(user)** Clone template 9000 to a new VM on `local-lvm` (not `store-lvm`),
   first boot, add its age key to `.sops.yaml`, switch to the config.
4. Stop the service on the old VM, move its state (databases via a fresh
   dump), start on the new one, check it.
5. Switch Traefik routes / DNS to the new VM. Old VM stays stopped two weeks,
   then **(user)** delete it.
6. Update `docs/homelab.md` and `docs/lodestar.md` (enrolment, `fleet = true`).

Per-VM specifics:

- **archipelago:** image built with `dockerTools.buildLayeredImage` from a
  pinned Archipelago source (flake input), `virtualisation.oci-containers` for
  web + multiworld, native nginx, `SECRET_KEY` from sops, ports 50000–50010/tcp,
  `onboot`. No backup.
- **media:** `services.jellyfin` with `hardware.graphics` + `amdgpu`, config
  stays on `/store/jellyfin`, library read-only from `archive/shares`. Immich if
  revived: `services.immich` with `services.postgresqlBackup` writing to
  `/store/db-dumps/immich`.
- **Main (last):** Traefik native with all routes in Nix and DNS-01 via
  Cloudflare; `services.nextcloud` on the same major version (32),
  `datadir = "/store/nextcloud/data"`; MariaDB current LTS, restored from the
  10.7 dump; `services.mysqlBackup` to `/store/db-dumps/nextcloud` at 01:30
  (replaces the cron from phase 3); `services.collabora-online`. Rehearse on
  the temporary IP with a restored DB before the cut-over.

Once no VM disk is left on `store-lvm`: remove the iSCSI storage from PVE and
the `store/proxmox-vms` zvol from TrueNAS, which also frees its reservation
on `store`.

## Verification (every phase that touches Nix)

```sh
nix eval .#nixosConfigurations.hermes.config.system.build.toplevel.drvPath
nix eval .#nixosConfigurations.hephaestus.config.system.build.toplevel.drvPath
nix eval .#nixosConfigurations.nixos-manager.config.system.build.toplevel.drvPath
nix eval .#darwinConfigurations.atlas.system.drvPath
nix eval .#darwinConfigurations.apollo.system.drvPath
nix flake check --no-build --keep-going
```

On nixos-manager:

```sh
systemctl list-timers 'borgbackup-*'
sudo borg-job-store list
sudo borg-job-store info --last 1
```
