# Fleet manager: dashboard + push agent (design)

Date: 2026-10-12. Status: draft, waiting for review.

## Goal

One place on the homelab that shows which commit of this repo every machine
(servers and laptops) is running, and an **"apply newest"** button. Pressing
it tells the machine to update itself; nothing updates without that press.
Alongside this, the homelab VMs move from Rocky/Debian to NixOS, managed from
this repo.

## Decisions so far

- **Dashboard** that lists every system and the commit it's on.
- **Push over the tailnet.** Every machine runs a small daemon that listens on
  its Tailscale address and accepts requests **only from nixos-manager**.
  "Apply newest" makes the server send "go to commit X and switch" to the
  machines.
- **Every machine builds from `~/.flake`** in the main user's home.
- **Dirty or diverged checkout: skip and report.** The daemon never touches
  local changes. The dashboard shows why it skipped ("dirty", "2 commits ahead").
- **Per-device button plus "apply to all".**
- **Two branches:**
  - `unstable` (renamed from `main`): new work lands here. Laptops always follow it.
  - `stable`: servers follow it. Unstable is promoted to stable when ready.
    VMs are migrated to NixOS on this branch.
- Works on NixOS **and** nix-darwin (atlas and apollo are Macs).
- **Rust**, server and agent in one cargo workspace in this flake (`pkgs/fleet/`).

## Why not an existing tool

| Option | Why not (alone) |
|---|---|
| DAWO-Sextant | NixOS only by design. OIDC/LDAP, PXE imaging, compliance: about 80% would have to go. Beta, one maintainer. |
| comin | Pull-based but auto-applies every new commit (no button), NixOS only. |
| deploy-rs / colmena | Push over SSH, builds on the deployer. No dashboard, and doesn't use the machine's own `~/.flake`. |
| Clan | A whole framework to adopt. Darwin support is still growing. |

What's left to build is small: a server with a web page, and an agent with a
tiny HTTP API that runs `git` and `*-rebuild`.

## Architecture

```
                                  tailnet
 ┌──────────────────────────┐  GET  /status   (every 60s)  ┌──────────────────────┐
 │ fleet server             │ ───────────────────────────▶ │ fleet agent          │
 │ (nixos-manager, .170)    │  POST /apply {commit}        │ (every machine, root)│
 │  - web dashboard (Preact)│ ───────────────────────────▶ │  listens on its      │
 │  - state store           │  GET  /apply/log,            │  Tailscale IP only,  │
 │  - bare mirror of repo   │       /activations           │  accepts only        │
 │                          │ ───────────────────────────▶ │                      │
 └──────────────────────────┘                              │  nixos-manager       │
            │ git fetch (every few min)                    └──────────────────────┘
            ▼
   github.com/Waayway/nixos-waayway  (branches: unstable, stable)
```

All connections go **from** the server **to** the agents. Agents never call
the server.

### Channels

- Each host file declares its channel, for example `fleet.channel = "stable";`.
  Hosts in `hosts/servers/` default to `stable`, hosts in `hosts/workstations/`
  to `unstable`.
- **Promote** (dashboard button, or plain `git push`): fast-forward `stable` to
  a commit on `unstable`. The server only offers a commit if it's an ancestor
  of `unstable`.
- To push `stable`, the server needs write access to the GitHub repo: a deploy
  key with write access, stored with sops (`secrets/nixos-manager.yaml`).
  With GitHub branch protection, only fast-forwards to `stable` are allowed.

### Fleet server

- Packaged in this flake and enabled with a NixOS module (`services.fleet-server`).
- **Host list** comes from the flake itself (every host with the fleet agent
  enabled), with its Tailscale name. No separate inventory.
- Keeps a bare mirror of the repo, fetched every few minutes, for branch
  heads and the commit messages between "running" and "newest".
- **Status polling:** every 60s it calls `GET /status` (and `GET /activations`)
  on every host that Tailscale reports online. See "Online state".
- **Dashboard**, one row per host:
  - name, OS, channel
  - commit it's running, and how many commits behind its channel head
  - local checkout state: branch, clean/dirty, ahead/behind
  - on/off (from Tailscale), last seen
  - last built (last activation) and by whom
  - status of the last apply, with its log
  - an **Apply newest** button
- Above the table: an **Apply newest to all on `<channel>`** button per channel,
  and **Promote unstable → stable**.
- **Apply newest** sends `POST /apply {commit}` (the channel head at the moment
  you press) to the host(s). It also stores that as the host's *desired commit*:
  a laptop that's asleep or offline gets the request **re-sent automatically**
  the next time a status poll reaches it and it's still behind. Pressing again
  replaces the desired commit with the new head.

### Fleet agent

- Rust, a second binary in the same workspace.
  - NixOS: systemd service. Darwin: launchd daemon.
- Runs as root because the rebuild needs it. Every `git` command runs as the
  main user (`sudo -u <user> git -C ~/.flake …`), so file ownership and
  `safe.directory` stay right.
