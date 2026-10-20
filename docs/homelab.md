# Homelab inventory

What runs on the Proxmox host `pve`, surveyed 2026-10-12. Update this file when a
VM moves to NixOS or a service changes. Migration and backup plans:
`docs/plans/2026-10-12-homelab-backup-design.md` and `-plan.md`.

## State since 2026-10-19

The front-door rebuild (`docs/plans/2026-10-19-homelab-front-door-*.md`) is live: UniFi
forwards 80/443 to the **router** (since 2026-10-19, about 22:00), which serves the
internet and the tailnet; **prod** runs Nextcloud, Jellyfin and Immich. Main and media
are shut down. **identity** (VM 111, Kanidm at `id.vanwaaij.com`) is the sign-in
for the apps and the sign-in gate. Details in the sections "100 prod", "110 router"
and "111 identity" below; the
2026-10-12 survey sections for the other VMs are updated per VM when it is done.

Open items:

- **Pantry** (custom Nextcloud app): its migration broke at the cutover because two
  `occ upgrade` ran at once; repaired (backup
  `/store/db-dumps/nextcloud/pantry-before-repair-2026-10-19.sql.gz`). Pantry 0.37.0 is
  enabled again (no data lost). Rule: wait for "Initializing finished" in the container
  log before `occ` after a restart.
- **Immich**: Main's old photos (`/store/immich/library`, mounted read-only in the
  container at `/mnt/old-library`) are not yet added as an external library; waiting
  for an API key from the user.
