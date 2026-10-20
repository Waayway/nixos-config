# Homelab inventory

What runs on the Proxmox host `pve`, surveyed 2026-10-12. Update this file when a
VM moves to NixOS or a service changes. Migration and backup plans:
`docs/plans/2026-10-12-homelab-backup-design.md` and `-plan.md`.

## State since 2026-10-19

The front-door rebuild (`docs/plans/2026-10-19-homelab-front-door-*.md`) is live: UniFi
forwards 80/443 to the **router** (since 2026-10-19, about 22:00), which serves the
internet and the tailnet; **prod** runs Nextcloud, Jellyfin and Immich. Main and media
are shut down. Details in the sections "100 prod" and "110 router" below; the
2026-10-12 survey sections for the other VMs are updated per VM when it is done.

Open items:

- **Pantry** (custom Nextcloud app 0.37.0) is disabled: its migration `32Date20260908`
  failed on Nextcloud 32.0.15 (unknown column `delete_on_done_default`).
- **Immich**: Main's old photos (`/store/immich/library`, mounted read-only in the
  container at `/mnt/old-library`) are not yet added as an external library; waiting
  for an API key from the user.
- **GPU**: the Intel Arc A380 (arrives 2026-10-20) goes to VM 100 (plan Task 4 Step
  3b, not done); the Radeon Pro WX 7100 leaves the host the same day.
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
    thin pool `local-lvm` 338 GB (69% used).
  - `sda` 500 GB = iSCSI LUN from TrueNAS (`iqn.2005-10.org.freenas.ctl:proxmox-vms`)
    → VG `nfs-vg` → storage `store-lvm` (**97% full**, 15 GB free, thick LVM,
    `saferemove 0`).
- PCI passthrough: AMD chipset SATA (02:00.1) and Marvell 88SE9215 SATA (04:00.0)
  → TrueNAS; Radeon Pro WX 7100 (mapping `WX7100`) still on media's config (media
  is off; the card leaves 2026-10-20, the Intel Arc A380 goes to prod).
- Root cron: `/root/update_cert.sh` every 12 h (Tailscale cert for the PVE web UI).
- Proxmox firewall: disabled. No vzdump/backup jobs. No notification targets.
- `/var/lib/vz/dump` has only `vzdump-qemu-nixos-template.vma.zst`.

## VMs

| ID | Name | State | OS | vCPU / RAM | Disk (storage) | Role |
|---|---|---|---|---|---|---|
| 100 | prod | running, onboot | NixOS (this repo) | 4 / 16 GB | 64 GB (local-lvm) | Nextcloud, Jellyfin, Immich (containers); Arc A380 pending |
| 101 | router | stopped | NixOS (old attempt) | 2 / 2 GB | 64 GB (store-lvm) | unused, to delete |
| 105 | deploy-box (`jenkins-vm`) | **shut down**, onboot 0 | Rocky 10.1 | 2 / 4 GB | 64 GB (store-lvm) | Jenkins, to retire |
| 108 | Main (was 100) | **shut down**, onboot 0 | Rocky 10.2 | 4 / 8 GB | 128 GB (store-lvm) | old Traefik + Nextcloud, kept for rollback |
| 110 | router | running, onboot | NixOS (this repo) | 2 / 2 GB | 16 GB (local-lvm) | front door: Traefik, split DNS, Tailscale Services |
| 118 | vpn (was 110) | running, onboot | Rocky 10.1 | 1 / 1 GB | 16 GB (local-lvm) | WireGuard (wg-easy) |
| 120 | media | **shut down**, onboot 0 | Rocky 10.1 | 4 / 8 GB + WX7100 | 128 GB (store-lvm) | old Jellyfin/Immich; `hostpci0` mapping WX7100 still set |
| 130 | truenas | running, onboot, starts first | TrueNAS 26.0.0-**BETA.2** | 4 / 16 GB + 2 SATA HBAs | 32 GB (local-lvm) | NFS + iSCSI storage |
| 170 | nixos-manager | running | NixOS (this repo) | 8 / 8 GB | 64 GB (store-lvm) | Lodestar server, Linux builder |
| 200 | minecraft | stopped | Rocky 10.1 | 4 / 12 GB | 128 GB (local-lvm) | Minecraft + BlueMap |
| 201 | archipelago | running, **not onboot** | Rocky 10.1, no guest agent | 2 / 8 GB | 64 GB (store-lvm) | Archipelago multiworld (`ap.vanwaaij.com`) |
| 230 | router-test | unverified | NixOS (this repo) | 1 / 2 GB | unverified | router's test twin, test Service `test-whoami-test` |
| 9000 | nixos-26.05-template | template | NixOS | 2 / 2 GB | 4.3 GB (store-lvm) | base image |

