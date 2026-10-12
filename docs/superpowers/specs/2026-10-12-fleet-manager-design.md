# Fleet manager: dashboard + pull agent (design)

Date: 2026-10-12. Status: draft, waiting for review.

## Goal

One place on the homelab that shows which commit of this repo every machine
(servers and laptops) is running, and an **"apply newest"** button. Pressing
it tells the machine to update itself; nothing updates without that press.
Alongside this, the homelab VMs move from Rocky/Debian to NixOS, managed from
this repo.

## Decisions so far

What the user decided:

- **Dashboard** that lists every system and the commit it's on.
- **Pull, not push.** A small daemon on each machine notices "apply newest"
  and rebuilds itself. Machines behind NAT or asleep catch up when they're back.
- **Every machine builds from `~/.flake`** in the main user's home.
- **Dirty or diverged checkout: skip and report.** The daemon never touches
  local changes. The dashboard shows why it skipped ("dirty", "2 commits ahead").
- **Per-device button plus "apply to all".**
- **Two branches:**
  - `unstable`: new work lands here. Laptops always follow it.
  - `stable`: servers follow it. Unstable is promoted to stable when ready.
    VMs are migrated to NixOS on this branch.

What I'm assuming (correct me):

- It must work on NixOS **and** nix-darwin (atlas and apollo are Macs). That rules
  out DAWO-Sextant (NixOS only, enterprise scope). We borrow its ideas, not its
  code: pull-based updates, branches per ring, a check-in agent, and
  "a change must build before it ships".
- Everything talks over the **tailnet**. Nothing is exposed publicly.

## Why not an existing tool

| Option | Why not (alone) |
|---|---|
| DAWO-Sextant | NixOS only by design. OIDC/LDAP, PXE imaging, compliance: about 80% would have to go. Beta, one maintainer. |
| comin | Pull-based but auto-applies every new commit (no button), NixOS only. |
| deploy-rs / colmena | Push over SSH. Fine for servers, awkward for laptops that are offline or asleep. No dashboard. |
| Clan | A whole framework to adopt. Darwin support is still growing. |

What's left to build is small: a server with a web page and a short API,
and an agent that runs `git` and `*-rebuild`.

## Architecture

```
            tailnet
 ┌──────────────────────────┐      poll every 60s       ┌────────────────────┐
 │ fleet server             │ ◀──────────────────────── │ fleet agent        │
 │ (nixos-manager VM, .170) │   report status,          │ (every machine,    │
 │  - web dashboard         │   receive "apply X"       │  runs as root)     │
 │  - JSON API              │ ────────────────────────▶ │  git (as user)     │
 │  - SQLite                │                           │  *-rebuild switch  │
 │  - bare mirror of repo   │                           └────────────────────┘
 └──────────────────────────┘
            │ git fetch (every few min)
            ▼
   github.com/Waayway/nixos-waayway  (branches: unstable, stable)
```

### Channels

- Each host file declares its channel, for example `fleet.channel = "stable";`.
  Hosts in `hosts/servers/` default to `stable`, hosts in `hosts/workstations/`
  to `unstable`.
- **Promote** (dashboard button, or plain `git push`): fast-forward `stable` to
  a commit on `unstable`. The server only offers a commit if it's an ancestor
  of `unstable`.
- `main` is retired. It becomes `unstable`, or is kept in sync with it as an
  alias (open question 1).

### Fleet server

- Go, one binary, server-rendered HTML (no JS build), SQLite for state.
  Packaged in this flake and enabled with a NixOS module (`services.fleet-server`).
- It keeps a bare mirror of the repo and fetches it every few minutes. That's
  how it knows the head of each branch and the commit messages between
  "running" and "newest".
- **Dashboard**, one row per host:
  - name, OS, channel
  - commit it's running, and how many commits behind its channel head
  - local checkout state: branch, clean/dirty, ahead/behind
  - last check-in (online/offline)
  - status of the last apply, with the tail of its log
  - an **Apply newest** button
- Above the table: an **Apply newest to all on `<channel>`** button per channel,
  and **Promote unstable → stable**.
- **Apply newest** stores a *desired commit* for the host: its channel's head at
  the moment you press. Offline hosts pick it up later. Pressing again updates
  it to the new head.

### Fleet agent

- Go, one static binary. Its module comes from the same source as the server.
  - NixOS: systemd service.
  - Darwin: launchd daemon.
- Runs as root because the rebuild needs it. Every `git` command runs as the main user
  (`sudo -u <user> git -C ~/.flake …`), so file ownership and `safe.directory`
  stay right.
