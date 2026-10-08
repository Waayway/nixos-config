# atlas: Darwin support on merge-servers + new work MacBook

Date: 2026-10-08
Branch: `merge-servers` (local, tracks `origin/merge-servers` @ 5713725)

## Goal

Install a new work MacBook (M4 Max, host **atlas**, user **thijsvanwaaij**) from this
repo and end up with the same setup as the current work laptop (`14m2max`, still
managed by the separate `~/.flake` flake), minus apps that were explicitly dropped.

Success: on a fresh Mac, install Nix, clone, run one `darwin-rebuild switch
--flake ~/.flake#atlas`, and apps, CLIs, shell, Ghostty, AeroSpace, git and macOS
defaults match the current laptop. Existing hosts keep evaluating.

## Non-goals

- Migrating the current laptop (`14m2max`) onto this repo. `~/.flake` is left
  untouched (it will no longer find `nixos-waayway/config/*`; that is accepted).
- Changing what apollo installs.
- sops secrets on atlas (documented onboarding only).
- WezTerm, Zed settings, `.ideavimrc`, `~/.aliases` contents.

## Current state (findings)

1. `darwinConfigurations` does not evaluate: `flake.nix` passes `nixpkgs` to
   `lib/mkDarwin.nix`, which does not accept it; `mkDarwin` imports the deleted
   `modules/workstations/darwin` and reads `isServer`/`isLaptop`, which hosts no
   longer define (they use `type`).
2. `nixosConfigurations` do not evaluate on the pushed commit: `modules/system.nix`
   and `modules/home.nix` list `./editor`, `./security`, `./vm-specific`, which do
   not exist (`lib.fileset.toList` throws).
3. Convention: every module is imported on every host; platform guards live inside
   the file (`lib.optionalAttrs hostPlatform.isLinux/isDarwin`). Several Linux-only
   modules are not guarded yet. `mkIf` is not enough — defining an option that
   does not exist on nix-darwin is an error even under `mkIf false`, so guards
   must use `optionalAttrs` (or `optional` for imports).
4. `modules/darwin/*` installs apollo's full app set unconditionally (show-control
   rig, docker, kicad, codex, …).
5. nix-homebrew's pinned brew 4.5.9 on the current laptop cannot parse the current
   cask API; the repo already pins brew 5.1.14 — keep that.

## Design

### 1. Structure

- **mkDarwin fixes**: accept `nixpkgs`; base config `../modules/system.nix`; home
  entry `../modules/home.nix`; derive `isServer` from `type == "server"` and stop
  reading `isLaptop`; pass `importCurDir` like `mkSystem`. Home-manager enable is
  read from `options.home-manager.enable` the same way `mkSystem` does.
- **Missing module dirs**: `modules/system.nix` / `modules/home.nix` filter the
  path list with `builtins.pathExists` so listed-but-absent dirs are skipped
  (entries kept, in case they exist in unpushed work).
