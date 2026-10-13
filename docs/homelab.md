# Homelab inventory

What runs on the Proxmox host `pve`, surveyed 2026-10-12. Update this file when a
VM moves to NixOS or a service changes. Migration and backup plans:
`docs/plans/2026-10-12-homelab-backup-design.md` and `-plan.md`.

## Access

- `ssh pve` (root, tailnet `pve.tail41ca60.ts.net`, LAN 10.0.10.50).
- VMs: `ssh -J pve <user>@10.0.10.<vmid>` with `~/.ssh/proxmox_vms_rsa`
  (`~/.ssh/config` matches `10.0.10.*`). Each Rocky VM has its own login user,
  all with passwordless sudo:

  | VM | user |
  |---|---|
  | 100 Main | `goedenaam` |
  | 105 deploy-box | `jenkins` |
  | 120 media | `media` |
  | 201 archipelago | `archipelago` |
  | 170 nixos-manager | `manager` |
  | 110 vpn | none reachable: port 22 closed from the LAN |
  | 130 truenas | the key isn't accepted for any user. Use the web UI (https://10.0.10.130) |

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
  → TrueNAS; Radeon Pro WX 7100 (mapping `WX7100`) → media.
- Root cron: `/root/update_cert.sh` every 12 h (Tailscale cert for the PVE web UI).
- Proxmox firewall: disabled. No vzdump/backup jobs. No notification targets.
- `/var/lib/vz/dump` has only `vzdump-qemu-nixos-template.vma.zst`.

## VMs

| ID | Name | State | OS | vCPU / RAM | Disk (storage) | Role |
|---|---|---|---|---|---|---|
| 100 | Main | running, onboot | Rocky 10.2 | 4 / 8 GB | 128 GB (store-lvm) | Traefik ingress + Nextcloud, tag `production` |
| 101 | router | stopped | NixOS (old attempt) | 2 / 2 GB | 64 GB (store-lvm) | unused, to delete |
| 105 | deploy-box (`jenkins-vm`) | running, onboot | Rocky 10.1 | 4 / 4 GB | 64 GB (store-lvm) | Jenkins, to retire |
| 110 | vpn | running, onboot | Rocky 10.1 | 1 / 1 GB | 16 GB (local-lvm) | unknown, one Docker container |
| 120 | media | running, onboot | Rocky 10.1 | 4 / 8 GB + WX7100 | 128 GB (store-lvm) | Jellyfin (Immich, downloads stopped) |
| 130 | truenas | running, onboot, starts first | TrueNAS 26.0.0-**BETA.2** | 4 / 16 GB + 2 SATA HBAs | 32 GB (local-lvm) | NFS + iSCSI storage |
| 170 | nixos-manager | running | NixOS (this repo) | 4 / 8 GB | 32 GB (store-lvm) | Lodestar server, Linux builder |
| 200 | minecraft | stopped | Rocky 10.1 | 4 / 12 GB | 128 GB (local-lvm) | Minecraft + BlueMap |
| 201 | archipelago | running, **not onboot** | Rocky 10.1, no guest agent | 4 / 8 GB | 64 GB (store-lvm) | Archipelago multiworld (`ap.vanwaaij.com`) |
| 9000 | nixos-26.05-template | template | NixOS | 2 / 2 GB | 4.3 GB (store-lvm) | base image |

The Garage LXC (140) that older notes mention no longer exists; `/store/garage`
on TrueNAS is empty.

Orphaned disks (referenced as `unusedN` or not referenced at all), not yet
checked for contents: `local-lvm:vm-105-disk-{0..3}` (4 × 64 GB), `vm-120-disk-0`
(128 GB), `vm-170-disk-0` (32 GB); VM 200 `unused0` points at a storage
`local-store` that doesn't exist.

### 100 Main

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
  - Hairpin-NAT workaround: `extra_hosts nextcloud.vanwaaij.com:10.0.10.100`.