- **Each poll** (every 60s, and once at wake/boot):
  1. Collect status:
     - the running system's commit (`system.configurationRevision`, see below)
     - the `~/.flake` HEAD and branch
     - `git status --porcelain` (dirty or clean)
     - ahead/behind against the channel's remote branch
  2. `POST /api/v1/checkin` with that status. The reply includes the desired
     commit, if there is one.
- **Apply** (when the desired commit differs from the running one):
  1. `git fetch origin`.
  2. Checks. Any of these → **skip**, report the reason, don't touch anything:
     - the checkout is dirty
     - the checkout isn't on the channel branch
     - the checkout has commits not on origin
     - the desired commit isn't reachable by fast-forward
  3. `git merge --ff-only <desired>`.
  4. Rebuild:
     - NixOS: `nixos-rebuild switch --flake ~/.flake#<host>`
     - Darwin: `darwin-rebuild switch --flake ~/.flake#<host>`
  5. Report success or failure, with the last ~200 lines of output. A failed
     build doesn't switch, so the old system keeps running. The checkout stays
     on the new commit, and the dashboard shows "checkout ahead of running system".
- Only one apply runs at a time (lock file). The agent never runs commands
  other than these: the server sends a commit hash, never a command.

### Knowing which commit is running

Set `system.configurationRevision = inputs.self.rev or inputs.self.dirtyRev or "unknown";`
in `lib/mkSystem.nix` and `lib/mkDarwin.nix`. The agent reads it from
`nixos-version --configuration-revision` or `darwin-version --configuration-revision`.
A build from a dirty tree shows up as `<rev>-dirty`.

### Auth (no tokens)

- The server listens only on its Tailscale address.
- It identifies callers with the Tailscale LocalAPI `whois` (the tagged node
  name) instead of passwords or device tokens:
  - **Agents:** a check-in is accepted only if the node name matches the host
    name it reports and the node has a fleet tag (e.g. `tag:fleet`).
  - **Dashboard:** buttons only work for the user `Waayway@`. Others get
    read-only access, or none (open question 4).
- Tailscale ACL: `tag:fleet` → `tag:manager:443` only.

## Migration of the homelab

Today on pve (Proxmox VE 9.1, 5900X, 78 GB RAM):

| ID | Name | Now | Plan |
|---|---|---|---|
| 100 | Main (production) | Rocky 10.2, Docker incl. Traefik | NixOS, services ported (inventory needed) |
| 105 | deploy-box / jenkins-vm | Rocky 10.1 | NixOS, or retire (see open question 6) |
| 110 | vpn | Rocky 10.1 | NixOS |
| 120 | media | Rocky 10.1, GPU passthrough WX7100 | NixOS (amdgpu, passthrough stays) |
| 130 | truenas | TrueNAS 26 beta, HBA passthrough | **stays TrueNAS** (storage appliance) |
| 140 | garage (LXC) | Debian 13, Garage S3 | NixOS VM or NixOS LXC (`services.garage`) |
| 201 | archipelago | unknown, no guest agent | NixOS |
| 200 | minecraft | stopped | NixOS when needed |
| 101 | router | NixOS, stopped | decide (open question 7) |
| 170 | nixos-manager | NixOS, stopped, offline for 55 days | becomes the **fleet server** |
| 9000 | nixos-26.05-template | NixOS image | base for new VMs |

Out of scope: the Proxmox host itself (stays PVE) and the Hetzner
`primary-server` (open question 5).

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
   - Create the `unstable` and `stable` branches.
1. **Fleet server + agent (MVP):** check-in, dashboard, per-device "Apply newest",
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

- Go unit tests:
  - the "may this apply?" logic (dirty / ahead / diverged / not ff)
  - the server's desired-commit and promote rules
- NixOS VM test (`nixosTests` style): a server, two agents and a local git remote.
  Press apply and expect the agent to switch. Dirty checkout and expect a skip
  with its reason.
- By hand on atlas for the darwin/launchd path.

## Open questions

1. What happens to `main`: rename it to `unstable`, or keep it as an alias? (Recommendation: rename it.)
2. Where does the code live: in this flake (`pkgs/fleet/`) or in its own repo?
   (Recommendation: in this flake, so there's one repo to manage. Move it out if it grows.)
3. Go for server and agent? (Recommendation: yes, one static binary, easy on darwin.)
4. Dashboard for others on the tailnet: read-only or no access?
5. Hetzner `primary-server`: add it to this flake and fleet (`stable`) now, or later?
6. Is the deploy-box/Jenkins VM still needed once the fleet manager exists?
7. Router VM 101 (NixOS, stopped): still needed?
8. The old work laptop (`14m2max`) is outside this repo: should it join or stay out?
