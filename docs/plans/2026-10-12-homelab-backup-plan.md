# Homelab: encrypted off-site backups and NixOS migration (plan)

Design: `2026-10-12-homelab-backup-design.md`. Inventory: `docs/homelab.md`.
Steps marked **(user)** need Hetzner Robot, the Proxmox console, the TrueNAS UI
or 1Password; everything else can be done from the repo and over SSH.

Secrets first (opnix replaces sops-nix), then backups. Backups don't depend on
the migration: the backup host (nixos-manager) is already NixOS, and the data
stays on ZFS whichever VM uses it.

## Phase 0: answers and accounts

1. **(user)** Answer the open questions in the design (Storage Box size,
   TrueNAS Apps, NFS export of `store/shares`, VM 110, Immich/downloads,
   1Password plan, alert channel).
2. **(user)** 1Password:
   - vault **Homelab**;
   - a **service account** with read-only access to Homelab only; store its
     token as an item in your private vault (it's the bootstrap secret);
   - item `tailscale-authkey`: a new tagged, reusable Tailscale auth key (the
     one in `secrets/common.yaml` stays in git history, so it gets revoked in
     phase 1).
3. **(user)** Hetzner Robot, Storage Box:
   - enable SSH support (port 23);
   - create sub-account `-sub1` for the backup host;
   - enable automatic snapshots (for example daily, keep 7, plus weekly, keep 4);
   - main account login into 1Password (private vault, not Homelab).
4. **(user)** TrueNAS:
   - dataset `store/internal/db-dumps` (owner: the UID the dump job runs as);
   - `snapdir=visible` on `store/internal`, `store/shares`, `archive/internal`,
     `archive/shares` (Datasets → Edit → Advanced → Snapshot directory);
   - periodic snapshot tasks, recursive on `store` and on `archive`, daily at
     02:00, naming `backup-%Y-%m-%d_%H-%M`, keep 3 days. Exclude
     `store/proxmox-vms`;
   - NFS exports read-only for 10.0.10.170 on the four datasets (`store/shares`
     gets a new NFS share next to its SMB share);
   - a read-only API key → item `truenas-api` in Homelab;
   - add the `proxmox_vms_rsa` public key to `truenas_admin` so the remaining
     inventory (Apps, pool layout, scrub/SMART) can be done over SSH.
5. **(user)** VM 110: look at the container from the Proxmox console, note it
   in `docs/homelab.md`.

## Phase 1: opnix replaces sops-nix

Files: `flake.nix`, `lib/mkSystem.nix`, `lib/mkDarwin.nix`,
`modules/secrets/opnix.nix` (new), `modules/secrets/sops.nix` (removed),
`modules/networking/tailscale.nix`, `.sops.yaml` and `secrets/` (removed),
`AGENTS.md`, `README.md`.

1. **Spike: done 2026-10-13** on a throwaway VM (199, cloned from template
   9000) instead of nixos-manager, with opnix 0.11.0 (`0ea3a9e`, 2026-08-18)
   on this repo's nixpkgs. Service account `opnix-homelab` (read-only on
   Homelab; token in the Personal vault, item "opnix-homelab service
   account"). Results:

   | Test | Result |
   |---|---|
   | No token file | switch succeeds; `opnix-secrets` logs a warning, exits 0, keeps existing files |
   | Fetch | file in `/var/lib/opnix/secrets/<name>` with the configured owner/mode; `secretPaths` points at it; the consumer is restarted automatically when the value changes |
   | Value changed in 1Password | arrives on the next opnix run (switch, restart, reboot); polling is **off** by default |
   | 1Password unreachable, switch | new generation is active, but `switch-to-configuration` **exits 4** (failed unit) after ~95 s (3 attempts); old file and running consumers untouched |
   | 1Password unreachable, reboot | boots, but `multi-user.target` is **~100 s late** (opnix is a oneshot wanted by it); consumers start with the old file afterwards |
   | Recovery | first run after the network is back applies everything, including pending owner/mode changes |
   | Token removed | same as no token: exit 0, old files stay |
   | nix-darwin | atlas and apollo evaluate with the darwin module imported, `enable = false` |
   | CPU | Proxmox's default vCPU (no SSE4.1) makes the 1Password SDK's WebAssembly core run interpreted: **88 s per run instead of 4 s**. All VMs use `cpu: host`; the template now does too (`7ccedd4`) |

   Other things learned: `opnix-secrets` has `StartLimitBurst = 2` per hour,
   so a switch plus one manual restart already hits the limit; after each
   successful run the path watcher (`opnix-secrets-restart`) fetches
   everything a second time, and two concurrent runs once returned
   "internal server error"; the error text on a network failure suggests an
   invalid token, which is misleading. Secrets live on disk under
   `/var/lib/opnix`, not in `/run`, so they survive reboots.

   Verdict: usable. Step 3 below adds the settings that address the findings.
2. `flake.nix`: add `opnix`; `lib/mkSystem.nix` imports
   `inputs.opnix.nixosModules.default`, `lib/mkDarwin.nix`
   `inputs.opnix.darwinModules.default`.
3. `modules/secrets/opnix.nix` (Linux only, via `lib.optionalAttrs
   hostPlatform.isLinux`; servers only, workstations need no server secrets):
   ```nix
   services.onepassword-secrets = {
     enable = hostPlatform.isServer;
     tokenFile = "/etc/opnix-token";
     # The main run already restarts changed consumers; the path watcher
     # only adds a second fetch per run.
     systemdIntegration.changeDetection.enable = false;
     # Rotations reach servers without a switch.
     systemdIntegration.polling = { enable = true; interval = "6h"; };
   };
   systemd.services.opnix-secrets = {
     # Don't hold boot or a switch for minutes when 1Password is down;
     # consumers start with the files they have.
     serviceConfig.TimeoutStartSec = "60s";
     unitConfig.StartLimitBurst = lib.mkForce 6;
   };
   ```
   Lodestar should show an apply that ends with exit 4 and only
   `opnix-secrets` failed as "applied, secrets not refreshed" rather than a
   failed apply (note in `docs/lodestar.md` open items).
4. `modules/networking/tailscale.nix`: replace `sops.secrets.tailscale_authkey`
   with an opnix secret `reference = "op://Homelab/tailscale-authkey/credential"`
   and `authKeyFile = config.services.onepassword-secrets.secretPaths.tailscaleAuthKey`.
5. Remove sops-nix: the input, both `sops` module imports in `lib/`,
   `modules/secrets/sops.nix`, `.sops.yaml`, `secrets/`. `nix flake lock`
   drops it from `flake.lock`.
6. Docs: `AGENTS.md` (layout entry for `secrets/`, the sops gotcha becomes an
   opnix gotcha: token at `/etc/opnix-token`, vault Homelab, item names are a
   contract), `README.md` (the "Adding sops secrets" section becomes "Adding a
   server secret": create the item in Homelab, reference it in the module),
   lodestar's `deployKeyFile` description (example with opnix; in the
   lodestar repo).
7. Evaluate all five hosts, `nix flake check --no-build --keep-going`, build
   nixos-manager on itself. Commit, push to `unstable`, promote, apply via
   Lodestar. Check `tailscale status` on nixos-manager afterwards.
8. **(user)** Revoke the old Tailscale auth key (still readable in git history).

## Phase 2: backup module and the backup host

Files: `modules/backup/restic.nix`, `modules/backup/notify.nix`,
`modules/backup/backrest.nix`, `hosts/servers/nixos-manager.nix`.

1. `modules/backup/restic.nix` as in the design: options `enable`,
   `repos.<name>.{datasets,paths,sqlite,timerConfig,pruneOpts}`; per repo a
   `services.restic.backups` entry, the `storagebox` SSH alias and known host,
   NFS `fileSystems` (ro, automount), the snapshot bind-mount and SQLite dump
   in `backupPrepareCommand`, the dataset check against the TrueNAS API,
   `backupCleanupCommand` stamp, `runCheck` with `--read-data-subset=2%`,
   `OnFailure`. Secrets via opnix (`restic-<repo>`, `storagebox-backup`,
   `truenas-api`). Off by default.
2. `modules/backup/notify.nix`: `notify@.service` posting the failed unit name
   and the last journal lines to ntfy (item `ntfy`), plus the stamp-age timer.
3. Generate the Storage Box key: `ssh-keygen -t ed25519 -N "" -f
   <scratch>/storagebox-backup`. **(user)** private key into item
   `storagebox-backup` in Homelab, public key onto `-sub1`
   (`ssh-copy-id -p 23 -s uXXXX-sub1@uXXXX.your-storagebox.de`); delete the
   scratch copy. **(user)** items `restic-store` and `restic-archive` with
   generated passwords (1Password's generator, 40+ characters).
4. Host file:
   ```nix
   backup.restic = {
     enable = true;
     repos.store = {
       datasets = {
         store-internal = "10.0.10.130:/mnt/store/internal";
         store-shares = "10.0.10.130:/mnt/store/shares";
         archive-internal = "10.0.10.130:/mnt/archive/internal";
       };
       sqlite.lodestar = "/var/lib/lodestar-server/lodestar.db";
       timerConfig.OnCalendar = "*-*-* 02:30";
     };
     repos.archive = {
       datasets.archive-shares = "10.0.10.130:/mnt/archive/shares";
       timerConfig.OnCalendar = "Sun 03:00";
       pruneOpts = [ "--keep-weekly 4" "--keep-monthly 6" ];
     };
   };
   ```
5. Grow nixos-manager's disk (**(user)** `qm resize 170 virtio0 +32G`, then
   grow the partition and filesystem), and fix the server gating so Flatpak and
   interception-tools leave it; delete `/var/lib/fleet-server`.
6. Format with the repo's nixfmt, evaluate all five hosts, build on
   nixos-manager, commit, push to `unstable`, promote, apply via Lodestar.
7. `modules/backup/backrest.nix`: a systemd service for `pkgs.backrest` (no
   NixOS module exists), listening on the tailnet IP only, state in
   `/var/lib/backrest`, repo passwords from opnix. Add both repos in its UI as
   existing repositories with no plans (scheduling stays in Nix). Then point
   `backrest-browser` at it.

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

1. `store` repo first: `sudo systemctl start restic-backups-store` (the initial
   600 GiB takes hours; watch `journalctl -fu restic-backups-store`). The repo
   is created on first use (`initialize = true`).
2. Restore test: restore one Nextcloud file and the latest Nextcloud dump to
   `/tmp/restore`; `gunzip -t` the dump, compare the file's checksum with the
   live copy. Also try it from Backrest.
3. Restore from nothing: on this Mac, with only 1Password, `restic -r
   sftp:uXXXX-sub1@uXXXX.your-storagebox.de:23/restic/store snapshots`. This
   proves recovery doesn't depend on any server.
4. `archive` repo: start by hand; the initial 3.26 TiB takes days on a home
   uplink. If it's interrupted, the next run skips what's already uploaded.
5. Trigger a failure on purpose (wrong repo path) and check that the
   notification arrives; revert.
6. Write the restore runbook in `docs/homelab.md`.

## Phase 5: fixes on the current setup

Can run in parallel with phases 1–4; none of it waits for the migration.
Numbers are referenced from "What could be better" in `docs/homelab.md`.

1. **VM 101:** activate its LV on pve, mount the root read-only, look for
   anything worth keeping, then **(user)** `qm destroy 101` → 64 GB free on
   `store-lvm`.
2. **Orphaned disks and template:** for `local-lvm:vm-105-disk-{0..3}`,
   `vm-120-disk-0`, `vm-170-disk-0`: check `lvs` data usage and the partition
   table; **(user)** delete what's stale. Remove the dangling `unused0` from VM
   200 (`qm set 200 --delete unused0`). Move template 9000 to `local-lvm`
   (`qm disk move 9000 virtio0 local-lvm --delete`).
3. **nixos-manager off iSCSI:** `qm disk move 170 virtio0 local-lvm --delete`
   (online), so the backup host and fleet manager don't depend on TrueNAS for
   their own disk.
4. **Stopped services:** `qm set 201 --onboot 1`. **(user)** VM 105: shut down,
   delete after two weeks.
5. **Dead things:** delete `/opt/voice-memo` on media; remove the `bluemap`
   route from `~/traefik/dynamic/media.yml` (and `immich` and `/opt/jellyfetch`
   if they're not revived).
6. **Secrets and certificates on Main:** `chmod 600` on `~/traefik/.env`,
   `~/nextcloud/.env`, `/opt/archipelago/deploy/config.yaml` (on 201).
   **(user)** In Cloudflare, check the Traefik token is scoped to `Zone:DNS:Edit`
   on `vanwaaij.com` only; rotate it if it's broader. Switch the routers in
   `dynamic/*.yml` and the Nextcloud labels to `certResolver: cloudflare`;
   check that the wildcard cert is issued before removing the HTTP-01 resolver.
7. **Patching the Rocky VMs until they migrate:** `dnf install dnf-automatic`,
   `upgrade_type = security`, `apply_updates = yes`, enable
   `dnf-automatic.timer` on 100, 110, 120, 201. Pin image tags in the compose
   files (`traefik:v3.x`, `nextcloud:32.0.x`, `jellyfin/jellyfin:10.x`) and
   update deliberately.
8. **MariaDB 10.7 → 10.11 LTS** on Main, after the first good backup (phase 4):
   fresh dump, `image: mariadb:10.11`, `MARIADB_AUTO_UPGRADE=1`, start, check
   `occ status` and the logs. Rollback = old image + restore the dump.
9. **SSH:** pve `PermitRootLogin prohibit-password` in
   `/etc/ssh/sshd_config.d/`, test a second session before closing the first.
   Remove `waayway@wdesktop` from pve's keys if that desktop is gone.
10. **Storage access (user, TrueNAS):** NFS exports per IP —
    `store/internal` → main (rw), media (rw), nixos-manager (ro);
    `archive/shares` → media (ro), nixos-manager (ro); `archive/internal`,
    `store/shares` → nixos-manager (ro) plus whoever needs them. Review SMB
    users and share ACLs on `store/shares` and `archive/shares`; disable SMB1
    and guest access.
11. **TrueNAS off the beta (user):** save the config (phase 3.3), set the update
    train to stable, don't install further betas, upgrade to 26.0 stable when
    it ships. Going back to 25.10 is likely impossible if the pools use 26's
    feature flags (`zpool get all | grep feature@`). Also check pool layout
    (mirror/raidz), and that scrubs (monthly) and SMART tests (weekly short,
    monthly long) are scheduled.
12. **pve updates:** `apt full-upgrade` in a quiet window, reboot, check every
    VM comes back (TrueNAS first, `startup: order=1` is already set).

## Phase 6: migrate VMs to NixOS, one at a time

Order: vpn (or retire) → archipelago → media → Main. Per VM:

1. `hosts/servers/<name>.nix` (thin: identity, `netInterface` with a new
   temporary IP, enabled options) and service modules (feature modules with
   `enable`). Secrets in `secrets/<name>.yaml`.
2. Evaluate all hosts, build on nixos-manager.
3. **(user)** Clone template 9000 to a new VM on `local-lvm` (not `store-lvm`),
   first boot, **(user)** `sudo opnix token set`, switch to the config.
4. Stop the service on the old VM, move its state (databases via a fresh
   dump), start on the new one, check it.
5. Switch Traefik routes / DNS to the new VM. Old VM stays stopped two weeks,
   then **(user)** delete it.
6. Update `docs/homelab.md` and `docs/lodestar.md` (enrolment, `fleet = true`).

Per-VM specifics:

- **archipelago:** image built with `dockerTools.buildLayeredImage` from a
  pinned Archipelago source (flake input), `virtualisation.oci-containers` for
  web + multiworld, native nginx, `SECRET_KEY` from opnix (item `archipelago-secret`, rotated), ports 50000–50010/tcp,
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

## Phase 7: after the migration

1. **iSCSI gone:** once no VM disk is on `store-lvm`, **(user)** remove the
   `store-lvm` and `store-iscsi` storages from PVE, the iSCSI share and the
   `store/proxmox-vms` zvol from TrueNAS (frees its reservation on `store`).
2. **SSH keys:** new ed25519 key for server access replaces
   `proxmox_vms_rsa`; the public keys live in the repo (the users module), so
   rotating is a commit. One login user per NixOS host as today.
3. **Updates as code:** a weekly scheduled job (GitHub Actions or a timer on
   nixos-manager) runs `nix flake update` on `unstable` and opens a PR or
   commits; workstations follow `unstable`, servers get it through
   `lodestar promote` + apply. MariaDB/Postgres major upgrades stay manual
   (`services.mysql.package` pinned).
4. **Firewalls:** every service module opens only its own ports
   (`networking.firewall.allowedTCPPorts`); backends behind Traefik only accept
   Main's IP (`networking.firewall.extraInputRules` / `interfaces`). PVE
   firewall on at datacenter level with a host rule set: SSH and 8006 from
   10.0.10.0/24 and the tailnet. **(user)** enable it from the console so a
   mistake can't lock you out; VM firewalls stay off in PVE (the NixOS
   firewall does that job).
5. **Monitoring and alerts:** one ntfy topic (self-hosted on Main or ntfy.sh).
   - PVE: Datacenter → Notifications → a webhook/gotify target, matchers for
     backup, replication, updates, fencing.
   - TrueNAS: Alert Services → same channel (pool degraded, SMART, scrub errors,
     disk space).
   - restic: `notify@.service` from phase 2.
   - `services.gatus` on nixos-manager: checks the public URLs (Nextcloud,
     Jellyfin, ap, Immich) and the internal services, alerts to ntfy.
   - Later: node-exporter + Prometheus/Grafana if trends are wanted; Traefik
     already exposes metrics.
6. **Hairpin NAT:** **(user)** a local DNS override `*.vanwaaij.com` →
   10.0.10.100 on the router (or `networking.hosts` on the NixOS hosts), then
   drop the `extra_hosts` workaround from the Nextcloud config.
7. **Optional, at-rest encryption on TrueNAS:** create encrypted datasets,
   `zfs send | zfs recv` the data over, swap shares, destroy the old ones. Needs
   free space equal to the largest dataset, so do `store` first (1.27 TiB free).

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
systemctl list-timers 'restic-backups-*'
sudo restic-store snapshots
sudo restic-store stats latest
```
