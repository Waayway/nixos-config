# Repo restructure: implementation plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Sort `modules/` into `common/`, `workstation/`, `server/`, split `lib/`
into `lib/` (builders) and `tools/` (module helpers), and fix what was on the
wrong hosts (dev toolchains, sshd, root's key, server shell, GPU config).

**Architecture:** Phase 1 (Tasks 1–3) moves files without changing any host;
a snapshot of all 9 configurations proves it. Phase 2 (Tasks 4–9) changes behaviour,
one commit per change, each with a written expected snapshot diff. Task 10
updates docs, Task 11 rolls out.

**Tech Stack:** Nix flakes, NixOS 26.05, nix-darwin, home-manager,
nixos-hardware.

**Spec:** `docs/plans/2026-10-21-repo-restructure-design.md`

## Global Constraints

- Every module is imported on every host; folders are structure only. A file
  under `server/` is gated on `isServer` or a server-only option; under
  `workstation/` on `!isServer`, a workstation-only option, or home-manager.
- Platform gating stays `lib.optionalAttrs hostPlatform.isLinux` / `isDarwin`
  around the whole module, never `mkIf`.
- Never merge attrsets with `//` when both sides can share a top-level key;
  use `lib.mkMerge`.
- `git mv` for every move (history). New files must be `git add`ed before
  evaluating.
- Format touched `.nix` files with
  `$(nix build --no-link --print-out-paths --inputs-from . nixpkgs#nixfmt)/bin/nixfmt <files>`.
- Commit only your own paths (`git commit -m "…" -- <paths>`), conventional
  style, ending with `Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>`,
  as `Thijs van Waaij <thijs@vanwaaij.com>`. Never stash/reset the user's work.
- Work on `unstable`, in the checkout (no worktrees). Don't push until Task 11,
  and ask first.
- Old plans in `docs/plans/` are history: don't rewrite their paths.

## Review Focus

1. **A path that moved but a reference didn't**: `wallpapers_home.nix`'s
   `../../wallpapers` needs one more `../`; `../identity/branding/…` in
   immich/jellyfin/nextcloud stays valid only because services and identity
   both end up under `server/`. Covered by the eval + snapshot in Task 3.
2. **A darwin eval breaking on a Linux-only option** in a file that used to
   be Linux-only and is now split (zsh, openssh, tailscale, user). Every task
   evals atlas and apollo.
3. **Losing SSH to a laptop** when sshd goes off (Task 6). Task 11 tests
   Tailscale SSH to hermes and hephaestus before they apply it.
4. **The workstation shell quietly changing** (Task 5): duplicate compinit,
   lost aliases, two prompts. Task 5 compares the generated rc files.
5. **prod's transcoding breaking** after the Intel profile (Task 8): Task 11
   checks `vainfo`, Jellyfin QSV and Immich OpenVINO on prod.

---

### Task 1: Snapshot harness and baseline

**Files:**
- Create: `$S/snapshot.nix` and `$S/snap.sh`, where `$S` is the session
  scratchpad (not committed).

**Interfaces:**
- Produces: `$S/snap.sh <name>` writes `$S/<name>.json` (normalised, sorted).
  Later tasks run `$S/snap.sh after-N` and
  `diff <(jq -S . $S/base.json) <(jq -S . $S/after-N.json)`.

- [ ] **Step 1: Write `$S/snapshot.nix`**: a function of the flake returning
  `{ nixos.<host> = …; darwin.<host> = …; }`, with only JSON-safe values:

```nix
flake:
let
  lib = flake.inputs.nixpkgs.lib;
  names = ps: lib.sort lib.lessThan (map (p: p.name or (toString p)) ps);
  on = lib.filterAttrs (_: v: v.enable or false);
  hm = c: lib.mapAttrs (_: u: {
    files = lib.attrNames u.home.file;
    xdg = lib.attrNames u.xdg.configFile;
    packages = names u.home.packages;
    zsh = { inherit (u.programs.zsh) enable enableCompletion shellAliases; init = u.programs.zsh.initContent; };
    starship = u.programs.starship.enable;
  }) (c.home-manager.users or { });
  users = c: lib.mapAttrs (_: u: {
    keys = u.openssh.authorizedKeys.keys;
    shell = if u.shell == null then null else u.shell.name or (toString u.shell);
  } // lib.optionalAttrs (u ? linger) { inherit (u) linger extraGroups; })
    (lib.filterAttrs (n: u: n == "root" || (u.isNormalUser or true)) c.users.users);
  common = c: {
    packages = names c.environment.systemPackages;
    etc = lib.attrNames (on c.environment.etc);
    aliases = c.environment.shellAliases;
    users = users c;
    hm = hm c;
    zsh = c.programs.zsh.enable;
  };
  homelab = c: lib.mapAttrs (_: v: v.enable or null) (c.homelab or { })
    // { routes = c.homelab.routes or null; access = c.homelab.access or null; };
in
{
  nixos = lib.mapAttrs (_: s: let c = s.config; in common c // {
    homelab = homelab c;
    openssh = { inherit (c.services.openssh) enable openFirewall settings; };
    tailscale = { inherit (c.services.tailscale) enable extraUpFlags authKeyFile; };
    services = lib.attrNames (on c.systemd.services);
    userServices = lib.attrNames (on c.systemd.user.services);
    ports = { inherit (c.networking.firewall) allowedTCPPorts allowedUDPPorts; };
    graphics = { inherit (c.hardware.graphics) enable enable32Bit; extra = names c.hardware.graphics.extraPackages; };
    firmware = c.hardware.enableRedistributableFirmware;
    initrd = c.boot.initrd.kernelModules;
    kernelParams = c.boot.kernelParams;
    videoDrivers = c.services.xserver.videoDrivers;
    xserver = c.services.xserver.enable;
    bluetooth = c.hardware.bluetooth.enable;
  }) flake.nixosConfigurations;
  darwin = lib.mapAttrs (_: s: let c = s.config; in common c // {
    defaults = c.system.defaults;
    casks = names c.homebrew.casks;
    brews = names c.homebrew.brews;
    onActivation = c.homebrew.onActivation;
    launchd = lib.attrNames c.launchd.daemons ++ lib.attrNames c.launchd.user.agents;
  }) flake.darwinConfigurations;
}
```

  If a field fails to evaluate on some host, drop that field for every host
  and note it here; don't wrap it in `tryEval`.

- [ ] **Step 2: Write `$S/snap.sh`**: runs
  `nix eval --json --impure --expr "import $S/snapshot.nix (builtins.getFlake \"git+file://$HOME/.flake\")"`,
  replaces `/nix/store/[a-z0-9]{32}-` with `/nix/store/H-`, pipes through
  `jq -S .` and writes `$S/$1.json`. (Untracked files are invisible to
  `git+file`: `git add` new files before snapping.)

- [ ] **Step 3: Baseline.** Run `$S/snap.sh base`.
  Expected: valid JSON with 7 `nixos` hosts (hephaestus, hermes, identity,
  nixos-manager, prod, router, router-test) and 2 `darwin` hosts (apollo, atlas). Then `$S/snap.sh base2` and `diff $S/base.json $S/base2.json`.
  Expected: no output (the snapshot is deterministic).

---

### Task 2: Split `lib/` into `lib/` and `tools/`

**Files:**
- Move: `lib/{mkAppCategory,color,routeType,routesFrom,accessType,accessFrom,accessProblems}.nix` → `tools/`
- Create: `tools/default.nix` (same body as `lib/default.nix`; comment says
  "helpers for modules, the `tools` specialArg")
- Modify: `lib/default.nix` (comment: "system builders, used by systems.nix as `builders`"),
  `systems.nix`, `programs.nix`, `lib/mkSystem.nix`, `lib/mkDarwin.nix`,
  comments in `tools/routesFrom.nix` / `tools/accessFrom.nix` (`lib/default.nix` → `tools/default.nix`)

**Interfaces:**
- Produces: in `systems.nix`, `builders = import ./lib { inherit lib; }` and
  `tools = import ./tools { inherit lib; }`; `builderArgs` carries both.
  `builders.{mkSystem,mkDarwin,mkHome,mkDeployNode,discoverHosts,mkUser,umport,importCurDir}`;
  `tools.{mkAppCategory,color,routeType,routesFrom,accessType,accessFrom,accessProblems}`.
  Modules still get `tools` (now `tools/`), `umport`, `importCurDir` as specialArgs.

- [ ] **Step 1:** `git mv` the seven files, create `tools/default.nix`.
- [ ] **Step 2:** In `systems.nix` use `builders.discoverHosts`, `builders.mkSystem`,
  `builders.mkDarwin`, `builders.mkDeployNode`. In `lib/mkSystem.nix` and
  `lib/mkDarwin.nix` take `builders` as an argument and use `builders.mkHome`,
  `builders.umport`, `builders.importCurDir`; `tools.color` stays. `programs.nix`:
  `tools = import ./tools { inherit lib; };`.
- [ ] **Step 3: Verify.** `git add -A lib tools`, then `$S/snap.sh after-2`,
  diff with `base`. Expected: no difference. The five host evals from AGENTS.md
  print drvPaths, and `nix flake check --no-build --keep-going` passes.
  `rg -n 'import \./lib' systems.nix programs.nix` shows exactly one line, in `systems.nix`.
- [ ] **Step 4: Commit** `refactor(lib): builders in lib/, module helpers in tools/`
  with paths `lib tools systems.nix programs.nix`.

---

### Task 3: Move the modules into `common/`, `workstation/`, `server/`

Pure moves. **Every condition stays exactly as it is**, even where it's wrong
for the new folder: Tasks 4–9 fix those.

**Files (the moves, `git mv`):**

| From | To |
|---|---|
| `boot/ console/ locale/ nix/ system/ packages/` | `common/<same>/` |
| `hardware/nixos-hardware.nix` | `common/hardware/` |
| `networking/{networking,firewall,resolved}.nix` | `common/networking/` |
| `shell/{zsh,git,neovim}.nix` | `common/shell/` |
| `lodestar/{agent.nix,lodestar-agent-signing.pem}` | `common/lodestar/` |
| `apps/ darwin/ desktop/ development/ gaming/` | `workstation/<same>/` |
| `hardware/` (everything else, incl. `graphics.nix`) | `workstation/hardware/` |
| `shell/{zsh_home,git_home,zellij_home,zoxide_home}.nix`, `shell/starship.toml` | `workstation/shell/` |
| `services/{docker,updates,nextcloud,immich,jellyfin}.nix` | `server/services/` |
| `homelab/` (all) + `services/lan.nix` | `server/homelab/` |
| `identity/ backup/ truenas/` | `server/<same>/` |
| `lodestar/server.nix` | `server/lodestar/` |
| `networking/openssh-server.nix` | `server/networking/openssh.nix` |
| `secrets/opnix.nix` | `server/secrets/` |
| `users/{proxmox-vms_rsa.pub,break-glass-root_ed25519.pub}` | `server/users/` |
| `vm-specific/proxmox-guest.nix` | `server/proxmox/` |
| `darwin/home.nix` | deleted (imported by nothing) |

**Files (splits, same conditions as today):**
- `networking/openssh.nix` → `common/networking/openssh.nix` (unchanged).
  `server/networking/openssh.nix` keeps its current `optionalAttrs isLinux`
  with no `isServer` gate (Task 6 adds it).
- `networking/tailscale.nix` → `common/networking/tailscale.nix` (the base
  `services.tailscale` block) + `server/networking/tailscale.nix` (the
  `mkIf hostPlatform.isServer` block, with `allTags`; args `config lib tags hostPlatform`).
- `users/user.nix` → `common/users/user.nix` (description, home, isNormalUser,
  groups, sudo, `root.hashedPassword = "!"`) + `server/users/user.nix`
  (`openssh.authorizedKeys.keys = lib.optional isServer proxmoxKey`,
  `linger = isServer`, root's break-glass key still on every Linux host).
  Both Linux parts inside `optionalAttrs isLinux`. Replace today's `//` with
  `lib.mkMerge` while splitting.
- `modules/system.nix` and `modules/home.nix`: `paths = [ ./common ./workstation ./server ]`
  (drop the `pathExists` filter and the old list). `home.nix` keeps its
  server warning.
- Fix `workstation/desktop/wallpapers_home.nix`: `../../wallpapers` → `../../../wallpapers`.

- [ ] **Step 1:** Do the moves and splits, `git add -A modules`.
- [ ] **Step 2:** `ls modules` shows exactly `common home.nix server system.nix workstation`.
  `find modules -maxdepth 1 -type d` has no old category left.
- [ ] **Step 3: Verify.** `$S/snap.sh after-3`, diff with `base`. Expected:
  no difference, except store paths whose only change is the module's
  new location (`…-source/modules/identity/…` → `…-source/modules/server/identity/…`).
  List those lines in the commit message body. Five host evals pass,
  `nix flake check --no-build --keep-going` passes.
- [ ] **Step 4: Commit** `refactor(modules): common/, workstation/, server/`
  with path `modules`.

---

### Task 4: Dev toolchains only on workstations

**Files:** Modify `modules/workstation/development/{go,java,js,python,rust,sql}.nix`.

- [ ] **Step 1:** Wrap each module's config in `lib.mkIf (!hostPlatform.isServer)`
  (python/sql: around their existing `mkMerge`; the darwin `optionalAttrs` parts
  stay inside).
- [ ] **Step 2: Verify.** `$S/snap.sh after-4`, diff with `after-3`.
  Expected: only the servers' `packages` change. These names disappear:
  `rustup`, `go`, `gotools`, `templ`, `go-task`, the jdk, `nodejs`,
  `python3`/`pip`/`virtualenv`, `uv`, and the sql tools. Workstations and
  darwin: no difference. Five evals pass.
- [ ] **Step 3: Commit** `fix(development): toolchains only on workstations`.

---

### Task 5: One system-wide zsh

**Files:**
- Modify: `modules/common/shell/zsh.nix`
- Move: `modules/workstation/shell/starship.toml` → `modules/common/shell/starship.toml`
- Modify: `modules/workstation/shell/zsh_home.nix`

**Interfaces:**
- Produces: on every host, `programs.zsh` with completion, autosuggestions and
  syntax highlighting; `environment.shellAliases = { ls = "lsd"; l = "ls -l"; la = "ls -la"; cat = "bat"; md = "glow"; }`
  plus `ip = "ip --color=auto"` on Linux only; `lsd bat glow starship` in
  `environment.systemPackages`; `environment.etc."starship.toml".source = ./starship.toml`;
  `STARSHIP_CONFIG=/etc/starship.toml` in `environment.variables`; the shell
  init runs `eval "$(starship init zsh)"` when `$TERM != dumb`.

- [ ] **Step 1: Save the before.** On atlas: `cp ~/.zshrc /etc/zshrc $S/` (as
  `zshrc.home.before`, `zshrc.etc.before`); and the same from hermes over
  Tailscale SSH (`ssh waayway@hermes cat ~/.zshrc /etc/zshrc`).
- [ ] **Step 2: Write `common/shell/zsh.nix`.** One attrset per platform
  (`if hostPlatform.isDarwin then … else …`, like `openssh.nix`), inside a shared
  `lib.mkMerge`:
  - NixOS: `programs.zsh.{enable,enableCompletion,autosuggestions.enable,syntaxHighlighting.enable}`,
    `programs.zsh.interactiveShellInit`, `users.defaultUserShell = pkgs.zsh`.
  - nix-darwin: `programs.zsh.{enable,enableCompletion,enableAutosuggestions,enableSyntaxHighlighting}`,
    `programs.zsh.interactiveShellInit`.
  - Both: `environment.shells`, `environment.shellAliases`, the packages, the
    `/etc/starship.toml` link, `STARSHIP_CONFIG`.
- [ ] **Step 3: Trim `zsh_home.nix`.** Remove the aliases moved to system level, the
  zsh-syntax-highlighting plugin, `autosuggestion.enable`, `programs.starship`,
  the `starship.toml` link and the lsd/bat/glow packages. Set
  `programs.zsh.enableCompletion = false` (the system zsh runs compinit).
  Keep `sp`, `cd=z`, the bindkeys, the PATH exports, `~/.aliases` and brew shellenv.
- [ ] **Step 4: Verify the eval.** `$S/snap.sh after-5`, diff with `after-4`.
  Expected: every host gains `aliases` and `etc` entries (`starship.toml`,
  zsh files); servers gain `lsd bat glow starship`; under `hm` the
  starship/aliases/plugin and `.config/starship.toml` disappear. Nothing else.
- [ ] **Step 5: Verify the shell on atlas.** `darwin-rebuild switch --flake ~/.flake#atlas`,
  then open a new shell: `alias ls cat sp cd` all resolve, the starship prompt
  shows once, `echo $STARSHIP_CONFIG` is `/etc/starship.toml`, and
  `zsh -ixc exit 2>&1 | rg -c compinit` doesn't count higher than before.
  Diff the new `~/.zshrc` and `/etc/zshrc` against the saved ones: only the moved
  lines changed places.
- [ ] **Step 6: Verify on a server.** Build router-test's toplevel on nixos-manager
  (AGENTS.md bundle recipe). Expected: it builds, and its `etc/zshrc` contains
  `starship init zsh` and the aliases.
- [ ] **Step 7: Commit** `feat(shell): system-wide zsh and starship for every host`.

---

### Task 6: sshd and keys only on servers

**Files:**
- Modify: `modules/common/networking/openssh.nix` → Linux:
  `services.openssh.enable = lib.mkDefault false;` and nothing else. Darwin unchanged.
- Modify: `modules/server/networking/openssh.nix` →
  `optionalAttrs isLinux { config = mkIf isServer { services.openssh = { enable = true; openFirewall = true; settings = { PasswordAuthentication = false; KbdInteractiveAuthentication = false; X11Forwarding = false; PermitRootLogin = "prohibit-password"; }; }; environment.enableAllTerminfo = true; }; }`
  (no more `mkForce`: nothing else sets these).
- Modify: `modules/server/users/user.nix`: root's break-glass key under `mkIf isServer`.

- [ ] **Step 1:** Make the three changes.
- [ ] **Step 2: Verify.** `$S/snap.sh after-6`, diff with `after-5`.
  Expected, hermes and hephaestus: `openssh.enable` false, port 22 gone
  from `ports`, `sshd` gone from `services`, root's `keys` empty, `enableAllTerminfo`
  terminfo packages gone. Servers: `openssh.settings` the same values as today
  (only the `mkForce` gone, so no difference). Darwin: nothing.
  `nix eval .#nixosConfigurations.hermes.config.services.tailscale.extraUpFlags`
  still contains `--ssh`.
- [ ] **Step 3: Commit** `fix(ssh): sshd and the break-glass key only on servers`.

---

### Task 7: GPU and hardware cleanup

**Files:**
- Create: `modules/common/hardware/firmware.nix` (Linux:
  `hardware.enableRedistributableFirmware = true;` on every Linux host).
- Create: `modules/workstation/hardware/amd-gpu.nix`. Option
  `hardware.amdgpu.extras.enable` (`mkEnableOption "ROCm OpenCL and LACT for an AMD GPU"`);
  config: `hardware.amdgpu.opencl.enable`, `hardware.graphics.extraPackages = [ rocmPackages.rocm-smi rocmPackages.clr.icd ]`,
  LACT (package, systemd unit, `wantedBy`), the `/opt/rocm/hip` tmpfiles rule.
  Linux only.
- Delete: `modules/workstation/hardware/graphics.nix`.
- Modify: `modules/workstation/desktop/wayland.nix`: add `services.xserver.enable = true;`.
- Modify: `modules/workstation/hardware/bluetooth.nix`: **no option of its own.**
  Today it declares `bluetooth.enable`, but the hosts set NixOS's
  `hardware.bluetooth.enable`, so this module's config (blueman, powerOnBoot,
  Experimental/FastConnectable, mpris-proxy) never applies. Gate it on
  `config.hardware.bluetooth.enable` and stop setting `hardware.bluetooth.enable`
  inside it.
- Modify: `hosts/workstations/hermes.nix`: remove `boot.initrd.kernelModules = [ "amdgpu" ]`
  and `services.xserver.videoDrivers`; add `hardware.amdgpu.extras.enable = true;` under `options`.
- Modify: `hosts/workstations/hephaestus.nix`: add `hardware.amdgpu.extras.enable = true;`.

- [ ] **Step 1:** Make the changes.
- [ ] **Step 2: Verify.** `$S/snap.sh after-7`, diff with `after-6`.
  Expected:
  - hermes/hephaestus: `videoDrivers` `[ "amdgpu" ]` → `[ "modesetting" ]`; `extra`
    loses `mesa`; `initrd` keeps amdgpu (from the profile's `amdgpu.initrd`);
    `services` and `userServices` gain blueman and `mpris-proxy`; `packages` gain blueman.
    Graphics `enable`/`enable32Bit`, LACT and ROCm unchanged.
  - Servers: `firmware` false → true. prod: already true, no change.
  - Darwin: nothing.
- [ ] **Step 3: Build** hermes's toplevel on nixos-manager. Expected: success.
- [ ] **Step 4: Commit** `refactor(hardware): GPU from nixos-hardware, AMD extras behind an option, bluetooth module applies`.

---

### Task 8: prod's Intel Arc through nixos-hardware

**Files:**
- Modify: `hosts/servers/prod.nix`: `options.hardware.profiles = [ "common-gpu-intel" ];`;
  in `config`: `hardware.intelgpu.vaapiDriver = "intel-media-driver";`.
- Modify: `modules/server/services/docker.nix`, the `intelGpu` block: remove
  `hardware.enableRedistributableFirmware` (now common) and the
  `hardware.graphics` block. Keep `boot.kernelParams = [ "i915.enable_guc=3" ]`
  and `libva-utils`; the profile doesn't set those. Update the option's
  description: "the host side comes from the nixos-hardware `common-gpu-intel` profile".

- [ ] **Step 1:** Make the changes.
- [ ] **Step 2: Verify.** `$S/snap.sh after-8`, diff with `after-7`.
  Expected, prod only: `graphics.enable32Bit` may become true, `extra` gains
  `intel-compute-runtime`, `initrd` gains `i915`, and the 32-bit media driver
  appears if `enable32Bit` is on. `intel-vaapi-driver` and `intel-ocl` must
  **not** appear. `kernelParams` unchanged. Everything else the same.
- [ ] **Step 3: Build** prod's toplevel on nixos-manager. Expected: success.
- [ ] **Step 4: Commit** `refactor(prod): Intel GPU from the nixos-hardware profile`
  with paths `hosts/servers/prod.nix modules/server/services/docker.nix`.

---

### Task 9: Option renames

| From | To | Set in |
|---|---|---|
| `modules.locale.*` | `locale.*` | nowhere (defaults only) |
| `workstation.debloat.*` | `darwin.debloat.*` | atlas |
| `workstation.homebrew.removeUndeclared` | `darwin.homebrew.removeUndeclared` | atlas |
| `hardware.thermalforge.enable` | `darwin.thermalforge.enable` | atlas |

(`darwin.*` is the agreed prefix for macOS-only options; the last two aren't in
the design's list but follow that rule.)

**Files:** `modules/common/locale/locale.nix`, `modules/workstation/darwin/{debloat,homebrew,thermalforge}.nix`,
`hosts/workstations/atlas.nix`, and any reader (`rg -n 'workstation\.(debloat|homebrew)|hardware\.thermalforge|modules\.locale' modules hosts`).

- [ ] **Step 1:** Rename the options and their readers, update atlas's host file.
- [ ] **Step 2: Verify.** That `rg` returns nothing. `$S/snap.sh after-9`,
  diff with `after-8`: no difference. Five evals pass.
- [ ] **Step 3: Commit** `refactor(options): darwin.* for macOS-only options, locale.*`.

---

### Task 10: Docs

**Files:** `AGENTS.md`, `docs/modules.md`, `docs/lodestar.md`, `docs/homelab.md`,
and an addendum to the design doc listing what changed while building (bluetooth fix,
the two extra darwin renames, `intelGpu` keeping the GuC parameter and `libva-utils`).

- [ ] **Step 1:** `AGENTS.md`:
  - Layout section: the new tree, `lib/` vs `tools/`.
  - Rules: "the folder must match the condition", "one file per role".
  - SSH: workstations are reached through Tailscale SSH only.
  - Remove `services/`, `vm-specific/`, `hardware/graphics.nix` mentions.
- [ ] **Step 2:** `docs/modules.md`: the three roots and which gate belongs to
  which; the per-role split with an example (openssh).
- [ ] **Step 3:** Fix paths in `docs/lodestar.md` and `docs/homelab.md`
  (`rg -n 'modules/' docs/*.md` → every hit points at an existing path).
- [ ] **Step 4: Commit** `docs: repo layout after the restructure`.

---

### Task 11: Rollout (ask before each push)

- [ ] **Step 1: Full check.** Five evals, `nix flake check --no-build --keep-going`,
  and on nixos-manager build all 7 Linux toplevels and run the flake checks
  (`nix flake check -L`) from a bundle of `unstable`. Atlas:
  `nix build .#darwinConfigurations.atlas.system --no-link`.
- [ ] **Step 2: Tailscale SSH to the laptops.** `tailscale status` shows hermes and
  hephaestus online; `ssh waayway@hermes true` and `ssh waayway@hephaestus true`
  succeed **through Tailscale SSH** (`tailscale ssh waayway@hermes true`). If either
  fails, stop: don't push.
- [ ] **Step 3: Push `unstable`** (ask first; Waayway token, AGENTS.md). Workstations
  apply through Lodestar. Then atlas: `darwin-rebuild switch`. Apollo: tell the user.
- [ ] **Step 4: Check the workstations.** On hermes: `systemctl is-active sshd` →
  inactive, a new shell has the prompt and aliases, bluetooth works.
- [ ] **Step 5: Promote and apply router-test first** (`lodestar promote --yes`, apply
  router-test only). On router-test: `ssh` with the Proxmox key works, the zsh
  prompt shows, `which rustup` → not found.
- [ ] **Step 6: Apply the other servers** through Lodestar. On prod:
  `ls /dev/dri/renderD128`, `vainfo` shows the iHD driver, a Jellyfin transcode
  uses QSV (dashboard → Playback → "Transcoding" shows hardware), the
  `immich-machine-learning` container is up with OpenVINO in its logs. On failure:
  `nixos-rebuild switch --rollback` on prod, then fix in a new commit.