- NFS mounts: `/store` (TrueNAS `/mnt/store/internal`), `/archive`
  (`/mnt/archive/internal`, empty).
- firewalld: ssh, cockpit, dhcpv6-client (Docker publishes 80/443 around it).
- Secrets in plain files: `~/traefik/.env` (Cloudflare token), `~/nextcloud/.env`
  (DB and admin passwords).

### 105 deploy-box (jenkins-vm)

- Jenkins LTS (jdk21) in Docker, 127.0.0.1:8080, reached through the VM's own
  Tailscale (`jenkins-vm`, Tailscale Serve on :443).
- `/home/jenkins/jenkins_home` + `go-cache` (1.6 GB total). The Docker socket and
  binary are mounted into Jenkins (root-equivalent on the VM).
- Being retired; not backed up.

### 110 vpn

- 1 vCPU, 1 GB, 2.2 GB of 14 GB used. Docker with one container and a compose
  network (`br-…`). No SSH from the LAN (port 22 closed), no Tailscale.
  What it does is unknown: check from the Proxmox console.

### 120 media

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
- Pools and datasets (TrueNAS UI, 2026-10-12), all **unencrypted**:

  | Dataset | Used | Shared as | Contents |
  |---|---|---|---|
  | `archive` (pool) | 3.26 TiB, 2.07 TiB free | (pool also hosts TrueNAS Apps) | |
  | `archive/internal` | 96 KiB | NFS | empty |
  | `archive/shares` | 3.26 TiB | SMB + NFS | incl. `jellyfin` (3.3 TB media library) |
  | `store` (pool) | 1.26 TiB, 1.27 TiB free | | |
  | `store/internal` | 299.6 GiB | NFS | `nextcloud` 248 GB, `immich` 52 GB, `jellyfin` config 152 MB, `garage` empty |
  | `store/proxmox-vms` (zvol) | 74.6 GiB | iSCSI | VM disks behind `store-lvm` (not backed up) |
  | `store/shares` | 300.2 GiB | SMB | SMB shares (contents not inspected) |

  The children of `store` add up to about 675 GiB of the 1.26 TiB used; the rest
  is probably the zvol's reservation (500 GB volsize) or snapshots.
- NFS exports `/mnt/store/internal`, `/mnt/archive/internal`,
  `/mnt/archive/shares/jellyfin` to `*` (any host on the LAN), `sec=sys`.
- Not yet inventoried (no shell access): which TrueNAS Apps run on `archive`,
  snapshot and replication tasks, pool layout (mirror/raidz), SMART/scrub
  schedules, config backup.

### 170 nixos-manager

- NixOS from this repo (`hosts/servers/nixos-manager.nix`), on `stable`.
- Lodestar server + agent; state in `/var/lib/lodestar-server/lodestar.db`
  (SQLite) + `mirror.git`. Leftover `/var/lib/fleet-server` from before the
  rename (67 MB).
- Root disk 32 GB, 83% used; `/var/lib/flatpak` (1.3 GB) and
  `interception-tools` run on it although it's a server.

### 200 minecraft (stopped)

- Rocky 10.1, 128 GB disk on local-lvm. Serves BlueMap on :8100 when running.
  Not inspected (VM is off).

### 201 archipelago (`ap.vanwaaij.com`)

- Docker compose in `/opt/archipelago/deploy`: nginx (10.0.10.201:8080) + web +
  multiworld, image `archipelago-base` built from `/opt/archipelago/src`.
- State: SQLite `/opt/archipelago/data/ap.db3` (840 KB), `custom_worlds` (empty).
  Doesn't need backing up.
- firewalld opens 50000–50010/tcp (game ports) but nothing listens there now.
- `SECRET_KEY` sits in plain text in `deploy/config.yaml`.

## Backups today

