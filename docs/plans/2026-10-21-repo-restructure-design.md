# Repo restructure: design

Date: 2026-10-21. Status: design agreed in chat, not started.
Plan: `2026-10-21-repo-restructure-plan.md`.

## Why

`modules/` has 25 categories in one flat list and `lib/` mixes the system
builders with helpers that modules call. You can't tell from a folder name who
gets it: `services/` turns out to be Docker, Nextcloud, Immich and Jellyfin
(servers only), `development/` installs rust/go/python/java/node on every
server, and `networking/openssh-server.nix` hardens the laptops too. Servers run
zsh as their login shell but get none of the shell setup, because all of it is
home-manager, which servers don't run.

## Goals

- Every folder says who gets it: **common** (every host), **workstation**
  (laptops, desktop, Macs), **server** (the Proxmox VMs).
- Every host evaluates to the same configuration after the moves; behaviour
  changes are separate, deliberate steps with an expected diff.
- Servers get a basic zsh (aliases, prompt, highlighting) without home-manager.
- Things that live on every host only because a server once needed them, or
  vice versa, move to the right place (dev toolchains, sshd, root's key).

Not goals: splitting the repo, changing how hosts are discovered, renaming the
`homelab.*` / `workstation.apps.*` / `backup.*` / `truenas.*` option trees.

## Decisions

1. **Folders are structure only.** Every module is still imported on every
   host (`modules/system.nix` imports `common/`, `workstation/` and `server/`;
   `modules/home.nix` the same with `includeHome`). A module still turns itself
   off by condition (`optionalAttrs isLinux`/`isDarwin`, `mkIf (!isServer)`,
   `mkIf isServer`, an enable option). The folder must match the condition: a
   file under `server/` is gated on `isServer` or on a server-only enable
   option, a file under `workstation/` on `!isServer` or a workstation-only
   option or home-manager.
2. **A module with parts for several roles is split into one file per role**,
   same category name under each root (`common/networking/openssh.nix` +
   `server/networking/openssh.nix`). Each file holds only what its role adds.
3. **`lib/` and `tools/` are two top-level folders.**
   - `lib/`: building systems. `mkSystem`, `mkDarwin`, `mkHome`,
     `mkDeployNode`, `discoverHosts`, `mkUser`, `umport`, `importCurDir`. Used
     by `systems.nix` (as `builders`) and the builders themselves.
   - `tools/`: helpers called from modules, `programs.nix` and `tests/`.
     `mkAppCategory`, `color`, `routeType`, `routesFrom`, `accessType`,
     `accessFrom`, `accessProblems`. Still the `tools` specialArg, so no call
     site in a module changes.
   Both keep the flat `default.nix` (every file becomes `<name>`).
4. **One shared zsh at system level** (`common/shell/zsh.nix`) for every host
   and every user (root included): completion, autosuggestions, syntax
   highlighting, `environment.shellAliases` (ls/l/la → lsd, cat → bat,
   md → glow, ip --color), lsd/bat/glow, and starship with `starship.toml` via
   `/etc/starship.toml` + `STARSHIP_CONFIG`. Starship is initialised from the
   shell init on both platforms (nix-darwin has no `programs.starship`). Option
   names differ per platform (NixOS `syntaxHighlighting.enable`,
   `autosuggestions.enable`; nix-darwin `enableSyntaxHighlighting`,
   `enableAutosuggestions`), so the module builds one attrset per platform.
   `workstation/shell/zsh_home.nix` keeps only the workstation extras:
   bun/cargo/flutter/npm PATH lines, brew shellenv, `~/.aliases`, `sp`,
   `cd=z`, the ctrl-arrow bindings. Home-manager's own completion, plugins
   and starship are switched off so nothing runs twice. Result on a
   workstation: the same shell as today.
5. **SSH:** sshd is off on workstations; they are reached through Tailscale
   SSH (`--ssh`, already on everywhere). Servers run sshd hardened (no
   passwords, no keyboard-interactive, no X11, root `prohibit-password`,
   firewall open). The break-glass root key and the Proxmox user key are
   server-only (`server/users/`), as is `linger`.
6. **Hardware:** `common/hardware/` holds `nixos-hardware.nix` (the
   `hardware.profiles` list, now used by servers too) and `firmware.nix`
   (`hardware.enableRedistributableFirmware`). `graphics.nix` is removed: the
   nixos-hardware GPU profiles already set what it set
   (`hardware.graphics.enable`, `enable32Bit`, amdgpu in initrd, mesa); the
   `videoDrivers = [ "amdgpu" ]` lines (module and hermes's host file) are the
   old X11 driver and go, the profile's `modesetting` is right for Wayland;
   `services.xserver.enable` moves to `workstation/desktop/`. What's left
   (ROCm OpenCL, rocm-smi, `/opt/rocm/hip`, LACT) becomes
   `workstation/hardware/amd-gpu.nix` behind `hardware.amdgpu.extras.enable`,
   set in hermes's and hephaestus's host files. The rest of `hardware/`
   (sound, printing, power-management, bluetooth, framework, caps-to-esc) is
   workstation.
7. **prod's Intel Arc A380 uses nixos-hardware:** prod sets
   `hardware.profiles = [ "common-gpu-intel" ]` and
   `hardware.intelgpu.vaapiDriver = "intel-media-driver"` (otherwise the
   profile also installs `intel-vaapi-driver` and `intel-ocl`, which are for
   older iGPUs). Driver stays `i915` (the default). The hand-written driver
   lines in `homelab.containers.intelGpu` (`server/services/docker.nix`) go;
   the option keeps only the container side (`/dev/dri`, groups). The
   profile adds `intel-compute-runtime`; that's accepted.
8. **Dev toolchains** (`workstation/development/`) are gated `!isServer`.
9. **Option renames, outliers only:** `bluetooth` → `hardware.bluetooth`,
   `modules.locale` → `locale`, `workstation.debloat` → `darwin.debloat`.
   macOS-only options are `darwin.*`. `bootloader` stays (moving it under
   `boot.loader` would sit in a NixOS namespace). Everything else keeps its
   name.
10. Dead code goes: `modules/darwin/home.nix` (imported by nothing) and the
    `editor/` and `security/` entries in `system.nix` / `home.nix` (folders
    that don't exist).

## Target layout

```
lib/          default mkSystem mkDarwin mkHome mkDeployNode discoverHosts
              mkUser umport importCurDir
tools/        default mkAppCategory color routeType routesFrom accessType
              accessFrom accessProblems
modules/
  system.nix home.nix
  common/
    boot/        boot kernel
    console/     console
    locale/      locale
    nix/         nix
    system/      journald zram
    packages/    packages
    hardware/    nixos-hardware firmware
    networking/  networking firewall resolved tailscale openssh (off)
    shell/       zsh (system) starship.toml git neovim
    users/       user (name, home, groups, sudo; no keys)
    lodestar/    agent lodestar-agent-signing.pem
  workstation/
    apps/        all categories, flatpak, ghostty_home
    darwin/      everything in darwin/ today except home.nix
    desktop/     everything in desktop/ today (+ xserver.enable)
    development/ go java js python rust sql
    gaming/      steam
    hardware/    amd-gpu sound printing power-management bluetooth framework
                 caps_to_esc caps_to_esc_home
    shell/       zsh_home (extras) git_home zellij_home zoxide_home
  server/
    services/    docker updates nextcloud immich jellyfin
    homelab/     router/ routes routes-option access-option links lan storage
    identity/    kanidm access people branding/
    backup/      restic backrest homelab restic-truenas.sh
    truenas/     truenas homelab reconcile.sh
    lodestar/    server
    networking/  openssh (on, hardened) tailscale (tagged auth key)
    secrets/     opnix
    users/       user (break-glass + proxmox keys, linger) + the .pub files
    proxmox/     proxmox-guest (was vm-specific/)
```

## How we know it worked

- A snapshot script (scratchpad, not committed) dumps, per host (all 9 configurations), a
  fixed set of evaluated values to JSON: system package names, `homelab.*`,
  users (keys, shell, linger, groups), `services.openssh`, enabled
  `systemd.services`, firewall ports, `hardware.graphics` packages,
  `boot.initrd.kernelModules`, the home-manager `home.file` / `xdg.configFile`
  names, `/etc` file names, and on darwin `system.defaults` and the Homebrew
  lists.
- Phase 1 (moves): the snapshot is identical before and after every commit.
- Phase 2 (behaviour): each commit's snapshot diff is exactly the expected one
  written in the plan, nothing else.
- Every commit: the five host evals from AGENTS.md and
  `nix flake check --no-build --keep-going` pass. Linux toplevels build on
  nixos-manager; atlas builds locally.

## Risks

- **Locking yourself out of a laptop** (sshd off). Before that commit reaches
  hermes/hephaestus, Tailscale SSH to both is tested.
- **The shell changes on workstations.** Checked by comparing `~/.zshrc` and
  `/etc/zshrc` / `/etc/zshenv` before and after on atlas and hermes, and by
  opening a shell.
- **prod's GPU transcoding.** After the switch: `/dev/dri/renderD128` exists,
  `vainfo` shows iHD, a Jellyfin transcode uses QSV, Immich ML starts on
  OpenVINO. The previous generation stays in GRUB.
- **Docs and plans that reference old paths.** `AGENTS.md`, `docs/modules.md`,
  `docs/lodestar.md` and `docs/homelab.md` are updated; old plans in
  `docs/plans/` stay as written (history).
