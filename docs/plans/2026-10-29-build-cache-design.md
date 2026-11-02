# Build once: a fleet binary cache and a build gate in Lodestar

Status: agreed in conversation 2026-10-29, written for review. Option A of the
"compile once and distribute" discussion; option B (Lodestar builds and pushes finished
systems, agents only switch) is the production-grade design for later. Spans `~/.flake`
(VM, storage, routes, clients) and `~/lodestar` (the build gate).

## Why

Every host builds its own system, including Lodestar's Rust packages, which no public
cache has. On 2026-10-29 that OOM-killed router and identity (2 GB), filled the 16 GB
disks of router, identity and monitor with failed builds, and starved monitor's Grafana,
Prometheus and Loki while it compiled. Each host compiling the same thing is waste even
where it works.

## Goal

- Every Linux host's system for a commit is built exactly once, on one machine, before
  any host applies it. Hosts only download.
- A commit that does not build never reaches a host: if any Linux host of a channel fails
  to build, no host on that channel applies it.
- Success: router, identity and monitor apply through Lodestar without compiling; a
  broken commit fails once, centrally, with its log.

Out of scope: darwin hosts (atlas, apollo) — their systems need a Mac to build and both
Macs are laptops; they keep building themselves (an always-on Mac could become a darwin
builder later without changing this design). Pushing closures to hosts (option B).

## Overview

```
 push / promote / updater            apply (dashboard, CLI)
          │                                 │
          ▼                                 ▼
  Lodestar server (nixos-manager) ── build gate: lock <commit>, build missing hosts,
          │  ssh-ng (user lodestar)          write <commit>.json, unlock
          ▼
  cache VM 171 (10.0.10.171): builds in its local store (32 GB scratch)
          │  cache-publish: nix copy → file cache, signed
          ▼
  TrueNAS NFS dataset  /mnt/nix-cache  ◄── nginx /nix/ ◄── router route
                                                       https://cache.vanwaaij.com/nix
          ▲                                            (tailnet-only, svc:cache)
          └──────────── every Linux host substitutes from it ───────────┘
```

## 1. The cache VM

- Proxmox VM **171 `cache`**, `10.0.10.171`, next to nixos-manager (170): 8 vCPU,
  8 GB RAM, 32 GB disk (build scratch only), `cpu: host`, `onboot 1`, cloned from
  template 9000. Host file `hosts/servers/cache.nix`: `type = "server"`, tags
  `tag:nixos,tag:cache`, `fleet = true`, channel `stable`. `docs/vmids.md` and
  `docs/homelab.md` updated.
- Its own `/nix/store` stays local (a Nix store on NFS is unreliable: SQLite and locks).
  The Proxmox auto-GC (`min-free` 1 GiB / `max-free` 4 GiB,
  `modules/server/proxmox/disk-space.nix`) keeps it small; published paths do not need
  to stay in the local store.
- User **`lodestar`** (no password, no shell login beyond Nix and `cache-publish`):
  `nix.settings.trusted-users` includes it (remote builds of input-addressed derivations
  need a trusted user). Its authorized key is the public half of 1Password Homelab item
  `lodestar-builder-key`; `command=`-restriction is not used because `ssh-ng://` runs
  `nix-daemon --stdio`.
- Tailscale tag `tag:cache` added to the policy's `tagOwners` (owned by
  `autogroup:admin` and `tag:nixos`, like every server tag).

## 2. Storage on TrueNAS

- A child dataset **`store/internal/nix-cache`**, created once by hand (pools and
  datasets stay manual), owner matching the cache VM's `lodestar` uid (mapped via the
  share's `mapall`). It is **never backed up**: the cache is rebuildable. The `store`
  snapshot task in `modules/server/truenas/homelab.nix` excludes it (like
  `store/proxmox-vms`), and the restic backups read `store/internal` from its
  snapshots, which don't contain a child dataset's files, so no restic change is
  needed. Its NFS share (`nfsShares.nix-cache`, path `/mnt/store/internal/nix-cache`,
  hosts `[ "10.0.10.171" ]`) is code in the same file. Mounted on the cache VM
  at `/mnt/nix-cache` with a systemd automount **without idle timeout** (AGENTS.md
  gotcha), owner `lodestar`.
- The directory is a Nix **file binary cache**: `nix-cache-info`, `*.narinfo`,
  `nar/*.nar.zst`. Plain files, safe over NFS.