The Garage LXC (140) that older notes mention no longer exists; `/store/garage`
on TrueNAS is empty.

Orphaned disks (referenced as `unusedN` or not referenced at all), not yet
checked for contents: `local-lvm:vm-105-disk-{0..3}` (4 × 64 GB), `vm-120-disk-0`
(128 GB), `vm-170-disk-0` (32 GB); VM 200 `unused0` points at a storage
`local-store` that doesn't exist.

### 100 prod

- NixOS from this repo (`hosts/servers/prod.nix`), `10.0.10.100`, tailnet
  `100.121.0.124` (tags `tag:nixos`, `tag:prod`), Lodestar agent. 4 vCPU, 16 GB, 64 GB
  on `local-lvm`. Backends only; the router is the only way in from outside.
- Containers via `virtualisation.oci-containers` (modules `modules/services/{nextcloud,
  jellyfin,immich,docker,updates}.nix`):
  - **Nextcloud 32.0.15** (`nextcloud:32-apache`, track `32-apache`), MariaDB 11.4,
    Redis; **Collabora** at `office.vanwaaij.com`. Backend `http://10.0.10.100:8080`.
    User data on `/store/nextcloud/data`. Pantry is disabled (see open items).
  - **Jellyfin 10.11**: config `/store/jellyfin/config` (the original media-VM config;
    backup copy `/store/jellyfin-backup-2026-10-19`), library `/archive/jellyfin`.
  - **Immich v2** (fresh install): media `/store/immich-v2`, Postgres in a container;
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
  Services `nextcloud`, `jellyfin`, `immich`, `office`, `archipelago`, `traefik`
  (split DNS `vanwaaij.com` to the router; CoreDNS resolves names through
  `<name>.tail41ca60.ts.net`), subnet route and exit node.
- Routes come from the `homelab.routes` of every host in this flake (prod's modules
  declare `nextcloud`, `office`, `jellyfin`, `immich`) plus `homelab.router.extraRoutes`
  for backends outside it (`modules/homelab/routes.nix`: `archipelago`, `traefik`);
  unknown hosts get 404. The `tailnet` entrypoint sets
  `X-Homelab-Via: tailnet`, the `public` entrypoint strips it.
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

### 118 vpn (was 110)

- `10.0.10.118`; UniFi forwards 51820/udp here (WireGuard, wg-easy, `WG_HOST=server.vanwaaij.com`).
- 1 vCPU, 1 GB, 2.2 GB of 14 GB used. Docker with one container and a compose
  network (`br-…`). No SSH from the LAN (port 22 closed), no Tailscale.
  What it does is unknown: check from the Proxmox console.

### 120 media (shut down)

Shut down, `onboot 0`; Jellyfin and Immich now run on prod. The state below is the
last survey. The `hostpci0` mapping WX7100 is still set on the VM.

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
- Root disk 64 GB (grown from 32 GB on 2026-10-19 after a full disk during an apply), 8 vCPU; `/var/lib/flatpak` (1.3 GB) and
  `interception-tools` run on it although it's a server.

### 200 minecraft (stopped)

- Rocky 10.1, 128 GB disk on local-lvm. Serves BlueMap on :8100 when running.
  Not inspected (VM is off).

### 201 archipelago (`ap.vanwaaij.com`)

- 2 vCPU. Routed by the router (`archipelago`, basic auth).

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

Ordered roughly by risk. "Plan" refers to the phases and steps in
`docs/plans/2026-10-12-homelab-backup-plan.md`.

