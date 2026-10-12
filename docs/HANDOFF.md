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
  - `homebrew.nix`: nix-homebrew, trusted taps, base casks (aerospace,
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

## Fleet manager (branch `fleet-manager`, 2026-10-12)

A dashboard and agent that roll out config changes across the hosts. Design:
`docs/superpowers/specs/2026-10-12-fleet-manager-design.md`; plan:
`docs/superpowers/plans/2026-10-12-fleet-manager.md`.

### What exists

- `pkgs/fleet/`: cargo workspace (`fleet-proto`, `fleet-agent`, `fleet-server`
  with `migration`) and `web/` (Preact + shadcn, Vite). The server embeds the
  built dashboard (`fleet-web` package).
- Modules in `modules/fleet/`: `agent.nix` (`services.fleet-agent`, systemd or
  launchd), `server.nix` (`services.fleet-server`, Linux only), `audit-hook.nix`
  (logs every activation, also manual rebuilds). Both open their port on
  `tailscale0` only (agent 7461, dashboard 8080). The server runs as the
  `fleet-server` system user, which is made a Tailscale operator
  (`services.tailscale.extraSetFlags`) for `tailscale status`/`whois`.
- Host attributes: `fleet = true;` enrols a host, `channel = "stable" | "unstable";`
  picks its branch. Defaults: servers `stable`, workstations `unstable`.
  `nixos-manager` has `fleet = true` and runs the server.

### Run it locally

```sh
nix develop .#fleet                          # cargo, rustc, node 22, sqlite, git
nix run .#fleet-demo                         # simulated fleet, dashboard at http://127.0.0.1:8080
nix run .#fleet-demo -- --listen 127.0.0.1:18080 --speed 4
```
Frontend work: run the demo on another port, then from `pkgs/fleet/web`:
```sh
FLEET_API=http://127.0.0.1:18080 nix develop ../../..#fleet -c npm run dev   # Vite proxies /api to the demo
```
Tests (cargo and node only exist in the dev shell; the `cargo` on PATH is an
unconfigured rustup):
```sh
cd pkgs/fleet && nix develop ../..#fleet -c cargo test --workspace
cd pkgs/fleet/web && nix develop ../../..#fleet -c npx vitest run
nix build .#checks.aarch64-darwin.fleet-bindings   # generated TS types are up to date
nix eval .#checks.x86_64-linux.fleet-firewall.drvPath   # agent/dashboard ports open on tailscale0
```
State-changing API calls need the header `X-Fleet: 1` (CSRF guard), e.g.
`curl -X POST -H 'X-Fleet: 1' http://127.0.0.1:18080/api/hosts/hermes/apply`.

### fleetctl

`pkgs/fleet/fleetctl` is a small CLI over the server API (library plus thin
`main.rs`; tests run it against the demo server). It is installed on every
fleet host via `services.fleet-agent` (`ctlPackage`), or run it from the repo
with `nix run .#fleetctl -- <args>`. Access is by Tailscale identity as for the
dashboard (no tokens); a 403 means this device is not allowed. Server URL:
`--server` or `FLEET_SERVER`, default `http://nixos-manager:8080`.

```sh
fleetctl status                          # host, os, channel, online, running, behind, last apply
fleetctl rebuild hermes --wait           # force rebuild: re-applies the channel head even if
                                         # the host already runs it; exit 0 only if it ended ok
fleetctl rebuild --channel stable --wait [--timeout 900]
fleetctl log hermes [APPLY_ID]           # default: the host's last apply
fleetctl promote [--yes]                 # shows candidate + subject; --yes moves stable
fleetctl audit --limit 20
FLEET_SERVER=http://127.0.0.1:18080 fleetctl status   # against the local demo
```
An offline host answers `unreachable`: the apply is recorded and the server
re-sends it when the host comes online (`--wait` then blocks until timeout).

### Adding a host to the fleet

Set `fleet = true;` in its host file (and `channel = ...` to override the
default), then switch it once by hand. After that it appears in the dashboard
once the server can reach it over Tailscale on port 7461. Hosts also need
`tag:fleet` in Tailscale (see below).

### Verified on nixos-manager (2026-10-12)

- nixos-manager is the Linux builder: `ssh -J pve manager@10.0.10.170`
  (flakes on, `manager` is a trusted user). Linux packages, `fleet-bindings`,
  `fleet-firewall` and the VM test `checks.x86_64-linux.fleet-vm` all build
  and pass there. The VM test exercises a real apply as root with the
  root-to-user privilege drop.
- nixos-manager itself runs this branch (`nixos-rebuild boot` + reboot from
  `~/.flake`, branch `fleet-manager` for now): fleet-server and fleet-agent
  active, LAN 10.0.10.170, Tailscale 100.92.102.84.

### Not verified

- The darwin agent (launchd, Detach launcher) has not run on a Mac yet.
- The proxmox template image evaluates but has not been built or booted.

### Still needs the user

1. **Branch rename on GitHub:** `main` to `unstable` (also the default branch),
   create `stable`, add a ruleset on `stable`. Then rename the branch in each
   checkout and update the push command and branch name in this file.
2. **nixos-manager bootstrap (partly done):** it runs this branch and its host
   key already decrypts `secrets/common.yaml` (`host_vms_base`), and
   `listenAddress` 100.92.102.84 is confirmed. Left: move `~/.flake` to
   `stable` once it exists; create `secrets/nixos-manager.yaml` with a write
   deploy key and point `deployKeyFile` at the sops secret path; the secret
   must be readable by the server's user (`sops.secrets.<name> = { owner =
   "fleet-server"; mode = "0400"; };`); first switch.
3. **Tailscale ACL:** `tag:fleet` on enrolled hosts; `tag:manager` to
   `tag:fleet:7461`; dashboard access for `Waayway@github`, `tag:nixos` and
   `tag:personal`.
4. **Enrolment:** `fleet = true` on atlas, apollo, hermes and hephaestus, then
   a first real apply on hermes and on atlas.
5. Build and boot the proxmox template once (`nix build .#proxmox-template`
   on nixos-manager) before creating new VMs from it.
6. VM migration (spec, "Migration of the homelab").