## 3. Signing and publishing

- Key pair generated once: `nix-store --generate-binary-cache-key cache.vanwaaij.com-1`.
  Secret: 1Password Homelab item `nix-cache-signing-key` (field `credential`), delivered
  only to the cache VM by opnix (owner `lodestar`, 0400). Public key committed in
  `modules/common/nix/cache.nix`.
- **`cache-publish <commit> <store-path>…`** (a script in the cache VM's module, run by
  Lodestar over SSH as `lodestar`):
  1. Take the closure of the given paths and keep **only the paths built on the cache
     VM** (`nix path-info --json` `ultimate: true`); everything with a cache.nixos.org
     signature is left out — clients get those from cache.nixos.org, which they try
     first. `nix copy --no-recursive --to
     'file:///mnt/nix-cache?compression=zstd&secret-key=<file>'` those paths
     (already-present paths are skipped). Measured 2026-10-29: of a 7.5 GB server
     closure 87 MB is local (router), nixos-manager 312 MB, hermes 1.9 GB (mostly unfree
     apps Hydra doesn't cache: Discord, 1Password, Spotify, IPMIView); all Linux hosts
     together ≈ 2.5 GB raw, ≈ 1.5–2 GB zstd, plus little for the previous commit.
  2. Write `/mnt/nix-cache/.roots/<commit>` listing the published paths (the pruner's
     keep set is these lists, not full closures).
  3. Run the pruner.
- **Pruner** (`cache-prune`, also a daily timer): the keep set is the union of the
  paths listed in the `.roots` files of the **current and previous published commit of
  every channel** (Lodestar passes the channel → commit map as `.roots/channels.json` on each
  publish). Every `.narinfo` outside the keep set is deleted with the `.nar` it points
  to; then `.roots` files of commits no longer kept. A run never deletes anything if
  `channels.json` is missing or unreadable.

## 4. Serving

- nginx on the cache VM serves `/mnt/nix-cache` at `/nix/` on port 80
  (`nix-cache-info` at `/nix/nix-cache-info`), `.narinfo` with `Cache-Control:
  no-cache`, `.nar.zst` cacheable. Firewall: port 80 only from the router
  (`10.0.10.110`), like Lodestar's proxy listener.
- Router route **`homelab.routes.cache`**: host `cache.vanwaaij.com`, backend
  `http://10.0.10.171:80`, `public = false`, tailnet Service `svc:cache`, **no
  `auth.gate`** (Nix cannot log in; the tailnet policy is the access control). URL:
  **`https://cache.vanwaaij.com/nix`**.
- Tailnet policy: `svc:cache` added to the Services grant for `autogroup:member`,
  `tag:personal`, `tag:nixos` (servers reach it like prod reaches `svc:id`), and to the
  router's auto-approved Services.

## 5. Clients

`modules/common/nix/cache.nix`, every **Linux** host (servers and workstations; not
darwin):

```nix
nix.settings = {
  extra-substituters = [ "https://cache.vanwaaij.com/nix" ];
  extra-trusted-public-keys = [ "cache.vanwaaij.com-1:<public key>" ];
  connect-timeout = 5;
  fallback = true;
};
```

If the router or the cache is down, Nix falls back to cache.nixos.org and local builds
after the timeout; nothing hangs. `fallback = true` is required: without it a
substituter that times out fails the build instead of building locally (found by the
end-to-end VM test, 2026-11-02). A dead cache costs ~30 s per apply (5 attempts × 5 s). Agents are unchanged: they still `nix build` their own
system, which now only downloads.

## 6. The build gate (Lodestar)

Generic in `~/lodestar`; `~/.flake` only sets values.

### Options

```nix
services.lodestar-server.builds = {
  enable = false;                       # off: applies behave as today
  store = "ssh-ng://lodestar@10.0.10.171";
  sshKeyFile = "/var/lib/opnix/secrets/lodestarBuilderKey";
  publishCommand = [ "cache-publish" ];  # run over the same SSH connection
  timeoutSecs = 7200;
};
```

### Lock and result: one build per commit

- Directory `state_dir/builds/`. For commit `C`:
  - **`C.lock`**: an exclusive `flock` taken for the whole of "check, build, publish,
    write result". Taken in a blocking task (`flock` blocks), held across the build,
    released on drop; if the server dies the kernel releases it with the process, so a
    stale lock can't block later builds.
  - **`C.json`**: `{ commit, hosts: { <name>: { ok, path?, log_tail?, built_at } } }`,
    written atomically (temp file + rename) under the lock.
- `ensure_built(commit, hosts) -> BuildResult`: take the lock; read `C.json`; build only
  the hosts **missing** from it (one `nix build --no-link --print-out-paths --store
  <store> --eval-store auto` over all missing hosts' toplevels, in a worktree of `C`;
  per-host results come from building with `--keep-going` and reading which outputs
  exist); publish the new paths; merge into `C.json`; unlock. A second caller for the
  same commit blocks on the lock, then finds every host in `C.json` and builds nothing.
  **Every path to building goes through this function** (prebuild, apply, updater).
- Results are final: a commit cannot change. `lodestar build <commit> --retry`
  (admin, tailnet-only) removes the failed hosts from `C.json` under the lock so the next
  call rebuilds them (network or disk failures).

### Which hosts

For a channel `K` at commit `C`: every **Linux** host in the hosts file whose channel is
`K`. darwin hosts are never built here.

### Callers

1. **Prebuild:** after each mirror fetch, every channel whose head changed gets
   `ensure_built(head, linux hosts of that channel)` in a background task; prebuilds run
   one at a time (the lock already serialises same-commit work).
2. **Apply** (host or channel, dashboard, CLI, re-send): before anything is sent to an
   agent, `ensure_built(C, linux hosts of the channel)`. If **any** host failed, the
   apply is refused for the **whole channel** (HTTP 409 "build of C failed on the
   builder: <host>", audit `apply-refused`), nothing is sent. While it waits, the
   dashboard shows the channel as "building". darwin-only applies skip the gate.
3. **Updater:** its build step calls the gate with the candidate commit made in its
   worktree (`ensure_built_in(dir, commit, hosts)`), so a pushed bump is already built
   and published when it is promoted and applied.

### Retention

After each successful publish Lodestar sends the channel → current/previous built
commit map with the publish (`channels.json`), so the pruner knows what to keep.
`state_dir/builds/*.json` older than 30 days and not referenced by that map are
deleted with their lock files.

### Visibility

- Metrics: `lodestar_build_last_result{channel,result}` (1 for the last result: `ok`,
  `failed`), `lodestar_build_duration_seconds{channel}`,
  `lodestar_build_last_timestamp_seconds{channel}`.
- `GET /api/channels` (or the snapshot) gains per channel: `build: { commit, state:
  building|ok|failed, failed_hosts, finished_at }`. Dashboard ChannelCard shows it.
- CLI: `lodestar build status` and `lodestar build <commit> --retry`.
- Grafana/alerts (`~/.flake`): an alert when a channel's last build failed.

## 7. Bootstrap and rollout

1. Create 1Password items `nix-cache-signing-key` and `lodestar-builder-key`; the
   `store/internal/nix-cache` dataset by hand, its NFS share and snapshot exclusion
   (TrueNAS-as-code).
2. Clone VM 171 from template 9000 (sizes above); first system built on nixos-manager
   and copied, then `opnix token set`; enrol in Lodestar.
3. Router route + Services grant + `tag:cache` in the tailnet policy (API, as before).
4. Clients get `cache.nix`; cache usable once published paths exist.
5. Lodestar release with the gate (`builds.enable = false` first), then enable it on
   nixos-manager; prebuild of the current heads fills the cache; apply the servers.

## 8. Testing

- Rust unit/integration tests with a fake `nix`/SSH runner (as the updater's FakeNix):
  two concurrent `ensure_built` for one commit build once; a restarted gate reads
  `C.json` and builds nothing; one failed host → the whole channel's apply is refused;
  `--retry` rebuilds only the failed hosts; darwin hosts are never built; atomic result
  writes (a crash between build and write leaves no partial file).
- Lock: a test holding `C.lock` from another process (or thread) makes `ensure_built`
  wait, not build.
- Pruner: fixture cache directory — keep set from two channels' current and previous
  roots survives, everything else is deleted, missing `channels.json` deletes nothing.
- NixOS VM test: server + builder node + client node; prebuild publishes to a file cache
  served by nginx; the client's `nix build` substitutes the toplevel without building.
- `~/.flake`: all hosts evaluate; the cache route, firewall rule and client settings
  evaluate on every Linux host; darwin has no substituter change.

## Open questions

None blocking. Later: darwin builder (always-on Mac), option B (push closures).
