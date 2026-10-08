# Handoff: atlas setup (2026-10-08)

Context for a new Claude Code session continuing the work started on the old
laptop. Read this first, then `README.md` (new-Mac checklist) and
`docs/superpowers/specs/2026-10-08-atlas-darwin-design.md` (original design;
partly superseded, see "Decisions since the spec").

## Where things are

- Repo: `github.com/Waayway/nixos-waayway`, branch **`main`**. `merge-servers`
  is old; don't use it.
- On **atlas** (this machine: MacBook Pro M4 Max, macOS 27, user
  `thijsvanwaaij`) the repo is cloned at `~/.flake`.
- The **old work laptop** (`14m2max`, M2 Max, macOS 26) still runs a separate
  standalone flake in its own `~/.flake` with this repo nested at
  `~/.flake/nixos-waayway`. It is not managed by this repo; leave it alone.
- Other hosts: `apollo` (personal MacBook M1 Pro, user `thijsvw`), `hermes`
  (Framework 13, NixOS), `hephaestus` (desktop, NixOS), `nixos-manager` (server).

## How the user wants the repo (conventions)

- **Host files are thin.** Only identity (`system`, `user`, `type`), which
  modules/categories are enabled (`options`), and small per-host values. No
  package lists, cask lists or macOS settings in host files. Today atlas only
  carries its git email and Finder sidebar list in `config`.
- **Shared modules are the repo defaults.** The repo is still in development;
  macOS settings in `modules/darwin/` apply to every Mac.