| # | Problem | Fix | Plan |
|---|---|---|---|
| 1 | **No backups at all**, on-site or off-site. A failed pool, a bad TrueNAS beta update or ransomware loses Nextcloud and photos. | Nightly encrypted restic backups of every ZFS dataset + DB dumps to the Storage Box; Storage Box snapshots; repo passwords in 1Password; local ZFS snapshots for fast restores; Backrest for browsing. | 0, 2–4 |
| 2 | **Production storage on TrueNAS 26.0.0-BETA.2.** | Export the config, switch the update train to stable, upgrade to 26.0 stable when it ships; no further betas. | 5.11 |
| 3 | **Circular storage dependency**: five VM disks on an iSCSI LUN served by a VM on the same host. | New NixOS VMs go on `local-lvm` (stateless, ~32 GB each); move nixos-manager's disk now; drop the iSCSI storage and zvol once the last Rocky VM is gone. | 5.3, 6, 7.1 |
| 4 | **`store-lvm` 97% full**, about 450 GB of orphaned disks on `local-lvm`. | Delete VM 101 and stale orphaned disks; move the template to `local-lvm`. | 5.1, 5.2 |
| 5 | **NFS exported to `*`** with `sec=sys`; SMB permissions unchecked. | Exports per client IP, read-only where possible; review SMB users/ACLs. | 5.10 |
| 6 | **Secrets in plain text** (`.env`, `config.yaml`). | Now: `chmod 600`, tighten the Cloudflare token to DNS-edit on `vanwaaij.com` only. Migration: everything into the 1Password Homelab vault, delivered by opnix (replaces sops-nix); rotate each secret as it moves. | 1, 5.6, 6 |
| 7 | **Manual patching**: 222 pending on pve, no automatic updates on Rocky, `:latest` images, MariaDB 10.7 EOL. | NixOS: weekly `flake.lock` bump on `unstable` → promote → Lodestar apply. Until then `dnf-automatic` (security) on the Rocky VMs and MariaDB to 10.11 LTS. pve: monthly `apt full-upgrade`, update notifications. | 5.7, 5.8, 5.12, 7.3 |
| 8 | **Firewalls inconsistent**: PVE firewall off, none on media, Jellyfin open on the LAN, Docker bypasses firewalld. | NixOS hosts already enable `networking.firewall` with SSH-only defaults; each service module opens only its own ports, backends accept only Main's IP. PVE firewall on for the host (22, 8006 from LAN + tailnet). | 6, 7.4 |
| 9 | **Dead routes and stopped services** (Immich, BlueMap, jellyfetch, voice-memo). | Decide Immich/downloads; remove dead routes and voice-memo. | 5.5 |
| 10 | **SSH**: pve root allows passwords, one shared RSA key, vpn/TrueNAS unreachable. | `PermitRootLogin prohibit-password` on pve; new ed25519 key for VMs, keys managed in the repo; TrueNAS key-only admin; vpn either NixOS or gone. | 5.9, 7.2 |
| 11 | **No monitoring or alerting.** | One ntfy channel for everything: PVE notifications, TrueNAS alerts, restic failures, Gatus uptime checks for the public URLs, disk/SMART alerts. | 7.5 |
| 12 | **HTTP-01 everywhere** although a DNS-01 wildcard resolver exists. | Routers to the `cloudflare` resolver (one wildcard cert, no port-80 dependency, tailnet-only hosts possible). | 5.6, 6 |
| 13 | **nixos-manager** runs workstation bits, has a leftover `/var/lib/fleet-server`, disk 83% full. | Gate Flatpak/interception-tools on `!isServer`, delete the leftover, grow the disk. | 2.5 |
| 14 | **Archipelago isn't `onboot`.** | `qm set 201 --onboot 1`. | 5.4 |
| 15 | **Hairpin NAT** worked around with `extra_hosts` in Nextcloud. | Split DNS: `*.vanwaaij.com` → 10.0.10.100 on the LAN resolver (router), or `networking.hosts` on the NixOS hosts. | 7.6 |
