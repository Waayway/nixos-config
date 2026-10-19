# Homelab front door: production VM 100 — technical plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

Plain-language version (what happens, who does what): `2026-10-19-homelab-front-door-production-plan.md`.

**Goal:** NixOS VM 100 (`prod`, `10.0.10.100`) runs Nextcloud 32 (+ MariaDB, Redis,
Collabora), Jellyfin and Immich on data mounted from TrueNAS at `/store` and `/archive`;
verified over the tailnet on copies of the databases; then one cutover moves the
databases, the GPU and the public port forward (to the router).

**Architecture:** A generic `homelab.storage` module mounts TrueNAS NFS on any VM. One
feature module per app under `modules/services/` declares the service, its
`homelab.routes` entry (route name = Tailscale Service name) and its `lodestar.links`
entry, with a per-app `live` switch: `live = false` → the router's public router for that
host serves a maintenance page; `true` → it proxies to VM 100. The tailnet path always
goes to VM 100. Main and media are never modified beyond stopping containers at cutover.

**Tech Stack:** NixOS 26.05 (`services.nextcloud` with `pkgs.nextcloud32`,
`services.mysql` MariaDB 11.4, `services.collabora-online`, `services.jellyfin`
10.11, `services.immich` 2.7), NFS, Traefik 3.7 on the router, Tailscale API
(`op://Homelab/tailscale-policy-authkey`), Proxmox `qm`.

**Spec:** `docs/plans/2026-10-19-homelab-front-door-design.md` (section C), amended by the
user on 2026-10-19: generic `/store` + `/archive` mounts; databases move last; tailnet
verification before any public change; maintenance page during cutover; Kanidm/OIDC
deferred to the identity plan; the router plan's Task 9 (cutover via Main) is replaced by
Task 8 here.

**Depends on:** router plan Tasks 1–8 (router 110 live on the tailnet, split DNS →
router, `homelab.routes` with `tailnet.address`).

## Global Constraints

- VM 100: `10.0.10.100`, hostname `prod`, 6 cores, 16 GB, 64 GB root on `local-lvm`
  (≈84 GB free there), `tags = [ "tag:prod" ]` (policy: `"tag:prod": ["autogroup:admin", "tag:nixos"]`).
- Old Main: VMID 100 → 108, IP `10.0.10.108` (user changes the IP). Its disk is
  `store-lvm:vm-100-disk-0`.
- Mounts: `/store` ← `10.0.10.130:/mnt/store/internal`, `/archive` ←
  `10.0.10.130:/mnt/archive/shares` (new export), NFS, `_netdev`, `x-systemd.automount`.
- Paths: Nextcloud data `/store/nextcloud/data` (same files as Main, owned uid/gid 33);
  Jellyfin config: test copy `/store/jellyfin-test/config`, after cutover the original
  `/store/jellyfin/config`; library `/archive/jellyfin`; Immich media `/store/immich-v2`,
  old photos `/store/immich/library` as a read-only external library; dumps
  `/store/db-dumps/{nextcloud,immich}`.
- Hostnames: `nextcloud.vanwaaij.com`, `office.vanwaaij.com` (Collabora),
  `jellyfin.vanwaaij.com`, `immich.vanwaaij.com`; route/Service names `nextcloud`,
  `office`, `jellyfin`, `immich`.
- Nextcloud: major 32 (DB from 32.0.8 upgraded to nixpkgs' 32.0.15 by `occ upgrade`);
  `instanceid`, `passwordsalt`, `secret` carried over from Main's `config.php` via
  1Password item `nextcloud-config` (field `secrets`, JSON) → `services.nextcloud.secretFile`;
  `trusted_proxies = [ "10.0.10.110" ]`, `overwriteprotocol = "https"`.
- Secrets never printed; never in the repo.
- Repo rules as in the router plan's context file (modules always imported, gated; RFC
  nixfmt; own paths; author thijs@vanwaaij.com; no AI trailer; no push without the user).