- **Git access:** the agent fetches with the user's own Git setup. A launchd or
  systemd daemon has no login session, so it can't reach the macOS keychain
  or a `gh` credential helper. The `~/.flake` remote must therefore use **SSH
  with a key file** (no passphrase-only agent), or a read-only deploy key
  that the agent passes through `GIT_SSH_COMMAND`. Check this per host at
  enrollment.
- **API** (only on the Tailscale address):
  - `GET /status`:
    - the running system's commit (`system.configurationRevision`, see below)
    - the `~/.flake` HEAD and branch, clean or dirty, ahead/behind origin
    - the state of the current or last apply (idle / running / ok / skipped / failed + reason)
  - `POST /apply {commit}`: starts an apply in the background and returns
    immediately (`202`). Returns `409` if one is already running.
  - `GET /apply/log`: output of the current or last apply.
  - `GET /activations?since=<n>`: activation lines for the audit log.
- **Apply:**
  1. `git fetch origin`.
  2. Checks. Any of these → **skip**, record the reason, don't touch anything:
     - the checkout is dirty
     - the checkout isn't on the host's channel branch
     - the checkout has commits not on origin
     - the commit isn't reachable by fast-forward
  3. `git merge --ff-only <commit>`.
  4. Rebuild:
     - NixOS: `nixos-rebuild switch --flake ~/.flake#<host>`
     - Darwin: `darwin-rebuild switch --flake ~/.flake#<host>`
  5. Record success or failure and keep the log. A failed build doesn't
     switch, so the old system keeps running. The checkout stays on the new
     commit, and the dashboard shows "checkout ahead of running system".
- Only one apply at a time. The server sends a commit hash, never a command;
  the agent validates it as a 40-character hex hash.

### Audit log

Every entry has a time, host, kind, actor and details. Sources:

1. **Dashboard actions:** apply, apply to all, promote. The actor is the Tailscale
   identity of whoever pressed the button.
2. **Agent commands:** every command the agent runs (`git fetch`,
   `git merge --ff-only`, `*-rebuild switch`) with start and end time, exit
   code and log. The agent reports these through `GET /status` and the apply log.
3. **Every activation, including manual ones** (the hook into the nix command):
   - A fleet module adds an activation script to every system: `system.activationScripts`
     on NixOS, `system.activationScripts.postActivation` on darwin.
   - It runs on every switch, whether it came from the dashboard or from a
     hand-typed `darwin-rebuild switch`. It appends one JSON line to
     `/var/lib/fleet-agent/activations.jsonl`:
     - time
     - `configurationRevision` (including `-dirty`)
     - store path
     - generation number
     - trigger: `FLEET_APPLY_ID` when the agent ran it, otherwise `SUDO_USER`
   - The agent serves it at `GET /activations?since=<n>`. The server copies new
     lines into `audit_events` on every poll, so an offline machine catches up later.
   - "Last built" on the dashboard is the last activation, so it's also right
     after a manual switch.

Nix's `post-build-hook` is not used: it fires for every derivation built, and
not on activation.

### Online state

- The server reads Tailscale's status on nixos-manager (LocalAPI
  `/localapi/v0/status`, the same data as `tailscale status --json`). Per peer
  it takes: online/offline, last seen, OS, Tailscale IPs.
- The dashboard combines that with the agent poll into one state per host:
  - **off**: Tailscale says offline. Shows "last seen …".
  - **on, agent unreachable**: Tailscale online, but `GET /status` fails.
  - **on**: both answer.
- The server only polls agents that Tailscale reports online, and re-sends a
  pending apply as soon as a host goes from off to on.
- The agent's address comes from the same status data (MagicDNS name or IP), so
  the host list needs no IPs.

### Knowing which commit is running

Set `system.configurationRevision = inputs.self.rev or inputs.self.dirtyRev or "unknown";`
in `lib/mkSystem.nix` and `lib/mkDarwin.nix`. The agent reads it from
`nixos-version --configuration-revision` or `darwin-version --configuration-revision`.
A build from a dirty tree shows up as `<rev>-dirty`.

### Access control

- **Agents** listen only on their Tailscale IP and accept only requests from
  nixos-manager's Tailscale IP. Two layers:
  - Tailscale ACL: only `tag:manager` may reach `tag:fleet` on the agent port.
  - The agent itself rejects any other source IP.
- **Dashboard** listens only on nixos-manager's Tailscale address. Buttons only
  work for the user `Waayway@` (checked with Tailscale `whois`); others get
  read-only access, or none (open question 1).

## Technology choices

1. **Communication:** the server pushes to the agents over plain HTTP on the
   tailnet; agents never call the server (see Architecture).
2. **Backend:** Rust with axum (tokio), serving a JSON API under `/api` and the
   built frontend.
3. **Frontend:** Preact + `preact/compat`, the official shadcn/ui components,
   Vite, Tailwind v4, TypeScript. Nix builds it with `buildNpmPackage`; the
   output is embedded in the server binary (`rust-embed`), so nixos-manager runs
   one binary. In development, Vite's dev server proxies `/api` to the Rust server.
4. **Storage:** SQLite in `/var/lib/fleet-server`, through the **SeaORM** ORM
   (async, on sqlx). Entities and migrations are written in Rust
   (`sea-orm-migration`) and run at startup.