- **Platform guards:** `lib.optionalAttrs hostPlatform.isLinux/isDarwin`, not
  `mkIf` (options that don't exist on a platform error even under `mkIf false`).
- **Never merge attrsets with `//` when both sides can share a top-level key**
  (e.g. `home`, `nix`): `//` is shallow and silently drops the left side. Use
  `lib.mkMerge`. This bit us twice (see below).
- **Formatting:** RFC-style nixfmt from the repo's nixpkgs, not the old 0.6
  nixfmt that may be on PATH:
  `$(nix build --no-link --print-out-paths --inputs-from . nixpkgs#nixfmt)/bin/nixfmt <files>`
- **No git worktrees**; work directly in the checkout.
- **LSPs come from nixvim** (`inputs.nixvim`); don't add language servers as packages.
- Commit messages end with
  `Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>`.
- **Pushing:** the active `gh` account may lack access to the repo. Push with
  the `Waayway` account's token for that one command:
  ```sh
  git -c credential.helper= -c 'credential.helper=!f(){ echo username=Waayway; echo "password=$(gh auth token -u Waayway)"; }; f' push origin main
  ```
  Ask before pushing unless the user already said to.

## Architecture (as of `a4ef7c0`)

- `flake.nix` discovers hosts in `hosts/*/` (`lib/discoverHosts.nix`);
  `*-darwin` systems go through `lib/mkDarwin.nix`, others `lib/mkSystem.nix`.
  Every module in `modules/` is imported on every host (`umport`);
  `*_home.nix` files are home-manager modules.
- `lib/mkHome.nix`: home-manager wiring; `backupFileExtension = "before-nix"`
  baseline for every host.
- **App categories:** `modules/apps/<category>.nix`, built with
  `lib/mkAppCategory.nix`. Option `workstation.apps.<category>.enable`, plus
  `workstation.apps.<category>.<app>.enable` (default true) to refine per host.
  Each app maps to nixpkgs on Linux and to nixpkgs or a Homebrew cask on darwin.
  Categories: browsers, communication, media, office, ai, editors, database,
  containers, electronics, audio, utilities.
- **macOS:** `modules/darwin/`:
  - `defaults.nix`: Dock (Firefox, Ghostty, TIDAL), Finder, keyboard, trackpad,
    Liquid Glass/transparency, locale, Siri off, Stage Manager off.
  - `spotlight.nix`: Spotlight categories/sources.
  - `system.nix`: hostname, firewall on, display sleep 60 min, Touch ID sudo,
    post-activation `activateSettings -u` and Handoff off (per-host keys).
  - `homebrew.nix`: nix-homebrew, trusted taps, base casks (aerospace, ice,
    ghostty), option `workstation.homebrew.removeUndeclared` = keep|uninstall|zap.
  - `packages.nix` (coreutils, mas, cocoapods, pdf2image brew),
    `thermalforge.nix` (`hardware.thermalforge.enable`),
    `aerospace_home.nix` + `aerospace.toml`, `finder_sidebar_home.nix` +
    `finder-sidebar.swift` (`darwin.finderSidebar`), `applications.nix`.
- Shared CLI tools: `modules/packages/packages.nix`; languages in
  `modules/development/` (go, js, python+uv, rust, java, sql incl. darwin
  postgresql@16+pgvector brews).
- Wallpapers: `modules/desktop/wallpapers_home.nix` links `~/.wallpapers` on
  every workstation; on Macs a random one is set each switch (`darwin.wallpaper`).
- Remote Login (sshd) is off on every Mac (`modules/networking/openssh.nix`).

## Decisions since the spec

- Host files thin; everything else moved to shared modules (user was explicit
  about this).
- Cross-platform `workstation.apps.*` categories replaced
  `modules/darwin/apps/*` and the old Linux app modules.
- VSCodium (nixpkgs) replaces VS Code; Zed is a cask on darwin.
- Homebrew cleanup is the `removeUndeclared` option; atlas uses `zap`.
- brew pinned to 7.0.8 (first release that knows macOS 27); nix-darwin bumped
  for brew 7's `--force-cleanup`; third-party taps need `trusted = true`.

## atlas status / next steps

The first switches on atlas stopped in the Homebrew step (fixed since), so
home-manager hadn't run yet (no zsh config/prompt/AeroSpace). Xcode is now
installed and its license accepted. Next:

1. `git -C ~/.flake checkout hosts/workstations/atlas.nix` (undo the temporary
   `thermalforge.enable = false` edit, if still there), then
   `git -C ~/.flake pull && sudo darwin-rebuild switch --flake ~/.flake#atlas`.
2. Confirm: starship prompt + aliases in a new Ghostty window, AeroSpace running,
   `~/.wallpapers` exists, ThermalForge in /Applications and running, firewall
   on, Handoff off.
3. Log out/in once; approve AeroSpace (Accessibility) and System Events prompts.
4. Remaining checklist items in `README.md` (sign-ins, `gh auth login`, switch
   again after Drive sync/repo clones for the sidebar, sops age key).
5. Things only verified on macOS 26: sidebar helper (deprecated
   LSSharedFileList API), Liquid Glass key `NSGlassDiffusionSetting`, Spotlight
   keys. Check they took effect on 27.

## Known issues / open items

- `hephaestus` and `nixos-manager` don't evaluate: their host files use the
  user's in-progress `workstation.terminal/neovim/desktop.*` and `server`
  options that no module declares yet. Not caused by this work; leave unless asked.
- `modules/boot/boot.nix` merges two `lib.mkIf` blocks with `//`, so the grub
  branch is lost; a separate session was started for it.
- Next switch on **apollo** changes it: repo-default macOS settings, Remote
  Login off, shared CLI tools, postgres/JDK, VSCodium instead of VS Code, Zed cask.
- Next switch on **hermes** enables the Nix settings that were silently dropped
  before (flakes in nix.conf, trusted user, auto-optimise, weekly GC deleting
  generations older than 7 days).

## Gotchas learned on atlas

- If the Homebrew step fails, activation stops and **home-manager never runs**.
  Order: system settings → Homebrew → post-activation (activateSettings,
  Handoff, ThermalForge setup) → home-manager.
- ThermalForge's formula compiles from source and needs the full Xcode app.
- Writing `com.apple.universalaccess` needs Full Disk Access for the terminal.
- Scroll direction and similar `defaults` are read at login; `activateSettings -u`
  in post-activation applies most of them immediately.
- sops on macOS looks for keys in `~/Library/Application Support/sops/age/`; set
  `SOPS_AGE_KEY_FILE=~/.config/sops/age/keys.txt`. Generate keys with
  `nix shell nixpkgs#age -c age-keygen` (not `nix run nixpkgs#age`). atlas's age
  key is in `.sops.yaml` and `secrets/common.yaml` is re-encrypted for it; the
  private key must be at `~/.config/sops/age/keys.txt` on atlas before using secrets.

## Verifying changes

```sh
nix build .#darwinConfigurations.atlas.system --no-link
nix eval .#darwinConfigurations.apollo.system.drvPath
nix eval .#nixosConfigurations.hermes.config.system.build.toplevel.drvPath
```
New files must be `git add`ed before flakes can see them.