## Review Focus

1. Nextcloud's storage id: the DB says `local::/var/www/html/data/`; the new path must be
   rewritten in `oc_storages` at every DB import, or every file looks new (Task 5, Task 8).
2. File ownership over NFS (root squashed): services must run with the uid that owns the
   data (Nextcloud 33) or the copy must be chowned (Jellyfin) (Task 3, Task 5).
3. Two Nextclouds on one data dir: the VM-100 instance has `nextcloud-cron` and app
   updates off until `live` (Task 3, Step 1 expectations).
4. Jellyfin's DB holds absolute container paths (`/config`, `/cache`, `/media`): the unit
   binds those paths so they stay valid (Task 3).
5. A `live = false` app's public host returns the maintenance page (503), never another
   app or a Traefik 404 (Task 2).

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

### Task 3: VM 100 configuration

**Files:** create `hosts/servers/prod.nix`, `modules/services/nextcloud.nix`,
`modules/services/jellyfin.nix`, `modules/services/immich.nix`; modify
`modules/homelab/routes.nix` (remove the hand routes `nextcloud`, `jellyfin`; keep
`archipelago`, `traefik`).

**Produces:** per app `homelab.<app> = { enable; live : bool = false; }`, plus
`homelab.jellyfin = { configDir : str; gpu : bool = false; }`. Each module declares
`homelab.routes.<name> = { host; backend = "http://10.0.10.100:<port>"; maintenance = !live; tailnet.address = <Service IP>; }`
(nextcloud/jellyfin keep their existing Service IPs 100.76.170.121 / 100.84.78.44; immich
and office get theirs in Task 6) and a `lodestar.links` entry.

- [ ] **Step 0:** `hosts/servers/prod.nix`: thin; user `prod`, IP `10.0.10.100`,
  `tags = [ "tag:prod" ]`, `fleet = true`, `options = { homelab.storage.enable = true; homelab.nextcloud.enable = true; homelab.jellyfin = { enable = true; configDir = "/store/jellyfin-test/config"; }; homelab.immich.enable = true; }`.
- [ ] **Step 1: Expectations** on `prod` (fail first):
  - Nextcloud: `services.nextcloud.package.version` starts with `32.`;
    `hostName == "nextcloud.vanwaaij.com"`; `datadir` such that data is
    `/store/nextcloud/data`; `config.dbtype == "mysql"`; `database.createLocally`;
    `configureRedis`; `settings.trusted_proxies == [ "10.0.10.110" ]`;
    `settings.overwriteprotocol == "https"`; `secretFile` from opnix;
    `users.users.nextcloud.uid == 33` and group gid 33 (verify 33 is free in NixOS's
    `ids`); `systemd.timers.nextcloud-cron.enable == false` while `live = false`;
    `appstoreEnable == false`; apps `contacts`, `calendar`, `richdocuments` from
    `nextcloud32Packages.apps` (and `pantry` if packaged; otherwise note it).
  - Collabora: `services.collabora-online.enable`, port 9980, `aliasGroups` allow
    `https://nextcloud.vanwaaij.com`; route `office`.
  - Jellyfin: `services.jellyfin.enable`; unit has `BindPaths` `<configDir>:/config`,
    `/var/cache/jellyfin:/cache`, and `BindReadOnlyPaths` `/archive/jellyfin:/media`,
    with Jellyfin's data/config dirs pointing at `/config` (match the official image's
    layout `--datadir /config --cachedir /cache`); `gpu = false` → no
    `hardware.graphics`.
  - Immich: `services.immich.enable`, `mediaLocation == "/store/immich-v2"`,
    `machine-learning` on, host `0.0.0.0`, port 2283.
  - Backups: `services.mysqlBackup` (`nextcloud`, `/store/db-dumps/nextcloud`, 01:30),
    `services.postgresqlBackup` (`immich`, `/store/db-dumps/immich`).
  - Firewall: app ports (80/nextcloud nginx, 9980, 8096, 2283) open on the LAN interface.
  - `homelab.routes` collected by the router: `nextcloud`, `office`, `jellyfin`,
    `immich` with `maintenance = true`.