5. **Audit log:** three sources, one `audit_events` table (see "Audit log").
6. **On/off state** comes from Tailscale (see "Online state").
7. **Live updates:** a WebSocket between dashboard and server (`/api/ws`,
   axum's built-in support). The server pushes host changes, apply progress
   and log lines as typed JSON messages; the frontend reconnects with backoff
   and asks for a full snapshot after reconnecting.
8. **Actions are REST:** buttons are `POST /api/...` requests (apply, apply to
   all, promote). Each request is checked with Tailscale `whois`, written to the
   audit log, and answered with a status (`202`, `409` if already running).
   The WebSocket only carries server → browser updates.
9. **Shared types:** API and WebSocket message types are defined once in Rust
   (`fleet-proto`) and exported to TypeScript with `ts-rs`.
10. **Layout:** cargo workspace in `pkgs/fleet/` with `fleet-proto`,
    `fleet-server` and `fleet-agent`; the frontend in `pkgs/fleet/web/`.
11. **Nix build:** `crane` for the Rust crates (dependencies cached separately),
    `buildNpmPackage` for the frontend.
12. **Agent config** from the NixOS/darwin module (`services.fleet-agent`):
    port (default `7461`), nixos-manager's Tailscale name to accept requests
    from, and main user and channel taken from the host file.

## Migration of the homelab

Today on pve (Proxmox VE 9.1, 5900X, 78 GB RAM):

| ID | Name | Now | Plan |
|---|---|---|---|
| 100 | Main (production) | Rocky 10.2, Docker incl. Traefik | NixOS, services ported (inventory needed) |
| 105 | deploy-box / jenkins-vm | Rocky 10.1 | NixOS, or retire (see open question 3) |
| 110 | vpn | Rocky 10.1 | NixOS |
| 120 | media | Rocky 10.1, GPU passthrough WX7100 | NixOS (amdgpu, passthrough stays) |
| 130 | truenas | TrueNAS 26 beta, HBA passthrough | **stays TrueNAS** (storage appliance) |
| 140 | garage (LXC) | Debian 13, Garage S3 | NixOS VM or NixOS LXC (`services.garage`) |
| 201 | archipelago | unknown, no guest agent | NixOS |
| 200 | minecraft | stopped | NixOS when needed |
| 101 | router | NixOS, stopped | decide (open question 4) |
| 170 | nixos-manager | NixOS, stopped, offline for 55 days | becomes the **fleet server** |
| 9000 | nixos-26.05-template | NixOS image | base for new VMs |

Out of scope: the Proxmox host itself (stays PVE) and the Hetzner
`primary-server` (open question 2).

Per VM, on `stable`:

1. List its services, data paths, ports and secrets. Needs SSH access to the
   Rocky VMs, which this Mac doesn't have yet.
2. Write `hosts/servers/<name>.nix` and its modules. Port Docker services to
   native NixOS modules where they exist, otherwise to `virtualisation.oci-containers`.
3. Create a new VM from template 9000 next to the old one, with a new IP.
4. Copy the data, switch DNS/Traefik over, keep the old VM stopped for two weeks,
   then delete it.

Order: nixos-manager (fleet server) → vpn (small) → garage → media →
archipelago → Main (largest, production) last.

**Storage warning:** `store-lvm` (iSCSI, 500 GB) is **97% full**. Running old
and new VMs side by side needs room. Free some up, or temporarily put new VMs
on `local-lvm` (about 100 GB free).

## Phases

0. **Repo groundwork**
   - Fix evaluation of `nixos-manager` and `hephaestus` (the undeclared
     `server` and `workstation.terminal/neovim/desktop` options).
   - Set `configurationRevision`.
   - Rename `main` to `unstable` (also the GitHub default branch), create `stable`
     from it, and point every `~/.flake` checkout at `unstable`.
1. **Fleet server + agent (MVP):** status polling, dashboard, per-device "Apply newest",
   skip-and-report. Test with the NixOS VM test framework (server + 2 agents)
   and on atlas.
2. **Enrollment:** agent on atlas, apollo, hermes, hephaestus, plus `tag:fleet`
   in the Tailscale ACL.
3. **Apply to all + Promote** buttons.
4. **VM migration** per the table above.
5. **Later, not in v1:**
   - binary cache (Attic on Garage), so laptops don't build everything themselves
   - notifications
   - only update laptops on AC power
   - health check with automatic rollback for servers

## Testing

- Rust unit tests:
  - the "may this apply?" logic (dirty / ahead / diverged / not ff)
  - the server's desired-commit and promote rules
- NixOS VM test (`nixosTests` style): a server, two agents and a local git remote.
  Press apply and expect the agent to switch. Dirty checkout and expect a skip
  with its reason.
- By hand on atlas for the darwin/launchd path.

## Open questions

1. Dashboard for others on the tailnet: read-only or no access?
2. Hetzner `primary-server`: add it to this flake and fleet (`stable`) now, or later?
3. Is the deploy-box/Jenkins VM still needed once the fleet manager exists?
4. Router VM 101 (NixOS, stopped): still needed?
5. The old work laptop (`14m2max`) is outside this repo: should it join or stay out?
