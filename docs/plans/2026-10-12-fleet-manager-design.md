# Fleet manager: dashboard + push agent (design)

Date: 2026-10-12. Status: approved, revised after review (see "Review changes").

## Goal

One place on the homelab that shows which commit of this repo every machine
(servers and laptops) is running, and an **"apply newest"** button. Pressing
it tells the machine to update itself; nothing updates without that press.
Alongside this, the homelab VMs move from Rocky/Debian to NixOS, managed from
this repo.

## Decisions

- **Dashboard** that lists every system and the commit it's on.
- **Push over the tailnet.** Every machine runs a small daemon that listens on
  its Tailscale address and accepts requests **only from nixos-manager**.
  "Apply newest" makes the server send "go to commit X and switch".
- **Every machine builds from `~/.flake`** in the main user's home.
- **Dirty or diverged checkout: skip and report.** The daemon never touches
  local changes. The dashboard shows why it skipped.
- **Per-device button plus "apply to all".**
- **Two branches** in `github.com/Waayway/nixos-config` (public):
  - `unstable` (renamed from `main`): new work lands here. Laptops follow it.
  - `stable`: servers follow it. Unstable is promoted to stable when ready.
- **Pull is anonymous.** The repo is public; only the fleet server holds a
  credential (a GitHub deploy key with write access, used only to promote).
- Works on NixOS **and** nix-darwin (atlas and apollo are Macs).
- **Rust** server and agent, **Preact + shadcn/ui** frontend, all in this flake
  under `pkgs/fleet/`.

## Why not an existing tool

| Option | Why not (alone) |
|---|---|
| DAWO-Sextant | NixOS only by design. OIDC/LDAP, PXE imaging, compliance: about 80% would have to go. Beta, one maintainer. |
| comin | Pull-based but auto-applies every new commit (no button), NixOS only. |
| deploy-rs / colmena | Push over SSH, builds on the deployer. No dashboard, and doesn't use the machine's own `~/.flake`. |
| Clan | A whole framework to adopt. Darwin support is still growing. |

## Architecture

```
                                  tailnet
 ┌──────────────────────────┐  GET  /status   (every 60s)  ┌──────────────────────┐
 │ fleet server             │ ───────────────────────────▶ │ fleet agent          │
 │ (nixos-manager, .170)    │  POST /apply {id, commit}    │ (every machine, root)│
 │  - web dashboard (Preact)│ ───────────────────────────▶ │  listens on its      │
 │  - SQLite (SeaORM)       │  GET  /apply/log,            │  Tailscale IP only,  │
 │  - bare mirror of repo   │       /activations           │  accepts only        │
 │                          │ ───────────────────────────▶ │  nixos-manager       │
 └──────────────────────────┘                              └──────────────────────┘
            │ git fetch (every 5 min, and on every button press)
            ▼
   github.com/Waayway/nixos-config  (branches: unstable, stable)
```

All connections go **from** the server **to** the agents. Agents never call
the server. nixos-manager runs an agent too and updates itself the same way.

### Hosts and channels

- **Channel is a host-file attribute**, like `system` and `type`:
  `channel = "stable";`. If absent it defaults by category in `flake.nix`:
  `hosts/servers/` → `stable`, `hosts/workstations/` → `unstable`.
- **Fleet membership** is a host-file attribute `fleet = true;` (default
  `false` until a host is enrolled).