- **GPU**: the Intel Arc A380 is passed through to prod (q35, `hostpci` mapping
  `ArcA380`; Jellyfin QSV via `encoding.xml`, Immich ML on OpenVINO). The WX 7100
  mapping is removed. See "What could be better" for the open findings (#16 to #50).
- TrueNAS NFS export `/mnt/archive/shares` (id 8) is declared in
  `modules/truenas/homelab.nix` and applied.

## Access

- VMIDs and IPs follow `docs/vmids.md` (also in the `pve` node notes): the
  IP's last octet is the VMID.
- `ssh pve` (root, tailnet `pve.tail41ca60.ts.net`, LAN 10.0.10.50).
- VMs: `ssh -J pve <user>@10.0.10.<vmid>` with `~/.ssh/proxmox_vms_rsa`
  (`~/.ssh/config` matches `10.0.10.*`). Each Rocky VM has its own login user,
  all with passwordless sudo:

  | VM | user |
  |---|---|
  | 100 prod | `prod` |
  | 108 Main (shut down, was 100) | `goedenaam` |
  | 105 deploy-box (shut down) | `jenkins` |
  | 110 router | `router` |
  | 120 media (shut down) | `media` |
  | 201 archipelago | `archipelago` |
  | 170 nixos-manager | `manager` |
  | 118 vpn (was 110) | none reachable: port 22 closed from the LAN |
  | 130 truenas | `automation` (key: 1Password Homelab/truenas-automation, passwordless sudo; use `sudo midclt call …`) |

- VM sizes (vCPU, RAM, disks) and `onboot` live on `pve` (`qm config <id>`), not in
  this repo.
- Tailscale policy edits go through the API with the 1Password Homelab item
  `tailscale-policy-authkey` (see `docs/lodestar.md`, "Tailscale policy").
- Guest-exec is disabled in the qemu agent on the Rocky VMs (`qm guest exec`
  fails); `qm guest cmd <id> get-osinfo|network-get-interfaces|get-fsinfo` work.

## Host: pve

- Proxmox VE 9.1.9, kernel 7.0.2-2-pve, up 55 days, **222 packages upgradable**.
- Ryzen 9 5900X, 78 GB RAM, RTL8125 2.5GbE (`nic0` → `vmbr0`, 10.0.10.50/24,
  gw 10.0.10.1). Tailscale on the host (offers an exit node).
- Disks:
  - NVMe 465 GB (KIOXIA): `pve` VG: root 96 GB (27% used), swap 8 GB,
    thin pool `local-lvm` 338 GB (**86% used** on 2026-10-20, alert threshold 80%).
  - `sda` 500 GB = iSCSI LUN from TrueNAS (`iqn.2005-10.org.freenas.ctl:proxmox-vms`)
    → VG `nfs-vg` → storage `store-lvm` (thick LVM, `saferemove 0`). The LUN was
    grown to **1 TiB** on 2026-10-20 (it was 97% full at 500 GB).
- PCI passthrough: AMD chipset SATA (02:00.1) and Marvell 88SE9215 SATA (04:00.0)
  → TrueNAS; Intel Arc A380 (mapping `ArcA380`) → prod. `/etc/modprobe.d/vfio-arc.conf`
  binds the Arc to vfio; it worked at the reboot after it was added, confirm on the
  next pve reboot. The WX 7100 mapping is removed (also from media's config).
- Subnet route 10.0.10.0/24: both pve and the router advertise it; after the reboot
  pve is primary (failover works).
- Root cron: `/root/update_cert.sh` every 12 h (Tailscale cert for the PVE web UI).
- Proxmox firewall: disabled. No vzdump/backup jobs. No notification targets.
- `/var/lib/vz/dump` has only `vzdump-qemu-nixos-template.vma.zst`.

## VMs

| ID | Name | State | OS | vCPU / RAM | Disk (storage) | Role |
|---|---|---|---|---|---|---|
| 100 | prod | running, onboot | NixOS (this repo), q35 | 4 / 16 GB + Arc A380 | 64 GB (local-lvm) | Nextcloud, Jellyfin, Immich (containers) |
| 101 | router | stopped | NixOS (old attempt) | 2 / 2 GB | 64 GB (store-lvm) | unused, to delete |
| 105 | deploy-box (`jenkins-vm`) | **shut down**, onboot 0 | Rocky 10.1 | 2 / 4 GB | 64 GB (store-lvm) | Jenkins, to retire |
| 108 | Main (was 100) | **shut down**, onboot 0 | Rocky 10.2 | 4 / 8 GB | 128 GB (store-lvm) | old Traefik + Nextcloud, kept for rollback |
| 110 | router | running, onboot | NixOS (this repo) | 2 / 2 GB | 16 GB (local-lvm) | front door: Traefik, split DNS, Tailscale Services |
| 111 | identity | running, onboot | NixOS (this repo) | 1 / 2 GB | 16 GB (store-lvm) | Kanidm (`id.vanwaaij.com`), sign-in for apps |
| 118 | vpn (was 110) | running, onboot | Rocky 10.1 | 1 / 1 GB | 16 GB (local-lvm) | WireGuard (wg-easy) |
| 120 | media | **shut down**, onboot 0 | Rocky 10.1 | 4 / 8 GB | 128 GB (store-lvm) | old Jellyfin/Immich (`hostpci` removed) |
| 130 | truenas | running, onboot, starts first | TrueNAS 26.0.0-**BETA.2** | 4 / 16 GB + 2 SATA HBAs | 32 GB (local-lvm) | NFS + iSCSI storage |
| 170 | nixos-manager | running, onboot (set 2026-10-20) | NixOS (this repo) | 8 / 8 GB | 64 GB (store-lvm) | Lodestar server, Linux builder |
| 200 | minecraft | stopped | Rocky 10.1 | 4 / 12 GB | 128 GB (local-lvm; move to store-lvm aborted, see below) | Minecraft + BlueMap |
| 201 | archipelago | running, onboot (set 2026-10-20) | Rocky 10.1, no guest agent | 2 / 8 GB | 64 GB (store-lvm) | Archipelago multiworld (`ap.vanwaaij.com`) |
| 230 | router-test | running, not onboot | NixOS (this repo) | 1 / 2 GB | 16 GB (store-lvm) | router's test twin, test Service `test-whoami-test` |
| 9000 | nixos-26.05-template | template | NixOS | 2 / 2 GB | 4.3 GB (store-lvm) | base image |

The Garage LXC (140) that older notes mention no longer exists; `/store/garage`
on TrueNAS is empty.

Orphaned disks (referenced as `unusedN` or not referenced at all), not yet
checked for contents or deleted: `local-lvm:vm-105-disk-0` (`unused0` on 105) and
`vm-105-disk-1..3` (unreferenced, 3 × 64 GB), `vm-120-disk-0` (`unused0` on 120,
128 GB), `vm-170-disk-0` (`unused0` on 170, 32 GB); VM 200 `unused0` points at a
storage `local-store` that doesn't exist. A partial copy `nfs-vg/vm-200-disk-0` of
Minecraft's disk is left on store-lvm (see "200 minecraft").

### 100 prod

- NixOS from this repo (`hosts/servers/prod.nix`), q35 machine with the Arc A380
  passed through (`hostpci`, mapping `ArcA380`), `10.0.10.100`, tailnet
  `100.121.0.124` (tags `tag:nixos`, `tag:prod`), Lodestar agent. 4 vCPU, 16 GB, 64 GB
  on `local-lvm` (the move to store-lvm is not done yet). Backends only; the router is
  the only way in from outside. On q35 the NIC is `enp6s18`, not `ens18`: set
  `homelab.lan.interface` per host (the default is `ens18`).
- Containers via `virtualisation.oci-containers` (modules `modules/services/{nextcloud,
  jellyfin,immich,docker,updates}.nix`):
  - **Nextcloud 32.0.15** (`nextcloud:32-apache`, track `32-apache`), MariaDB 11.4,
    Redis; **Collabora** at `office.vanwaaij.com`. Backend `http://10.0.10.100:8080`.
    User data on `/store/nextcloud/data`. Pantry is disabled (see open items).
  - **Jellyfin 10.11**: hardware transcoding (QSV) on the Arc A380, set by editing
    `encoding.xml` (backup next to it); config `/store/jellyfin/config` (the original media-VM config;
    backup copy `/store/jellyfin-backup-2026-10-19`), library `/archive/jellyfin`.
  - **Immich v2** (fresh install, ML on OpenVINO): media `/store/immich-v2`, Postgres in a container;
    Main's old library `/store/immich/library` is mounted read-only at
    `/mnt/old-library` (external library still to be added).
- Mounts (`modules/homelab/storage.nix`): `/store` = TrueNAS `/mnt/store/internal`,
  `/archive` = `/mnt/archive/shares`, NFS automounts.
- **Dumps:** nightly 01:30, `<app>-db-dump` timers write
  `/store/db-dumps/<app>/<app>-<date>.sql.gz` (apps `nextcloud` via `mariadb-dump`,
  `immich` via `pg_dumpall`; newest N kept, mode 0600). They land on ZFS, so the
  restic backups pick them up. Restore: stop the app container, then
  `zcat <dump> | docker exec -i <db-container> ...` (`nextcloud-db`: `mariadb -u root
  nextcloud` with `MYSQL_PWD` set from the container's root password; `immich-postgres`:
  `psql --username=<DB_USERNAME>`); the exact invocations are unverified, test on a
  copy first. The restic repos also hold `/store/internal` for file-level restores.
- **Updates:** the floating images (Nextcloud, Jellyfin, Immich) are pulled by a weekly
  timer, Friday 23:00; it reports to Healthchecks (1Password Homelab item
  `healthchecks-prod-updates`). **Renovate** (installed on the GitHub repo, config
  `renovate.json`, Saturdays before 06:00) opens PRs for images in
  `modules/services/*.nix`; floating tracks get a PR only when the track changes
  (minor or major, e.g. Jellyfin 10.11 to 10.12), never for patches or digests.
- Secrets from 1Password via opnix (`nextcloud-config`, `immich-config`, ...). NFS
  automounts must not have an idle timeout (see AGENTS.md, "Gotchas").

### 110 router

- NixOS from this repo (`hosts/servers/router.nix`, modules in `modules/homelab/router/`),
  `10.0.10.110`, tailnet `router` (`100.73.124.104`, tags `tag:nixos`, `tag:router`).
- The **front door** for the internet (UniFi forwards 80/443 here) and for the tailnet:
  Traefik with one `*.vanwaaij.com` wildcard certificate (Let's Encrypt DNS-01 via
  Cloudflare; token in 1Password `cloudflare-dns-token`), a maintenance page, Tailscale
  Services `nextcloud`, `jellyfin`, `immich`, `office`, `archipelago`, `traefik`, `id`,
  `auth`, `truenas`, `backrest`
  (split DNS `vanwaaij.com` to the router; CoreDNS resolves names through
  `<name>.tail41ca60.ts.net`), subnet route and exit node.
- Routes come from the `homelab.routes` of every host in this flake (prod's modules
  declare `nextcloud`, `office`, `jellyfin`, `immich`) plus `homelab.router.extraRoutes`
  for backends outside it (`modules/homelab/routes.nix`: `archipelago`, `traefik`,
  `truenas`, `backrest`);
  unknown hosts get 404. The `tailnet` entrypoint sets
  `X-Homelab-Via: tailnet`, the `public` entrypoint strips it.
- **The sign-in gate**: the router runs Docker and oauth2-proxy (`router/gate.nix`), a
  Kanidm client; routes with `auth.gate` (archipelago, backrest, traefik, truenas) ask it
  through Traefik forwardAuth. See `docs/identity.md`.
- **router-test (230, `10.0.10.230`)** is its test twin (test Service
  `test-whoami-test`), kept for tests.
- Rollback to the old setup: Main (108) is intact but shut down and its Traefik was
  detached from the Tailscale sidecar (originals as `*.pre-108` next to each file).

### 108 Main (shut down)

Shut down after the cutover (2026-10-19), `onboot 0`; the description below is the
state when it was last running. Was VMID/IP 100 until the renumbering to 108.

- Docker, compose projects in `/home/goedenaam/{traefik,nextcloud}`.
- **Traefik v3** (`traefik:v3`) sharing the network stack of a Tailscale sidecar
  (`tailscale/tailscale:latest`, tailnet name `traefik`). Publishes 80/443 on the
  LAN; dashboard on `traefik.tail41ca60.ts.net`; metrics on 127.0.0.1:8082
  (nothing scrapes them).
  - ACME: `letsencrypt` (HTTP-01) is used by every router; a `cloudflare`
    DNS-01 resolver for `*.vanwaaij.com` is defined but the routers don't use it.
  - File routes (`dynamic/`): `ap.vanwaaij.com` → 10.0.10.201:8080,
    `immich.vanwaaij.com` → 10.0.10.120:2283 (**down**), `jellyfin.vanwaaij.com`
    → 10.0.10.120:8096, `bluemap.vanwaaij.com` → 10.0.10.200:8100 (**VM stopped**).
  - Docker routes: `nextcloud.vanwaaij.com`.
- **Nextcloud 32.0.8** (`nextcloud:stable`, app + cron container), 3 users,
  apps: contacts, pantry, richdocuments + richdocumentscode (built-in Collabora).
  - MariaDB **10.7** (EOL since 2023), data `~/nextcloud/data/db` (1.7 GB, binlog on).
  - Redis 7, data `~/nextcloud/data/redis`.
  - Code/config/apps in `~/nextcloud/data/nextcloud/{html,config,custom_apps}`.
  - User data on NFS: `/store/nextcloud/data` = TrueNAS `store/internal/nextcloud` (**248 GB**).
  - Hairpin-NAT workaround: `extra_hosts` for `nextcloud.vanwaaij.com`.
- NFS mounts: `/store` (TrueNAS `/mnt/store/internal`), `/archive`
  (`/mnt/archive/internal`, empty).
- firewalld: ssh, cockpit, dhcpv6-client (Docker publishes 80/443 around it).
- Secrets in plain files: `~/traefik/.env` (Cloudflare token), `~/nextcloud/.env`
  (DB and admin passwords).

### 105 deploy-box (jenkins-vm, shut down)

Shut down, 2 vCPU, `onboot 0`.

- Jenkins LTS (jdk21) in Docker, 127.0.0.1:8080, reached through the VM's own
  Tailscale (`jenkins-vm`, Tailscale Serve on :443).
- `/home/jenkins/jenkins_home` + `go-cache` (1.6 GB total). The Docker socket and
  binary are mounted into Jenkins (root-equivalent on the VM).
- Being retired; not backed up.

### 111 identity

- NixOS from this repo (`hosts/servers/identity.nix`, modules in `modules/identity/`),
  `10.0.10.111`, tag `tag:identity`, Lodestar agent. Runs **Kanidm** at
  `id.vanwaaij.com`: passkey sign-in, OIDC for Nextcloud, Immich, Jellyfin and Proxmox, and the
  oauth2-proxy **sign-in gate** (`auth.vanwaaij.com`, shown as "Services") that the
  router puts in front of admin tools and Archipelago. Who may use which app comes from
  Nix (`modules/identity/access.nix`, `people.nix`); Kanidm group membership is
  overwritten from Nix on each provisioning run.
- Online backups go to TrueNAS `store/authentication` (NFS, this VM only, mounted
  with `RequiresMountsFor`); they are in the restic backups since 2026-10-20.
- Router entry: Tailscale Services `id` and `auth`; Kanidm is passed through without
  TLS termination. How-to (people, apps, recovery, upgrades, backup): `docs/identity.md`.

### 118 vpn (was 110)

- `10.0.10.118`; UniFi forwards 51820/udp here (WireGuard, wg-easy, `WG_HOST=server.vanwaaij.com`).
- 1 vCPU, 1 GB, 2.2 GB of 14 GB used. Docker with one container and a compose
  network (`br-…`). No SSH from the LAN (port 22 closed), no Tailscale.
  What it does is unknown: check from the Proxmox console.

### 120 media (shut down)

Shut down, `onboot 0`; Jellyfin and Immich now run on prod. The state below is the
last survey. The `hostpci` mapping to the WX 7100 has been removed.

- Docker compose projects in `/opt`:
  - **Jellyfin** (`jellyfin/jellyfin:latest`), running, :8096 open on the LAN,
    VA-API via `/dev/dri` (WX7100). Config/cache on NFS `/store/jellyfin`
    (152 MB); media on NFS `/jellyfin` = TrueNAS `/mnt/archive/shares/jellyfin`
    (**3.3 TB**, read-only mount).
  - **Immich**: compose in `/opt/immich`, **not running** (`immich.vanwaaij.com`
    route is dead). Library on NFS `/store/immich/library` (52 GB total in
    `/store/immich`), Postgres data locally `/opt/immich/immich-postgres`
    (262 MB); ML configured for ROCm.
  - **jellyfetch** (gluetun ProtonVPN WireGuard + qBittorrent), exited 7 weeks
    ago. `/opt/jellyfetch/jellyfin` holds 4.6 GB of downloads.
  - **voice-memo**: deprecated, no longer used (source and 140 KB data in
    `/opt/voice-memo`); can be deleted.
- No firewall (firewalld not enabled). Disk: root 70 GB (35%), `/home` 50 GB (2%).

### 130 truenas

- TrueNAS 26.0.0-BETA.2 (beta on the storage everything depends on). Two SATA
  controllers passed through; boot disk on `local-lvm`.
- Managed as code since 2026-10-13: `modules/truenas/` declares snapshot tasks,
  dataset properties, cron jobs and NFS shares; `truenas-reconcile` on
  nixos-manager applies them (on switch, daily 05:00; `sudo truenas-reconcile
  check` for a dry run). Pools, datasets and users stay manual.
- Pools (both healthy, last scrubs 0 errors; scrub weekly, Sunday 00:00):

  | Pool | Layout | Size / allocated |
  |---|---|---|
  | `store` | RAIDZ1, 4 × KIOXIA EXCERIA SATA SSD 960 GB (consumer) | 3.83 TB / 1.84 TB |
  | `archive` | RAIDZ1, 3 × Seagate IronWolf ST4000VN006 4 TB | 11.99 TB / 7.16 TB |

- Datasets, all **unencrypted**, compression on:

  | Dataset | Used | Shared as | Contents |
  |---|---|---|---|
  | `archive/internal` | 96 KiB | NFS | empty |
  | `archive/shares` | 3.26 TiB | SMB `archive` + NFS (`jellyfin` subfolder) | incl. `jellyfin` (3.3 TB media library) |
  | `store/authentication` | empty | NFS, 10.0.10.111 only | Kanidm's online backups (root `65534:65534 0700`, root squashed) |
  | `store/internal` | 299.6 GiB | NFS | `nextcloud` 248 GB, `immich` 52 GB, `jellyfin` config 152 MB, `garage` empty, `db-dumps/` |
  | `store/proxmox-vms` (zvol) | 74.6 GiB | iSCSI | VM disks behind `store-lvm` (not backed up) |
  | `store/shares` | 300.2 GiB | SMB `store` | SMB shares |

  The four data datasets have `snapdir=visible`. TrueNAS's hidden `.system`
  dataset lives on `archive`; there are no TrueNAS Apps.
- Snapshots: tasks on `store` (recursive, without `proxmox-vms`) and `archive`
  (recursive), daily 02:00, `backup-%Y-%m-%d_%H-%M`, kept 3 days. Read by the
  restic backups; also the quick local restore.
- SMART: TrueNAS 26 has no SMART schedules; cron jobs run `smartctl` short
  (Saturday 03:00) and long (1st of the month 04:00) on all `ata-*` disks.
- NFS exports: `/mnt/store/internal`, `/mnt/archive/internal`,
  `/mnt/archive/shares/jellyfin` to `*` (any host on the LAN), read-write,
  root squashed. Snapshots are **not** readable over NFS (`expose_snapshots`
  needs an Enterprise licence), which is why restic runs on TrueNAS itself.
- Alerts: e-mail and SNMP trap. Updates: profile EARLY_ADOPTER (that's why it's
  on a beta).
- Users: `automation` (management, full sudo), `backup-readonly` (read-only API
  key in Homelab/truenas-api).

### 170 nixos-manager

- NixOS from this repo (`hosts/servers/nixos-manager.nix`), on `stable`.
- Lodestar server + agent; state in `/var/lib/lodestar-server/lodestar.db`
  (SQLite) + `mirror.git`. Leftover `/var/lib/fleet-server` from before the
  rename (67 MB).
- Root disk 64 GB (grown from 32 GB on 2026-10-19 after a full disk during an apply), 8 vCPU, onboot 1 (set 2026-10-20); `/var/lib/flatpak` (1.3 GB) and
  `interception-tools` run on it although it's a server.

### 200 minecraft (stopped)

- Rocky 10.1, 128 GB disk on local-lvm. Serves BlueMap on :8100 when running.
  Not inspected (VM is off).
- Disk move to store-lvm **aborted** during the GPU shutdown: the config still points
  at local-lvm, and a partial copy `nfs-vg/vm-200-disk-0` remains on store-lvm
  (remove it, then retry the move).

### 201 archipelago (`ap.vanwaaij.com`)

- 2 vCPU, onboot 1 (set 2026-10-20). Routed by the router (`archipelago`, behind the
  sign-in gate), but **still reachable directly on `10.0.10.201:8080` without the
  gate** (finding #31).

- Docker compose in `/opt/archipelago/deploy`: nginx (10.0.10.201:8080) + web +
  multiworld, image `archipelago-base` built from `/opt/archipelago/src`.
- State: SQLite `/opt/archipelago/data/ap.db3` (840 KB), `custom_worlds` (empty).
  Doesn't need backing up.
- firewalld opens 50000–50010/tcp (game ports) but nothing listens there now.
- `SECRET_KEY` sits in plain text in `deploy/config.yaml`.

## Backups today

Since 2026-10-13: restic from nixos-manager to the Hetzner Storage Box
(`u592252-sub2`, 10 TB), encrypted client-side. Repos `restic/store` (daily
02:30: `store/internal`, `store/shares`, `archive/internal`, TrueNAS config
database, Lodestar DB) and `restic/archive` (Sunday 03:00: `archive/shares`).
restic runs on TrueNAS against the 02:00 ZFS snapshots; reporting to
Healthchecks (Homelab/healthchecks.io). Code: `modules/backup/`. Restore:
`sudo restic-store snapshots` / `restore` on nixos-manager.

## Dashboard

Every hosted application is on Lodestar's **Services** tab
(`http://100.92.102.84:8080/#/services`, tailnet), with an HTTP check every 60 s
from nixos-manager and the state of the machine it runs on.

- A NixOS service declares its link next to itself, inside its module's `mkIf`:
  `lodestar.links.<id> = { title; url; group; … };` (see
  `modules/backup/backrest.nix`). `host` defaults to that machine.
- Services on machines this flake doesn't manage yet are listed in
  `modules/homelab/links.nix` with an explicit `host`. When a VM moves to NixOS,
  its entry moves into the service's module.
- `check.url` probes another address than the link (Main's Traefik isn't
  reachable from the LAN, so Jellyfin and Archipelago are probed on their
  backends); `check.insecureTls` for self-signed UIs; `check.enable = false` for
  links that can't be probed (Nextcloud, for now).
- Option reference: `~/lodestar/docs/operations.md` ("Service links").

Main's ports 80/443 time out from the LAN (from `pve` and nixos-manager, by
public name and by 10.0.10.100) while they answer from outside: worth a look
when Main moves to NixOS.

## Data that needs backing up

Scope (decided 2026-10-12): **everything on the ZFS pools plus database dumps.
No VM disks, no vzdumps**: VMs are rebuilt from this repo. Not backed up:
the iSCSI zvol `store/proxmox-vms`, Archipelago (not needed), voice-memo
(deprecated), Jenkins (being retired).

| Data | Where | Size | How |
|---|---|---|---|
| `store/internal` | TrueNAS | 300 GiB | files (Nextcloud data, Immich library, Jellyfin config) |
| `store/shares` | TrueNAS | 300 GiB | files |
| `archive/shares` | TrueNAS | 3.26 TiB | files (mostly Jellyfin media) |
| `archive/internal` | TrueNAS | 96 KiB | files |
| Nextcloud DB | Main, MariaDB (VM disk, not on ZFS) | 1.7 GB on disk | dump to ZFS first |
| Immich DB (if revived) | media, Postgres (VM disk) | 262 MB | dump to ZFS first |
| Lodestar DB | nixos-manager `/var/lib/lodestar-server/lodestar.db` | 100 KB | SQLite `.backup` |
| TrueNAS config | TrueNAS | small | export to a dataset |

Total: about 3.9 TiB, of which 3.26 TiB is `archive/shares`.

## What could be better, and the fix

Ordered roughly by risk within each group. "Plan" refers to the phases and steps in
`docs/plans/2026-10-12-homelab-backup-plan.md`; rows 16 and up come from the front-door
and identity work (2026-10-19/20) and have no plan step yet. Status: open, partly
done, fixed (with date).

| # | Problem | Fix | Plan | Status |
|---|---|---|---|---|
| 1 | **No backups at all**, on-site or off-site. A failed pool, a bad TrueNAS beta update or ransomware loses Nextcloud and photos. | Nightly encrypted restic backups of every ZFS dataset + DB dumps to the Storage Box; Storage Box snapshots; repo passwords in 1Password; local ZFS snapshots for fast restores; Backrest for browsing. | 0, 2–4 | Fixed 2026-10-13 (see "Backups today") |
| 2 | **Production storage on TrueNAS 26.0.0-BETA.2.** | Export the config, switch the update train to stable, upgrade to 26.0 stable when it ships; no further betas. | 5.11 | Open |
| 3 | **Circular storage dependency**: VM disks on an iSCSI LUN served by a VM on the same host. | New NixOS VMs go on `local-lvm` (stateless, ~32 GB each); drop the iSCSI storage and zvol once the last Rocky VM is gone. Note: identity (111) and nixos-manager (170) are on store-lvm; prod's move to store-lvm and Minecraft's (partial) move go the other way, so decide one direction. | 5.3, 6, 7.1 | Open |
| 4 | **Disk space**: `local-lvm` at 86% (threshold 80%) and orphaned disks; `store-lvm` was 97% full. | store-lvm LUN grown to 1 TiB (2026-10-20). Inspect and delete the orphaned disks (105-disk-0..3, 120-disk-0, 170-disk-0), VM 101, the partial `nfs-vg/vm-200-disk-0`; move the template to `local-lvm`. | 5.1, 5.2 | Partly done: store-lvm fixed; orphans not deleted |
| 5 | **NFS exported to `*`** with `sec=sys`; SMB permissions unchecked. | Exports per client IP, read-only where possible; review SMB users/ACLs. (`store/authentication` is already limited to 10.0.10.111.) | 5.10 | Open |
| 6 | **Secrets in plain text** (`.env`, `config.yaml`). | Now: `chmod 600`, tighten the Cloudflare token to DNS-edit on `vanwaaij.com` only. Migration: everything into the 1Password Homelab vault, delivered by opnix (replaces sops-nix); rotate each secret as it moves. | 1, 5.6, 6 | Partly done: NixOS hosts use opnix; Rocky VMs open |
| 7 | **Manual patching**: 222 pending on pve, no automatic updates on Rocky, `:latest` images. | NixOS: weekly `flake.lock` bump on `unstable` → promote → Lodestar apply. Until then `dnf-automatic` (security) on the Rocky VMs. pve: monthly `apt full-upgrade`, update notifications. (MariaDB 10.7 on Main is gone with the cutover: prod runs 11.4.) | 5.7, 5.8, 5.12, 7.3 | Partly done: prod containers have a weekly pull + Renovate |
| 8 | **Firewalls inconsistent**: PVE firewall off, Docker bypasses firewalld. | NixOS hosts enable `networking.firewall` with SSH-only defaults; each service module opens only its own ports, backends accept only the router's IP (10.0.10.110). PVE firewall on for the host (22, 8006 from LAN + tailnet). Archipelago: see #31. | 6, 7.4 | Partly done |
| 9 | **Dead routes and stopped services** (BlueMap, jellyfetch, voice-memo). | Remove dead routes and voice-memo; delete Main (108), media (120). | 5.5 | Partly done: Main/media shut down, not deleted |
| 10 | **SSH**: pve root allows passwords, one shared RSA key, vpn/TrueNAS unreachable. | `PermitRootLogin prohibit-password` on pve; new ed25519 key for VMs, keys managed in the repo; TrueNAS key-only admin; vpn either NixOS or gone. | 5.9, 7.2 | Open |
| 11 | **No monitoring or alerting.** | One ntfy channel for everything: PVE notifications, TrueNAS alerts, restic failures, Gatus uptime checks for the public URLs, disk/SMART alerts (would have caught local-lvm at 86%). | 7.5 | Open (Lodestar Services tab checks HTTP only) |
| 12 | **HTTP-01 everywhere** although a DNS-01 wildcard resolver exists. | Routers to the `cloudflare` resolver. | 5.6, 6 | Fixed 2026-10-19: the router uses one DNS-01 wildcard cert |
| 13 | **nixos-manager** runs workstation bits, has a leftover `/var/lib/fleet-server`, disk was 83% full. | Gate Flatpak/interception-tools on `!isServer`, delete the leftover, grow the disk. | 2.5 | Partly done: disk grown to 64 GB; rest unverified |
| 14 | **Archipelago isn't `onboot`.** | `qm set 201 --onboot 1`. | 5.4 | Fixed 2026-10-20 (also nixos-manager 170) |
| 15 | **Hairpin NAT** worked around with `extra_hosts` in Nextcloud. | Split DNS `vanwaaij.com` to the router. | 7.6 | Fixed 2026-10-19 (split DNS on the router) |
| 16 | **Apollo**: the Lodestar apply fails with "activate failed (exit 1)" since before this work (also on 42f68c8d). The Mac is offline, so the cause is unknown. | Read the activation log when apollo is online. | - | Open |
| 17 | **deploy-box (105)** is shut down with `onboot 0`; its disks are orphaned. | Retire it with the other Rocky leftovers (final cleanup). | - | Open |
| 18 | **Minecraft (200) disk move** to store-lvm aborted during the GPU shutdown; the config is on local-lvm and a partial copy `nfs-vg/vm-200-disk-0` takes space on store-lvm. | Remove the partial copy, retry the move (or leave it on local-lvm, see #3). prod (100) is also still on local-lvm. | - | Open |
| 19 | **Arc A380 passthrough** depends on `/etc/modprobe.d/vfio-arc.conf` on pve (not in this repo). | Confirmed once after a reboot (prod has the GPU); confirm on the next pve reboot. | - | Fixed, re-check on next reboot |
| 20 | **Subnet route**: pve, not the router, is primary for 10.0.10.0/24 after the reboot (both advertise). | None needed (failover works); decide whether the router should be primary. | - | Open (cosmetic) |
| 21 | **Tailscale re-login** (new node key) leaves CoreDNS, `tailscale-serve` and `tailscaled-set` stale until a reboot; no restart on address change. | Restart these units when the Tailscale address changes. | - | Open |
| 22 | **Tailscale Services**: after creating or renaming a Service, the host needs `tailscale serve drain svc:X` + `tailscale serve advertise svc:X` before the Service IP is routed (seen for `test-whoami-test` and `auth`). | Do it in the router module or the runbook. | - | Open |
| 23 | **tailscaled-autoconnect** fails when the prefs differ after a logout ("`tailscale up` requires --reset"). | Manual `--reset`; make the unit reset by itself. | - | Open |
| 24 | **opnix trust credential** (`tag:nixos`) may assign its own tag or tags it owns, not a mix. That is why `tag:nixos` owns itself and every server tag in the policy. | Keep in mind when adding tags; document in `docs/lodestar.md`. | - | Open (documentation) |
| 25 | **Tailscale policy** has no SSH rule for `tag:identity` (health warning). | Add the rule (policy edits are via the API). | - | Open |
| 26 | **CoreDNS host zones capture subdomains** (forwarded to MagicDNS, NXDOMAIN); duplicate route hosts would break the Corefile and nothing asserts against it. | Add an assertion for duplicate hosts; handle subdomains in the zones. | - | Open |
| 27 | **Router module**: middleware order is the alphabetical key order of a route's middlewares; reserved names (`maintenance`, `auth`) can collide through `//`; the gate route is outside the name/host clash checks. | Explicit middleware ordering; include the gate route in the clash checks. | - | Open |
| 28 | **router-test (230)** serves the real routes and holds the live Cloudflare token; disk was down to 3.1 GB. | Strip the real routes and the token from the test twin; grow the disk (unverified). | - | Open |
| 29 | **Tailnet clients all look like 127.0.0.1** to backends (Tailscale Serve): Nextcloud brute-force throttling sees one IP for every tailnet client, and in Jellyfin every client looks like LAN. | Set Jellyfin "Known proxies" to 10.0.10.110; review Nextcloud trusted proxies / throttling. | - | Open |
| 30 | **`X-Homelab-Via` can be forged** by going straight to a backend. | Consumers trust it only from 10.0.10.110; firewall the backends to the router. | - | Open |
| 31 | **Archipelago (201)** is reachable directly on `10.0.10.201:8080`, bypassing the sign-in gate. | Allow only 10.0.10.110 (firewalld + DOCKER-USER on the Rocky VM; not managed by this repo). | - | Open |
| 32 | **Containers on NFS** on prod don't recover if TrueNAS is late at boot (`RequiresMountsFor` fails, no retry). | Retry the mounts / restart the containers once the mount is up. | - | Open |
| 33 | **Immich machine-learning** sometimes hangs at start (unhealthy). | Automatic restart on unhealthy. | - | Open |
| 34 | **`homelab.lan.interface`** defaults to `ens18`, wrong for q35 VMs (prod: `enp6s18`); the NixOS firewall lines for container ports are cosmetic (Docker publishes past the firewall; exposure is limited by binding to the LAN address). | Set the interface per host, or detect it (make generic). | - | Open |
| 35 | **DB dumps** on `/store/db-dumps` (and Kanidm's online backups, 0666) are readable by squashed root (uid 65534) on other NFS clients. Kanidm's backups contain hashes and OAuth2 secrets. | Dedicated dataset/share per consumer (done for `authentication`, export to 10.0.10.111 only) or encrypt; question for the user for the other dumps. | - | Partly done |
| 36 | **Weekly update**: a container without a healthcheck counts as healthy as soon as it runs; the "not running, skipped" log line is inaccurate for exited containers. | Add healthchecks; fix the log message. | - | Open |
| 37 | **Renovate**: the floating list in `renovate.json` is maintained by hand; the Immich group would put a PostgreSQL major in the same PR as an Immich major. | Sync the list with the modules; check upstream's compose before merging such a PR. | - | Open |
| 38 | **Nextcloud Pantry app**: migration broke at the cutover because two `occ upgrade` ran at once (repaired). | Rule: wait for "Initializing finished" before `occ` after a restart; never run two `occ upgrade` at once. | - | Repaired, rule documented |
| 39 | **Circles app** logs a background-job error every 5 minutes in Nextcloud (upgrade noise, harmless). | Disable the app or wait it out. | - | Open (cosmetic) |
| 40 | **Kanidm backup dataset** `store/authentication`: root `65534:65534 0700` set by hand, not declared. | Declare it in `modules/truenas/` (share id 9 is declared; give it the `[nix] authentication` comment so a reconcile doesn't duplicate it, switch the manager together). | - | Open |
| 41 | **Kanidm depends on TrueNAS at start** (backup mount `RequiresMountsFor`); login doesn't start if TrueNAS is down at boot. | Make the mount non-blocking for the IdP. | - | Open |
| 42 | **Kanidm sees the router's address** for all clients (passthrough without PROXY protocol). | Enable PROXY protocol or accept. | - | Open |
| 43 | **Gate cookie** `.vanwaaij.com` is sent to every subdomain (HttpOnly, Secure, SameSite=lax). | Accept or scope per host; also `--trusted-proxy-ip=127.0.0.1/32` was suggested for oauth2-proxy. | - | Open |
| 44 | **Removing an app from access** keeps its Kanidm group, client and scope map (`--no-auto-remove`). | Delete by hand when an app is retired. | - | Open (by design) |
| 45 | **Identity's system** includes neovim and moonlight-qt (some app modules are not gated off on servers). | Gate those app modules on `!isServer`. | - | Open |
| 46 | **Kanidm upgrades** must go one minor at a time. | Renovate PR per minor; run `kanidmd domain upgrade-check` first. | - | Open (process) |
| 47 | **Kanidm backup schedule**: the next backup after an ACME reload runs a day later (skipped day). | Re-trigger the backup after a cert reload. | - | Open |
| 48 | **Identity module code**: the `withAccess` filter is duplicated in `accessFrom.nix` and `accessProblems.nix`; policy passwords went via `docker -e` (visible in container config while running; should go via stdin); `/store/kanidm` is a hard dependency of the IdP; failure tests don't check the message; the test Kanidm gets all prod clients. | Deduplicate; pass secrets on stdin; the rest are minor. Stdin handover and the overwrite/no-revoke comment were done (3896032). | - | Open (minor) |
| 49 | **Jellyfin config** edited by hand (`encoding.xml`). | Keep the backup next to it; consider declaring it. | - | Open (minor) |
| 50 | **Kanidm look**: default icons, "Sign-in gate" name, credential page CSS, reset links using the IP. | App icons, the client shown as "Services", a centred credential card, reset links on `id.vanwaaij.com`. | - | Fixed 2026-10-20 (commits `b26199c`, `a8c4830`, `09f7869`, `d5b2c8c`) |

| 51 | **LAN devices without Tailscale** could not reach any `*.vanwaaij.com`: UniFi DNS returned the WAN IP and there is no hairpin NAT. | UniFi local DNS record `*.vanwaaij.com` to `10.0.10.110`. | - | Fixed 2026-10-20 |
| 52 | **Public wifi**: `id` and `auth` reported unreachable from public wifi; public DNS gives the WAN IP (no AAAA) and both answer over it. | Needs details from the user (device, Tailscale state, error). | - | Open |
| 53 | **Kanidm client secrets** for Immich and Jellyfin live in app state (Immich DB `system_metadata`, Jellyfin `SSO-Auth.xml`), Proxmox in `domains.cfg`, Nextcloud in its `oidc` provider; rotating a secret in Kanidm means updating each by hand. | Accept, or script the updates. | - | Open (by design) |
| 54 | **Nextcloud `allow_local_remote_servers`** is on (SSRF guard off instance-wide) so it can reach Kanidm; a member named like a local account (such as `admin`) would link to it. | Egress filter; an assertion against such names. | - | Open |
| 55 | **Proxmox users** are created by hand (`pveum user add <name>@kanidm` + acl); there is no group sync. `root@pam` stays the emergency login. | Accept for one admin. | - | Open (by design) |
| 56 | **Kanidm restore** is documented but not rehearsed. | Rehearse once on router-test's Kanidm. | - | Open |
| 57 | **Kanidm CLI in the secret script** runs with `verify_ca=false`. | Checked: `KANIDM_URL` is the VM's own LAN address with the tools container on the host network, so it never leaves the VM. | - | Closed |
| 58 | **Immich OAuth** settings were written to the database directly; **Arie** needs an Immich account (`arie@vanwaaij.com`) before SSO links. | Create it in Immich. | - | Open (user) |
| 59 | **2 GB VMs run out of memory building themselves**: Lodestar applies on router and identity were OOM-killed (2026-10-20). | Build on nixos-manager and switch with `--target-host` (as done), or let the agent use the manager as a remote builder. | - | Open |
| 60 | **`lodestar promote` fails** with "Host key verification failed" (no deploy key yet, lodestar.md open item 1). | Promote by pushing the same commit to `stable` until the deploy key exists. | - | Open |

## Open plan items

- Identity plan: done (Tasks 8 to 10); docs in `docs/identity.md`.
- Lodestar plan (`lodestar.vanwaaij.com`, OIDC, actions only from the tailnet): not
  started.
- Final cleanup: delete Main (108), media (120), deploy-box (105), VM 101, the orphaned
  disks and the partial `nfs-vg/vm-200-disk-0`.
- WireGuard (vpn 118): move to a shared Tailscale exit node later (the other users
  still use WireGuard).
