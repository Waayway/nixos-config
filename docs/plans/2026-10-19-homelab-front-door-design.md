# Homelab front door: design

One router VM in front of everything the homelab serves, one login (Kanidm) for every
app, and Lodestar on a real URL that is read-only from the internet and fully usable
over Tailscale. Replaces Main (VM 100) as ingress and, later, Main and media as the
place the apps run.

Status: approved in conversation 2026-10-19 (all sections). Implementation plans per
part, starting with the template and the router.

This supersedes phase 6 of `2026-10-12-homelab-backup-plan.md` for Main and media
(Traefik moves to its own router VM; Nextcloud, Jellyfin and Immich share one
production VM).

## Goals

- `lodestar.vanwaaij.com` always works. Off the tailnet: the Services tab, read-only.
  On the tailnet: the full dashboard, and actions for Lodestar admins.
- Every app is reachable by the same name from the internet and from the tailnet; on
  the tailnet the traffic goes over Tailscale Services.
- One routing server (Traefik) that a new app joins with one Nix declaration.
- One self-hosted login for every app; users and access declared in Nix, next to the
  services ("rebuild and go").

## Decisions

- **Port forward, not Cloudflare Tunnel.** The tunnel caps uploads at 100 MB per
  request (Immich uploads videos in one request) and Cloudflare's terms forbid serving
  mostly video (Jellyfin) through it. Jellyfin and Immich need a port forward anyway,
  so the tunnel would only add a second way in. Cloudflare stays the DNS provider (and
  DNS-01 for certificates); records are DNS-only.
- **Same name on both paths via split DNS**, not two URLs. On the tailnet, Tailscale's
  split DNS sends `vanwaaij.com` lookups to a resolver on the router that answers
  `<app>.vanwaaij.com` with the app's Tailscale Service IP.
- **Kanidm as identity provider** (considered: Authelia, Authentik, Pocket ID).
  Declarative provisioning in NixOS (`services.kanidm.provision`), passkeys and TOTP
  built in, one Rust binary. Apps without OIDC get `oauth2-proxy` in front.
- **Kanidm on its own VM at home** (considered: on the router; on Hetzner). Separation
  of concerns; behind the same front door as everything else. Hetzner only becomes
  worth it if the tailnet itself logs in through Kanidm (it removes the
  chicken-and-egg of remote access depending on the homelab); moving is a backup
  restore plus a DNS change.
- **The tailnet stays on GitHub, free plan.** Custom OIDC on Tailscale means a custom
  domain tailnet (business use, paid) and a support request to switch an existing
  tailnet. Maybe later.
- **WireGuard stays for now.** Others use it (Jellyfin and their provider's TV app
  over the home connection). Replacing it with a shared Tailscale exit node is
  possible later; not part of this design.
- **Lodestar identity from the login, not from the source IP.** Behind Traefik and
  Tailscale Services the peer address is lost; OIDC plus a header that only Traefik's
  tailnet entrypoint sets (and its public entrypoint strips) replaces `whois` for
  browser access. The CLI keeps the direct tailnet listener.

## Machines

The IP's last octet is the VMID (notes on `pve`). New VMs are cloned from template
9000 onto `local-lvm`.

| VMID | IP | Name | Role | Size |
|---|---|---|---|---|
| 100 | 10.0.10.100 | prod (new) | Nextcloud, Jellyfin (GPU), Immich | 6 cores, 16 GB, 64 GB root |
| 108 | 10.0.10.100 until C | Main (old) | renumbered from 100 during C, then shut down | as is |
| 110 | 10.0.10.110 | router | Traefik, CoreDNS, Tailscale Services, oauth2-proxy, subnet route, exit node | 2 cores, 2 GB, 16 GB root |
| 111 | 10.0.10.111 | identity | Kanidm | 1 core, 2 GB |
| 118 | 10.0.10.118 | vpn (old) | renumbered from 110, WireGuard keeps running | as is |
| 120 | 10.0.10.120 | media (old) | shut down after C | as is |
| 230 | 10.0.10.230 | router-test | test VM for the template, router and identity configs | 1 core, 2 GB |

