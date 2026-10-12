# Fleet manager

A dashboard on `nixos-manager` that shows which commit of this repo every
machine runs, and pushes "go to commit X and switch" to a small agent on each
machine over Tailscale. Design: `docs/plans/2026-10-12-fleet-manager-design.md`;
implementation plan: `docs/plans/2026-10-12-fleet-manager-plan.md`.

## Branches

- `unstable`: new work lands here. Workstations (laptops, desktop) follow it.
- `stable`: servers follow it. It is the GitHub default branch. Move it forward
  with **Promote** in the dashboard or `fleetctl promote --yes` (fast-forward
  only, needs the server's deploy key; see "Open items").
- `main` is the old branch and is no longer used.

A host's channel comes from its host file (`channel = "stable" | "unstable";`),
default by folder: `hosts/servers/` → `stable`, `hosts/workstations/` →
`unstable`. The agent skips an apply when the host's `~/.flake` is not on its
channel branch, has local changes, or has commits that aren't on GitHub.

## Parts

- `pkgs/fleet/` (cargo workspace):
  - `fleet-proto`: shared types; exported to TypeScript in `web/src/bindings`.
  - `fleet-agent`: root daemon on every enrolled host. Listens on the host's
    Tailscale address, port 7461, and only accepts `nixos-manager`. Runs git and
    the build as the host's user, the switch as root, in a separate process
    (systemd-run / detached) so a switch that restarts the agent can't kill it.
  - `fleet-server`: dashboard + API on `nixos-manager` (100.92.102.84:8080).
    SQLite (SeaORM), a git mirror of the repo, `tailscale status/whois` for
    on/off state and access, WebSocket for live updates, embedded frontend.
    `fleet-server demo` runs it against a simulated fleet.
  - `fleetctl`: CLI for the same API.
  - `web/`: Preact + shadcn/ui dashboard (Vite, Tailwind).
- `modules/fleet/`:
  - `agent.nix` (`services.fleet-agent`, systemd on NixOS, launchd on darwin;
    also installs `fleetctl`).
  - `server.nix` (`services.fleet-server`, NixOS only, runs as user
    `fleet-server`, made a Tailscale operator for status/whois).
  - `audit-hook.nix`: every activation (also manual rebuilds and boots) is
    logged to `/var/lib/fleet-agent/activations.jsonl` and shows up in the
    dashboard's audit log.
- Both services open their port on `tailscale0` only.

## Enrolling a host

1. In its host file: `fleet = true;` (and `channel = ...` to override).
2. Make sure `~/.flake` is a clean checkout of its channel branch tracking
   `origin` (`https://github.com/Waayway/nixos-config`).
3. Switch it once by hand. It shows up in the dashboard when the server can
   reach port 7461 over Tailscale.

## Using it

Dashboard: http://nixos-manager:8080 (only your own tailnet devices get in).

```sh
fleetctl status                          # host, os, channel, online, running, behind, last apply
fleetctl rebuild hermes --wait           # force rebuild: re-applies the channel head even if the
                                         # host already runs it; exit 0 only if it ended ok
fleetctl rebuild --channel stable --wait [--timeout 900]
fleetctl log hermes [APPLY_ID]           # default: the host's last apply
fleetctl promote [--yes]                 # shows the candidate; --yes moves stable
fleetctl audit --limit 20
nix run .#fleetctl -- status             # without installing
```

`fleetctl` talks to `http://nixos-manager:8080`; override with `--server` or
`FLEET_SERVER`. An offline host answers `unreachable`: the apply is recorded and
the server re-sends it when the host comes back online.

State-changing API calls need the header `X-Fleet: 1` (CSRF guard), e.g.
`curl -X POST -H 'X-Fleet: 1' http://nixos-manager:8080/api/hosts/hermes/apply`.

## Developing

```sh
nix run .#fleet-demo                         # simulated fleet, dashboard at http://127.0.0.1:8080
nix run .#fleet-demo -- --listen 127.0.0.1:18080 --speed 4
nix develop .#fleet                          # cargo, rustc, node 22, sqlite, git
cd pkgs/fleet && nix develop ../..#fleet -c cargo test --workspace
cd pkgs/fleet/web && nix develop ../../..#fleet -c npx vitest run
cd pkgs/fleet/web && FLEET_API=http://127.0.0.1:18080 nix develop ../../..#fleet -c npm run dev
nix build .#checks.aarch64-darwin.fleet-bindings        # TS bindings up to date
```

Linux-only checks run on nixos-manager (see AGENTS.md, "Linux builder"):
`checks.x86_64-linux.fleet-vm` (server, two agents and a git remote in VMs),
`checks.x86_64-linux.fleet-firewall`.

## Tailscale policy

The tailnet uses an explicit grants policy (no allow-all). It contains the
fleet rules: `nixos-manager` → agents on tcp:7461, your devices
(`Waayway@github`, `tag:personal`, `tag:nixos`, `tag:fleet`) → dashboard on
tcp:8080, and SSH to `nixos-manager` for remote builds. Laptops you use
yourself stay untagged: a tag replaces the device's user identity.

## Status (2026-10-12)

- `nixos-manager` runs `stable` from GitHub and is managed by the fleet itself:
  applies from `fleetctl` and the dashboard work end to end (fetch, fast-forward,
  build as user, switch as root, audit trail).
- Verified: Linux packages and the VM test on nixos-manager; the demo; the
  dashboard and `fleetctl` against the real server.
- Not verified yet: the darwin agent (launchd) on a real Mac.

## Open items

1. Write deploy key for promote: create `secrets/nixos-manager.yaml` with a
   GitHub deploy key (write access), declare it with
   `sops.secrets.<name> = { owner = "fleet-server"; mode = "0400"; };` and set
   `services.fleet-server.deployKeyFile`. Add a GitHub ruleset on `stable`
   (no force pushes, linear history).
2. Advertise `tag:fleet` on enrolled Linux hosts (agent module) and fix
   nixos-manager's Tailscale tags (it still carries `tag:server`).
3. Enrol atlas, apollo, hermes and hephaestus (`fleet = true`).
4. `fleetctl rebuild --wait` against the host that runs the server loses its
   connection when that switch restarts the server; it should retry.
5. Agent race: a just-finished apply can rarely be recorded as "interrupted"
   (`fleet-agent/src/apply.rs`, `read_record`): re-read the record after taking
   `apply.lock`.
6. Build and boot the proxmox template once, then migrate the VMs (see the
   design, "Migration of the homelab").
