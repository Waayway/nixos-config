# Build Cache Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Every Linux host's system for a commit is built once on a cache VM, published as a signed file cache on TrueNAS, served at `https://cache.vanwaaij.com/nix`, and Lodestar refuses to apply a commit to a channel until all its Linux hosts built.

**Architecture:** Lodestar (nixos-manager) gets a build gate: a per-commit `flock` lockfile plus an atomic result file in `state_dir/builds/`; every build (prebuild on head moves, applies, the updater) goes through it and builds only hosts missing from the result, on the cache VM via `nix build --store ssh-ng://lodestar@…`, then calls `cache-publish` there. A generic Lodestar NixOS module `services.lodestar-cache` provides the cache-host role (builder user, `cache-publish`, `cache-prune`, nginx). The flake adds VM 171, the TrueNAS dataset share, the router route, the client substituter and the values.

**Tech Stack:** Rust (tokio, std `File::lock` — Rust ≥ 1.89, toolchain here is 1.95 — serde), NixOS modules, nginx, NFS, Nix file binary cache, Traefik route (router), Tailscale policy API, 1Password/opnix.

**Spec:** `~/.flake/docs/plans/2026-10-29-build-cache-design.md`. Tasks L* are in `~/lodestar` (branch `build-cache` from `main`), F* in `~/.flake` (`unstable`), O* are operations needing Thijs's go-ahead (1Password, TrueNAS, Proxmox, tailnet policy, pushes).

## Global Constraints

- One build per commit: every path to building goes through `BuildGate::ensure_built` (or, for the updater, `build_dir` + `record`); lock file `state_dir/builds/<commit>.lock` (`std::fs::File::lock`, exclusive, taken in `spawn_blocking`), result `state_dir/builds/<commit>.json` written via temp file + `rename`.
- Only **Linux** hosts are built; darwin hosts never.
- A failed host blocks the **whole channel**: apply → HTTP 409 `build of <commit> failed on the builder: <host>[, <host>…]`, audit `apply-refused`, nothing sent to agents.
- Build failures are final; only `lodestar build retry <commit>` (admin, tailnet-only) removes failed hosts from a result. "Builder unreachable" and publish failures are not recorded: the hosts stay missing, applies get a 409 and prebuild/re-send retry with backoff (final review, 2026-11-02).
- Publish only paths built on the cache VM (`ultimate: true`), never full closures; `nix copy --no-recursive --to 'file://<dir>?compression=zstd&secret-key=<file>'`.
- Pruner keep set = union of `.roots/<commit>` lists for the current and previous published commit of every channel in `.roots/channels.json`; missing/unreadable `channels.json` → delete nothing.
- Cache URL `https://cache.vanwaaij.com/nix`; key name `cache.vanwaaij.com-1`; clients `extra-substituters`, `extra-trusted-public-keys`, `connect-timeout = 5`, `fallback = true`, Linux only.
- Cache VM: VMID 171, `10.0.10.171`, 8 vCPU, 8 GB, 32 GB disk, tags `tag:nixos,tag:cache`, channel `stable`; nginx port 80 open only to `10.0.10.110`.
- Storage: dataset `store/internal/nix-cache` (manual), NFS share path `/mnt/store/internal/nix-cache` to `10.0.10.171` only, excluded from the `store` snapshot task; mounted at `/mnt/nix-cache`, automount **without idle timeout**.
- 1Password Homelab items: `nix-cache-signing-key` (field `credential`), `lodestar-builder-key` (SSH key).
- Options default off: `services.lodestar-server.builds.enable = false` keeps today's behaviour.
- Conventions: lodestar `AGENTS.md` (cargo fmt, clippy `-D warnings`, tests in `<crate>/tests/`, validate every git/nix argument), `~/.flake/AGENTS.md` (module gating, nixfmt, commit own paths, never stash). Commits carry no `Co-Authored-By` or other AI attribution trailer.

## Review Focus