None. No vzdump jobs, no backup tools on any VM, no off-site copy. Whether
TrueNAS takes ZFS snapshots is unknown. The Hetzner Storage Box isn't
connected yet.

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
| 1 | **No backups at all**, on-site or off-site. A failed pool, a bad TrueNAS beta update or ransomware loses Nextcloud and photos. | Nightly encrypted borg backups of every ZFS dataset + DB dumps to the Storage Box; Storage Box snapshots; keys in 1Password; local ZFS snapshots for fast restores. | 0–4 |
| 2 | **Production storage on TrueNAS 26.0.0-BETA.2.** | Export the config, switch the update train to stable, upgrade to 26.0 stable when it ships; no further betas. | 5.11 |
| 3 | **Circular storage dependency**: five VM disks on an iSCSI LUN served by a VM on the same host. | New NixOS VMs go on `local-lvm` (stateless, ~32 GB each); move nixos-manager's disk now; drop the iSCSI storage and zvol once the last Rocky VM is gone. | 5.3, 6, 7.1 |
| 4 | **`store-lvm` 97% full**, about 450 GB of orphaned disks on `local-lvm`. | Delete VM 101 and stale orphaned disks; move the template to `local-lvm`. | 5.1, 5.2 |
| 5 | **NFS exported to `*`** with `sec=sys`; SMB permissions unchecked. | Exports per client IP, read-only where possible; review SMB users/ACLs. | 5.10 |
| 6 | **Secrets in plain text** (`.env`, `config.yaml`). | Now: `chmod 600`, tighten the Cloudflare token to DNS-edit on `vanwaaij.com` only. Migration: everything into sops, rotate each secret as it moves. | 5.6, 6 |
| 7 | **Manual patching**: 222 pending on pve, no automatic updates on Rocky, `:latest` images, MariaDB 10.7 EOL. | NixOS: weekly `flake.lock` bump on `unstable` → promote → Lodestar apply. Until then `dnf-automatic` (security) on the Rocky VMs and MariaDB to 10.11 LTS. pve: monthly `apt full-upgrade`, update notifications. | 5.7, 5.8, 5.12, 7.3 |
| 8 | **Firewalls inconsistent**: PVE firewall off, none on media, Jellyfin open on the LAN, Docker bypasses firewalld. | NixOS hosts already enable `networking.firewall` with SSH-only defaults; each service module opens only its own ports, backends accept only Main's IP. PVE firewall on for the host (22, 8006 from LAN + tailnet). | 6, 7.4 |
| 9 | **Dead routes and stopped services** (Immich, BlueMap, jellyfetch, voice-memo). | Decide Immich/downloads; remove dead routes and voice-memo. | 5.5 |
| 10 | **SSH**: pve root allows passwords, one shared RSA key, vpn/TrueNAS unreachable. | `PermitRootLogin prohibit-password` on pve; new ed25519 key for VMs, keys managed in the repo; TrueNAS key-only admin; vpn either NixOS or gone. | 5.9, 7.2 |
| 11 | **No monitoring or alerting.** | One ntfy channel for everything: PVE notifications, TrueNAS alerts, borg failures, Gatus uptime checks for the public URLs, disk/SMART alerts. | 7.5 |
| 12 | **HTTP-01 everywhere** although a DNS-01 wildcard resolver exists. | Routers to the `cloudflare` resolver (one wildcard cert, no port-80 dependency, tailnet-only hosts possible). | 5.6, 6 |
| 13 | **nixos-manager** runs workstation bits, has a leftover `/var/lib/fleet-server`, disk 83% full. | Gate Flatpak/interception-tools on `!isServer`, delete the leftover, grow the disk. | 2.5 |
| 14 | **Archipelago isn't `onboot`.** | `qm set 201 --onboot 1`. | 5.4 |
| 15 | **Hairpin NAT** worked around with `extra_hosts` in Nextcloud. | Split DNS: `*.vanwaaij.com` → 10.0.10.100 on the LAN resolver (router), or `networking.hosts` on the NixOS hosts. | 7.6 |
