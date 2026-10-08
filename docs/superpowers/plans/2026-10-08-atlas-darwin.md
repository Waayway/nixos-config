# atlas Darwin Host Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make `darwinConfigurations.atlas` build from `merge-servers` with the agreed app/CLI/dotfile set, without changing apollo's installs or breaking NixOS hosts.

**Architecture:** Fix `mkDarwin` to use the shared module tree; guard Linux-only modules with `lib.optionalAttrs hostPlatform.isLinux`; make darwin app groups opt-in; add `hosts/workstations/atlas.nix`.

**Tech Stack:** Nix flakes, nix-darwin 26.05, home-manager 26.05, nix-homebrew.

**Spec:** `docs/superpowers/specs/2026-10-08-atlas-darwin-design.md`

## Global Constraints

- Guards use `lib.optionalAttrs` / `lib.optionals` on `hostPlatform.*`, never `mkIf`, for options absent on nix-darwin.
- apollo's cask/brew/systemPackages sets must not change.
- No `darwin-rebuild switch` on this laptop; build only. No push.

## Review Focus

- A NixOS host losing config because a guard was put on a module it uses → eval all NixOS hosts' drvPath (Task 1, Task 5).
- Home-manager Linux GUI modules (hyprland/eww/theme) building on darwin → atlas build (Task 5).
- Ghostty package collision with the cask → `ghostty-bin` on darwin.
- `~/.aerospace.toml` overwrite on apollo → covered by `backupFileExtension`.
- Homebrew `zap` on atlas removing user-installed casks → intended, documented in README.

---

### Task 1: Make the tree evaluate (mkDarwin + missing dirs + Linux guards)

**Files:** Modify `flake.nix`, `lib/mkDarwin.nix`, `modules/system.nix`, `modules/home.nix`, and each Linux-only module that fails darwin eval.

- [ ] Baseline: record `nix eval` failures for `nixosConfigurations.{hermes,hephaestus,nixos-manager}` and `darwinConfigurations.apollo`.
- [ ] `modules/{system,home}.nix`: filter `paths` through `builtins.pathExists`.
- [ ] `mkDarwin`: accept `nixpkgs`; base `../modules/system.nix`; home `../modules/home.nix` via `mkHome` with `isDarwin = true`; `isServer = type == "server"`; `home-manager.enable` read like mkSystem; add `importCurDir`; `type`, `tags` in extraArgs.
- [ ] Iterate `nix eval .#darwinConfigurations.apollo.system.drvPath`, adding the minimal `isLinux` guard to each module it names, until it evaluates.
- [ ] Verify: every NixOS host's `config.system.build.toplevel.drvPath` evaluates.
- [ ] Commit.

### Task 2: Opt-in darwin app groups (apollo unchanged)

**Files:** `modules/darwin/apps/{audio,browsers,dev}.nix`, `modules/darwin/homebrew.nix`, `hosts/workstations/apollo.nix`.

- [ ] Before: dump apollo `homebrew.casks`, `homebrew.brews`, `homebrew.taps` (sorted) to scratch.
- [ ] Add `options.darwin.apps.<group>.enable`; move `codex`, `db-browser-for-sqlite` to apollo, `focusrite-control-2` to audio; `cleanup = lib.mkDefault "none"`.
- [ ] apollo enables `darwin.apps.{audio,browsers,dev}`.
- [ ] Verify: after-dump equals before-dump.
- [ ] Commit.

### Task 3: Shared home/dev changes

**Files:** `modules/development/python.nix` (+uv), `modules/apps/ghostty_home.nix` (`ghostty-bin` on darwin, `gtk-single-instance` Linux-only), create `modules/shell/git_home.nix`, `modules/shell/zsh_home.nix` (PATH space fix + darwin-only brew shellenv / postgresql@16 PATH / `~/.aliases`), create `modules/darwin/aerospace_home.nix` + `modules/darwin/aerospace.toml` (copy of `~/.aerospace.toml`).

- [ ] Implement; aerospace/darwin zsh bits guarded on `hostPlatform.isDarwin`.
- [ ] Verify: apollo + NixOS hosts still evaluate.
- [ ] Commit.

### Task 4: atlas host

**Files:** Create `hosts/workstations/atlas.nix`.

- [ ] system/user/type/options per spec; casks, taps, brews, nix packages exactly as spec §2; `homebrew.onActivation.cleanup = "zap"`; git email; `backupFileExtension = "before-nix"`.
- [ ] Defaults overrides (captured from current laptop): `NSGlobalDomain.AppleICUForce24HourTime = true`, `dock.tilesize = 62`, `dock.largesize = 64`, `dock.magnification = true`, `finder.ShowStatusBar = true`, `loginwindow.GuestEnabled = false`.
- [ ] Verify: `nix eval .#darwinConfigurations.atlas.system.drvPath`.
- [ ] Commit.

### Task 5: Full build + README

- [ ] `nix build .#darwinConfigurations.atlas.system --no-link` succeeds.
- [ ] Re-run apollo before/after diff and NixOS evals.
- [ ] README: "New Mac (atlas) bootstrap" section + manual apps (Xcode, MacUtil) + sops onboarding steps.
- [ ] Commit.