Last of all, after C: delete Main (108) and media (120).

## Template 9000 (agreed)

Before any clone: bring `template/proxmox.nix` up to the current nixpkgs and modules,
build the image on nixos-manager, replace template 9000 and boot-test it (VM 230 is
the first clone).

## A. Router, VM 110 (agreed)

### Traffic

- **Public:** internet → UniFi port forward 80/443 → `10.0.10.110` → Traefik
  entrypoint `public` (80 only redirects to HTTPS).
- **Tailnet:** device → Tailscale Service (`svc:lodestar`, `svc:jellyfin`, …)
  advertised by the router → Traefik entrypoint `tailnet`, which sets
  `X-Homelab-Via: tailnet`. The public entrypoint strips that header.
- **Certificates:** one Let's Encrypt wildcard `*.vanwaaij.com` via Cloudflare DNS-01,
  used by both entrypoints. Token in 1Password Homelab (`cloudflare-dns-token`, moved
  there from Main's `~/traefik/.env`), delivered by opnix.
- **Split DNS:** CoreDNS on the router answers `<app>.vanwaaij.com` with the app's
  Tailscale Service IP and forwards everything else. Tailscale admin: split DNS
  `vanwaaij.com` → the router.
- **Tailscale:** the router also advertises `10.0.10.0/24` (subnet route) and an exit
  node.

### Routes as code

`homelab.routes.<name>`, declared next to the service:

```nix
homelab.routes.jellyfin = {
  host = "jellyfin.vanwaaij.com";
  backend = "http://10.0.10.120:8096";
  public = true;      # Traefik public entrypoint
  tailnet = true;     # Tailscale Service svc:jellyfin + split-DNS record
  auth.gate = false;  # true: oauth2-proxy forward-auth (section D)
};
```

The router collects every `homelab.routes` in the flake (as Lodestar collects
`lodestar.links`) and generates Traefik routers, the `tailscale serve --service`
config and CoreDNS records. Routes for backends this flake doesn't manage yet (Main,
media, archipelago) are declared by hand in `modules/homelab/routes.nix`, active on the
router only, like `modules/homelab/links.nix`. Lodestar's Services links can be derived
from the same data.

Tailscale assigns each Service its IP when the Service is created in the admin
console; that IP is recorded in the route (`tailnet.address`) so CoreDNS can answer
for it. A route with `tailnet = true` and no address yet is served publicly only and
reported by an evaluation warning.

LAN devices without Tailscale resolve the public record and reach the router through
UniFi's NAT loopback (hairpin); no LAN DNS override is part of this design.

Initial routes point at today's backends: Nextcloud on Main, Jellyfin on 120, `ap.` on
201 (keeps its basic auth until the gate exists).

### Build and cutover

1. Repo: template refresh, `hosts/servers/router.nix`, the routes module, Traefik,
   CoreDNS, Tailscale. Evaluate all hosts, build on nixos-manager.
2. **Test VM 230** (Claude, on `pve`): same config under its own hostname and test
   `svc:` names; check every route with `curl --resolve` from the LAN and over the
   tailnet.
3. **vpn → 118** (Claude, on `pve`): stop VM 110, renumber to 118, set its IP to
   `10.0.10.118` by editing its network config on the stopped disk from `pve` (no
   login into the VM works), start, check WireGuard answers. **User:** point the 51820/udp forward in
   UniFi at `10.0.10.118`.
4. **Router 110** (Claude): clone 9000, `sudo opnix token set`, switch to the config.
5. **Tailscale admin console** (user, or Claude via an OAuth client in 1Password
   Homelab): create the Services, approve the router as host and its subnet route and
   exit node, split DNS, grants (snippet in the plan).
6. Router runs alongside Main; every name tested against `10.0.10.110` and over the
   tailnet.
7. Nextcloud on Main publishes its port on `10.0.10.100`; `trusted_proxies` gets
   `10.0.10.110`; its hairpin entry `nextcloud.vanwaaij.com` → `.110`.
8. **User:** move the 80/443 forward from `.100` to `.110`. Then stop Main's Traefik
   and its Tailscale sidecar `traefik`; the Traefik dashboard becomes `svc:traefik`.