- **Linux guards**: every module that sets NixOS-only options is wrapped in
  `lib.optionalAttrs hostPlatform.isLinux` (system modules) or guarded on the
  same flag (home modules: hyprland/eww/rofi/swaync/theme/wallpapers). Includes at
  least: boot/*, console, locale, networking/* (incl. tailscale + its sops
  secret), hardware/*, desktop/* except fonts, gaming, system/*, apps/flatpak,
  apps/1password, apps/web, apps/media, apps/office, apps/other,
  users/user.nix (Linux-only fields), secrets/sops (Linux `sshKeyPaths`).
  Exact list is whatever fails to evaluate for atlas; each guard is the minimal one.
- **Opt-in darwin app groups**: `modules/darwin/apps/{audio,browsers,dev}.nix`
  get `options.darwin.apps.<group>.enable` (per `docs/Flake Docs/Modules.md`).
  apollo enables all three. From the shared `homebrew.nix` cask list,
  `codex` and `db-browser-for-sqlite` move to `hosts/workstations/apollo.nix`,
  `focusrite-control-2` moves to the audio group. Net effect for apollo: identical
  cask/brew/package set.
- **Homebrew cleanup**: `homebrew.onActivation.cleanup` stays `"none"` in the
  shared module as `lib.mkDefault`; atlas overrides to `"zap"`.

### 2. atlas contents

Host lives in `hosts/workstations/atlas/default.nix` (directory host, so it can
carry `aerospace.toml`). `system = "aarch64-darwin"`, user `thijsvanwaaij` /
"Thijs van Waaij", `type = "macbook"`, `home-manager.enable = true`,
`home-manager.backupFileExtension = "before-nix"`. No darwin app groups enabled.

Shared (cross-platform modules, every host):
- zsh/starship/zoxide/zellij, git + gh, nixvim, base packages, JetBrains Mono NF.
- go, node22, deno, bun, rustup, python3, sql-studio, discord.
- `uv` added to `modules/development/python.nix`.
- Ghostty: `ghostty_home.nix` uses `pkgs.ghostty-bin` on Darwin (app comes from the
  existing `ghostty` cask; home-manager writes config only); `gtk-single-instance`
  only on Linux.
- New `modules/shell/git_home.nix`: `user.name = "Thijs van Waaij"`,
  `push.autoSetupRemote = true`, `pull.rebase = false`, gh as credential helper
  (`programs.gh.gitCredentialHelper`). Email is per host.
- Fix `zsh_home.nix` PATH entries with a stray space (`"$HOME/.local/bin :$PATH"`).
- Darwin-only zsh additions (guarded): `eval "$(/opt/homebrew/bin/brew shellenv)"`
  in profile, `/opt/homebrew/opt/postgresql@16/bin` on PATH,
  `[ -f ~/.aliases ] && source ~/.aliases`.

Shared darwin base `homebrew.nix` casks (atlas inherits): aerospace, jordanbaird-ice,
pgadmin4, spotify, ghostty.

atlas host config:
- Casks: firefox, ungoogled-chromium, vscodium, cursor, zed, android-studio,
  claude, claude-code, opencode-desktop, lm-studio, ollama-app,
  microsoft-word, microsoft-excel, microsoft-powerpoint, microsoft-outlook,
  microsoft-onenote, microsoft-teams, onedrive, google-drive, obsidian,
  telegram, tidal, obs, audacity, krita, betterdisplay, 1password,
  tailscale-app, elgato-stream-deck.
- Taps: `producerguy/tap`. Brews: postgresql@16, pgvector, pdf2image,
  producerguy/tap/thermalforge.
- Nix packages: tmux, cloudflared, cocoapods, coreutils, just, jdk17,
  poppler-utils, rclone, scc, opencode, mas, fzf, ripgrep, watch,
  lua-language-server, stylua, nixd, nixfmt, emmet-ls, intelephense,
  typescript-language-server, tailwindcss-language-server, pyright.
- Git email `thijs@vriend.studio`.
- `~/.aerospace.toml` from `hosts/workstations/atlas/aerospace.toml` (copy of the
  current laptop's file).
- macOS defaults: capture the current laptop with `defaults read` and override
  only keys that differ from `modules/darwin/system.nix` (known: Finder column
  view, 24h clock, guest login off, Dock size).

Dropped vs. current laptop: zen, google-chrome, dockdoor, macs-fan-control,
pycharm-ce, visual-studio-code, macwhisper, upscayl, utm, parallels,
balenaetcher, all audio/show-control apps, Dante, wacom-tablet, displaylink,
caldigit utility, qemu, virt-manager, whisperkit-cli, unbound, nix postgresql_17,
python.org Python 3.12, nvm, mac-app-util (repo uses its rsync activation script).

Manual install: Xcode, MacUtil.

### 3. Bootstrap, secrets, verification

Bootstrap (README section):
1. macOS setup with account `thijsvanwaaij`; `xcode-select --install`.
2. Official multi-user Nix installer (not Determinate — repo manages `nix.*`).
3. `git clone https://github.com/Waayway/nixos-waayway ~/.flake && git -C ~/.flake checkout merge-servers`
4. `sudo nix run nix-darwin/nix-darwin-26.05#darwin-rebuild -- switch --flake ~/.flake#atlas`
5. Manual: Xcode, MacUtil, app sign-ins.

Secrets: atlas declares none; sops-nix stays imported. Onboarding documented:
age key → `.sops.yaml` → `sops updatekeys` from a keyed machine.

Verification (on the current laptop, no switch):
- `nix build .#darwinConfigurations.atlas.system` succeeds.
- apollo evaluates; its `homebrew.casks`, `homebrew.brews` match pre-change apollo
  intent (audio + browsers + dev groups + base + codex/db-browser).
- `nixosConfigurations.<each>.config.system.build.toplevel.drvPath` evaluates
  for every NixOS host.

Git: commits on local `merge-servers`, one per logical step; no push without
approval.
