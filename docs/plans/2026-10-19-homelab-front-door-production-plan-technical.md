# Homelab front door: production VM 100 — technical plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

Plain-language version (what happens, who does what): `2026-10-19-homelab-front-door-production-plan.md`.

**Goal:** NixOS VM 100 (`prod`, `10.0.10.100`) runs Nextcloud 32 (+ MariaDB, Redis,
Collabora), Jellyfin and Immich from their official Docker images on data mounted from
TrueNAS at `/store` and `/archive`; verified over the tailnet on copies of the databases;
then one cutover moves the databases, the GPU and the public port forward (to the router).

**Architecture:** NixOS provides the VM (Docker engine, TrueNAS mounts, Tailscale,
firewall, timers). Each app is a feature module under `modules/services/` that declares
its containers with `virtualisation.oci-containers` (translated from upstream's compose
file), its `homelab.routes` entry (route name = Tailscale Service name), its
`lodestar.links` entry and its nightly DB dump, with a per-app `live` switch
(`live = false` → the router's public router serves the maintenance page). A weekly
timer pulls floating tags; Renovate proposes pinned/major updates as pull requests. The
router's CoreDNS resolves `<name>.vanwaaij.com` through the Service's MagicDNS name, so
routes carry no IPs.

**Tech Stack:** NixOS 26.05, `virtualisation.oci-containers` (backend `docker`),
images `nextcloud:32-apache`, `mariadb:11.4`, `redis:7-alpine`, `collabora/code`,
`jellyfin/jellyfin:10.11`, Immich `v2` (server, machine-learning, valkey, its pinned
PostgreSQL); NFS; Traefik 3.7 + CoreDNS on the router; Renovate (GitHub app);
Healthchecks.io; Tailscale API; Proxmox `qm`.

**Spec:** `docs/plans/2026-10-19-homelab-front-door-design.md` (section C, revised
2026-10-19: Docker). The router plan's Task 9 (cutover via Main) is replaced by Task 8
here.

**Depends on:** router plan Tasks 1–8 (router 110 live on the tailnet, split DNS →
router).

## Global Constraints

- VM 100: `10.0.10.100`, hostname `prod`, 6 cores, 16 GB, 64 GB root on `local-lvm`,
  `tags = [ "tag:prod" ]` (already in the Tailscale policy).
- Old Main: IP `10.0.10.108` (user), VMID 100 → 108 (Claude); disk `store-lvm:vm-100-disk-0`.
- Mounts: `/store` ← `10.0.10.130:/mnt/store/internal`, `/archive` ←
  `10.0.10.130:/mnt/archive/shares` (done in Task 1). Every container using them gets
  `RequiresMountsFor` on its systemd unit.
- Container paths as in today's setups: Nextcloud data `/store/nextcloud/data` →
  `/var/www/html/data`; Jellyfin `<configDir>` → `/config`, cache → `/cache`,
  `/archive/jellyfin` → `/media` (ro); Immich upload location `/store/immich-v2`, old
  photos `/store/immich/library` → read-only external library.
- Databases on VM 100's disk under `/var/lib/prod/<app>/db`; nightly dumps to
  `/store/db-dumps/<app>` (01:30).
- Versions: floating minor tracks for apps (`nextcloud:32-apache`,
  `jellyfin/jellyfin:10.11`, Immich `v2`); pinned for `mariadb:11.4`, Immich's PostgreSQL
  (exact upstream tag+digest), `redis:7-alpine`, `valkey`, `collabora/code`.
- Weekly update: Friday 23:00 (`OnCalendar=Fri 23:00`), pull + restart changed
  containers, ping `op://Homelab/healthchecks-prod-updates/credential` (`/start`, success,
  `/fail` with the log tail).
- Hostnames/route names: `nextcloud`, `office` (Collabora), `jellyfin`, `immich` on
  `*.vanwaaij.com`.
- Secrets never printed; never in the repo (1Password Homelab via opnix).
- Repo rules (AGENTS.md): modules always imported, gated; RFC nixfmt; own paths; author
  thijs@vanwaaij.com; no AI trailer; no push without the user.

## Review Focus

1. Two Nextclouds on one data dir: the VM-100 cron container is off until `live`
   (Task 3).
2. File ownership over NFS (root squashed): images run as the uids that own the data
   (Nextcloud www-data 33, Jellyfin 1000 via `--user 1000:1000` as today, Immich as
   upstream) (Task 3, Task 5).
3. A `live = false` app's public host returns the maintenance page (503), never another
   app (Task 2, checked live in Task 6).
4. The weekly update must not jump majors: floating tags are minor tracks only; pinned
   images are never pulled to newer versions by the timer (Task 3b).
5. CoreDNS name resolution via MagicDNS: if a Service name doesn't resolve, the record is
   omitted (NXDOMAIN → public answer is not returned either), never a stale IP (Task 2b).

---

### Task 1: Generic TrueNAS mounts

**Files:** create `modules/homelab/storage.nix`; modify `modules/truenas/homelab.nix`
(NFS share for `/mnt/archive/shares`).

- [ ] **Step 1:** Create `hosts/servers/prod.nix` first (Task 3 Step 0, with only identity
  and `homelab.storage.enable = true` for now). Expectations (`nix eval` on `prod`): `fileSystems."/store".device ==
  "10.0.10.130:/mnt/store/internal"`, `fileSystems."/archive".device ==
  "10.0.10.130:/mnt/archive/shares"`, `fsType == "nfs"`, options contain `_netdev` and
  `x-systemd.automount`; `boot.supportedFilesystems` includes nfs.
- [ ] **Step 2:** Implement `options.homelab.storage.enable`, Linux-only, `mkIf`.
- [ ] **Step 3:** Declare the `/mnt/archive/shares` export in `modules/truenas/homelab.nix`
  (same shape as the existing `/mnt/archive/shares/jellyfin` one, read-write, LAN).
  nixos-manager applies TrueNAS config from `stable`, so also create the share now with
  `sudo midclt call sharing.nfs.create '{…}'` on TrueNAS (`ssh -J pve
  automation@10.0.10.130`) matching the declaration; `sudo truenas-reconcile check` on
  nixos-manager after the next promote must show no diff for it.
- [ ] **Step 4:** Hosts evaluate; commit `feat(homelab): generic /store and /archive mounts`.

### Task 2: Maintenance page and route switches on the router

**Files:** modify `lib/routeType.nix`, `modules/homelab/router/default.nix`.

**Produces:** route field `maintenance : bool = false`; when true, the route's public
router (and only that one) goes to service `maintenance` = a local nginx on
`127.0.0.1:8097` answering every path with **503** and a small HTML page ("We're working
on it — back soon", `vanwaaij.com`, no external assets, `Retry-After: 3600`).

- [ ] **Step 1:** Expectations on `router`: with a test route `maintenance = true`, its
  `-public` router's service is `maintenance` and its `-tailnet` router's service is the
  route's own; nginx listens on 127.0.0.1:8097 only.
- [ ] **Step 2:** Implement. **Step 3:** Evaluate all hosts; build router on
  nixos-manager; commit `feat(homelab): router maintenance page`.

### Task 2b: Routes resolve by Service name (no IPs in the repo)

**Files:** modify `lib/routeType.nix` (remove `tailnet.address`),
`modules/homelab/router/dns.nix`, `modules/homelab/router/tailscale.nix` (drop the
missing-address warning), `modules/homelab/routes.nix`, `hosts/servers/router-test.nix`
(drop `echo.tailnetAddress`), and any module setting `tailnet.address`.

- [ ] **Step 1:** Expectations on `router` / `router-test`: no `tailnet.address` option;
  CoreDNS config for each published tailnet route maps `<host>` to
  `<servicePrefix><name>.tail41ca60.ts.net` (CoreDNS `rewrite name exact … answer auto`
  in the `vanwaaij.com` zone, forwarded to `100.100.100.100`); other names forward to
  1.1.1.1 / 9.9.9.9 as before; the tailnet domain is an option
  (`homelab.router.tailnetDomain`, default `"tail41ca60.ts.net"`).
- [ ] **Step 2:** Implement; build router + router-test; switch router-test first and
  check from atlas: `dig +short @100.64.217.0 whoami-test.vanwaaij.com` → `100.126.16.116`;
  then the router: `dig +short @100.73.124.104 jellyfin.vanwaaij.com` → `100.84.78.44`.
- [ ] **Step 3:** Commit `feat(homelab): router DNS follows Tailscale Service names`.

### Task 3: VM 100 configuration (Docker)

**Files:** replace the native modules from commit 165f4b0
(`modules/services/{nextcloud,jellyfin,immich}.nix`) with container modules; create
`modules/services/docker.nix` (engine, shared network, dump/update helpers) if useful;
modify `hosts/servers/prod.nix`, `modules/homelab/routes.nix` (hand routes `nextcloud`,
`jellyfin` removed), `modules/homelab/links.nix` (their links removed).

**Produces:** per app `homelab.<app> = { enable; live : bool = false; }`, plus
`homelab.jellyfin = { configDir : str; gpu : bool = false; }`. Each module declares its
containers, `homelab.routes.<name> = { host; backend = "http://10.0.10.100:<port>"; maintenance = !live; }`,
a `lodestar.links` entry, its dump timer.

- [ ] **Step 0:** `hosts/servers/prod.nix` options: `homelab.storage.enable = true;
  homelab.nextcloud.enable = true; homelab.jellyfin = { enable = true; configDir =
  "/store/jellyfin-test/config"; }; homelab.immich.enable = true;`.
- [ ] **Step 1: Expectations** on `prod` (fail first):
  - `virtualisation.docker.enable`, `virtualisation.oci-containers.backend == "docker"`.
  - Nextcloud: containers `nextcloud-app` (`nextcloud:32-apache`, port 80 on the LAN,
    volumes `/store/nextcloud/data:/var/www/html/data` and local html/config/custom_apps
    under `/var/lib/prod/nextcloud`), `nextcloud-cron` (same image, `/cron.sh`, only
    when `live`), `nextcloud-db` (`mariadb:11.4`, data `/var/lib/prod/nextcloud/db`,
    `MARIADB_AUTO_UPGRADE=1`), `nextcloud-redis` (`redis:7-alpine`), `collabora`
    (`collabora/code`, port 9980, `aliasgroup1=https://nextcloud.vanwaaij.com`,
    `extra_params=--o:ssl.enable=false --o:ssl.termination=true`); env from an opnix
    env file (`op://Homelab/nextcloud-config/env`: DB passwords, admin); trusted proxy
    `10.0.10.110`, `OVERWRITEPROTOCOL=https`, `OVERWRITEHOST=nextcloud.vanwaaij.com`.
  - Jellyfin: `jellyfin/jellyfin:10.11`, `--user 1000:1000`, volumes `<configDir>:/config`,
    `/var/cache/jellyfin:/cache`, `/archive/jellyfin:/media:ro`, port 8096; `/dev/dri`
    and the render/video groups only when `gpu`.
  - Immich: server (`ghcr.io/immich-app/immich-server:v2`, port 2283,
    `/store/immich-v2:/data`, `/store/immich/library:/mnt/old-library:ro`),
    machine-learning (`…immich-machine-learning:v2`), `valkey` and PostgreSQL exactly as
    upstream's compose for the v2 line (tag + digest), DB at `/var/lib/prod/immich/db`.
  - Each container's unit has `RequiresMountsFor` for the /store or /archive paths it uses.
  - Dumps: `nextcloud-db-dump` and `immich-db-dump` timers at 01:30 writing
    `/store/db-dumps/<app>/<app>-%F.sql.gz`, keeping 14.
  - Router collects routes `nextcloud`, `office`, `jellyfin`, `immich`, all
    `maintenance = true`.
  - Firewall: 80, 9980, 8096, 2283 open on the LAN.
- [ ] **Step 2: Implement.** Translate upstream compose files; keep a comment with the
  upstream file/version each module follows.
- [ ] **Step 3:** All hosts evaluate; build `prod` and `router` on nixos-manager; nixfmt;
  commit `feat(prod): Nextcloud, Jellyfin and Immich as containers on VM 100`.

### Task 3b: Weekly updates and Renovate

**Files:** create `modules/services/updates.nix`, `renovate.json` (repo root).

- [ ] **Step 1:** Expectations on `prod`: timer `prod-container-update` with
  `OnCalendar = "Fri 23:00"`, `Persistent = true`; its service pulls only the floating
  images (list derived from the app modules, an option `homelab.containers.floating`),
  restarts containers whose image id changed, pings Healthchecks (`/start`, success,
  `/fail` with the last 100 log lines) from the opnix secret.
- [ ] **Step 2:** `renovate.json`: a regex manager over `modules/services/**/*.nix` for
  `image = "<repo>:<tag>"` (and `@sha256:` digests); package rules: floating app images →
  only `major` updates; pinned images → all updates; `automerge = false`; label
  `containers`; schedule weekly. Validate with
  `npx --yes --package renovate -- renovate-config-validator renovate.json`.
- [ ] **Step 3 (user):** install the Renovate GitHub app on `Waayway/nixos-config`
  (after the next push); Claude checks the onboarding PR.
- [ ] **Step 4:** Commit `feat(prod): weekly container updates and Renovate`.

### Task 4: Main to 108, VM 100 up

- [ ] **Step 1 (user):** Main's IP `10.0.10.100` → `10.0.10.108`, then the web port
  forward 80/443 → `.108`. Claude checks `ssh -J pve goedenaam@10.0.10.108`, a
  `--resolve`d `status.php` → 200, and updates Main's Nextcloud `extra_hosts` hairpin to
  `10.0.10.108` (keep a `.pre-108` copy), `docker compose up -d`.
- [ ] **Step 2:** At a moment the user OKs: `qm shutdown 100`; `lvrename` its
  `store-lvm` disk `vm-100-disk-0` → `vm-108-disk-0`; move `100.conf` → `108.conf` with
  the disk renamed; `qm start 108`; Main answers on `.108`.
- [ ] **Step 3:** `qm clone 9000 100 --name prod --full --storage local-lvm`,
  `--cores 6 --memory 16384 --onboot 1`, `qm resize 100 virtio0 64G`; switch to `#prod`
  from nixos-manager; reboot; on `.100`, tagged `tag:nixos,tag:prod`; `/store` and
  `/archive` readable.
- [ ] **Step 4:** On TrueNAS create `/mnt/store/internal/{immich-v2,jellyfin-test,db-dumps/nextcloud,db-dumps/immich}`
  with owners matching the container uids.

### Task 5: Copies for testing

- [ ] **Step 1 — Nextcloud:** copy Main's `config.php` secrets (`instanceid`,
  `passwordsalt`, `secret`, DB settings adapted) into 1Password `nextcloud-config`; copy
  `custom_apps` (pantry) from Main; dump Main's DB
  (`docker exec nextcloud-db mariadb-dump --single-transaction --routines --triggers nextcloud`)
  and stream it into `nextcloud-db` on VM 100; start the app; `occ upgrade`,
  `occ maintenance:mode --off`; `occ status` → installed, no DB upgrade needed.
- [ ] **Step 2 — Jellyfin:** `rsync -a /store/jellyfin/config/ /store/jellyfin-test/config/`,
  start; `/System/Info/Public` answers.
- [ ] **Step 3 — Immich:** starts empty.
- [ ] **Step 4:** The copy steps are scripts on VM 100 (`prod-sync-nextcloud-db`,
  `prod-sync-jellyfin`), declared in the modules, reused at the cutover; commit.

### Task 6: Tailnet points at VM 100

- [ ] **Step 1 (user):** create Services `immich` and `office` (tcp:443).
- [ ] **Step 2:** Policy via API (controller): grant + autoApprovers for `svc:immich`,
  `svc:office`.
- [ ] **Step 3:** Switch the router (first time with Task 2/2b/3 routes); `tailscale serve
  drain`/`advertise` for new Services if they aren't routed.
- [ ] **Step 4 — checks over the tailnet (split DNS):** Nextcloud `status.php` 200;
  WebDAV `PROPFIND` with an app password → 207; `/.well-known/caldav` → 301;
  `https://office.vanwaaij.com/hosting/discovery` → 200; Jellyfin
  `/System/Info/Public` 200; Immich `/api/server/ping` → pong. Public path: the router's
  public entrypoint (`--resolve … :10.0.10.110`) returns the 503 maintenance page for all
  four; the internet itself still reaches Main (`.108`).

### Task 7: The user tests

- [ ] User checks the plain plan's list on laptop and phone; Claude fixes and re-checks.
  Immich: user creates the admin account; Claude adds `/mnt/old-library` as a read-only
  external library with an API key the user creates.

### Task 8: Cutover (user picks the moment)

- [ ] **Step 1 (user):** web port forward → `10.0.10.110`. Check from outside: the four
  app hosts → 503 page; `ap.` → 401.
- [ ] **Step 2:** Main: `occ maintenance:mode --on`, stop `nextcloud-app` and
  `nextcloud-cron`; media: stop `jellyfin`.
- [ ] **Step 3:** `prod-sync-nextcloud-db` (fresh dump → recreate → import → `occ upgrade`
  → maintenance off).
- [ ] **Step 4:** `homelab.jellyfin.configDir = "/store/jellyfin/config"`, `gpu = true`.
- [ ] **Step 5:** `qm shutdown 120`; move `hostpci0: mapping=WX7100` to VM 100; reboot 100.
- [ ] **Step 6:** `live = true` for all four; switch prod and router; commit `feat(prod): live`.
- [ ] **Step 7:** Checks from outside: Nextcloud login, `status.php`, WebDAV 207,
  CalDAV/CardDAV discovery, Collabora; Jellyfin plays with VA-API; Immich ping; `ap.`
  401; Nextcloud admin overview clean. User confirms on the phone.
- [ ] **Step 8 — Rollback:** forward → `.108`; Main `docker compose up -d`, maintenance
  off; media: GPU back to 120, start Jellyfin there. Nothing on Main or media was changed
  or deleted.

### Task 9: Docs and cleanup

- [ ] `docs/homelab.md` (VM 100 prod and its containers, Main 108 and media 120 shut
  down, mounts, dumps and restore steps, the update timer and Renovate), `AGENTS.md`
  machine table (+ prod), router plan Task 9 marked superseded. Main and media:
  `qm shutdown`, `onboot 0`. Commit `docs(homelab): production VM 100`.
