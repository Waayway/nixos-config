# Homelab front door: template and router implementation plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** A refreshed template 9000 and a NixOS router VM (110) that takes over Main's
Traefik: public on the port forward, on the tailnet through Tailscale Services with
split DNS, routes declared in Nix.

**Architecture:** One `homelab.router` feature module (Traefik, CoreDNS, Tailscale
serve) driven by route declarations: `homelab.routes` next to NixOS services
(collected flake-wide by `tools.routesFrom`, like Lodestar's `linksFrom`) plus
`homelab.router.extraRoutes` for backends this flake doesn't manage yet. Tested on a
throwaway VM 230 before VM 110 exists; Main stays the rollback.

**Tech Stack:** NixOS 26.05, Traefik 3.7 (`services.traefik`), CoreDNS 1.14,
Tailscale 1.98 (`services.tailscale.serve`), opnix, Proxmox `qm` on `pve`.

**Spec:** `docs/plans/2026-10-19-homelab-front-door-design.md` (sections "Template
9000" and "A. Router").

## Global Constraints

- VMID = last octet of the IP: router `10.0.10.110`, test `10.0.10.230`, vpn moves to
  `10.0.10.118`. New disks on `local-lvm`, never `store-lvm` (97% full).
- Router VM: 2 cores, 2 GB, 16 GB root. Test VM 230: 1 core, 2 GB.
- One Let's Encrypt wildcard `*.vanwaaij.com` (+ `vanwaaij.com`) via Cloudflare
  DNS-01; token from 1Password Homelab item `cloudflare-dns-token`.
- Header `X-Homelab-Via: tailnet` is set by the `tailnet` entrypoint and removed by
  the `public` entrypoint.
- Tailscale Service name = route name (`svc:<name>`), endpoint `tcp:443` →
  `tcp://127.0.0.1:8443`.
- Repo rules (AGENTS.md): every module always imported, feature modules gated on
  their `enable`, no `//` on shared top-level keys, RFC nixfmt from the repo's
  nixpkgs, commit only own paths, commits as `thijs@vanwaaij.com`, no AI trailer
  (global CLAUDE.md overrides AGENTS.md here), never push without asking.
- The user changes UniFi port forwards and, unless an OAuth client is provided, the
  Tailscale admin console. Everything on `pve` is done by Claude.

## Review Focus

1. A public request carrying `X-Homelab-Via: tailnet` must reach the backend without
   it (Task 6, Step 3).
2. A request for a host no route declares returns 404, never another app (Task 6,
   Step 3).
3. A route with `tailnet.enable = true` but no `tailnet.address` is served publicly,
   gets no DNS record, and evaluation warns (Task 2, Step 1; Task 4, Step 1).
4. Two configurations declaring the same route name or the same `host` fail
   evaluation with both names in the message (Task 2, Step 1).
5. After the cutover, Nextcloud login, CalDAV/CardDAV discovery and the client IP in
   Nextcloud's log behave as before (Task 9, Step 5).

---

### Task 1: Refresh nixpkgs and template 9000, first clone as VM 230

**Files:**
- Modify: `flake.lock` (input `nixpkgs` only)
- Modify: `template/proxmox.nix` only if the build or boot test needs it

**Interfaces:**
- Produces: template 9000 on `local-lvm` built from the current `nixos-26.05`;
  VM 230 (`10.0.10.230` once switched in Task 6) booted from it.

- [ ] **Step 1:** `nix flake update nixpkgs` (not `nixpkgs-unstable`). The lock is from
  2026-05-24; servers follow this input, so this is also their 26.05 point update.
- [ ] **Step 2:** Evaluate all five hosts (AGENTS.md "Verifying changes"); all print a
  drvPath. `nix build .#darwinConfigurations.atlas.system --no-link` succeeds.
- [ ] **Step 3:** Ship a bundle of `unstable` to nixos-manager (AGENTS.md "Linux
  builder") and build the image there with the token (procedure in the header comment
  of `template/proxmox.nix`), plus `.#nixosConfigurations.nixos-manager.config.system.build.toplevel`.
  Expected: both build; the image is a `vzdump-qemu-*.vma.zst`.
- [ ] **Step 4:** On `pve`: keep the old dump as
  `/var/lib/vz/dump/vzdump-qemu-nixos-template-2026-10-13.vma.zst`, copy the new one in,
  `qm destroy 9000`, `qmrestore <new.vma.zst> 9000 --storage local-lvm --unique`,
  `qm set 9000 --name nixos-26.05-template`, `qm template 9000`.
- [ ] **Step 5:** `qm clone 9000 230 --name router-test --full --storage local-lvm`,
  `qm set 230 --cores 1 --memory 2048`, start. Expected: within 2 minutes
  `qm guest cmd 230 network-get-interfaces` shows a DHCP address and
  `ssh nixos@<addr>` (key `~/.ssh/proxmox_vms_rsa`) works; `/etc/opnix-token` exists.
- [ ] **Step 6:** Commit `flake.lock` (and `template/proxmox.nix` if changed):
  `chore(flake): update nixpkgs; refresh proxmox template`.

### Task 2: Route option and flake-wide collector

**Files:**
- Create: `lib/routeType.nix` (`{ lib }: lib.types.submodule { … }`, shared by both
  route options)
- Create: `modules/homelab/routes-option.nix` (options only, every platform)
- Create: `lib/routesFrom.nix`
- Create: `tests/routes-from.nix`
- Modify: `programs.nix` (add `checks.x86_64-linux.routes-from`)

**Interfaces:**
- Produces: option `homelab.routes.<name>` of type `tools.routeType { inherit lib; }`
  (also the element type of `homelab.router.extraRoutes` in Task 3):
  - `host`: `str`, FQDN, required
  - `backend`: `str`, `http(s)://…` URL or the literal `"api@internal"`; assertion on
    anything else
  - `public`: `bool`, default `true`
  - `tailnet.enable`: `bool`, default `true`
  - `tailnet.address`: `nullOr str`, default `null` (the Service IP, filled in after
    the Service exists)
  - `basicAuth.usersFile`: `nullOr str`, default `null` (htpasswd lines)
  - `middlewares`: `attrsOf anything`, default `{}`; Traefik `http.middlewares`
    entries added for this route (named `<route>-<key>`) and attached to both of its
    routers, for whatever Main's config has that the fields above can't express
- Produces: `tools.routesFrom { nixosConfigurations }` → attrset name → route with
  extra attribute `declaredBy` (configuration name). Configurations without the
  option are skipped (darwin is not passed in).

- [ ] **Step 1: Write the failing check** `tests/routes-from.nix`, same shape as
  `~/lodestar/nix/tests/links-from.nix` (stub configurations via `lib.evalModules`
  over `routes-option.nix`, `builtins.tryEval` for failures). Asserts:
  - `r.a.declaredBy == "alpha"`, `r.a.public == true`, `r.a.tailnet.enable == true`,
    `r.a.tailnet.address == null`;
  - two configurations declaring name `dup` → evaluation fails, message contains
    `dup`;
  - two different names with the same `host` → fails, message contains both names;
  - `backend = "javascript:x"` → fails; `"api@internal"` and `"http://10.0.10.1:80"`
    pass;
  - a configuration without `homelab` is skipped.
- [ ] **Step 2:** `nix build .#checks.x86_64-linux.routes-from` → fails (missing
  files).
- [ ] **Step 3:** Implement `lib/routeType.nix`, `modules/homelab/routes-option.nix`
  (`options.homelab.routes = attrsOf routeType`, default `{}`) and
  `lib/routesFrom.nix`; wire the check in `programs.nix` (pass `tools.routesFrom` and
  `lib`).
- [ ] **Step 4:** The check builds; all five hosts still evaluate.
- [ ] **Step 5:** Commit: `feat(homelab): homelab.routes and routesFrom`.

### Task 3: Router module — Traefik

**Files:**
- Create: `modules/homelab/router/default.nix` (options + Traefik), Linux only
- Create: `modules/homelab/routes.nix` (hand routes for unmanaged backends)
- Modify: `modules/homelab/links.nix` (Traefik link moves to the router module)

**Interfaces:**
- Consumes: `lib/routeType.nix`, `tools.routesFrom`.
- Produces: options `homelab.router = { enable; acmeStaging (bool, false);
  servicePrefix (str, ""); tailnetServices (nullOr (listOf str), null = all);
  extraRoutes (attrsOf routeType, {}); echo = { enable (bool, false);
  tailnetAddress (nullOr str, null); }; }` and the read-only
  value `homelab.router.routes` = `routesFrom { inherit (inputs.self) nixosConfigurations; }`
  merged with `extraRoutes` (a name in both is an assertion failure). Tasks 4 and 5
  read `homelab.router.routes`.

- [ ] **Step 0: Host files** `hosts/servers/router.nix` and
  `hosts/servers/router-test.nix` as specified in Task 5 Step 1, and the options
  block of `modules/homelab/router/default.nix` (no config yet), so both hosts
  evaluate. `git add` them.
- [ ] **Step 1: Write the expectations** as `nix eval` checks against `router-test`.
  Expected values:
  - `…router-test.config.services.traefik.staticConfigOptions.entryPoints` has
    `web` (`:80`, redirect to `public`/https), `public` (`:443`), `tailnet`
    (`127.0.0.1:8443`);
  - `…entryPoints.public.http.middlewares == [ "strip-marker@file" ]`,
    `…entryPoints.tailnet.http.middlewares == [ "tailnet-marker@file" ]`;
  - `…dynamicConfigOptions.http.routers` contains `jellyfin-public` and
    `jellyfin-tailnet` with rule ``Host(`jellyfin.vanwaaij.com`)``;
  - `networking.firewall.allowedTCPPorts` contains 80 and 443.
  Run them; they fail.
- [ ] **Step 2: Implement** in `modules/homelab/router/default.nix`
  (`lib.optionalAttrs hostPlatform.isLinux { options…; config = lib.mkIf cfg.enable … }`):
  - static config: entrypoints above; `api.dashboard = true`; both TLS entrypoints
    `http.tls = { certResolver = "cloudflare"; domains = [ { main = "vanwaaij.com"; sans = [ "*.vanwaaij.com" ]; } ]; }`;
    resolver `cloudflare`: email `thijs@vanwaaij.com`, storage
    `/var/lib/traefik/acme.json`, `dnsChallenge.provider = "cloudflare"`,
    `caServer` = LE staging when `acmeStaging`.
  - dynamic config: middlewares `strip-marker` (`headers.customRequestHeaders."X-Homelab-Via" = ""`)
    and `tailnet-marker` (`= "tailnet"`); per route `<name>-public` if `public`,
    `<name>-tailnet` if `tailnet.enable`, service `<name>` with one server
    `{ url = backend; }` (no service when `api@internal`; the routers point at it),
    middleware `<name>-auth` (`basicAuth.usersFile`) when set, plus the route's own
    `middlewares`.
  - secret `cloudflareDnsToken` = `op://Homelab/cloudflare-dns-token/credential`,
    owner `traefik`, services `[ "traefik" ]`;
    `systemd.services.traefik.environment.CF_DNS_API_TOKEN_FILE` = its path.
  - firewall: TCP 80, 443.
  - `lodestar.links.traefik` (moved from `links.nix`): url
    `https://traefik.vanwaaij.com`, host defaults to the router.
  - `echo.enable`: `pkgs.whoami` on `127.0.0.1:8099` as a systemd service and
    `extraRoutes.whoami-test` (`host = "whoami-test.vanwaaij.com"`, backend
    `http://127.0.0.1:8099`, `tailnet.address = cfg.echo.tailnetAddress`).
- [ ] **Step 3: `modules/homelab/routes.nix`**, `mkIf config.homelab.router.enable`,
  sets `homelab.router.extraRoutes` from Main's current Traefik config, read first on
  Main (`~/traefik/dynamic/*.yml`, Nextcloud's Docker labels in
  `~/nextcloud/docker-compose.yml`): `nextcloud` (backend `http://10.0.10.100:<port
  chosen in Task 9>`, plus every middleware it has today, e.g. `.well-known`
  CalDAV/CardDAV redirects and security headers), `jellyfin`
  (`http://10.0.10.120:8096`, plus the middlewares in `media.yml`), `archipelago`
  (`http://10.0.10.201:8080`, `basicAuth.usersFile` from secret
  `op://Homelab/archipelago-basic-auth/htpasswd`, owner `traefik`), `traefik`
  (`api@internal`, `public = false`). Middlewares the route type can't express
  go into the route's `middlewares` field (Task 2). Immich and
  BlueMap are not routed (dead today).
- [ ] **Step 4:** Step 1 checks pass; all five hosts evaluate; nixfmt.
- [ ] **Step 5:** Create the 1Password items with the CLI (`op --account
  KVKXJLIAFVBK5GYLWVS37CJCTE item create --vault Homelab …`):
  `cloudflare-dns-token` (field `credential`, value from Main's `~/traefik/.env`) and
  `archipelago-basic-auth` (field `htpasswd`, the users line from
  `~/traefik/dynamic/archipelago.yml`). Never print the values.
- [ ] **Step 6:** Commit: `feat(homelab): router module with Traefik`.

### Task 4: Router module — Tailscale Services and split DNS

**Files:**
- Modify: `modules/homelab/router/default.nix` (or split into `tailscale.nix` and
  `dns.nix` in the same folder if `default.nix` passes ~200 lines)

**Interfaces:**
- Consumes: `homelab.router.routes`, `servicePrefix`, `tailnetServices`.

- [ ] **Step 1: Expectations** (`nix eval` on `router-test`), fail first:
  - `services.tailscale.serve.services` has exactly the prefixed names of routes with
    `tailnet.enable` (filtered by `tailnetServices` when set), each
    `endpoints."tcp:443" == "tcp://127.0.0.1:8443"`;
  - `services.coredns.config` contains `bind tailscale0`, a `hosts` line
    `<address> <host>` for every tailnet route with an address and none for a route
    without one, and `forward . 1.1.1.1 9.9.9.9`;
  - `warnings` contains a line naming each tailnet route that has no address;
  - `services.tailscale.extraSetFlags` contains `--advertise-routes=10.0.10.0/24` and
    `--advertise-exit-node`; `services.tailscale.useRoutingFeatures == "server"`;
  - `networking.firewall.interfaces.tailscale0` allows TCP and UDP 53.
- [ ] **Step 2: Implement.** CoreDNS zone `vanwaaij.com:53`; the unit gets
  `after`/`wants` `tailscaled.service` and `Restart = "on-failure"` (`bind
  tailscale0` fails until the interface exists).
- [ ] **Step 3:** Expectations pass; five hosts evaluate; nixfmt.
- [ ] **Step 4:** Commit: `feat(homelab): router tailnet services and split DNS`.

### Task 5: Host files, full build

**Files:**
- Modify: `hosts/servers/router.nix`, `hosts/servers/router-test.nix` (created in
  Task 3 Step 0)

**Interfaces:**
- Produces: `nixosConfigurations.router` and `.router-test`.

- [ ] **Step 1:** Both thin, like `hosts/servers/nixos-manager.nix`: `type = "server"`,
  `useDefaultHardware = true`, `isHomeServer = true`, `tags = [ "tag:router" ]`.
  - `router`: user `router`, `netInterface.ip = "10.0.10.110"`, `fleet = true`,
    `options.homelab.router.enable = true`.
  - `router-test`: user `router`, `netInterface.ip = "10.0.10.230"`, `fleet = false`,
    `options.homelab.router = { enable = true; acmeStaging = true; servicePrefix = "test-"; tailnetServices = [ "whoami-test" ]; echo.enable = true; }`
    (`echo.tailnetAddress` is added in Task 6 Step 4).
  Proxmox sizes live on `pve`, not here.
- [ ] **Step 2:** `git add`; all seven NixOS/darwin configurations evaluate;
  `nix flake check --no-build --keep-going` passes.
- [ ] **Step 3:** Build both toplevels on nixos-manager (bundle procedure). Expected:
  success.
- [ ] **Step 4:** Commit: `feat(router): router and router-test hosts`.

### Task 6: Test on VM 230

**Interfaces:**
- Consumes: VM 230 from Task 1, `nixosConfigurations.router-test`.

- [ ] **Step 1 (user, Tailscale admin console):** add to the policy, then create
  Service `svc:test-whoami-test` (port tcp:443) and later the real ones:
  ```json
  "tagOwners":     { "tag:router": ["autogroup:admin"] },
  "autoApprovers": { "routes": { "10.0.10.0/24": ["tag:router"] },
                     "exitNode": ["tag:router"],
                     "services": { "tag:router": ["tag:router"] } },
  "grants": [
    { "src": ["Waayway@github"], "dst": ["tag:router"], "ip": ["tcp:53", "udp:53"] },
    { "src": ["Waayway@github"], "dst": ["svc:*"],       "ip": ["tcp:443"] },
    { "src": ["Waayway@github"], "dst": ["10.0.10.0/24"], "ip": ["*"] },
    { "src": ["Waayway@github"], "dst": ["autogroup:internet"], "ip": ["*"] }
  ]
  ```
  (Check the exact `autoApprovers.services` and `svc:*` syntax in the console's
  policy editor; it validates on save.)
- [ ] **Step 2:** Switch VM 230: as `nixos`, clone the repo to `~/build` from a
  bundle and `sudo nixos-rebuild boot --flake ~/build#router-test`, reboot. Expected:
  it comes back on `10.0.10.230`, `tailscale status` shows `router-test` tagged
  `tag:router`, `systemctl is-active traefik coredns tailscale-serve` → active.
- [ ] **Step 3: Public path** from nixos-manager:
  - `curl -sk --resolve whoami-test.vanwaaij.com:443:10.0.10.230 -H 'X-Homelab-Via: tailnet' https://whoami-test.vanwaaij.com`
    → 200, output has no `X-Homelab-Via` line;
  - same with `--resolve nope.vanwaaij.com:443:10.0.10.230 https://nope.vanwaaij.com` → 404;
  - `curl -sI http://10.0.10.230/ -H 'Host: whoami-test.vanwaaij.com'` → 301/308 to https;
  - `curl -skI --resolve jellyfin.vanwaaij.com:443:10.0.10.230 https://jellyfin.vanwaaij.com`
    → Jellyfin answers; `ap.` → 401 without credentials;
  - certificate issuer is the LE staging CA (`openssl s_client … | openssl x509 -noout -issuer`).
- [ ] **Step 4: Tailnet path:** after the Service is approved, set its IP as
  `homelab.router.echo.tailnetAddress` in `router-test.nix`, rebuild 230. From atlas:
  `dig +short @<230's tailscale IP> whoami-test.vanwaaij.com` → the Service IP;
  `dig +short @<same> example.com` → an answer;
  `curl -sk --resolve whoami-test.vanwaaij.com:443:<svc IP> https://whoami-test.vanwaaij.com`
  → output contains `X-Homelab-Via: tailnet`.
- [ ] **Step 5:** Fix whatever failed in Tasks 3–5 (commit per fix), repeat until
  Steps 3–4 pass. Leave VM 230 running for the identity work (spec section D).

### Task 7: Move vpn to 118

- [ ] **Step 1:** On `pve`: `qm shutdown 110`, `qm config 110` saved to
  `~/vm110-config.txt` on `pve`. Renumber: rename its disks
  (`lvrename pve vm-110-disk-N vm-118-disk-N` for each), move
  `/etc/pve/qemu-server/110.conf` to `118.conf` with the disk names replaced.
- [ ] **Step 2:** Change its IP: map the disk (`kpartx`/`losetup -P` on the LV), mount
  the root read-write, edit the static address `10.0.10.110` → `10.0.10.118` in
  `/etc/NetworkManager/system-connections/*` (Rocky 10; check
  `/etc/sysconfig/network-scripts/` too), unmount, unmap.
- [ ] **Step 3:** `qm start 118`. Expected: `ping 10.0.10.118` answers and `ping
  10.0.10.110` doesn't; `qm guest cmd 118 network-get-interfaces` shows `.118`.
- [ ] **Step 4 (user):** point the UniFi 51820/udp forward at `10.0.10.118`; confirm a
  WireGuard client connects.

### Task 8: Router VM 110

- [ ] **Step 1:** `qm clone 9000 110 --name router --full --storage local-lvm`,
  `qm set 110 --cores 2 --memory 2048 --onboot 1`, `qm resize 110 scsi0 16G` (check
  the disk name in `qm config 9000`), start.
- [ ] **Step 2:** Switch it to `#router` as in Task 6 Step 2. Expected: on
  `10.0.10.110`, tagged, services active, a production LE certificate in
  `/var/lib/traefik/acme.json` within a few minutes.
- [ ] **Step 3 (user):** create the Services `svc:nextcloud`, `svc:jellyfin`,
  `svc:archipelago`, `svc:traefik` (tcp:443) and set split DNS `vanwaaij.com` →
  router's Tailscale IP. Record each Service IP as `tailnet.address` in
  `modules/homelab/routes.nix`; commit `feat(homelab): tailnet addresses`;
  rebuild 110.
- [ ] **Step 4:** Run Task 6 Step 3's checks against `10.0.10.110` (production cert:
  drop `-k`) and Step 4's over the tailnet with split DNS on (no `--resolve`):
  `curl -sI https://traefik.vanwaaij.com` from atlas → the dashboard.
- [ ] **Step 5:** `lodestar rebuild router --wait` shows the router in Lodestar once
  nixos-manager runs a revision that lists it (promote after the user's OK).

### Task 9: Cutover

- [ ] **Step 1:** On Main, in `~/nextcloud/docker-compose.yml`: publish the app on
  `10.0.10.100:8080:80` (use another port if 8080 is taken; update the `nextcloud`
  route), `docker compose up -d`. Then
  `occ config:system:set trusted_proxies 1 --value=10.0.10.110` (keep existing
  entries), `extra_hosts` `nextcloud.vanwaaij.com:10.0.10.110`. Keep a copy of the
  original files as `*.pre-router`.
- [ ] **Step 2:** `curl -sI --resolve nextcloud.vanwaaij.com:443:10.0.10.110 https://nextcloud.vanwaaij.com/status.php`
  → 200 with `"installed":true`.
- [ ] **Step 3 (user):** move the UniFi 80/443 forward from `10.0.10.100` to
  `10.0.10.110`.
- [ ] **Step 4:** From outside (phone off Wi-Fi, or a host with `--resolve` to the WAN
  IP): Nextcloud, Jellyfin and `ap.` answer with the new certificate. Then stop Main's
  Traefik and its Tailscale sidecar (`docker compose down` in `~/traefik`; the
  `traefik` tailnet device is removed by the user).
- [ ] **Step 5:** Nextcloud checks: browser login, `/.well-known/caldav` and
  `/.well-known/carddav` → 301 to `/remote.php/dav`, Admin → Overview shows no
  reverse-proxy warnings, `nextcloud.log` shows client IPs, not `10.0.10.110`.
- [ ] **Step 6: Rollback, if any check fails:** user moves the forward back to `.100`;
  `docker compose up -d` in `~/traefik`; restore the `*.pre-router` files.
- [ ] **Step 7: Docs:** `docs/homelab.md` (router VM, vpn → 118, Main no longer
  ingress, Jenkins "moves later" instead of "retired"), AGENTS.md machine table (+
  router, router-test), `docs/lodestar.md` Tailscale policy section (tag:router,
  grants), and a line in `docs/plans/2026-10-12-homelab-backup-plan.md` phase 6 that
  this design supersedes it for Main and media. Commit
  `docs(homelab): router in front`.