- [ ] **Step 2: Implement.** Nextcloud behind its own nginx on port 80 (NixOS default);
  Jellyfin via `systemd.services.jellyfin.serviceConfig` binds; GPU block
  (`hardware.graphics` + VA-API, jellyfin in `render`/`video`) under `gpu`.
- [ ] **Step 3:** All hosts evaluate; build `prod` and `router` on nixos-manager; nixfmt;
  commit `feat(prod): Nextcloud, Jellyfin and Immich on VM 100`.

### Task 4: Main to 108, VM 100 up

- [ ] **Step 1 (user):** Main's IP `10.0.10.100` → `10.0.10.108`, then the web port
  forward 80/443 → `.108`. Claude checks: `ssh -J pve goedenaam@10.0.10.108` works,
  `curl -sI --resolve nextcloud.vanwaaij.com:443:10.0.10.108 https://nextcloud.vanwaaij.com/status.php`
  → 200; update Main's Nextcloud `extra_hosts` hairpin to `10.0.10.108`
  (keep a `.pre-108` copy) and `docker compose up -d`.
- [ ] **Step 2:** At a moment the user OKs: `qm shutdown 100`; rename
  `store-lvm`'s `vm-100-disk-0` → `vm-108-disk-0` (`lvrename nfs-vg …`), move
  `100.conf` → `108.conf` with the disk name replaced, `qm start 108`; Main answers on
  `.108` again. Update `docs/homelab.md` access table later (Task 9).
- [ ] **Step 3:** Policy via API: `"tag:prod": ["autogroup:admin", "tag:nixos"]`.
- [ ] **Step 4:** `qm clone 9000 100 --name prod --full --storage local-lvm`,
  `--cores 6 --memory 16384 --onboot 1`, `qm resize 100 virtio0 64G`; switch to `#prod`
  from nixos-manager (agent-forwarded key, as for the router); reboot; on `.100`, tagged
  `tag:nixos,tag:prod`; `/store` and `/archive` mounted (`ls /store/nextcloud/data`,
  `ls /archive/jellyfin`).
- [ ] **Step 5:** On TrueNAS: create `/mnt/store/internal/{immich-v2,jellyfin-test,db-dumps/nextcloud,db-dumps/immich}`
  owned by the uids VM 100 uses for immich, jellyfin, mysql and postgres (read them on
  VM 100 with `id`).

### Task 5: Copies for testing

