# Fleet Manager Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** A Rust fleet server (dashboard on nixos-manager) and a Rust agent on every NixOS/nix-darwin host. The server shows which commit each host runs and, on a button press, pushes "go to commit X and switch" to the agents.

**Architecture:** Cargo workspace `pkgs/fleet/` with three crates: `fleet-proto` (shared types, exported to TS via ts-rs), `fleet-agent` (axum HTTP API, git checks, detached apply wrapper) and `fleet-server` (axum + SeaORM/SQLite, git mirror, Tailscale CLI, poller, REST + WebSocket, embedded Preact frontend). Built with crane and buildNpmPackage in this flake. Installed through NixOS/nix-darwin modules in `modules/fleet/`, driven by host-file attributes (`channel`, `fleet`).

**Tech Stack:** Rust (edition 2024, nixpkgs toolchain), tokio, axum (with `ws`), serde/serde_json, SeaORM + sea-orm-migration (sqlite), ts-rs, rust-embed, uuid, tempfile (tests). Frontend: Preact + preact/compat, @preact/preset-vite, Vite, Tailwind v4 (@tailwindcss/vite), shadcn/ui, TypeScript, vitest. Nix: crane, buildNpmPackage, nixosTest.

**Spec:** `docs/plans/2026-10-12-fleet-manager-design.md`. Read it before any task; it is the source of truth for behaviour. This plan fixes names, files, interfaces and tests.

## Global Constraints

- Repo URL default `https://github.com/Waayway/nixos-config`; push remote `git@github.com:Waayway/nixos-config`.
- Agent port default `7461`; agent state dir `/var/lib/fleet-agent`; server state dir `/var/lib/fleet-server`.
- Agent request body limit 4 KB; commits must be exactly 40 lowercase hex chars.
- Server: mirror fetch every 300 s and before every button press/promote; agent status poll every 60 s; `tailscale status --json` every 30 s; whois cached 60 s.
- Agent: background fetch at most every 600 s; keep the last 50 applies.
- Daemon PATH: `/run/current-system/sw/bin:/nix/var/nix/profiles/default/bin:/usr/bin:/bin:/usr/sbin:/sbin`.
- Running revision is read only from `/run/current-system/sw/bin/{nixos,darwin}-version --configuration-revision`.
- Dashboard access: login `Waayway@github`, or node tags `tag:nixos`, `tag:personal`, `tag:fleet`; else `403` (HTTP and WS upgrade).
- Repo conventions (`AGENTS.md / docs/fleet.md`):
  - host files stay thin
  - platform guards use `lib.optionalAttrs hostPlatform.isLinux/isDarwin`, not `mkIf`
  - never merge attrsets that may share a top-level key with `//`; use `lib.mkMerge`
  - format Nix with the repo's RFC nixfmt: `$(nix build --no-link --print-out-paths --inputs-from . nixpkgs#nixfmt)/bin/nixfmt <files>`
  - no git worktrees
  - new files must be `git add`ed before the flake sees them
  - commit messages end with `Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>`
- Do not touch the user's unrelated uncommitted files (`modules/hardware/caps_to_esc*.nix`). Commit only the paths you changed: `git commit -- <paths>`.
- This Mac (aarch64-darwin) has **no Linux builder**. Linux derivations are checked with `nix eval …drvPath`, never built. Rust and frontend tests run natively in `nix develop .#fleet`.
- Rust toolchain comes only from the flake dev shell (`nix develop .#fleet -c …`); the `cargo` on PATH is an unconfigured rustup.

## Review Focus

1. **The agent restarts during an apply** (its own switch replaced it, or the laptop slept). Expected: `/status` after restart reports the apply's real state from `applies/<id>.json`. A wrapper that died mid-run shows as `failed` with reason `interrupted`, never `running` forever. *Test in Task 6.*
2. **Checkout without `origin/<channel>`** (never fetched), detached HEAD, or a branch with no upstream. Expected: a skip with a clear reason (`wrong_branch`, `commit_not_on_channel`), no panic and no 500. *Test in Task 5.*
3. **GitHub unreachable when a button is pressed** (mirror fetch fails). Expected: the API answers `502` with the error, no apply row is created, and nothing is sent. *Test in Task 11.*
4. **Double press, or apply-to-all while a host is already applying.** Expected:
   - the agent answers `409` and no second rebuild starts
   - the server keeps the newest desired apply and re-sends it after the running one finishes, because that agent's last `apply_id` differs

   *Test in Task 12 (`should_resend`) and Task 7 (409).*
5. **Running revision is `unknown`, `<rev>-dirty`, or a commit not in the mirror.** Expected: `behind = null` (shown as "unknown"), the dirty badge set, and no re-send loop. *Test in Task 10 (`behind_count`) and Task 12.*

---

## File map

```
flake.nix                          + crane input, fleetHosts, packages, devShells, checks
lib/mkSystem.nix, lib/mkDarwin.nix + configurationRevision, `fleet` specialArg
lib/fleetHosts.nix                 NEW: hosts attrset → [{name,system,user,channel,os}]
hosts/servers/nixos-manager.nix    tailscaleTags→tags, drop undeclared options, fleet server on
hosts/workstations/hephaestus.nix  drop undeclared options
modules/vm-specific/proxmox-guest.nix  NEW: hardware for type=server + useDefaultHardware
modules/system.nix                 + ./fleet in the umport list
modules/fleet/agent.nix            NEW: services.fleet-agent (systemd + launchd)
modules/fleet/server.nix           NEW: services.fleet-server (NixOS only)
modules/fleet/audit-hook.nix       NEW: activation snippet → activations.jsonl
pkgs/fleet/Cargo.toml, Cargo.lock  workspace
pkgs/fleet/default.nix             crane + buildNpmPackage derivations
pkgs/fleet/fleet-proto/src/lib.rs  shared types
pkgs/fleet/fleet-agent/src/{main,config,git,checks,status,apply,launcher,activations,net,api}.rs
pkgs/fleet/fleet-server/src/{main,config,db/,mirror,tailscale,access,agent_client,poller,resend,api,ws,embed}.rs
pkgs/fleet/fleet-server/migration/  sea-orm-migration crate (workspace member `fleet-migration`)
pkgs/fleet/web/                    Vite + Preact + shadcn app; src/bindings/*.ts committed
tests/fleet-vm.nix                 NixOS VM test
```

---

### Task 1: Make every host evaluate again

**Files:**
- Modify: `hosts/servers/nixos-manager.nix`, `hosts/workstations/hephaestus.nix`
- Create: `modules/vm-specific/proxmox-guest.nix`
- Modify: whatever else evaluation proves broken (e.g. the `//` merge in `modules/boot/boot.nix` noted in HANDOFF), and nothing more.

**Interfaces:** Produces `nixosConfigurations.{hermes,hephaestus,nixos-manager}` and `darwinConfigurations.{atlas,apollo}`, all evaluating.

- [ ] **Step 1: Record the failures.** Run each command and expect `nixos-manager` and `hephaestus` to fail with ``The option `server' does not exist``:
  - `nix eval .#nixosConfigurations.<h>.config.system.build.toplevel.drvPath` for h in hermes, hephaestus, nixos-manager
  - `nix eval .#darwinConfigurations.<h>.system.drvPath` for h in atlas, apollo
- [ ] **Step 2: hephaestus.**
  - Remove `server = { };`.
  - Replace `workstation.terminal/neovim/desktop.*` with the options that already exist for the same things: grep `modules/` for `mkEnableOption` under `workstation`, the desktop modules and `modules/shell/neovim.nix`.
  - Where nothing equivalent is declared, delete the line and leave a one-line comment, the way `hermes.nix` does.