1. Two callers for the same commit at once (prebuild + apply, or two applies): the second waits and builds nothing (test in L3).
2. The server restarts mid-build: the lock is released by the kernel, no partial `<commit>.json` exists, the next call builds the missing hosts (test in L3: kill-between-build-and-write simulated by a builder that errors after build; result file absent or complete).
3. The cache VM is unreachable (SSH down): the build fails as a whole-channel refusal with a clear "builder unreachable" reason, and `--retry` recovers once it's back (test in L3/L5).
4. A darwin-only apply, or a channel whose only hosts are darwin: never waits on the gate (test in L5).
5. Router or cache down while a host applies: the client falls back after `connect-timeout = 5` instead of hanging (verified in L8's VM test by stopping nginx on the cache node and still applying with substitution from the other substituter disabled → local build path taken).

---

### Task L1: Config for builds

**Files:**
- Create: `lodestar-server/src/config/builds_config.rs`
- Modify: `lodestar-server/src/config/server_config.rs`, `config/mod.rs`, `nix/modules/server.nix`, `nix/tests/updates-module.nix` (or a new `nix/tests/builds-module.nix` registered in `flake.nix`)
- Test: `lodestar-server/tests/config.rs`

**Interfaces:**
- Produces (Rust): `pub struct BuildsConfig { pub enable: bool, pub store: String, pub ssh_key_file: Option<PathBuf>, pub publish_command: Vec<String>, pub timeout_secs: u64 }`, `#[serde(default)] pub builds: BuildsConfig` on `ServerConfig`, `impl BuildsConfig { pub fn check(&self) -> anyhow::Result<()> }` called from `server::start` next to `check_updates`. Defaults: `enable = false`, `store = ""`, `publish_command = ["cache-publish"]`, `timeout_secs = 7200`.
- Produces (Nix): `services.lodestar-server.builds = { enable; store; sshKeyFile; publishCommand; timeoutSecs; }` → config.json key `builds` with snake_case fields.
- [ ] **Step 1: Failing tests** — JSON `{"builds":{"enable":true,"store":"ssh-ng://lodestar@10.0.10.171","ssh_key_file":"/k","publish_command":["cache-publish"],"timeout_secs":7200}}` parses; absent `builds` → default disabled; `check()` rejects enabled with empty `store`, a `store` not starting with `ssh-ng://` or `ssh://`, an empty `publish_command`, `timeout_secs == 0`. Nix check: the generated config.json carries those keys; an enabled config with empty `store` fails an assertion.
- [ ] **Step 2–4:** RED, implement, GREEN (`nix develop -c cargo test -p lodestar-server --test config`, the Nix check).
- [ ] **Step 5: Commit** — `feat(server): builds config`.

### Task L2: Builder runner

**Files:**
- Create: `lodestar-server/src/builds/mod.rs`, `lodestar-server/src/builds/builder.rs`
- Modify: `lodestar-server/src/lib.rs`, `lodestar-server/src/state/app_state.rs` (`pub builder: Arc<dyn Builder>`, default `RemoteBuilder` from config)
- Test: `lodestar-server/tests/builder.rs`

**Interfaces:**
- Consumes: `ManagedHost { name, os, .. }`, `ServerConfig.nix_bin`, `BuildsConfig`.
- Produces:
  ```rust
  pub struct HostBuild { pub ok: bool, pub path: Option<String>, pub log_tail: Option<String> }
  #[async_trait] pub trait Builder: Send + Sync {
      /// Builds the toplevel of every host in `hosts` from the flake in `dir` on the builder store.
      async fn build(&self, dir: &Path, hosts: &[ManagedHost]) -> BTreeMap<String, HostBuild>;
      /// Runs the publish command on the builder: `<cmd…> <commit> <path>…`; `channels` JSON on stdin.
      async fn publish(&self, commit: &str, paths: &[String], channels: &serde_json::Value) -> anyhow::Result<()>;
  }
  pub struct RemoteBuilder { /* nix_bin, store, ssh_key_file, publish_command, timeout */ }
  ```
  `RemoteBuilder::build`: one `nix build --no-link --print-out-paths --keep-going --store <store> --eval-store auto --extra-experimental-features 'nix-command flakes' .#nixosConfigurations.<h>.config.system.build.toplevel …` for all hosts; map printed paths back to hosts by evaluating each host's `outPath` first (`nix eval --raw`); a host whose path wasn't printed is `ok: false` with the last 40 stderr lines. SSH options via `NIX_SSHOPTS` (`-i <key> -o IdentitiesOnly=yes -o StrictHostKeyChecking=accept-new`). `publish`: `ssh <user@host from store> <publish_command…> <commit> <paths…>` with `channels` JSON on stdin. Host names validated `^[A-Za-z0-9_.-]+$`, commit with `is_commit_hash`, paths must start with `/nix/store/`. `kill_on_drop`, timeout `timeout_secs`. darwin hosts passed in → `Err`/`ok: false` "darwin is not built here" (callers never pass them; defensive).
- [ ] **Step 1: Failing tests** — with a fake `nix` script on PATH (as the updater tests do) and a fake `ssh`: two hosts, fake prints one path → host A ok with path, host B failed with log tail; publish passes exactly `cache-publish <commit> <paths…>` and the channels JSON on stdin; an invalid host name or non-store path is rejected before any process runs; timeout kills the child.
- [ ] **Step 2–4:** RED, implement, GREEN.
- [ ] **Step 5: Commit** — `feat(server): remote builder for the build gate`.

### Task L3: Build gate (lockfile + result)

**Files:**
- Create: `lodestar-server/src/builds/gate.rs`, `lodestar-server/src/builds/result_file.rs`
- Modify: `lodestar-server/src/state/app_state.rs` (`pub builds: Arc<BuildGate>`)
- Test: `lodestar-server/tests/build_gate.rs`

**Interfaces:**
- Consumes: `Builder` (L2), `Mirror::worktree`/`remove_worktree` (exist), `ManagedHost`.
- Produces:
  ```rust
  #[derive(Serialize, Deserialize, Clone)] pub struct BuildResult { pub commit: String, pub hosts: BTreeMap<String, HostResult> }
  #[derive(Serialize, Deserialize, Clone)] pub struct HostResult { pub ok: bool, pub path: Option<String>, pub log_tail: Option<String>, pub built_at: i64 }
  impl BuildResult { pub fn failed_hosts(&self, hosts: &[ManagedHost]) -> Vec<String>; pub fn missing(&self, hosts: &[ManagedHost]) -> Vec<ManagedHost>; }
  pub struct BuildGate { dir: PathBuf /* state_dir/builds */ }
  impl BuildGate {
      pub async fn ensure_built(&self, state: &AppState, commit: &str, hosts: &[ManagedHost]) -> anyhow::Result<BuildResult>;
      pub async fn build_dir(&self, state: &AppState, dir: &Path, hosts: &[ManagedHost]) -> BTreeMap<String, HostResult>; // unlocked; updater only
      pub async fn record(&self, commit: &str, results: BTreeMap<String, HostResult>) -> anyhow::Result<()>; // merge under the lock
      pub async fn retry(&self, commit: &str) -> anyhow::Result<Vec<String>>; // removes failed hosts under the lock, returns them
      pub fn read(&self, commit: &str) -> Option<BuildResult>;
      pub async fn cleanup(&self, now: i64) -> anyhow::Result<()>; // 30-day retention of result files
  }
  ```
  `ensure_built`: filter `hosts` to Linux; take `<commit>.lock` (create, `File::lock()` in `spawn_blocking`, guard dropped at end); read `<commit>.json`; if nothing missing return it; else worktree of `commit` under `builds/work/<commit>`, `builder.build`, `builder.publish(commit, ok paths, channels map)`, merge, write atomically (`<commit>.json.tmp` → `rename`), remove the worktree, return. A failed publish marks the built hosts as failed with `log_tail = "publish failed: …"`. `channels` map = for each channel, its current head and the previous head that has a result file (from the gate's own index `builds/channels.json`, updated here).
- [ ] **Step 1: Failing tests** (fake `Builder` counting calls, bare-repo fixtures from `tests/mirror.rs`):
  - `second_caller_waits_and_builds_nothing` — two concurrent `ensure_built` for one commit → `builder.build` called once; both get the same result (Review Focus 1).
  - `lock_held_elsewhere_blocks` — hold `<commit>.lock` via `File::lock` in a thread; `ensure_built` doesn't call the builder until released.
  - `restart_reuses_result` — new `BuildGate` on the same dir with a complete `<commit>.json` → no build.
  - `only_missing_hosts_are_built` — result has host A; call with A and B → builder gets only B; merged result has both.
  - `no_partial_result_on_error` — builder returns, publish errors → result written with those hosts failed; builder that panics → no `<commit>.json` and the lock is free afterwards (Review Focus 2).
  - `darwin_hosts_are_never_built`.
  - `builder_unreachable_is_a_failure_for_every_host` with reason text "builder unreachable" (Review Focus 3); `retry` removes them and the next call builds again.
  - `atomic_write` — no `.tmp` file left behind.
  - `old_results_are_cleaned` — `cleanup(now)` deletes `<commit>.json` + `.lock` older than 30 days that are not a current/previous head in `channels.json`, keeps the rest; it skips a commit whose lock is held. Called after every successful `ensure_built`.
- [ ] **Step 2–4:** RED, implement, GREEN.
- [ ] **Step 5: Commit** — `feat(server): build gate with a per-commit lockfile`.

### Task L4: Applies go through the gate; prebuild on head moves

**Files:**
- Modify: `lodestar-server/src/api/apply_request.rs` (before `create_applies`), the re-send path (`lodestar-server/src/resend.rs` callers in the poller), `lodestar-server/src/poller/poll_loop.rs` (after `mirror.fetch()`), `lodestar-server/src/state/app_state.rs` (prebuild queue)
- Create: `lodestar-server/src/builds/prebuild.rs`
- Test: `lodestar-server/tests/api.rs`, `lodestar-server/tests/build_gate.rs`

**Interfaces:**
- Consumes: `BuildGate::ensure_built`, `BuildResult::failed_hosts` (L3).
- Produces: `pub async fn gate_apply(state: &AppState, channel: &str, commit: &str) -> Result<(), ApiError>` — no-op when `builds.enable == false` or the channel has no Linux hosts; otherwise `ensure_built(commit, linux hosts of channel)` and on any failure `ApiError` 409 with message `build of <commit7> failed on the builder: <hosts>` plus audit `apply-refused` `{commit, channel, failed_hosts}`. `pub fn spawn_prebuild(state, channel, head)` — one background prebuild at a time (a `tokio::sync::Mutex<()>`), deduplicated by the gate anyway. While `ensure_built` runs for a channel, the channel's build state is `building` (L6 exposes it).
- [ ] **Step 1: Failing tests** — host apply and channel apply call the gate with every Linux host of that channel; a failed host on the channel → 409 for an apply of a *different* host on the same channel, nothing recorded as desired, audit row present; darwin-only channel → no gate call (Review Focus 4); `builds.enable = false` → no gate call (today's behaviour); a re-sent desired apply whose commit's result has a failure is not re-sent; after a fetch that moves `stable`'s head, a prebuild for the new head runs once.
- [ ] **Step 2–4:** RED, implement, GREEN.
- [ ] **Step 5: Commit** — `feat(server): applies wait for the build gate; prebuild on new heads`.

### Task L5: Updater uses the gate

**Files:**
- Modify: `lodestar-server/src/updates/updater.rs` (step 5), `lodestar-server/src/updates/nix_runner.rs` (`build` stays for `builds.enable = false`)
- Test: `lodestar-server/tests/updater.rs`

**Interfaces:**
- Consumes: `BuildGate::build_dir`, `BuildGate::record` (L3).
- Produces: when `builds.enable`, step 5 calls `build_dir(worktree, changed linux hosts)` (darwin hosts keep `NixRunner::build`'s eval), treats any failed host as `BuildFailed{host}`, and after a successful `push_lock` calls `record(new_commit, results)` so the pushed commit is never built again. When disabled, unchanged.
- [ ] **Step 1: Failing tests** — enabled: the fake builder sees exactly the changed Linux hosts; after `Pushed`, `<new_commit>.json` exists with those hosts ok; a later `ensure_built(new_commit, same hosts)` doesn't call the builder; builder failure → `BuildFailed`, nothing pushed, nothing recorded. Disabled: existing tests unchanged.
- [ ] **Step 2–4:** RED, implement, GREEN.
- [ ] **Step 5: Commit** — `feat(server): updater builds through the gate`.

### Task L6: Visibility — metrics, API, CLI, dashboard

**Files:**
- Modify: `lodestar-proto/src/dashboard/channel_view.rs` (`pub build: Option<ChannelBuildView>`), new `lodestar-proto/src/dashboard/channel_build_view.rs`, `lodestar-server/src/updates/metrics.rs` (or `builds/metrics.rs` feeding the same renderer), `lodestar-server/src/api/app.rs` (`POST /builds/{commit}/retry` in `act_routes`, `GET /builds` in `read_routes`), `lodestar-cli/src/cli.rs` + `commands/build.rs`, `web/src/components/fleet/ChannelCard.tsx`, regenerate `web/src/bindings`
- Test: `lodestar-server/tests/api.rs`, `tests/metrics.rs`, CLI tests, `web/tests/build-state.test.tsx`

**Interfaces:**
- Produces: `ChannelBuildView { commit: String, state: String /* building|ok|failed */, failed_hosts: Vec<String>, finished_at: Option<i64> }`; metrics `lodestar_build_last_result{channel,result} 1` (`ok`/`failed`), `lodestar_build_last_timestamp_seconds{channel}`, `lodestar_build_duration_seconds{channel}`; CLI `lodestar build status` (table: channel, commit, state, failed hosts, age) and `lodestar build <commit> --retry`; ChannelCard shows "Building on the builder…", "Built", or "Build failed: <hosts>" with the retry button behind `ActGate`.
- [ ] **Step 1: Failing tests** — snapshot carries build state per channel; retry as reader → 403, as admin → 200 with removed hosts and audit `build-retry`; metrics lines exact; CLI table; ChannelCard renders the three states (text, not colour only).
- [ ] **Step 2–4:** RED, implement, GREEN (workspace tests, clippy, fmt, vitest, bindings).
- [ ] **Step 5: Commit** — `feat: build state in metrics, API, CLI and dashboard`.

### Task L7: `services.lodestar-cache` module (cache-host role)

**Files:**
- Create: `nix/modules/cache.nix` (exported as `nixosModules.cache`, also imported by `nixosModules.default`), `nix/packages/cache-scripts.nix` (`cache-publish`, `cache-prune` via `writeShellApplication` with `nix`, `jq`, `coreutils`), `nix/tests/cache-prune.nix` (fixture test, `runCommand`)
- Modify: `flake.nix` (export, checks), `README.md`, `docs/operations.md`

**Interfaces:**
- Produces (Nix): `services.lodestar-cache = { enable; user = "lodestar"; authorizedKeys; cacheDir = "/mnt/nix-cache"; signingKeyFile; listen.port = 80; allowedClients = [ ]; }`. Sets: user (no password, `nix.settings.trusted-users`), `cache-publish`/`cache-prune` on that user's PATH, a daily `cache-prune` timer, nginx serving `cacheDir` at `/nix/` (`.narinfo` `Cache-Control: no-cache`; `nix-cache-info` created by `cache-publish` if absent with `StoreDir: /nix/store`, `WantMassQuery: 1`, `Priority: 30`), firewall port open only to `allowedClients` (iptables rule like the monitoring agent's).
- `cache-publish <commit> <path>…` (channels JSON on stdin → `$cacheDir/.roots/channels.json`): closure of the paths, keep `ultimate == true`, `nix copy --no-recursive --to "file://$cacheDir?compression=zstd&secret-key=$signingKeyFile"`, write `.roots/<commit>`, run `cache-prune`.
- `cache-prune`: per spec section 3 and Global Constraints.
- [ ] **Step 1: Failing test** — `nix/tests/cache-prune.nix`: fixture dir with narinfos A–E, `.roots/c1` = A,B, `.roots/c2` = C, `.roots/c0` = D, `channels.json` keeping c1 and c2 → after prune A,B,C remain, D,E and `.roots/c0` gone, their `.nar.zst` deleted; without `channels.json` nothing is deleted.
- [ ] **Step 2–4:** RED, implement, GREEN (`nix build .#checks.<system>.cache-prune`).
- [ ] **Step 5: Commit** — `feat(nix): cache-host module with publish and prune`.

### Task L8: End-to-end VM test

**Files:**
- Modify: `nix/tests/vm.nix` (or a new `nix/tests/build-cache.nix` check)

**Interfaces:** Consumes L1–L7.
- [ ] **Step 1:** nodes: `manager` (lodestar-server with `builds.enable`, store `ssh-ng://lodestar@builder`), `builder` (`services.lodestar-cache.enable`, cacheDir on local disk, test signing key generated in the test), `client` (agent, substituter `http://builder/nix` + public key, no cache.nixos.org).
- [ ] **Step 2:** testScript: a channel apply to `client` → manager's gate builds on `builder`, publishes; `builder` serves `/nix/nix-cache-info`; `client`'s apply succeeds and its nix log shows `copying path … from 'http://builder/nix'` and no `building '…-system-path.drv'`; a second apply of the same commit doesn't build again (gate result file on manager unchanged, builder log shows no new build); stop nginx on `builder`, apply again on `client` → still succeeds within the timeout (Review Focus 5); a commit that fails to build (a host config with a deliberate failing derivation) → channel apply 409.
- [ ] **Step 3: Run on nixos-manager** (KVM; git bundle as in `~/.flake/AGENTS.md`). Expected: success.
- [ ] **Step 4: Commit** — `test(vm): build gate and cache end to end`.

### Task F1: TrueNAS share and snapshot exclusion

**Files:** Modify `~/.flake/modules/server/truenas/homelab.nix`.
- [ ] **Step 1:** `nfsShares.nix-cache = { path = "/mnt/store/internal/nix-cache"; hosts = [ "10.0.10.171" ]; }` (plus `mapall` to the cache VM's `lodestar` uid/gid if the share type supports it — follow the existing share options); add `"store/internal/nix-cache"` to the `store` snapshot task's `exclude`.
- [ ] **Step 2: Verify** — `nix eval` nixos-manager's truenas config renders the share and the exclude; `nix flake check --no-build --keep-going`.
- [ ] **Step 3: Commit** — `feat(truenas): nix-cache share, never snapshotted`.

### Task F2: Cache VM host and modules

**Files:**
- Create: `~/.flake/hosts/servers/cache.nix`, `~/.flake/modules/server/cache/cache.nix`
- Modify: `~/.flake/docs/vmids.md`, `~/.flake/docs/homelab.md`, `~/.flake/AGENTS.md` (machines table)

**Interfaces:** Consumes `services.lodestar-cache` (L7) via the lodestar input.
- [ ] **Step 1:** host file: `system = "x86_64-linux"`, user `cache`, `type = "server"`, `useDefaultHardware = true`, `isHomeServer = true`, `netInterface = { ip = "10.0.10.171"; prefixLength = 24; }`, `tags = [ "tag:cache" ]`, `fleet = true`. Module (gated on the host enabling `services.lodestar-cache`): `cacheDir = "/mnt/nix-cache"`, NFS automount of `10.0.10.130:/mnt/store/internal/nix-cache` without idle timeout, `signingKeyFile` from opnix `op://Homelab/nix-cache-signing-key/credential` (owner `lodestar`, 0400), `authorizedKeys` = the public key of `lodestar-builder-key` (committed after O1), `allowedClients = [ "10.0.10.110" ]`.
- [ ] **Step 2: Verify** — `nix eval .#nixosConfigurations.cache.config.system.build.toplevel.drvPath`; the NFS mount has no `x-systemd.idle-timeout`; firewall rule only for `10.0.10.110`; every host still evaluates.
- [ ] **Step 3: Commit** — `feat(cache): VM 171 serves the fleet's build cache`.

### Task F3: Router route, clients, Lodestar values, alert

**Files:**
- Create: `~/.flake/modules/common/nix/cache.nix`
- Modify: `~/.flake/modules/server/homelab/routes.nix` (or the cache module) for `homelab.routes.cache`, `~/.flake/modules/server/lodestar/server.nix` (`builds` values + opnix `lodestarBuilderKey`), `~/.flake/modules/server/monitoring/alerts.nix` (+ `tests/monitoring.nix` counts), `~/.flake/docs/lodestar.md`
- [ ] **Step 1:** route: host `cache.vanwaaij.com`, backend `http://10.0.10.171:80`, `public = false`, tailnet enabled, no gate. Clients (Linux only, `lib.optionalAttrs hostPlatform.isLinux`): substituter, public key (from O1), `connect-timeout = 5`, `fallback = true` (without it a timed-out substituter fails the build; L8). Lodestar: `builds = { enable = true; store = "ssh-ng://lodestar@10.0.10.171"; sshKeyFile = <opnix path>; }`. Alert check "Build failed": `lodestar_build_last_result{result="failed"} == 1`, `for = "0s"`, plain summary.
- [ ] **Step 2: Verify** — every host evaluates; darwin hosts have no new substituter; router renders the route and Service `svc:cache`; monitor test counts updated; `nix flake check --no-build --keep-going`.
- [ ] **Step 3: Commit** — `feat(cache): route, clients, Lodestar build gate on`.

### Task O1–O4: Operations (each needs Thijs's go-ahead)

- [ ] **O1 Secrets:** `nix-store --generate-binary-cache-key cache.vanwaaij.com-1 sk pk` in a scratch dir, `sk` into 1Password `nix-cache-signing-key` (`credential`), shred `sk`; commit `pk` in F2/F3. `op item create --category ssh --ssh-generate-key ed25519 --title lodestar-builder-key`; its public key into F2.
- [ ] **O2 TrueNAS:** create dataset `store/internal/nix-cache` (owner per F1); the share comes from F1 via `truenas-reconcile`.
- [ ] **O3 VM 171:** clone template 9000 (8 vCPU, 8 GB, 32 GB on store-lvm, `cpu: host`, `onboot 1`), first system built on nixos-manager and copied, `sudo opnix token set`; tailnet policy: `tag:cache` in `tagOwners` (owners `autogroup:admin`, `tag:nixos`), `svc:cache` in the Services grant (`autogroup:member`, `tag:personal`, `tag:nixos`) and auto-approved for `tag:router` (API, as before); `tailscale serve drain/advertise svc:cache` if needed.
- [ ] **O4 Rollout:** release lodestar (`builds.enable` stays off until the cache works), `nix flake update lodestar`, push, promote, apply nixos-manager, then flip `builds.enable`; watch the prebuild of `stable`'s head publish (`curl https://cache.vanwaaij.com/nix/nix-cache-info` from a tailnet device); apply the stable channel — router, identity and monitor must show only `copying path … from 'https://cache.vanwaaij.com/nix'`, no compiles; Grafana shows `lodestar_build_last_result{result="ok"}`.