- [ ] **Step 1 — Nextcloud DB copy:** on Main
  `docker exec nextcloud-db mariadb-dump --single-transaction --routines --triggers nextcloud`
  (credentials from Main's `.env`, never printed) → stream into VM 100's MariaDB
  (`mysql nextcloud`). Then `UPDATE oc_storages SET id='local::/store/nextcloud/data/' WHERE id='local::/var/www/html/data/';`.
- [ ] **Step 2 — Nextcloud secrets:** `instanceid`, `passwordsalt`, `secret` from Main's
  `config.php` → 1Password `nextcloud-config` (`secrets` = JSON) before the first start
  that matters; restart `nextcloud-setup`.
- [ ] **Step 3:** `nextcloud-occ upgrade`, `nextcloud-occ maintenance:mode --off`,
  `nextcloud-occ status` → installed, version 32.0.15, no DB upgrade needed;
  `nextcloud-occ files:scan --all --dry-run` is NOT run (it would touch the shared dir).
- [ ] **Step 4 — Jellyfin copy:** `rsync -a /store/jellyfin/config/ /store/jellyfin-test/config/`
  on VM 100, chown to jellyfin's uid, start jellyfin; `/System/Info/Public` answers.
- [ ] **Step 5 — Immich:** starts on an empty DB; nothing to copy.
- [ ] **Step 6:** Each copy step is a re-runnable script under
  `modules/services/` (e.g. `prod-sync-nextcloud-db`, `prod-sync-jellyfin`) installed on
  VM 100, so Task 8 runs the exact same thing; commit them.

### Task 6: Tailnet points at VM 100

- [ ] **Step 1 (user):** create Services `immich` and `office` (tcp:443).
- [ ] **Step 2:** Policy via API: grant + autoApprovers for `svc:immich`, `svc:office`.
- [ ] **Step 3:** Record their IPs as `tailnet.address`; switch router; `tailscale serve
  drain`/`advertise` for the two new Services if they don't get routed (known quirk).
- [ ] **Step 4 — Claude's checks over the tailnet (split DNS, no `--resolve`):**
  Nextcloud `status.php` 200 with `"maintenance":false`; WebDAV `PROPFIND` on
  `/remote.php/dav/files/<user>/` with an app password the user creates → 207;
  `/.well-known/caldav` → 301; `https://office.vanwaaij.com/hosting/discovery` → 200
  XML; Jellyfin `/System/Info/Public` 200; Immich `/api/server/ping` → `pong`.
  Public path still Main: `curl -sI https://nextcloud.vanwaaij.com` from outside the
  tailnet (e.g. nixos-manager with Tailscale DNS off, or `--resolve` to the WAN IP) shows
  Main.

### Task 7: The user tests

- [ ] User checks the plain plan's step 6 list on laptop and phone. Claude fixes what
  fails (commit per fix, re-run Task 6 Step 4). Immich: user creates the admin account;
  Claude adds `/store/immich/library` as an external library (read-only) through the
  Immich API with a key the user creates. Done when the user says it works.

### Task 8: Cutover (user picks the moment)

- [ ] **Step 1:** Router: all four routes already `maintenance = true` (live = false).
  **User:** web port forward → `10.0.10.110`. Check from outside: every app host → 503
  maintenance page; `ap.` → 401.
- [ ] **Step 2:** Main: `occ maintenance:mode --on`, then stop `nextcloud-app`,
  `nextcloud-cron`. media: stop `jellyfin`.
- [ ] **Step 3:** Run `prod-sync-nextcloud-db` (fresh dump → drop/recreate → import →
  `oc_storages` update → `occ upgrade` → `maintenance:mode --off`).
- [ ] **Step 4:** `homelab.jellyfin.configDir = "/store/jellyfin/config"`: chown the
  original to jellyfin's uid (record the old owner 1000:1000 for rollback). `gpu = true`.
- [ ] **Step 5:** `qm shutdown 120`; move `hostpci0: mapping=WX7100` from 120 to 100;
  restart 100.
- [ ] **Step 6:** Set `live = true` for all four apps; switch prod and router; commit
  `feat(prod): live`.
- [ ] **Step 7:** Checks from outside (phone off Wi-Fi or `--resolve` to the WAN IP):
  Nextcloud login page, `status.php` 200, WebDAV 207, CalDAV/CardDAV discovery,
  Collabora discovery; Jellyfin plays with VA-API (`/dev/dri/renderD128` used, ffmpeg log
  shows `vaapi`); Immich ping; `ap.` 401. Nextcloud admin overview: no warnings about
  proxies/HTTPS. User confirms on phone.
- [ ] **Step 8 — Rollback:** port forward → `.108`; on Main `docker compose up -d` and
  `occ maintenance:mode --off`; media: chown `/store/jellyfin/config` back to 1000:1000,
  move the GPU back to 120, start it. Nothing on Main or media was deleted.

### Task 9: Docs and cleanup

- [ ] `docs/homelab.md` (VM 100 prod, Main 108 and media 120 shut down, mounts, dumps,
  restore steps), `AGENTS.md` machine table (+ prod), `modules/homelab/links.nix`
  (drop Main/media entries now declared by the service modules), router plan Task 9
  marked superseded. Main and media: `qm shutdown`, `onboot 0`. Commit
  `docs(homelab): production VM 100`.