- [ ] **Step 3: nixos-manager.**
  - Remove `server = { };` and the undeclared `workstation.*` lines, using the same rule as Step 2.
  - Rename `tailscaleTags` to `tags`.
- [ ] **Step 4: Create `modules/vm-specific/proxmox-guest.nix`.**
  - Wrap it in `lib.optionalAttrs (hostPlatform.isLinux && hostPlatform.isServer && serverOptions.useDefaultHardware or false)`.
  - It imports `(modulesPath + "/profiles/qemu-guest.nix")`.
  - Settings, matching the nixos-generators `proxmox` format VM 170 was built from:
    - `fileSystems."/" = { device = "/dev/disk/by-label/nixos"; fsType = "ext4"; autoResize = true; }`
    - `boot.loader.grub.device = "/dev/vda"`
    - `boot.growPartition = true`
    - `services.qemuGuest.enable = true`
  - Only `mkSystem` passes `serverOptions`, so take it with a default (`serverOptions ? { }`).
  - `useDefaultHardware`, `isHomeServer` and `netInterface` are read in `mkSystem` without `or`. Change those three reads to `machineOptions.<x> or null` so workstations don't throw once forced.
- [ ] **Step 5: Re-run all five evals from Step 1.** Expected: each prints a `.drv` path.
- [ ] **Step 6: Format and commit.**
  ```bash
  git add modules/vm-specific/proxmox-guest.nix
  git commit -m "fix: nixos-manager and hephaestus evaluate again" -- hosts/ modules/vm-specific/ lib/mkSystem.nix <other touched files>
  ```

### Task 2: Revision, channel and fleet host list in the flake

**Files:**
- Create: `lib/fleetHosts.nix`
- Modify: `flake.nix`, `lib/mkSystem.nix`, `lib/mkDarwin.nix`

**Interfaces:**
- Produces:
  - flake output `fleetHosts`: a list of `{ name; system; user; channel; os; }` with `os ∈ {"linux","darwin"}`, containing only hosts with `fleet = true`. `user` is the user **name** string.
  - specialArg `fleet = { member : bool; channel : "stable"|"unstable"; hosts : <fleetHosts>; }` on every system.
  - `system.configurationRevision` set on every system.

- [ ] **Step 1: Failing checks.** Each must fail (missing attribute / null) before the change:
  - `nix eval .#fleetHosts --json`
  - `nix eval .#nixosConfigurations.hermes.config.system.configurationRevision`
- [ ] **Step 2: `lib/fleetHosts.nix`.**
  - Signature: `{ lib }: hosts: [ … ]`.
  - It needs each host's category, so change `lib/discoverHosts.nix` to add `category = "<dir name>"` to every host attrset it returns.
  - Channel defaults: `servers` → `"stable"`, everything else → `"unstable"`.
  - A host's own `channel` attribute wins.
  - `fleet` defaults to `false`.
- [ ] **Step 3: Wire it up.**
  - In `flake.nix`, compute `fleetHosts`, expose it as an output, and pass `fleetHosts` into `mkSystem`/`mkDarwin`. Both take it as a new named argument and add `fleet` to `extraArgs`.
  - In both builders add `system.configurationRevision = inputs.self.rev or inputs.self.dirtyRev or "unknown";` to the inline module.
- [ ] **Step 4: Verify.**
  - `nix eval .#fleetHosts --json` prints `[]`, because no host sets `fleet` yet.
  - Temporarily set `fleet = true;` in `hermes.nix`: the output becomes `[{"channel":"unstable","name":"hermes","os":"linux","system":"x86_64-linux","user":"waayway"}]`. Revert that.
  - The `configurationRevision` eval prints a 40-hex string with `-dirty` appended (the tree is dirty).
  - The five evals from Task 1 still pass.
- [ ] **Step 5: Commit** (`feat(fleet): channel, fleet host list and configurationRevision`).

### Task 3: Workspace, shared types, dev shell, packaging skeleton

**Files:**
- Create: `pkgs/fleet/Cargo.toml` (workspace members: `fleet-proto`, `fleet-agent`, `fleet-server`, `fleet-server/migration`), `pkgs/fleet/fleet-proto/{Cargo.toml,src/lib.rs}`, empty-main stubs for `fleet-agent` and `fleet-server`, `pkgs/fleet/default.nix`, `pkgs/fleet/.gitignore` (`target/`, `web/node_modules`, `web/dist`)
- Modify: `flake.nix` (input `crane.url = "github:ipetkov/crane"`, `devShells.<sys>.fleet`, `packages.<sys>.{fleet-agent,fleet-server}`, `checks.<sys>.fleet-bindings`)

**Interfaces:** Produces these `fleet-proto` types. All derive `Serialize, Deserialize, Clone, Debug, PartialEq, TS`, use `#[ts(export)]` and `#[serde(rename_all = "snake_case")]`, and use unix seconds as `i64` for times.

```rust
pub enum ApplyState { Idle, Running, Ok, Skipped, Failed }
pub enum SkipReason { FetchFailed, CommitNotFound, CommitNotOnChannel, WrongBranch, Dirty, NotFastForward }
pub struct ApplyRecord { pub apply_id: String, pub commit: String, pub state: ApplyState,
    pub skip_reason: Option<SkipReason>, pub message: Option<String>, pub exit_code: Option<i32>,
    pub started_at: Option<i64>, pub finished_at: Option<i64> }
pub struct CheckoutStatus { pub branch: Option<String>, pub head: Option<String>, pub dirty: bool,
    pub untracked: u32, pub ahead: Option<u32>, pub last_fetch_at: Option<i64> }
pub struct AgentStatus { pub host: String, pub os: String, pub agent_version: String,
    pub running: String, pub checkout: CheckoutStatus, pub apply: Option<ApplyRecord> }
pub struct ApplyRequest { pub apply_id: String, pub commit: String }
pub struct ActivationEvent { pub line: u64, pub time: i64, pub store_path: String, pub revision: String,
    pub generation: Option<u64>, pub trigger: String, pub sudo_user: Option<String> }
pub struct ActivationsResponse { pub events: Vec<ActivationEvent>, pub next: u64 }
pub struct LogChunk { pub apply_id: String, pub offset: u64, pub data: String, pub eof: bool }
// dashboard
pub enum OnlineState { Off, AgentUnreachable, On }
pub struct HostView { pub name: String, pub os: String, pub channel: String, pub online: OnlineState,
    pub last_seen: Option<i64>, pub running: Option<String>, pub running_dirty: bool,
    pub behind: Option<u32>, pub checkout: Option<CheckoutStatus>, pub last_apply: Option<ApplyRecord>,
    pub desired_apply_id: Option<String>, pub last_activation: Option<ActivationEvent> }
pub struct ChannelView { pub name: String, pub head: Option<String>, pub head_subject: Option<String> }
pub struct Snapshot { pub hosts: Vec<HostView>, pub channels: Vec<ChannelView>,
    pub promote_candidate: Option<String>, pub viewer: String }
pub struct AuditEvent { pub id: i64, pub time: i64, pub host: Option<String>, pub kind: String,
    pub actor: String, pub details: serde_json::Value }
pub enum WsMessage { Snapshot(Snapshot), HostUpdated(HostView), ChannelsUpdated(Vec<ChannelView>), ApplyLog(LogChunk) }
pub fn is_commit_hash(s: &str) -> bool
```

`WsMessage` is serialized as `#[serde(tag = "type", content = "data")]`.