9. **Rollback:** move the forward back to `.100` and start Main's Traefik. Nothing on
   Main is deleted.

### Risks

- CoreDNS on the router is a single point for `*.vanwaaij.com` on the tailnet;
  acceptable for the front door, watched by Lodestar's Services tab.
- DNS-01 needs no port forward, so certificates exist before the cutover.

## D. Identity, VM 111 (agreed)

- Kanidm only. Domain **`id.vanwaaij.com`** (hard to change later). Own Let's Encrypt
  certificate (DNS-01); Traefik passes `id.vanwaaij.com` through without terminating
  TLS. Public, and `svc:id` on the tailnet.
- **Two-factor:** passkeys preferred; password + TOTP allowed. Credential policy per
  group: `admins` and `lodestar-admins` require a passkey; nobody may use a password
  alone.
- **No mail server:** Kanidm sends no e-mail. New people and recoveries get a one-time
  link or QR code (`kanidm person credential create-reset-token <name>`), sent by
  hand. Logged-in users add their own devices.
- `idm_admin` password and every OIDC client secret in 1Password Homelab via opnix.
- **Login gate:** `oauth2-proxy` on the router as a Traefik forward-auth middleware,
  for apps without OIDC: `ap.` (replaces its basic auth), the Traefik dashboard,
  TrueNAS, Backrest.
- **Down:** new logins fail, existing sessions continue. Each app keeps one local
  break-glass admin in 1Password (Proxmox `root@pam`, TrueNAS admin, Nextcloud admin).
- **Backup:** Kanidm's online backup daily to `/store/kanidm` (NFS), picked up by the
  existing restic job.
- Tested on VM 230 first.

### Access as code

People are declared once; each service declares its own group, members and OIDC
client next to the service:

```nix
# modules/identity/people.nix
homelab.people = {
  thijs = { displayName = "Thijs"; email = "thijs@vanwaaij.com"; admin = true; };
};

# in the Jellyfin module
homelab.access.jellyfin = {
  members = [ "thijs" ];
  oidc.redirectUris = [ "https://jellyfin.vanwaaij.com/sso/OID/redirect/kanidm" ];
};

# a gated route
homelab.routes.archipelago = { host = "ap.vanwaaij.com"; auth.gate = true; };
homelab.access.archipelago.members = [ "thijs" ];
```

The identity VM collects every `homelab.access` and `homelab.people` in the flake into
`services.kanidm.provision` (group `<name>-users` per service, an OAuth2 client where
`oidc` is set). Changing members is a rebuild of the identity VM; a new OIDC client
also rebuilds the service's VM. Lodestar can apply both.

### What can use it

| Service | Where now | Moves to | How |
|---|---|---|---|
| Nextcloud (+ Collabora) | Main 100 | prod 100 | native, `user_oidc` |
| Immich | media 120 (stopped) | prod 100 | native |
| Jellyfin | media 120 | prod 100 | SSO plugin in the browser; TV/phone apps use Quick Connect or a password |
| Proxmox VE | `pve` | stays | native OpenID realm; `root@pam` stays as break-glass |
| Lodestar | nixos-manager 170 | stays | native, to build (section B) |
| Jenkins | deploy-box 105 | later its own VM (170–179) or custom software | `oic-auth` plugin |
| TrueNAS UI | 130 | stays | gate (no native OIDC outside the paid TrueNAS Connect) |
| Traefik dashboard | Main 100 | router 110 | gate |
| Backrest | nixos-manager 170 | stays | gate |
| Archipelago web | 201 | stays | gate (game ports 50000–50010 are plain TCP, outside Traefik) |
| BlueMap | 200 (stopped) | stays | public map, none |
| WireGuard | vpn 110 → 118 | stays for now | keys, none |
| Tailscale | SaaS | — | possible later, see Decisions |

## B. Lodestar at lodestar.vanwaaij.com (agreed)