- `flake.nix` builds `fleetHosts = [ { name, system, user, channel } ]` from
  `discoverHosts` (no evaluation of other systems' configs) and passes it to
  every system through `specialArgs`. The server module renders it to
  `/etc/fleet-server/hosts.json`, which the server reads at start. The agent
  module takes its own `user` and `channel` from the same data.
- **Tailscale name = host name** (both NixOS and nix-darwin set the hostname
  from the host's name).
- **Promote** (dashboard button): fast-forward `stable` to a commit on
  `unstable`. The server only offers a commit that is an ancestor of
  `unstable` and a descendant of the current `stable`. It pushes with
  `GIT_SSH_COMMAND="ssh -i <sops key path> -o IdentitiesOnly=yes"` to
  `git@github.com:Waayway/nixos-config`. A GitHub ruleset on `stable` blocks
  force pushes and requires linear history.

### Fleet server

- NixOS module `services.fleet-server` (options: `listenPort`, `repoUrl`
  default `https://github.com/Waayway/nixos-config`, `pushRemote`,
  `deployKeyFile`, `hostsFile`, `agentPort`, `allowedUsers`, `allowedTags`).
- Keeps a bare mirror of the repo in `/var/lib/fleet-server/mirror.git`,
  fetched every 5 minutes **and before resolving a button press or promote**.
  Used for branch heads, "behind" counts, and commit messages between
  "running" and "newest".
- **Status polling:** every 60s it calls `GET /status` (and
  `GET /activations?since=`) on every fleet host that Tailscale reports online.
- **Dashboard**, one row per host:
  - name, OS, channel
  - running commit (`-dirty` shown as a badge), commits behind its channel head
  - checkout: branch, HEAD, dirty, untracked count, ahead of origin
  - on/off (from Tailscale), last seen
  - last activation: when, commit, trigger
  - last apply: state, reason, log (opens in a sheet)
  - an **Apply newest** button
- Above the table: **Apply newest to all on `<channel>`** per channel, and
  **Promote unstable → stable**.
- **"Behind"** is computed by the server from its mirror:
  `rev-list --count <running>..origin/<channel>` (with `-dirty` stripped).
  If the running commit isn't in the mirror (local, unpushed commits) it's
  shown as "unknown".

### Desired commit and re-send rules

- **Apply newest** fetches the mirror, resolves the channel head, creates an
  apply with a server-generated `apply_id` (UUID), stores it as the host's
  *desired apply*, and sends `POST /apply {apply_id, commit}`.
- The server re-sends the desired apply automatically **only when**:
  - the host is online and reachable, and
  - its running commit isn't the desired commit, and
  - the agent's last apply is **not** this `apply_id` (i.e. it never received
    it, e.g. because it was asleep).
- If the agent's last apply **is** this `apply_id` and it ended `failed` or
  `skipped`, the server does **not** re-send. Pressing the button again
  creates a new apply and always sends.
- The agent ignores a `POST /apply` whose `apply_id` it already ran (returns
  `200` with that apply's state), so a retried request never rebuilds twice.
- "Online but `/status` fails" is treated as transient (a sleeping laptop
  can look online for a few minutes); it changes nothing in the rules above.

### Fleet agent

- Rust, second binary in the same workspace. NixOS: systemd service. Darwin:
  launchd daemon. Both run as root.
- Module `services.fleet-agent` (options: `port` default `7461`, `user`,
  `channel`, `managerHost` default `nixos-manager`, `repoUrl`,
  `flakePath` default `<user home>/.flake` as an absolute path,
  `rebuildCommand` (for tests), `stateDir` default `/var/lib/fleet-agent`).
- **Environment** set explicitly in the unit/plist: `HOME` of root and
  `PATH=/run/current-system/sw/bin:/nix/var/nix/profiles/default/bin:/usr/bin:/bin:/usr/sbin:/sbin`.
  The running revision is always read from
  `/run/current-system/sw/bin/{nixos,darwin}-version --configuration-revision`,
  never from a store path in the agent's own closure.
- **Listening:** the agent finds its Tailscale address by enumerating network
  interfaces for addresses in `100.64.0.0/10` (IPv4) and `fd7a:115c:a1e0::/48`
  (IPv6), with no dependency on the `tailscale` CLI. It retries binding with
  backoff and re-checks every minute (on macOS the address only exists while
  Tailscale is connected).
- **Accepting:** only requests whose source IP equals an address of
  `managerHost`, resolved through MagicDNS at request time (cached for 60s),
  IPv4 and IPv6. Request bodies are limited to 4 KB; only the routes below
  exist.
- **API:**
  - `GET /status`:
    - `running`: output of `*-version --configuration-revision`
    - `checkout`: branch, HEAD, `dirty` (tracked changes), untracked count,
      `ahead` (`rev-list --count origin/<channel>..HEAD`), time of last fetch
    - `apply`: the current or last apply (`apply_id`, commit, state
      idle/running/ok/skipped/failed, reason, started, finished)
  - `POST /apply {apply_id, commit}`: `202` started; `200` if this `apply_id`
    already ran; `409` if another apply is running; `400` if `commit` isn't
    40 hex characters.
  - `GET /apply/log?apply_id=`: log of that apply.
  - `GET /activations?since=<n>`: activation lines for the audit log.
- **Background fetch:** the agent fetches at most every 10 minutes (and at
  every apply) so `ahead` stays current without draining laptop batteries.
  All fetches are explicit:
  `git fetch https://github.com/Waayway/nixos-config '+refs/heads/*:refs/remotes/origin/*'`,
  so it works whatever the user's `origin` remote is, and never pushes.

### Apply

Git and the build run **as the user**, the switch **as root**. This avoids
root evaluating a repo owned by another user (libgit2 owner validation), and
`~` expanding to root's home.

The apply runs **outside the agent's process**, because a switch that changes
the agent restarts it and would otherwise kill the apply:
- NixOS: `systemd-run --unit fleet-apply-<id> --collect --property=Type=exec <apply wrapper>`
- Darwin: the launchd job sets `AbandonProcessGroup = true` and the wrapper
  detaches (`setsid`), so it survives the agent being restarted.

The wrapper (a subcommand of the agent binary, `fleet-agent apply <id> <commit>`)
writes `/var/lib/fleet-agent/applies/<id>.json` (state, reason, exit code,
timestamps) as it goes, and the log to `/var/lib/fleet-agent/applies/<id>.log`.
`GET /status` and `/apply/log` read those files, so a restarted agent reports
the right state. Only the last 50 applies are kept.

Steps:
1. Write `/var/lib/fleet-agent/apply-in-progress.json` `{apply_id, commit, started}`.
2. As the user: the explicit `git fetch` above.
3. Checks, as the user. Any failure → **skipped** with this reason, nothing touched:
   - `git cat-file -e <commit>^{commit}`: the commit exists after fetch
   - `git merge-base --is-ancestor <commit> origin/<channel>`: the commit is
     on the host's channel (a misconfigured server can't move a host anywhere else)
   - current branch is `<channel>`
   - `git diff --quiet HEAD` (no tracked changes; untracked files are
     reported but don't block, matching how Nix decides `-dirty`)
   - `git merge-base --is-ancestor HEAD <commit>`: fast-forward possible
     (also covers "local commits not on origin")
4. As the user: `git merge --ff-only <commit>`.
5. As the user: build.
   - NixOS: `nix build <flakePath>#nixosConfigurations.<host>.config.system.build.toplevel --no-link --print-out-paths`
   - Darwin: `nix build <flakePath>#darwinConfigurations.<host>.system --no-link --print-out-paths`
6. As root: switch.
   - `nix-env -p /nix/var/nix/profiles/system --set <out>`
   - NixOS: `<out>/bin/switch-to-configuration switch` (inside the transient unit,
     with `NIXOS_INSTALL_BOOTLOADER` unset)
   - Darwin: `<out>/activate` (what `darwin-rebuild switch` does)
7. Record `ok` or `failed` (+ exit code), delete `apply-in-progress.json`.

A failed build doesn't switch, so the old system keeps running. The checkout
stays on the new commit; the dashboard shows "checkout ahead of running
system". The next press re-runs the build (the ff check passes trivially).

With `rebuildCommand` set (tests), steps 5–6 run that command instead with
`<host>` and `<commit>` as arguments.

### Knowing which commit is running

Set `system.configurationRevision = inputs.self.rev or inputs.self.dirtyRev or "unknown";`
in `lib/mkSystem.nix` and `lib/mkDarwin.nix`. `nixos-version` and
`darwin-version` support `--configuration-revision`. A tree with tracked
changes builds as `<rev>-dirty`; untracked files don't make it dirty.

### Audit log

One `audit_events` table: time, host, kind, actor, details (JSON). Sources:

1. **Dashboard actions:** apply, apply to all, promote. Actor = Tailscale login
   name, or the node's name for tagged devices (see "Access control").
2. **Applies:** every apply with its id, commit, result, reason and timestamps,
   recorded by the server from `GET /status` (the log stays on the agent and
   is fetched for the server's copy when the apply ends).
3. **Every activation, including manual ones** (the hook into the nix command):
   - A fleet module adds an activation snippet: `system.activationScripts.fleetAudit`
     on NixOS, appended with `lib.mkAfter` to `system.activationScripts.postActivation`
     on darwin (the only hook that runs after Homebrew and home-manager).
   - It appends one JSON line to `/var/lib/fleet-agent/activations.jsonl`
     (`mkdir -p` first; the whole snippet ends in `|| true` so it can never
     break a switch):
     - time
     - `$systemConfig` (the store path being activated; on darwin
       `/run/current-system` is only relinked *after* `postActivation`)
     - revision, read from `$systemConfig` (`darwin-version.json` /
       `configuration-revision` file)
     - generation, from `readlink /nix/var/nix/profiles/system`
     - trigger:
       - `apply:<id>` if `/var/lib/fleet-agent/apply-in-progress.json` exists
       - `boot` if `/run/current-system` doesn't exist yet (NixOS runs
         activation at every boot)
       - otherwise `manual`, plus `SUDO_USER` when set (darwin; on NixOS the
         switch runs under `systemd-run`, which drops the environment)
   - The agent serves it at `GET /activations?since=<line>`. The server copies
     new lines into `audit_events` on every poll, so an offline machine catches
     up later.

Nix's `post-build-hook` is not used: it fires for every derivation built, and
not on activation.

### Online state

- The server shells out to `tailscale status --json` (every 30s) and
  `tailscale whois --json <ip>` (per dashboard request, cached 60s) on
  nixos-manager. No hand-rolled LocalAPI client.
- Per host: online/offline, last seen, OS, Tailscale IPs and DNS name.
- One state per host on the dashboard:
  - **off**: Tailscale says offline. Shows "last seen …".
  - **on, agent unreachable**: Tailscale online, but `GET /status` fails.
  - **on**: both answer.
- The server only polls agents that Tailscale reports online. The agent's
  address comes from the same data, so the host list needs no IPs.

### Access control

- **Agents:** listen only on their Tailscale address and accept only
  nixos-manager's addresses (see "Fleet agent"). Plus a Tailscale ACL: only
  `tag:manager` may reach `tag:fleet:7461`.
- **Dashboard:** listens only on nixos-manager's Tailscale address. Tagged
  devices have no user identity in Tailscale (`whois` returns
  `tagged-devices`), and every Linux host here is tagged `tag:nixos`. So access
  is granted when **either**:
  - `whois` login name is `Waayway@github` (untagged devices, e.g. atlas), or
  - the node carries one of `tag:nixos`, `tag:personal`, `tag:fleet`
    (devices only the owner controls).
  Everyone else gets `403`, on every request and on the WebSocket upgrade.
  Backed by an ACL rule `[Waayway@github, tag:nixos, tag:personal] → tag:manager:<dashboard port>`.
- Root-privileged agent hardening: source-IP check, 4 KB body limit, fixed
  routes, 40-hex commit check, and the "commit is on my channel" check.
  Source-IP auth is sound on a tailnet (WireGuard ties peer keys to IPs).

## Technology choices

1. **Communication:** the server pushes to the agents over plain HTTP on the
   tailnet; agents never call the server.
2. **Backend:** Rust with axum (tokio), JSON API under `/api`, serving the
   built frontend.
3. **Frontend:** Preact + `preact/compat`, the official shadcn/ui components,
   Vite, Tailwind v4, TypeScript.
4. **Storage:** SQLite in `/var/lib/fleet-server`, through **SeaORM**.
   Entities and migrations in Rust (`sea-orm-migration`), run at startup.
5. **Live updates:** a WebSocket (`/api/ws`). The server pushes host changes,
   apply progress and log lines as typed JSON; the frontend reconnects with
   backoff and asks for a full snapshot after reconnecting.
6. **Actions are REST:** `POST /api/...` (apply, apply to all, promote), each
   access-checked, audited and answered with a status. The WebSocket only
   carries server → browser updates.
7. **Shared types:** defined once in `fleet-proto` and exported to TypeScript
   with `ts-rs`. The generated `web/src/bindings/*.ts` are **committed**; a
   `nix flake check` runs `cargo test -p fleet-proto` with `TS_RS_EXPORT_DIR`
   and fails if they differ.
8. **Layout:** cargo workspace `pkgs/fleet/` with `fleet-proto`,
   `fleet-server`, `fleet-agent`; frontend in `pkgs/fleet/web/`.
9. **Nix build:** `crane` (new flake input) for the Rust crates;
   `buildNpmPackage` (committed `package-lock.json`, `npmDepsHash`) for the
   frontend. The server embeds the frontend with `rust-embed`
   (`interpolate-folder-path` feature, `#[folder = "$FLEET_WEB_DIST"]`); the
   crane `buildPackage` step sets `FLEET_WEB_DIST = "${web}"`. In development,
   Vite's dev server proxies `/api` to the Rust server.

## Migration of the homelab

Today on pve (Proxmox VE 9.1, 5900X, 78 GB RAM):

| ID | Name | Now | Plan |
|---|---|---|---|
| 100 | Main (production) | Rocky 10.2, Docker incl. Traefik | NixOS, services ported (inventory needed) |
| 105 | deploy-box / jenkins-vm | Rocky 10.1 | **retire** (Jenkins leaves the stack); not migrated |
| 110 | vpn | Rocky 10.1 | NixOS |
| 120 | media | Rocky 10.1, GPU passthrough WX7100 | NixOS (amdgpu, passthrough stays) |
| 130 | truenas | TrueNAS 26 beta, HBA passthrough | **stays TrueNAS** (storage appliance) |
| 140 | garage (LXC) | Debian 13, Garage S3 | NixOS VM or NixOS LXC (`services.garage`) |
| 201 | archipelago | unknown, no guest agent | NixOS |
| 200 | minecraft | stopped | NixOS when needed |
| 101 | router | NixOS, stopped (earlier attempt at a NixOS Main) | **delete** after a last look for anything worth keeping |
| 170 | nixos-manager | NixOS, stopped, offline for 55 days | becomes the **fleet server** |
| 9000 | nixos-26.05-template | NixOS image | base for new VMs |

Out of scope, not moving to NixOS:
- the Proxmox host itself (stays PVE)
- the Hetzner `primary-server`
- the old work laptop (`14m2max`)
- Jenkins (deploy-box), which is being removed

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
   - `hosts/servers/nixos-manager.nix`: rename `tailscaleTags` to `tags`
     (`lib/mkSystem.nix` reads `tags`; today `tag:manager` is never advertised).
   - Set `configurationRevision` in `mkSystem` and `mkDarwin`.
   - `channel` and `fleet` host attributes, `fleetHosts` in `specialArgs`.
1. **Branch rename** (needs the user, touches GitHub):
   - On GitHub: rename `main` → `unstable` (also the default branch), create
     `stable` from it, add the ruleset on `stable`.
   - Per checkout: `git branch -m main unstable && git fetch origin &&
     git branch -u origin/unstable && git remote set-head origin -a`.
   - Update `AGENTS.md / docs/fleet.md` (push command, branch name) and `README.md`.
   - Laptops must be on `unstable`, servers on `stable`, before enrolment
     (the agent skips otherwise). `flake.lock` is unaffected: no input
     references this repo.
2. **Fleet server + agent (MVP):** status polling, dashboard, per-device
   "Apply newest", desired-apply rules, skip-and-report, WebSocket. Tested
   with unit tests and the VM test (below).
3. **nixos-manager bootstrap** (needs the user and pve):
   - Start VM 170. Clone the repo at `/home/manager/.flake` on `stable`.
   - Add its SSH host key (as age key) to `.sops.yaml`; create
     `secrets/nixos-manager.yaml` with the write deploy key and a Tailscale
     auth key.
   - First switch by hand; enable `services.fleet-server` and the agent.
4. **Enrolment:** `fleet = true` and the agent on atlas, apollo, hermes,
   hephaestus. Tailscale ACL: `tag:fleet` on these hosts, the agent rule and
   the dashboard rule. Real switches tested by hand on hermes and atlas.
5. **Audit hook + Apply to all + Promote.**
6. **VM migration** per the table above.
7. **Later, not in v1:**
   - binary cache (Attic on Garage), so laptops don't build everything themselves
   - notifications
   - only update laptops on AC power
   - health check with automatic rollback for servers

(Phase numbers 1 and 2 can run in parallel; the code doesn't depend on the
rename.)

## Testing

- Rust unit tests:
  - the apply checks (missing commit / not on channel / wrong branch / dirty /
    not fast-forward), against real temporary git repos
  - the server's desired-apply and re-send rules, behind/unknown computation,
    promote ancestry rules
  - access control (login name, tags, 403)
- NixOS VM test: a server, two agents and a local bare git remote, with
  `services.fleet-agent.rebuildCommand` set to a fake that records its
  arguments and writes a fake revision. Covers fetch, ff, skip-on-dirty,
  HTTP, source-IP rejection and re-send. A real `nixos-rebuild` of this flake
  inside a VM is not feasible offline (every flake input would have to be in
  the VM's store), so it isn't attempted.
- Real switches by hand on hermes (NixOS) and atlas (darwin/launchd).

## Demo mode

Added after the user asked for it: demo mode is part of fleet itself.

- `fleet-server demo` (or `nix run .#fleet-demo`) runs the real server, poller,
  database, git mirror and dashboard against a simulated fleet: a throwaway git
  repo with `unstable`/`stable`, and in-process simulated agents that implement
  the real agent API.
- The simulated hosts cover every state the dashboard must show: successful
  applies with a streaming log, a dirty checkout that is skipped, a failed build,
  an unreachable agent, and a laptop that is off and comes online (showing the
  automatic re-send). A new commit lands on `unstable` every few minutes and
  promote really moves `stable` in the throwaway repo.
- The snapshot carries `demo: true` and the dashboard shows a "Demo" banner.
  Access control is off; it listens on loopback unless `--listen` says otherwise.

## Review changes (2026-10-12)

An independent review found these problems in the first version; all are
fixed above:

- The NixOS switch runs under `systemd-run`, which drops `FLEET_APPLY_ID` and
  `SUDO_USER`; the trigger now comes from an `apply-in-progress.json` file.
- Root evaluating the user's `~/.flake` from a daemon likely fails libgit2's
  owner check; build as the user, switch as root.
- A switch that restarts the agent would kill the apply; the apply now runs
  in its own transient unit / detached process and records state in files.
- `Waayway@` whois would lock out every tagged device; access now also
  accepts the owner's tags.
- The re-send rule looped on a failed build; applies now have ids and failed
  or skipped applies are not re-sent.
- Host list and channel now come from host-file attributes, not from
  evaluating other systems' NixOS options.
- Repo name corrected to `Waayway/nixos-config`.
- Smaller fixes: `tailscaleTags` → `tags`, daemon `PATH`/`HOME`, bind retry on
  macOS, CLI instead of LocalAPI, `$systemConfig` in the hook, `ahead`/`behind`
  split, channel-ancestry check, fake rebuild in the VM test, committed ts-rs
  bindings, crane input, mirror fetch on press.