- [ ] **Step 1: Failing test** in `fleet-proto`:
  - `is_commit_hash` accepts `"a".repeat(40)` and rejects 39 chars, uppercase, and `"…-dirty"`.
  - `WsMessage::HostUpdated(..)` serializes with `"type":"host_updated"`.
- [ ] **Step 2: Run it and expect it to fail.** `nix develop .#fleet -c cargo test -p fleet-proto` (run from `pkgs/fleet`).
  - The dev shell is `mkShell` with `cargo rustc clippy rustfmt nodejs_22 sqlite git`.
- [ ] **Step 3: Implement**, then `TS_RS_EXPORT_DIR=../web/src/bindings cargo test -p fleet-proto` writes the `.ts` files. Commit them.
- [ ] **Step 4: `pkgs/fleet/default.nix`.**
  - Signature: `{ pkgs, crane }: { fleet-agent, fleet-server, fleet-web, bindingsCheck }`.
  - Use `craneLib.buildDepsOnly` shared by both binaries, with `cargoExtraArgs = "-p <crate>"`.
  - `fleet-server` and `fleet-web` may be stubs until Tasks 9/14.
  - `bindingsCheck` runs `cargo test -p fleet-proto` with `TS_RS_EXPORT_DIR=$TMP/b` and `diff -r $TMP/b web/src/bindings`.
- [ ] **Step 5: Verify.**
  - `nix build .#fleet-agent` succeeds (aarch64-darwin).
  - `nix build .#checks.aarch64-darwin.fleet-bindings` passes.
  - `nix eval .#packages.x86_64-linux.fleet-agent.drvPath` prints a path.
- [ ] **Step 6: Commit** `pkgs/fleet`, `flake.nix`, `flake.lock`.

### Task 4: Agent config and git helpers

**Files:**
- Create: `fleet-agent/src/config.rs`, `fleet-agent/src/git.rs`
- Test: `fleet-agent/tests/common/mod.rs` (helper to build temp repos), `fleet-agent/tests/git.rs`

**Interfaces:**
- Consumes: Task 3 types.
- Produces:

```rust
// config.rs: JSON file passed as `--config <path>`
pub struct AgentConfig { pub host: String, pub user: String, pub channel: String, pub flake_path: PathBuf,
    pub repo_url: String, pub port: u16, pub manager_host: String, pub listen: Option<SocketAddr>,
    pub state_dir: PathBuf, pub rebuild_command: Option<Vec<String>>, pub launcher: Launcher,
    pub os: String /* "linux"|"darwin" */ }
pub enum Launcher { SystemdRun, Detach, Inline }   // serde snake_case
pub fn load(path: &Path) -> anyhow::Result<AgentConfig>
// git.rs: every call runs `git -C <flake_path>`. When the process is root and `user` is not root,
// drop to the user via std::os::unix::process::CommandExt::{uid,gid} (from getpwnam via `nix`
// or `users` crate) and set HOME/USER/LOGNAME.
pub struct Git { /* flake_path, run_as: Option<(u32,u32,PathBuf home)> */ }
impl Git {
  pub fn new(cfg: &AgentConfig) -> anyhow::Result<Git>;
  pub fn run(&self, args: &[&str]) -> anyhow::Result<std::process::Output>;   // never panics on non-zero
  pub fn fetch(&self, repo_url: &str) -> anyhow::Result<()>; // '+refs/heads/*:refs/remotes/origin/*'
  pub fn current_branch(&self) -> Option<String>;            // None on detached HEAD
  pub fn head(&self) -> Option<String>;
  pub fn is_dirty(&self) -> bool;                            // `git diff --quiet HEAD` != 0
  pub fn untracked_count(&self) -> u32;
  pub fn commit_exists(&self, c: &str) -> bool;              // cat-file -e c^{commit}
  pub fn is_ancestor(&self, a: &str, b: &str) -> bool;       // merge-base --is-ancestor
  pub fn ahead_of(&self, remote_ref: &str) -> Option<u32>;   // rev-list --count remote_ref..HEAD
  pub fn ff_merge(&self, c: &str) -> anyhow::Result<()>;
}
```

- [ ] **Step 1: Failing tests** in `tests/git.rs`. The helper creates a bare "remote" with branches `unstable`/`stable` and a clone checked out on `unstable`, with `repo_url` set to the bare path.
  - `fetch_then_commit_exists`
  - `dirty_tracked_only`: an untracked file gives `is_dirty()==false` and `untracked_count()==1`; a modified tracked file gives `true`.
  - `detached_head_branch_is_none`
  - `ahead_counts_local_commits`
  - `ff_merge_moves_head`
- [ ] **Step 2: Run them and expect failure.** `nix develop .#fleet -c cargo test -p fleet-agent --test git`
- [ ] **Step 3: Implement** `config.rs` and `git.rs`.
- [ ] **Step 4: Run and expect PASS.**
- [ ] **Step 5: Commit.**

### Task 5: Apply checks

**Files:**
- Create: `fleet-agent/src/checks.rs`
- Test: `fleet-agent/tests/checks.rs`