| Who | Path | Gets |
|---|---|---|
| anyone | public, not logged in | Services tab, read-only, all links with their state |
| logged in | public or tailnet | full dashboard, read-only |
| `lodestar-admins` | tailnet | everything, including rebuild and promote |
| `lodestar-admins` | public | read-only; actions show "only over Tailscale" |

Lodestar repo:

1. OIDC login (authorization code + PKCE), session cookie. Options `oidc.issuer`,
   `oidc.clientId`, `oidc.clientSecretFile`, `oidc.adminGroup`.
2. A second listener for Traefik on `10.0.10.170`, firewalled to the router. It
   trusts `X-Homelab-Via: tailnet` only from `trustedProxies` (`10.0.10.110`).
3. The tailnet listener stays as it is (`tailscale whois`), for the CLI.
4. CSRF rules unchanged (`X-Lodestar: 1`, same-origin).
5. VM test with Kanidm: anonymous sees only the Services tab; login works; actions without
   the header, or with it from an untrusted address, are refused.

This repo: `homelab.routes.lodestar` (public + tailnet, backend the new listener),
`homelab.access.lodestar`, the Lodestar link URL becomes
`https://lodestar.vanwaaij.com`.

All links are visible to anonymous visitors, on purpose: the repo is public and
`modules/homelab/links.nix` already lists them, internal URLs (LAN, `*.ts.net`) are not
reachable from the internet, and the page doubles as a public overview of what the
homelab hosts. The only extra thing it reveals is live up/down state.

## C. Production, VM 100 (agreed)

### VM

- VMID 100, `10.0.10.100`, hostname `prod`: 6 cores, 16 GB RAM, 64 GB root on
  `local-lvm` (about 100 GB free there: fits, but getting full). All data stays on
  TrueNAS over NFS.
- The WX7100 passthrough moves from media (120); media must be off before 100 starts.
- Open: the WX7100 may be replaced by a newer GPU (AV1, HDR tone mapping, Immich ML
  acceleration); the user is choosing one. The design only assumes one GPU passed
  through to VM 100.
- Old Main is renumbered 100 → 108 on `pve` while it is stopped for the Nextcloud
  move (renaming its disks needs the VM off). Its IP inside the VM stays `.100`; it is
  never started again after the move, so the new VM 100 can take `.100`.

### Nextcloud

- `services.nextcloud` on the same major version (32); moving to 33 is a separate
  step afterwards.
- MariaDB, current LTS, restored from a fresh dump of 10.7 (no switch to PostgreSQL:
  an extra migration for no real gain).
- Data stays on `/store/nextcloud/data`. Redis for caching and locking.
  `services.collabora-online` on its own subdomain.
- Kanidm login via `user_oidc`; existing accounts linked by username.
- Move: maintenance mode on → dump → stop the old containers → restore → `occ
  upgrade` check → router route to `10.0.10.100`. Rehearsed first on a clone at 230.

### Jellyfin

- `services.jellyfin` with VA-API on the WX7100.
- Config stays on `/store/jellyfin`, so libraries, users and watch progress carry
  over. Library read-only from `archive/shares`.
- SSO plugin in the browser; TV apps keep a password or Quick Connect.

### Immich

- `services.immich`, library on `/store/immich` (52 GB already there), database dumps
  to `/store/db-dumps/immich`.
- Machine learning on the CPU: the WX7100 (Polaris) is too old for current ROCm.
  Slower first indexing, otherwise fine.
- Start fresh (decided 2026-10-19): the library on `/store/immich` is re-imported
  and re-indexed; the old database on media is not migrated (albums, faces and sharing
  are rebuilt by hand).

### Not moving

jellyfetch (qBittorrent + ProtonVPN, exited since August) and voice-memo (deprecated).

### Old VMs

Main (108) and media (120) stay shut down. Deleting them is the very last step.

## Order

1. Template 9000 refresh.
2. A: router (test on 230, vpn → 118, router 110, cutover).
3. D: identity (Kanidm on 111, oauth2-proxy on the router).
4. B: Lodestar (lodestar repo, then this repo).
5. C: production VM 100.
6. Delete Main (108) and media (120).

Each part gets its own implementation plan (`2026-10-19-homelab-front-door-<part>-plan.md`).
