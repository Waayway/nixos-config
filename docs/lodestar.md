# Lodestar (fleet manager)

[Lodestar](https://github.com/Waayway/lodestar) shows which commit of this repo
every machine runs and applies a channel's newest commit to a host on request:
a dashboard and API on `nixos-manager`, an agent on every enrolled host, over
Tailscale. It used to live in this repo (`pkgs/fleet`, `modules/fleet`); it is
now its own flake. Usage, the CLI, options, the security model and development
(Rust, the demo, the VM test) are in the
[lodestar README](https://github.com/Waayway/lodestar#readme) and its
`docs/operations.md`. This page only covers how this repo uses it.

## Where things live

- `flake.nix`: input `lodestar` (`github:Waayway/lodestar`, nixpkgs follows
  ours). Update with `nix flake update lodestar`.
- `lib/mkSystem.nix` / `lib/mkDarwin.nix`: import
  `inputs.lodestar.nixosModules.default` (agent + server) /
  `inputs.lodestar.darwinModules.default` (agent) on every host, next to
  opnix. They also build the `fleet` specialArg
  (`{ member; channel; }`) from the host file.
- `modules/common/lodestar/agent.nix`: on every host with `fleet = true`, enables
  `services.lodestar-agent` with `user` = the host's user, `channel` = the
  host's channel, `managerHost = "nixos-manager"`,
  `repoUrl = "https://github.com/Waayway/nixos-config"`.
- `modules/server/lodestar/server.nix` (NixOS only, active where
  `services.lodestar-server.enable`): `hosts` from
  `lodestar.lib.hostsFrom` over all our NixOS and darwin configurations,
  `repoUrl`, `pushUrl = "git@github.com:Waayway/nixos-config"`,
  `allowedUsers = [ "Waayway@github" ]`,
  `allowedTags = [ "tag:nixos" "tag:personal" "tag:fleet" ]`; promote keeps the
  module default (`unstable` → `stable`).
- `hosts/servers/nixos-manager.nix`: `fleet = true`, `services.lodestar-server`
  `enable` and `listenAddress = "100.92.102.84"` (its Tailscale IP).

## Branches and channels

- `unstable`: new work; workstations follow it. `stable`: servers follow it;
  GitHub default branch. Move `stable` forward with **Promote** in the
  dashboard or `lodestar promote --yes` (needs the deploy key, open item 1).
- A host's channel: `channel = "stable" | "unstable";` in its host file,
  default by folder (`hosts/servers/` → `stable`, `hosts/workstations/` →
  `unstable`).

## Enrolling a host

1. In its host file: `fleet = true;` (and `channel = ...` to override).
2. Make sure `~/.flake` is a clean checkout of its channel branch with `origin`
   = `https://github.com/Waayway/nixos-config`.
3. Switch it once by hand. It shows up in the dashboard once the server can
   reach it on tcp:7461 over Tailscale (and after nixos-manager has been
   switched to a revision that lists it: the host list is computed at build
   time).

On a Mac, also place the opnix token once (before the first switch), then
switch twice (see "Agent signing on the Macs"):

```sh
NIXPKGS_ALLOW_UNFREE=1 nix shell --impure nixpkgs#_1password-cli -c \
  op read "op://Personal/opnix-homelab service account/credential" |
  sudo install -m 640 /dev/stdin /etc/opnix-token
```

## Agent signing on the Macs

The agent binary (`/var/lib/lodestar-agent/bin/lodestar-agent`) is signed with
one certificate for all Macs, so macOS permissions survive updates:
`modules/common/lodestar/lodestar-agent-signing.pem` (SHA-1
`f546f94d49ec2d267e04f47ad78181c70d282d02`). Its private key is the 1Password
document **Lodestar Agent Signing Key** (vault Homelab, file `key.pem`); opnix
(`modules/common/lodestar/agent.nix`) writes it to
`/var/lib/lodestar-agent/signing/key.pem` with the `opnix-homelab` token in
`/etc/opnix-token`. opnix runs as a launchd daemon (log
`/var/log/opnix-secrets.log`), after the activation that signs, so the first
switch fetches the key and the next one signs. Check with
`codesign -dr - /var/lib/lodestar-agent/bin/lodestar-agent`: it must name
`certificate leaf = H"f546f94d…"`.

## Using it

Dashboard: http://nixos-manager:8080. The `lodestar` CLI is installed on every
enrolled host with `LODESTAR_SERVER=http://nixos-manager:8080`:

```sh
lodestar status
lodestar rebuild hermes --wait
lodestar rebuild --channel stable --wait
nix run github:Waayway/lodestar -- status   # without installing
```

## Public URL

`https://lodestar.vanwaaij.com` (route `lodestar` in `modules/server/lodestar/server.nix`:
public and on the tailnet, not behind the gate; Lodestar logs in with Kanidm itself).
The router forwards to nixos-manager's proxy listener `10.0.10.170:8081`, which only the
router (`10.0.10.110`, `trustedProxies`) can reach: the firewall opens that port for
this source only and the server answers other peers with 403. The tailnet dashboard
(`http://nixos-manager:8080`) and the CLI are unchanged.

Who sees what:

- anonymous: a reduced Services feed (title, group, description, icon, up/down) and a
  **Log in** button;
- Kanidm group `lodestar-users` (`thijs`): the whole dashboard, read-only;
- Kanidm group `admins`: may also apply and promote, but only on requests that arrive
  over Tailscale (the router's tailnet entrypoint sets `X-Homelab-Via: tailnet`);
  elsewhere the buttons read "Only over Tailscale". An admin must **also be in
  `lodestar-users`**: Kanidm's scope map exists only for that group, so a user in
  `admins` alone is refused by Kanidm at login.

The Kanidm client `lodestar` is provisioned from `homelab.access.lodestar`
(redirect `https://lodestar.vanwaaij.com/auth/callback`, short user names, scopes
`openid profile groups`). Like every client, Kanidm generates its secret. It goes into
the 1Password item `kanidm-oauth2-lodestar` (Homelab vault, field `credential`; created
with `scripts/kanidm-oauth2-secret.sh lodestar` from atlas, Touch ID) and is delivered
to `/var/lib/opnix/secrets/kanidmOauth2Lodestar` (owner `lodestar-server`, mode 0400).
The server reads the file at each login, so a rotated secret needs no restart. Groups
come from the ID token at login: a membership change applies at the next login.

Policy grants (set 2026-10-20): nixos-manager uses MagicDNS, so `id.vanwaaij.com` resolves
to the tailnet Service `svc:id`. The host `nixos-manager` (it carries `tag:server`, not
`tag:manager`, see open item 2) has grants to the router on port 53 (split DNS) and to
`svc:id` on tcp:443. The Tailscale Service `lodestar` is granted to the same sources as
the other Services and auto-approved for `tag:router`. The router reaches the listener
over the LAN: no grant. The Services link of
this dashboard and Kanidm's "Services" tile (`homelab.identity.servicesUrl`) point to
`https://lodestar.vanwaaij.com`.

## nixos-manager

- Services: `lodestar-server.service` (user `lodestar-server`, state in
  `/var/lib/lodestar-server`: `lodestar.db`, `mirror.git`) and
  `lodestar-agent.service` (root, state in `/var/lib/lodestar-agent`). Config:
  `/etc/lodestar-server/{config,hosts}.json`, `/etc/lodestar-agent/config.json`.
- Ports 8080 and 7461 are opened on `tailscale0` only; 8081 (public URL) for the router's
  address only.
- Its `~/.flake` is a clean checkout of `stable` that the agent manages; don't
  build or edit there (see AGENTS.md, "Linux builder").

## Tailscale policy

The tailnet uses an explicit grants policy (no allow-all) with these rules:
`nixos-manager` → agents on tcp:7461 (the agents are `tag:fleet`, `tag:router` and
`tag:prod` hosts); your devices (`Waayway@github`,
`tag:personal`, `tag:nixos`, `tag:fleet`) → dashboard on tcp:8080; SSH to
`nixos-manager` for remote builds. Laptops you use yourself stay untagged: a
tag replaces the device's user identity.

Identity additions (2026-10-20, edited through the API): `tag:identity` (owned by
`autogroup:admin` and `tag:nixos`, like every server tag); `tag:identity` → `tag:router`
on port 53; `nixos-manager` → `tag:identity` on tcp:7461; Tailscale Services `id` and
`auth` (plus `truenas`, `backrest`), advertised by the router; `tag:prod` → `svc:id` on
tcp:443 so Nextcloud, Immich and Jellyfin can reach Kanidm. A new host that runs an
OIDC app needs the same grant to `svc:id`. After creating a Service, run
`tailscale serve drain svc:X` and `advertise svc:X` on the router. There is no SSH rule
for `tag:identity` yet (homelab.md finding 25). See `docs/identity.md`.

Monitoring additions (2026-10-22): `tag:monitor` (owned by `autogroup:admin` and
`tag:nixos`); `tag:monitor` → `tag:router` on port 53; `tag:monitor` added to the sources
of the Services grant (uptime probes of every route, and Grafana's sign-in through
`svc:id`); `nixos-manager` → `tag:monitor` on tcp:7461; Service `grafana`, auto-approved
for `tag:router`. The auto-approval didn't take when the router already advertised the
Service before it was created: `tailscale serve drain svc:grafana`, wait a few seconds,
`advertise` again (both in one go was too fast). See `docs/monitoring.md`.

## Open items

1. Write deploy key for promote: put a GitHub deploy key (write access) in
   the 1Password vault Homelab (item `lodestar-deploy-key`), declare it with
   `services.onepassword-secrets.secrets.lodestarDeployKey = { reference =
   "op://Homelab/lodestar-deploy-key/private key"; owner = "lodestar-server";
   mode = "0400"; services = [ "lodestar-server" ]; };` and set
   `services.lodestar-server.deployKeyFile =
   config.services.onepassword-secrets.secretPaths.lodestarDeployKey` (in
   `hosts/servers/nixos-manager.nix`). Add a GitHub ruleset on `stable` (no
   force pushes, linear history).
2. Advertise `tag:fleet` on enrolled Linux hosts (Lodestar has no option for
   it yet; use `services.tailscale.extraUpFlags`) and fix nixos-manager's
   Tailscale tags (it still carries `tag:server`).
3. Enrol hephaestus (`fleet = true`); atlas, apollo and hermes are enrolled.
4. Migrate the VMs (template 9000 is built from `template/proxmox.nix` and
   boot-tested since 2026-10-13; see
   `docs/plans/2026-10-12-homelab-backup-plan.md`, phase 6).
5. An apply where 1Password is unreachable ends with exit 4 because only
   `opnix-secrets` failed; the new generation is active and the old secret
   files stay. Show that as "applied, secrets not refreshed" instead of a
   failed apply.