**Interfaces:** Produces `pub fn check_apply(git: &Git, channel: &str, commit: &str) -> Result<(), SkipReason>`. It runs in the spec's order (Apply step 3), and the first failure wins:
1. `CommitNotFound`
2. `CommitNotOnChannel` (not an ancestor of `origin/<channel>`, **including when `origin/<channel>` doesn't exist**)
3. `WrongBranch` (`current_branch() != Some(channel)`, including detached HEAD)
4. `Dirty`
5. `NotFastForward` (HEAD isn't an ancestor of the commit; covers local commits)

- [ ] **Step 1: Failing tests**, one per reason plus `ok_when_clean_and_ff`:
  - `missing_commit` → `CommitNotFound`
  - `commit_only_on_other_branch` → `CommitNotOnChannel`
  - `no_remote_channel_ref` (fresh clone where `origin/stable` doesn't exist and channel = stable) → `CommitNotOnChannel`
  - `detached_head` → `WrongBranch`
  - `tracked_change` → `Dirty`
  - `untracked_only_is_ok` → `Ok`
  - `local_commit_diverged` → `NotFastForward`
- [ ] **Step 2: Run, and expect FAIL.**
- [ ] **Step 3: Implement.**
- [ ] **Step 4: Run, and expect PASS.**
- [ ] **Step 5: Commit.**

### Task 6: Apply wrapper, state files, launcher

**Files:**
- Create: `fleet-agent/src/apply.rs`, `fleet-agent/src/launcher.rs`, `fleet-agent/src/main.rs` (clap subcommands `serve --config` and `apply --config <id> <commit>`)
- Test: `fleet-agent/tests/apply.rs`

**Interfaces:** Produces:

```rust
// apply.rs
pub fn applies_dir(cfg: &AgentConfig) -> PathBuf;                   // <state_dir>/applies
pub fn read_record(cfg: &AgentConfig, id: &str) -> Option<ApplyRecord>;
pub fn latest_record(cfg: &AgentConfig) -> Option<ApplyRecord>;     // newest by started_at; a `Running`
    // record whose pid (stored in <id>.pid) is no longer alive is returned as Failed, message "interrupted"
pub fn read_log(cfg: &AgentConfig, id: &str, offset: u64) -> Option<LogChunk>;
pub fn run_apply(cfg: &AgentConfig, id: &str, commit: &str) -> ApplyRecord;  // the wrapper body
pub fn prune(cfg: &AgentConfig, keep: usize);                       // keep = 50
// launcher.rs
pub fn launch(cfg: &AgentConfig, config_path: &Path, id: &str, commit: &str) -> anyhow::Result<()>;
```

`run_apply` follows the spec's Apply steps 1–7 exactly:
- It writes `<state_dir>/apply-in-progress.json` and deletes it at the end.
- `<id>.json` is rewritten atomically (write a tmp file, then rename) at every state change. The log goes to `<id>.log`.
- The build runs as the user. The `nix build` attribute is `nixosConfigurations.<host>.config.system.build.toplevel` (linux) or `darwinConfigurations.<host>.system` (darwin).
- The switch runs as root:
  1. `nix-env -p /nix/var/nix/profiles/system --set <out>`
  2. then `<out>/bin/switch-to-configuration switch` (linux) or `<out>/activate` (darwin)
- If `rebuild_command` is set, it replaces the build and switch steps. It is run with args `[..cmd, host, commit]` and stdout/stderr go to the log.

`launch` behaviour:
- `SystemdRun`: `systemd-run --unit fleet-apply-<first 8 of id> --collect --property=Type=exec <self exe> apply --config <path> <id> <commit>`
- `Detach`: spawn the same command with `pre_exec(setsid)` and stdio set to null.
- `Inline`: spawn it as a plain child (tests).

- [ ] **Step 1: Failing tests.** Use a temp repo from Task 4, `rebuild_command = ["sh","-c","echo built $0 $1; exit 0"]` and `launcher = Inline`.
  - `apply_ok_moves_head_and_records_ok`: state `Ok`, HEAD == commit, the log contains `built`, and `apply-in-progress.json` is gone.
  - `apply_skips_dirty_and_leaves_tree`: state `Skipped`, `skip_reason == Dirty`, HEAD unchanged.
  - `apply_failed_build_records_exit_code`: the command `exit 3` gives `Failed` with `exit_code == Some(3)`, and HEAD == commit.
  - `interrupted_running_record_reports_failed`: write a `Running` record whose pid is dead. `latest_record` returns `Failed` with message `"interrupted"` (Review Focus 1).
  - `prune_keeps_50`.
  - `read_log_offset`: returns only the bytes after the offset, with `eof` true once the record is finished.
- [ ] **Step 2: Run, and expect FAIL.**
- [ ] **Step 3: Implement.**
- [ ] **Step 4: Run, and expect PASS.**
- [ ] **Step 5: Commit.**

### Task 7: Agent HTTP API, address discovery, source check, activations

**Files:**
- Create: `fleet-agent/src/{api.rs,net.rs,status.rs,activations.rs}`
- Test: `fleet-agent/tests/api.rs`

**Interfaces:** Produces:

```rust
// net.rs
pub fn tailscale_addrs() -> Vec<IpAddr>;          // local interfaces in 100.64.0.0/10 or fd7a:115c:a1e0::/48 (if-addrs crate)
pub fn is_tailscale(ip: IpAddr) -> bool;
pub struct SourceGuard { /* manager_host, cache 60s */ }
impl SourceGuard { pub fn new(host: String) -> Self; pub async fn allows(&self, ip: IpAddr) -> bool; } // tokio::net::lookup_host
// status.rs
pub fn collect(cfg: &AgentConfig, git: &Git) -> AgentStatus; // running via `<rev cmd> --configuration-revision`, "unknown" on error
// activations.rs
pub fn read_since(path: &Path, since: u64) -> ActivationsResponse; // line numbers are 0-based; skips malformed/partial lines
// api.rs
pub fn router(state: AppState) -> axum::Router; // GET /status, POST /apply, GET /apply/log?apply_id=&offset=, GET /activations?since=
```

Behaviour:
- The revision command is `/run/current-system/sw/bin/nixos-version` or `darwin-version`. Tests override it with a config field `revision_command: Option<Vec<String>>`; add it to `AgentConfig`.
- **Serving:** with `listen` set, bind it. Otherwise bind every `tailscale_addrs()` on `port`, retrying with backoff (1 s doubling to 60 s), and re-check the addresses every 60 s.
- **Source check:** use `ConnectInfo<SocketAddr>` and `SourceGuard`; reject with `403`.
- **Body limit:** `DefaultBodyLimit::max(4096)`.
- **`POST /apply`:**
  - `400` unless `is_commit_hash`.
  - `200` plus the record if `<id>.json` already exists.
  - `409` if `latest_record` is `Running`.
  - Otherwise `launch(..)` and `202`.
- **Background fetch:** a task fetches every 600 s. It is skipped while an apply runs, and records `last_fetch_at` in `<state_dir>/last_fetch`.

- [ ] **Step 1: Failing tests.** Use `tower::ServiceExt::oneshot` with `ConnectInfo` injected through `MockConnectInfo`.
  - `rejects_foreign_source` → 403
  - `bad_commit_400`
  - `apply_202_then_status_ok`: launcher Inline, then poll `/status` until the apply state is `Ok`.
  - `duplicate_apply_id_200`
  - `apply_while_running_409`: rebuild command `sleep 2`.
  - `body_over_4k_rejected` → 413
  - `activations_since_skips_partial_line`
  - `is_tailscale_ranges`: covers `100.95.164.9`, `fd7a:115c:a1e0::1`, `10.0.0.1`.
- [ ] **Step 2: Run, and expect FAIL.**
- [ ] **Step 3: Implement.**
- [ ] **Step 4: Run, and expect PASS.** Also run `cargo clippy -p fleet-agent -- -D warnings`.
- [ ] **Step 5: Commit.**

### Task 8: Audit activation hook and agent modules

**Files:**
- Create: `modules/fleet/audit-hook.nix`, `modules/fleet/agent.nix`
- Modify: `modules/system.nix` (add `./fleet`)

**Interfaces:**
- Consumes: the `fleet` specialArg (Task 2) and `inputs.self.packages.${system}.fleet-agent` (Task 3).
- Produces these options:
  - `services.fleet-agent.{enable (default fleet.member), port (7461), managerHost ("nixos-manager"), repoUrl, flakePath (default "/home/<user>/.flake" or "/Users/<user>/.flake"), rebuildCommand (null), revisionCommand (null, test-only), listen (null), package}`
  - The module writes `/etc/fleet-agent/config.json` (`environment.etc`) matching `AgentConfig`, with `host = currentSystemName`, `user = user.name`, `channel = fleet.channel`, `os` from the platform, and `launcher` = `systemd_run` (linux) or `detach` (darwin).

Rules:
- **Linux:** `systemd.services.fleet-agent`:
  - `wantedBy = [ "multi-user.target" ]`, `after = [ "tailscaled.service" "network-online.target" ]`
  - `path`/`environment.PATH` from Global Constraints
  - `serviceConfig.StateDirectory = "fleet-agent"`
  - **not** `restartIfChanged = false`: the apply survives a restart because it runs in its own unit.
- **Darwin:** `launchd.daemons.fleet-agent.serviceConfig`:
  - `ProgramArguments = [ "<pkg>/bin/fleet-agent" "serve" "--config" "/etc/fleet-agent/config.json" ]`
  - `RunAtLoad = true`, `KeepAlive = true`, `AbandonProcessGroup = true`
  - `EnvironmentVariables = { PATH = …; HOME = "/var/root"; }`
  - `StandardOutPath`/`StandardErrorPath = "/var/log/fleet-agent.log"`
  - Create `/var/lib/fleet-agent` in `system.activationScripts.postActivation`.
- Use platform guards with `lib.optionalAttrs hostPlatform.is…` around the `systemd`/`launchd` attrsets, combined with `lib.mkMerge`.
- **Audit hook:** a shell snippet, enabled whenever `services.fleet-agent.enable`.
  - NixOS: `system.activationScripts.fleetAudit = { deps = [ ]; text = …; }`
  - Darwin: `system.activationScripts.postActivation.text = lib.mkAfter …`
  - It appends one JSON line `{time, store_path, revision, generation, trigger, sudo_user}` to `/var/lib/fleet-agent/activations.jsonl`, with the fields defined in the spec's "Audit log" section.
  - `store_path` comes from `$systemConfig`. `revision` comes from `$systemConfig/configuration-revision` if present, else from `jq -r .configurationRevision $systemConfig/darwin-version.json`, else `"unknown"`.
  - It uses `${pkgs.jq}/bin/jq -nc` to build the line.
  - The whole snippet is wrapped in `( … ) || true`.
  - **The `line` field is not written; the agent derives it from the line number.**
- In `activations.rs`, also skip lines whose JSON lacks the required fields. The Task 7 test already covers partial lines.

- [ ] **Step 1: Failing eval.** Temporarily set `fleet = true;` in `hermes.nix` and `atlas.nix`. Before the change, `nix eval .#nixosConfigurations.hermes.config.systemd.services.fleet-agent.serviceConfig.ExecStart` fails.
- [ ] **Step 2: Implement both modules.**
- [ ] **Step 3: Verify.**
  - The ExecStart eval prints a path.
  - `nix eval --raw .#darwinConfigurations.atlas.config.environment.etc."fleet-agent/config.json".text` shows `"launcher":"detach"` and `"flake_path":"/Users/thijsvanwaaij/.flake"`.
  - `nix eval .#darwinConfigurations.atlas.config.launchd.daemons.fleet-agent.serviceConfig.AbandonProcessGroup` prints `true`.
  - `nix eval --raw .#nixosConfigurations.hermes.config.system.activationScripts.fleetAudit.text` contains `activations.jsonl`.
  - Extract that snippet into a file. Running it in a shell with `systemConfig=/run/current-system` and the state dir pointed at a temp dir (template the path with a variable for this) appends a valid JSON line on darwin.
  - Revert the temporary `fleet = true` edits.
  - The five evals from Task 1 still pass.
- [ ] **Step 4: Commit.**

### Task 9: Server config, database, migrations

**Files:**
- Create: `fleet-server/src/{main.rs,config.rs,db/mod.rs,db/entities/*.rs}` and `fleet-server/migration/` (crate `fleet-migration`)
- Test: `fleet-server/tests/db.rs`

**Interfaces:** Produces:

```rust
pub struct ServerConfig { pub listen: SocketAddr, pub agent_port: u16, pub hosts_file: PathBuf,
    pub repo_url: String, pub push_url: String, pub deploy_key_file: Option<PathBuf>,
    pub state_dir: PathBuf, pub access: AccessConfig, pub online: OnlineSource,
    pub mirror_fetch_secs: u64 /*300*/, pub poll_secs: u64 /*60*/, pub tailscale_bin: PathBuf }
pub enum AccessConfig { Tailscale { allowed_users: Vec<String>, allowed_tags: Vec<String> }, Disabled }
pub enum OnlineSource { Tailscale, Static { addresses: HashMap<String, String> } }  // Static: tests/dev, always online
pub struct FleetHost { pub name: String, pub system: String, pub user: String, pub channel: String, pub os: String }
pub fn load_hosts(path: &Path) -> anyhow::Result<Vec<FleetHost>>;
pub async fn connect(state_dir: &Path) -> anyhow::Result<DatabaseConnection>; // sqlite://<dir>/fleet.db?mode=rwc, runs Migrator::up
```

Tables, as SeaORM entities:
- `host_state`: `name` PK, `last_status` JSON nullable, `last_ok_at` i64 nullable, `activations_next` i64 default 0
- `applies`: `apply_id` PK, `host`, `commit`, `requested_by`, `requested_at`, `state`, `skip_reason` nullable, `message` nullable, `exit_code` nullable, `started_at`, `finished_at`, `log` text nullable
- `desired_applies`: `host` PK, `apply_id`
- `audit_events`: `id` autoincrement, `time`, `host` nullable, `kind`, `actor`, `details` JSON

Repository functions in `db/mod.rs`:
- `insert_apply`
- `update_apply_from_record(&ApplyRecord)`
- `set_desired(host, apply_id)`
- `desired(host) -> Option<applies::Model>`
- `save_status(host, &AgentStatus, now)`
- `insert_audit(time, host, kind, actor, details)`
- `recent_audit(limit) -> Vec<AuditEvent>`
- `activations_next(host)` / `set_activations_next(host, n)`

- [ ] **Step 1: Failing tests** against a temp-dir sqlite:
  - `migrations_run_twice_ok`
  - `desired_roundtrip`
  - `audit_insert_and_list_newest_first`
  - `status_roundtrip_json`
- [ ] **Step 2: Run, and expect FAIL.**
- [ ] **Step 3: Implement.** The SeaORM features are `sqlx-sqlite`, `runtime-tokio-rustls` and `macros`.
- [ ] **Step 4: Run, and expect PASS.**
- [ ] **Step 5: Commit.**

### Task 10: Git mirror and promote

**Files:**
- Create: `fleet-server/src/mirror.rs`
- Test: `fleet-server/tests/mirror.rs`

**Interfaces:** Produces:

```rust
pub struct Mirror { /* path = <state_dir>/mirror.git, repo_url, push_url, deploy_key */ }
impl Mirror {
  pub async fn open_or_init(cfg: &ServerConfig) -> anyhow::Result<Mirror>;  // git init --bare + fetch
  pub async fn fetch(&self) -> anyhow::Result<()>;                          // '+refs/heads/*:refs/heads/*' --prune
  pub async fn head(&self, channel: &str) -> Option<String>;
  pub async fn subject(&self, commit: &str) -> Option<String>;
  pub async fn behind_count(&self, running: &str, channel: &str) -> Option<u32>; // strips "-dirty"; None if not 40-hex or not in mirror
  pub async fn promote_candidate(&self) -> Option<String>;  // unstable head if stable is a strict ancestor of it
  pub async fn promote(&self, commit: &str) -> anyhow::Result<()>; // checks ancestry (commit ancestor of unstable,
      // stable ancestor of commit) then `git push <push_url> <commit>:refs/heads/stable` with
      // GIT_SSH_COMMAND="ssh -i <key> -o IdentitiesOnly=yes -o StrictHostKeyChecking=accept-new"
}
```

All git calls go through `tokio::process::Command`.

- [ ] **Step 1: Failing tests.** Use a local bare repo as both `repo_url` and `push_url`, with no deploy key.
  - `head_after_fetch`
  - `behind_strips_dirty`: `"<c1>-dirty"` with 2 commits after it → `Some(2)`
  - `behind_unknown_for_foreign_or_unknown`: `"unknown"` → `None`; a random 40-hex → `None` (Review Focus 5)
  - `promote_rejects_non_ancestor`
  - `promote_fast_forwards_stable`
  - `promote_candidate_none_when_equal`
  - `fetch_error_is_err`: a bogus URL returns `Err` and doesn't panic (Review Focus 3)
- [ ] **Step 2: Run, and expect FAIL.**
- [ ] **Step 3: Implement.**
- [ ] **Step 4: Run, and expect PASS.**
- [ ] **Step 5: Commit.**

### Task 11: Tailscale source and access control

**Files:**
- Create: `fleet-server/src/tailscale.rs`, `fleet-server/src/access.rs`
- Test: `fleet-server/tests/access.rs`, plus fixture files `fleet-server/tests/fixtures/{status.json,whois-user.json,whois-tagged.json}` (realistic shapes: `Peer` map with `HostName`, `DNSName`, `Online`, `LastSeen`, `OS`, `TailscaleIPs`, `Tags`; whois with `UserProfile.LoginName` and `Node.Tags`)

**Interfaces:** Produces:

```rust
pub struct PeerInfo { pub host: String, pub online: bool, pub last_seen: Option<i64>, pub os: String, pub addr: Option<IpAddr> }
pub fn parse_status(json: &str) -> anyhow::Result<HashMap<String, PeerInfo>>;  // key = HostName lowercased
pub struct Identity { pub login: Option<String>, pub tags: Vec<String>, pub node: String }
pub fn parse_whois(json: &str) -> anyhow::Result<Identity>;
pub trait OnlineProvider: Send + Sync { async fn peers(&self) -> HashMap<String, PeerInfo>; async fn whois(&self, ip: IpAddr) -> Option<Identity>; }
pub struct TailscaleCli { /* bin, 30s status cache, 60s whois cache */ }  // impl OnlineProvider
pub struct StaticOnline { /* from OnlineSource::Static */ }               // impl OnlineProvider, whois → None
// access.rs
pub enum Access { Allowed { actor: String }, Denied }
pub fn decide(cfg: &AccessConfig, id: Option<&Identity>) -> Access; // Disabled → Allowed{actor:"dev"}
pub async fn require_access(...) // axum middleware: 403 on Denied, inserts Actor extension
```

Actor = the login if present, otherwise the node name.

- [ ] **Step 1: Failing tests:**
  - `parse_status_fixture` (online and offline peers)
  - `user_login_allowed`
  - `tagged_nixos_allowed` (actor = node name)
  - `tagged_other_denied` (`tag:server`)
  - `no_identity_denied`
  - `disabled_allows`
  - `middleware_403`: a router with the middleware and a fake provider returning a foreign identity gets 403 on `/api/snapshot` and on `/api/ws`.
- [ ] **Step 2: Run, and expect FAIL.**
- [ ] **Step 3: Implement.**
- [ ] **Step 4: Run, and expect PASS.**
- [ ] **Step 5: Commit.**

### Task 12: Agent client, poller and re-send rules

**Files:**
- Create: `fleet-server/src/{agent_client.rs,resend.rs,poller.rs,state.rs}`
- Test: `fleet-server/tests/resend.rs`, `fleet-server/tests/poller.rs`

**Interfaces:** Produces:

```rust
// resend.rs (pure)
pub fn should_resend(desired: Option<&str /*apply_id*/>, desired_commit: Option<&str>,
                     status: &AgentStatus) -> bool;
// true iff desired is Some, status.running (minus "-dirty") != desired_commit,
// status.apply.map(|a| a.apply_id) != desired, and status.apply is not Running.
// agent_client.rs
pub struct AgentClient { /* reqwest::Client, 10s timeout, port */ }
impl AgentClient { status(addr)->Result<AgentStatus>; apply(addr,&ApplyRequest)->Result<StatusCode>;
                   log(addr,id,offset)->Result<LogChunk>; activations(addr,since)->Result<ActivationsResponse> }
// state.rs: shared app state
pub struct AppState { db, mirror: Arc<Mirror>, online: Arc<dyn OnlineProvider>, client: AgentClient,
                      hosts: Vec<FleetHost>, tx: broadcast::Sender<WsMessage>, cfg: Arc<ServerConfig> }
pub async fn host_view(state: &AppState, host: &FleetHost) -> HostView;
pub async fn snapshot(state: &AppState, viewer: String) -> Snapshot;
// poller.rs
pub async fn poll_once(state: &AppState);   // per host: peers() → off / status() → save, audit apply transitions,
    // pull new activations into audit_events (kind "activation"), should_resend → apply(), broadcast HostUpdated
pub async fn follow_log(state: &AppState, host: &FleetHost, apply_id: &str); // every 2s while Running: log(offset)
    // → broadcast ApplyLog; at eof store full log in applies.log
pub fn spawn(state: AppState);              // mirror fetch every 300s (+ChannelsUpdated), poll every 60s
```

Audit kinds:
- `apply_requested`, `promote` (from the API)
- `apply_finished` (from the poller, written when the agent's record for an apply first shows a terminal state; details = the record)
- `activation`

- [ ] **Step 1: Failing tests.** `resend.rs` covers the table of cases (Review Focus 4 and 5):
  - never received → true
  - same id `Failed` → false
  - same id `Skipped` → false
  - other id `Running` → false
  - other id finished and still behind → true
  - running == desired commit → false
  - running `"<desired>-dirty"` → false
  - no desired → false

  `poller.rs` uses an in-process fake agent: an axum router on `127.0.0.1:0` serving canned `/status` and `/activations` and recording `/apply` bodies, with `StaticOnline`.
  - `poll_saves_status_and_ingests_activations_once`: two polls give one audit row per activation.
  - `poll_resends_missed_apply`
  - `poll_does_not_resend_failed`
  - `offline_host_not_contacted`
- [ ] **Step 2: Run, and expect FAIL.**
- [ ] **Step 3: Implement.**
- [ ] **Step 4: Run, and expect PASS.**
- [ ] **Step 5: Commit.**

### Task 13: REST API, WebSocket, embedded frontend, `main`

**Files:**
- Create: `fleet-server/src/{api.rs,ws.rs,embed.rs}`, complete `main.rs`
- Test: `fleet-server/tests/api.rs`

**Interfaces:** Produces these routes. All routes except static assets sit behind `require_access`, and static assets are only served to allowed viewers as well.
- `GET /api/snapshot` → `Snapshot`
- `POST /api/hosts/{name}/apply`:
  1. `mirror.fetch()`. On error: `502` with `{error}`, and no row is created (Review Focus 3).
  2. Resolve `head(channel)`. If missing: `409`.
  3. Insert the apply (`requested_by` = actor), `set_desired`, write audit `apply_requested`.
  4. If the host is online, `client.apply`.
  5. Answer `202 {apply_id}`, and include `agent_status` (`202`/`409`/`unreachable`).
- `POST /api/channels/{channel}/apply` → the same for every host on that channel, one fetch, `202 {apply_ids}`.
- `POST /api/promote {commit}` → `mirror.fetch()`, then `mirror.promote(commit)`, audit `promote`, broadcast `ChannelsUpdated`, `200`. Ancestry errors give `409`.
- `GET /api/hosts/{name}/applies/{id}/log` → text: the stored log, or else the live `client.log(…, 0)`.
- `GET /api/audit?limit=100` → `Vec<AuditEvent>`
- `GET /api/ws`: after the upgrade, send `Snapshot` first, then forward the broadcast `WsMessage`s. A lagged receiver gets a fresh `Snapshot`.
- `embed.rs`: `#[derive(RustEmbed)] #[folder = "$FLEET_WEB_DIST"]` with the `interpolate-folder-path` feature. The SPA fallback is `index.html`.
  - For `cargo test` and dev, `build.rs` sets `FLEET_WEB_DIST` to `web/dist` when it isn't set, and creates the directory with a placeholder `index.html` if it is missing.
- `main.rs`: `fleet-server --config <path>`. It opens the DB and mirror, builds the provider from `online`, spawns the poller, and serves with `into_make_service_with_connect_info::<SocketAddr>()`.
  - With `AccessConfig::Tailscale`, the listen address must be a Tailscale IP. Otherwise refuse to start with a clear error.

- [ ] **Step 1: Failing tests.** Use the fake agent from Task 12, `StaticOnline`, `AccessConfig::Disabled` and a local bare repo.
  - `apply_endpoint_creates_desired_and_hits_agent`
  - `apply_endpoint_502_when_mirror_fetch_fails` (no row in `applies`)
  - `channel_apply_targets_only_that_channel`
  - `promote_moves_stable_and_audits`
  - `ws_sends_snapshot_first`: connect with `tokio-tungstenite` to a server on `127.0.0.1:0`.
  - `spa_fallback_serves_index`
- [ ] **Step 2: Run, and expect FAIL.**
- [ ] **Step 3: Implement.**
- [ ] **Step 4: Run, and expect PASS.** Also run `cargo clippy --workspace -- -D warnings`.
- [ ] **Step 5: Commit.**

### Task 13b: Demo mode

Added at the user's request: demo mode is part of fleet, so the real server and dashboard can be run and shown without any enrolled machine.

**Files:**
- Create: `fleet-server/src/demo/{mod.rs,repo.rs,agents.rs,online.rs}`
- Modify: `fleet-server/src/main.rs` (subcommands), `fleet-proto/src/lib.rs` (`Snapshot.demo: bool` + regenerated bindings), `fleet-server/src/state.rs` (`AppState.demo` flag → snapshot), `flake.nix` (`apps.<sys>.fleet-demo`)
- Test: `fleet-server/tests/demo.rs`

**Interfaces:**
- Consumes: `AppState`, `poller::spawn`, `api::router` (Task 13), `OnlineProvider` (Task 11), `Mirror` (Task 10), fleet-proto agent types.
- Produces:
  - CLI `fleet-server demo [--listen 127.0.0.1:8080] [--speed <f64, default 1.0>]`; `fleet-server --config <path>` keeps working (make it `fleet-server serve --config` and keep the bare `--config` form as an alias).
  - `pub async fn demo::start(listen: SocketAddr, speed: f64) -> anyhow::Result<DemoHandle>` (returns once the server is listening; `DemoHandle { addr, state: AppState, _tmp: TempDir }`, dropping it stops everything). `--listen` with a non-loopback IP prints a warning (access control is off in demo mode) but is allowed.
  - `Snapshot.demo: bool` (`#[serde(default)]`), true only in demo mode.

Behaviour (all timings divided by `speed`):
- `repo.rs`: a temp dir with a bare repo `fleet.git` and a work clone. Seeds 12 commits on `unstable` with realistic subjects from this repo's history (e.g. `fix(vscodium): run the settings.json edit as the user`, `feat(fleet): agent service modules and activation audit hook`), and `stable` at the 8th. Every 180 s a background task commits a new realistic subject to `unstable` and pushes it. The server config uses the bare repo path as both `repo_url` and `push_url` (no deploy key), so promote works for real.
- `agents.rs`: one in-process simulated agent per demo host, each an axum router on `127.0.0.1:0` implementing the exact agent API (`GET /status`, `POST /apply`, `GET /apply/log`, `GET /activations`) with the agent's status codes (202 / 200 duplicate id / 409 busy / 400 bad input). An apply streams realistic log lines (fetch, checks, `nix build …`, `building '/nix/store/…-nixos-system-<host>…drv'`, switch/activate) over ~10 s, then:
  - `ok`: running revision becomes the commit, an activation line with trigger `apply:<id>` is appended
  - per-host scripted outcomes below
- Demo hosts (FleetHost list, `os` from system):
  | host | system | channel | starts at | scripted behaviour |
  |---|---|---|---|---|
  | atlas | aarch64-darwin | unstable | 3 behind | checkout dirty → every apply `skipped: dirty` |
  | apollo | aarch64-darwin | unstable | 5 behind | offline for the first 120 s, then online (shows re-send of a pending apply) |
  | hermes | x86_64-linux | unstable | 2 behind | applies succeed |
  | hephaestus | x86_64-linux | unstable | 1 behind | Tailscale online but agent unreachable (router returns no listener) |
  | nixos-manager | x86_64-linux | stable | up to date | applies succeed |
  | vpn | x86_64-linux | stable | 1 behind | applies succeed |
  | media | x86_64-linux | stable | 1 behind | first apply fails (exit 1, `error: builder for '…' failed`), later ones succeed |
  Each host starts with one `manual` activation (with `sudo_user`) a few hours in the past.
- `online.rs`: `DemoOnline` implementing `OnlineProvider`: peers from the table (addr = the simulated agent's `127.0.0.1:<port>`, using the Static `ip:port` convention from Task 12), online flags per the table and timeline; `whois` → None. Access is `AccessConfig::Disabled`.
- The poller runs with `poll_secs = 5 / speed` (min 1) and `mirror_fetch_secs = 30 / speed` so the demo feels live; SQLite lives in the temp dir.
- `nix run .#fleet-demo` = `fleet-server demo`.

- [ ] **Step 1: Failing tests** (`tests/demo.rs`, all with `speed = 20.0`):
  - `demo_starts_and_serves_snapshot`: `GET /api/snapshot` → 7 hosts, `demo == true`, channels unstable+stable with heads, atlas `checkout.dirty == true`.
  - `demo_apply_hermes_reaches_ok`: POST apply hermes → 202; within 10 s the snapshot shows hermes `running == unstable head` and last_apply `ok`.
  - `demo_apply_atlas_skips_dirty`: → last_apply `skipped`, `skip_reason == dirty`.
  - `demo_media_first_apply_fails`: → `failed` with an exit code.
  - `demo_apollo_resend_after_online`: apply apollo while offline (`agent_status == "unreachable"`), then after it comes online the poller re-sends and it reaches `ok`.
  - `demo_promote_moves_stable`: POST promote with the promote candidate → 200, snapshot stable head == that commit.
- [ ] **Step 2: Run, and expect FAIL.**
- [ ] **Step 3: Implement.** Regenerate the TS bindings (`TS_RS_EXPORT_DIR=../web/src/bindings cargo test -p fleet-proto`), commit them.
- [ ] **Step 4: Verify.** `cargo test -p fleet-server`, workspace clippy `-D warnings`, `nix build .#fleet-server`, `nix build .#checks.aarch64-darwin.fleet-bindings`, and `nix run .#fleet-demo` then `curl -s 127.0.0.1:8080/api/snapshot | head -c 300` shows `"demo":true`.
- [ ] **Step 5: Commit.**

### Task 14: Frontend (Preact + shadcn)

**Files:**
- Create in `pkgs/fleet/web/`:
  - config: `package.json`, `package-lock.json`, `vite.config.ts`, `tsconfig.json`, `components.json`, `index.html`
  - app: `src/main.tsx`, `src/App.tsx`, `src/api.ts`, `src/ws.ts`, `src/format.ts`, `src/format.test.ts`, `src/index.css`
  - components: `src/components/{HostTable,HostRow,ApplyLogSheet,PromoteDialog,ChannelBar}.tsx`
  - shadcn components under `src/components/ui/`

**Interfaces:**
- Consumes: `src/bindings/*.ts` (Task 3) and the routes from Task 13.
- Produces:
  - `format.ts` exports `shortRev(rev: string): string` (7 chars, keeps `-dirty`)
  - `behindLabel(n: number | null): string` (`"up to date"` / `"3 behind"` / `"unknown"`)
  - `onlineLabel(h: HostView, now: number): string` (`"off · last seen 5m ago"` / `"on, agent unreachable"` / `"on"`)
  - `applyBadge(a: ApplyRecord | null): { text: string; variant: "default"|"secondary"|"destructive"|"outline" }`

Setup:
- Vite with `@preact/preset-vite` and `@tailwindcss/vite`.
- Aliases `react` → `preact/compat` and `react-dom` → `preact/compat` (also `react/jsx-runtime` → `preact/jsx-runtime`), plus `@` → `src`.
- Dev proxy `/api` (ws: true) → `http://127.0.0.1:8080`.
- Add the shadcn components with the CLI (`npx shadcn@latest add button table badge sheet dialog tooltip sonner`).

UI, as listed in the spec's Dashboard bullet:
- one table row per host, with an "Apply newest" button
- a channel bar with "Apply newest to all on <channel>" and "Promote unstable → stable"
- the log opens in a Sheet that appends `ApplyLog` chunks live
- Promote asks for confirmation in a Dialog that shows the commit subject
- toasts for API errors (502/409)

`ws.ts` reconnects with backoff 1 s doubling to 30 s and replaces state on every `Snapshot`.

- [ ] **Step 1: Failing test.** `format.test.ts` (vitest) covers each label function with the cases named above.
- [ ] **Step 2: Run it and expect FAIL.** `nix develop .#fleet -c sh -c 'cd web && npm ci && npx vitest run'`
- [ ] **Step 3: Implement the app.**
- [ ] **Step 4: Verify.**
  - `npx vitest run` and `npx tsc --noEmit` pass, and `npm run build` produces `web/dist/index.html`.
  - Run `fleet-server demo` (Task 13b) and point the Vite dev server at it. The dashboard shows a "Demo" banner when `snapshot.demo` is true.
  - Open `http://127.0.0.1:8080` in the browser pane and check: the host row renders, Apply shows running → ok with a live log, and the dirty-skip reason shows. Screenshot it.
- [ ] **Step 5: Commit**, including `package-lock.json`.

### Task 15: Nix packages, server module, flake checks

**Files:**
- Modify: `pkgs/fleet/default.nix`, `flake.nix`
- Create: `modules/fleet/server.nix`

**Interfaces:**
- Produces:
  - `packages.<sys>.{fleet-web,fleet-server,fleet-agent}`
  - `services.fleet-server.{enable, package, listenPort (8080), repoUrl, pushUrl, deployKeyFile (null), allowedUsers (["Waayway@github"]), allowedTags (["tag:nixos" "tag:personal" "tag:fleet"]), listenAddress (string, required: nixos-manager's Tailscale IPv4)}`
- The module writes `/etc/fleet-server/hosts.json` from `fleet.hosts` and `/etc/fleet-server/config.json`.
- Service: `systemd.services.fleet-server` with `StateDirectory = "fleet-server"` and `after = [ "tailscaled.service" ]`.
  - Use `ExecStartPre` to wait until the listen address exists, or `Restart = "on-failure"` with `RestartSec = 5`.
  - `path = [ git openssh tailscale ]`.
- Linux only (`lib.optionalAttrs hostPlatform.isLinux`).

Steps:
- [ ] **Step 1: Build the frontend in Nix.** `fleet-web` = `buildNpmPackage` with `src = ./web`, `npmDepsHash` (get it from the first failing build), `installPhase` copying `dist`.
- [ ] **Step 2: Embed it in the server.** `fleet-server` sets `FLEET_WEB_DIST = "${fleet-web}"` in the crane `buildPackage` args only (not `buildDepsOnly`).
- [ ] **Step 3: Enable on nixos-manager.**
  - `nixos-manager.nix` gets `fleet = true;` and `services.fleet-server.enable = true`.
  - `listenAddress` stays a placeholder `"100.92.102.84"` (its last known tailnet IP, from `tailscale status`), with a comment to confirm it at bootstrap.
- [ ] **Step 4: Verify.**
  - `nix build .#fleet-server` succeeds on darwin, and `strings result/bin/fleet-server | grep -c '<div id="app"'` is ≥ 1.
  - `nix eval .#nixosConfigurations.nixos-manager.config.system.build.toplevel.drvPath` succeeds.
  - `nix eval --raw .#nixosConfigurations.nixos-manager.config.environment.etc."fleet-server/hosts.json".text` lists nixos-manager.
  - `nix flake check --no-build` passes.
- [ ] **Step 5: Commit.**

### Task 16: NixOS VM test

**Files:**
- Create: `tests/fleet-vm.nix`
- Modify: `flake.nix` (`checks.x86_64-linux.fleet-vm`)

**Interfaces:** Consumes `modules/fleet/{agent,server}.nix`. Import them directly (not through `mkSystem`), with a minimal `fleet` specialArg, `_module.args` for `hostPlatform`/`user`/`currentSystemName`, and these settings:
- agents: `rebuildCommand` set to a fake script that writes `$2` into a file the test's `revision_command` reads, and `listen = "0.0.0.0:7461"`
- server: `OnlineSource::Static` and `AccessConfig::Disabled`

The server config JSON options needed for this (`online`, `access`) are exposed as `services.fleet-server.testing.{staticAddresses, disableAccess}`, documented as test-only.

Nodes:
- `remote`: a git daemon serving a bare repo with `unstable` and `stable`, over `git://`, so `repoUrl = "git://remote/fleet.git"`
- `manager`: the server, plus an agent for itself
- `laptop1`, `laptop2`: agents on `unstable`. `managerHost = "manager"` resolves through `/etc/hosts`.

Each agent's user has a clone at `/home/<user>/.flake` made in the test script.

Script:
1. Wait for the units to start.
2. `curl -X POST manager:8080/api/hosts/laptop1/apply` → 202.
3. Wait until `/api/snapshot` shows laptop1 running the head.
4. Make laptop2 dirty, then apply. Its snapshot shows `skip_reason == "dirty"` and its HEAD is unchanged.
5. `curl` from laptop1 to `laptop2:7461/status` → 403 (source check).
6. Stop laptop1's agent, push a new commit to `remote`, and apply laptop1 (agent down → `unreachable`). Start the agent again, and within 2 poll intervals (set `poll_secs` to 5 for the test) laptop1 runs the new head (re-send).

Steps:
- [ ] **Step 1: Write the test.**
- [ ] **Step 2: Verify.** `nix eval .#checks.x86_64-linux.fleet-vm.drvPath` evaluates. Running it needs an x86_64-linux builder with KVM, which this Mac doesn't have, so state that in the commit message and in the handoff below. Do not claim it passed.
- [ ] **Step 3: Commit.**

### Task 17: Docs

**Files:** Modify `AGENTS.md / docs/fleet.md`, `README.md` (short "Fleet manager" section).

- [ ] **Step 1: Write it.** Document:
  - how to run it locally (dev config, `nix develop .#fleet`, `npm run dev`)
  - how a host joins (`fleet = true`, channel)
  - which steps still need the user: the follow-ups below
  - that the VM test hasn't been run (no Linux builder)
- [ ] **Step 2: Commit.**

---

## Follow-ups (need the user; not in this plan)

1. **Branch rename** on GitHub: `main` → `unstable` (also the default branch), create `stable`, add a ruleset on `stable`. Then rename the branch in each checkout and update the push command in HANDOFF.
2. **nixos-manager bootstrap:**
   - start VM 170, clone the repo to `/home/manager/.flake` on `stable`
   - add the host's age key to `.sops.yaml`
   - create `secrets/nixos-manager.yaml` with a write deploy key and a Tailscale auth key
   - confirm `listenAddress`, then do the first switch
3. **Tailscale ACL:** `tag:fleet` on enrolled hosts, `tag:manager → tag:fleet:7461`, and dashboard access for `Waayway@github`, `tag:nixos` and `tag:personal`.
4. **Enrolment:** `fleet = true` on atlas, apollo, hermes and hephaestus, followed by a real apply on hermes and on atlas.
5. **A Linux builder for running the VM test:** `nix.linux-builder` on atlas, or a remote builder on pve.
6. Fix `template/proxmox.nix`, which imports the non-existent `modules/base/*` and `modules/servers/*`.
7. VM migration (spec, "Migration of the homelab").
