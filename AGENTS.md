# AGENTS.md

Guide for coding agents working in this repo: Thijs's Nix flake for every
machine he runs (NixOS laptops/desktop/servers and nix-darwin Macs), checked out
at `~/.flake` on each machine. Read this before changing anything.

## Machines

| Host | What | System | User | Folder |
|---|---|---|---|---|
| atlas | work MacBook Pro M4 Max, macOS 27 | aarch64-darwin | thijsvanwaaij | workstations |
| apollo | personal MacBook Pro M1 Pro | aarch64-darwin | thijsvw | workstations |
| hermes | Framework 13 (AMD) | x86_64-linux | waayway | workstations |
| hephaestus | desktop (AMD) | x86_64-linux | waayway | workstations |
| nixos-manager | Proxmox VM 170, Lodestar server + Linux builder | x86_64-linux | manager | servers |

Homelab: Proxmox host `pve` (`ssh pve`, root, on the tailnet; LAN
10.0.10.0/24, gateway 10.0.10.1). Other VMs there still run Rocky/Debian and are
being migrated to NixOS (see `docs/plans/2026-10-12-fleet-manager-design.md`).
Not managed by this repo: the Hetzner `primary-server`, the old work laptop
(`14m2max`), the Jenkins VM.

## Layout

- `flake.nix`: inputs only; outputs come from `systems.nix` (hosts →
  `nixosConfigurations`, `darwinConfigurations`, deploy-rs nodes) and
  `programs.nix` (packages: the proxmox template).
- `hosts/<category>/<name>.nix`: one file per machine. Categories are folders
  (`servers`, `workstations`); a host is `foo.nix` or `foo/default.nix`.
- `lib/`: `discoverHosts.nix`, `mkSystem.nix` (NixOS), `mkDarwin.nix`,
  `mkHome.nix` (home-manager), `mkAppCategory.nix`,
  `mkDeployNode.nix` (deploy-rs), `umport.nix` (recursive importer).
- `modules/<category>/`: all configuration. `*_home.nix` files are
  home-manager modules; everything else is a system module.
- `secrets/`: sops-nix files; recipients in `.sops.yaml`.
- `template/proxmox.nix`: base image for new Proxmox VMs.
- `docs/`: `lodestar.md`, `plans/` (designs and implementation plans, one pair per
  feature: `<date>-<topic>-design.md` and `<date>-<topic>-plan.md`), `modules.md` (module style).

## Rules (the user's conventions; follow them)

- **Every module is always imported.** `modules/system.nix` imports every file
  under `modules/` on every host. Never exclude a module per host or platform in
  the import list. A module switches its own config off by condition.
- **How a module turns itself off:**
  - Platform: `lib.optionalAttrs hostPlatform.isLinux` / `isDarwin` around the
    whole module, not `mkIf` (options that don't exist on the other platform
    error even under `mkIf false`).
  - Anything else (host type, an enable option): `config = lib.mkIf <cond> { … };`.
    Workstation-only modules use `lib.mkIf (!hostPlatform.isServer)`.
  - Both together:
    ```nix
    lib.optionalAttrs hostPlatform.isLinux {
      config = lib.mkIf (!hostPlatform.isServer) { … };
    }
    ```
  - Feature modules declare `options.<category>.<module>.enable` and wrap their
    config in `lib.mkIf config.<category>.<module>.enable` (see
    `docs/modules.md`).
- **Host files are thin:** identity (`system`, `user`, `type`, `tags`,
  `channel`, `fleet`), which modules/categories are enabled (`options`), and a
  few per-host values in `config`. No package lists, casks or macOS settings in
  host files; shared modules are the defaults.
- **Never merge attrsets with `//` when both sides can share a top-level key**
  (`users`, `home`, `nix`, `networking`, …): `//` is shallow and silently drops
  the left side. Use `lib.mkMerge`.
- **Apps** live in cross-platform categories under `modules/apps/`
  (`workstation.apps.<category>.enable`, single apps off with
  `workstation.apps.<category>.<app>.enable = false`); each app maps to nixpkgs
  on Linux and to nixpkgs or a Homebrew cask on darwin.
- **LSPs come from nixvim** (`inputs.nixvim`); don't add language servers as
  packages.
- **Formatting:** RFC-style nixfmt from the repo's nixpkgs (the nixfmt on PATH
  may be old):
  `$(nix build --no-link --print-out-paths --inputs-from . nixpkgs#nixfmt)/bin/nixfmt <files>`.
  Rust: `cargo fmt`; frontend: the repo's TypeScript settings.
- **No git worktrees.** Work in the checkout.
- **The user often has uncommitted work in the tree.** Never stash, reset or
  commit it. Commit only your own paths: `git commit -m "…" -- <paths>`.
- Commit messages: conventional style (`fix(scope): …`, `feat(lodestar): …`),
  ending with `Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>`.
- Ask before pushing unless the user said to push.

## Branches and pushing

- `unstable`: work lands here; workstations follow it. `stable`: servers follow
  it; GitHub default branch. `main` is no longer used.
- Repo: `https://github.com/Waayway/nixos-config` (public; anonymous fetch).
- The active `gh` account may lack push rights. Push with the `Waayway` token:
  ```sh
  git -c credential.helper= -c 'credential.helper=!f(){ echo username=Waayway; echo "password=$(gh auth token -u Waayway)"; }; f' push origin HEAD:unstable
  ```
- Servers get changes by promoting `unstable` to `stable` (dashboard or
  `lodestar promote --yes`) and applying through Lodestar (`docs/lodestar.md`).

## Verifying changes

New files must be `git add`ed before the flake can see them.

```sh
# every host evaluates (run all five after touching shared modules or lib/)
nix eval .#nixosConfigurations.hermes.config.system.build.toplevel.drvPath
nix eval .#nixosConfigurations.hephaestus.config.system.build.toplevel.drvPath
nix eval .#nixosConfigurations.nixos-manager.config.system.build.toplevel.drvPath
nix eval .#darwinConfigurations.atlas.system.drvPath
nix eval .#darwinConfigurations.apollo.system.drvPath
nix flake check --no-build --keep-going
# check a single option on a host
nix eval .#nixosConfigurations.nixos-manager.config.services.greetd.enable
```

- Derivation hashes change with every commit (`system.configurationRevision`
  embeds the git revision), so compare options, not `drvPath`s, to show a change
  doesn't affect a host.
- This Mac (atlas) has no Linux builder. Build Linux things on nixos-manager
  (next section). Darwin builds run locally:
  `nix build .#darwinConfigurations.atlas.system --no-link`.

## Linux builder: nixos-manager

`ssh -J pve manager@10.0.10.170` (key `~/.ssh/proxmox_vms_rsa`; also
`nixos-manager` on the tailnet). Flakes on, `manager` is a trusted Nix user, KVM
available (VM tests run), passwordless sudo. Its `~/.flake` is a clean checkout
of `stable` that the Lodestar agent manages: don't build or edit there. To build
another revision, ship it as a git bundle to a scratch clone:

```sh
git bundle create /tmp/b.bundle <branch>
scp -o ProxyJump=pve /tmp/b.bundle manager@10.0.10.170:/tmp/b.bundle
ssh -J pve manager@10.0.10.170 'rm -rf ~/build && git clone -q -b <branch> /tmp/b.bundle ~/build && cd ~/build && nix build --no-link -L .#nixosConfigurations.hermes.config.system.build.toplevel'
```

Rust builds are slow there (4 cores): minutes, not seconds.

## Lodestar (fleet manager)

The fleet manager is its own flake, `github:Waayway/lodestar` (input
`lodestar`; local clone `~/lodestar`). This repo only holds its values:
`modules/lodestar/` (agent on `fleet = true` hosts, server defaults) and the
nixos-manager host file. See `docs/lodestar.md` (where values live, enrolling a
host, open items). Rust/frontend work, its dev shell, demo and VM test happen in
the lodestar repo, not here; after a lodestar change, `nix flake update
lodestar` here.

## Gotchas

- **Servers vs. workstations:** `type = "server"` sets `hostPlatform.isServer`.
  Desktop, graphics, sound, printing, power-profile and Flatpak modules are
  gated on `!isServer`; a server that needs a GPU (e.g. the media VM) sets that
  in its host file.
- **Proxmox VMs** (`useDefaultHardware = true`) boot BIOS + GRUB from a single
  ext4 root labelled `nixos` (`modules/vm-specific/proxmox-guest.nix` sets
  `bootloader = "grub"`; the repo default is systemd-boot). A host file's
  `netInterface = { ip; prefixLength; }` pins its LAN address via
  systemd-networkd.
- **Switching a VM over SSH:** prefer `nixos-rebuild boot` + reboot when the
  network config changes; the previous generation stays in GRUB, and `pve`'s
  console is the fallback.
- **sops:** host age keys are derived from the SSH host key
  (`/etc/ssh/ssh_host_ed25519_key`; convert with `ssh-to-age`). Only
  workstations also have a user key file (`~/.config/sops/age/keys.txt`); a
  configured but missing key file fails the whole activation. On macOS, sops
  looks in `~/Library/Application Support/sops/age/`, so set
  `SOPS_AGE_KEY_FILE=~/.config/sops/age/keys.txt`. Generate keys with
  `nix shell nixpkgs#age -c age-keygen`.
- **nix-darwin activation order:** system settings → Homebrew →
  post-activation → home-manager. If Homebrew fails, home-manager never runs.
  ThermalForge compiles from source and needs the full Xcode app. Writing
  `com.apple.universalaccess` needs Full Disk Access for the terminal.
- **NixOS maps a machine's own hostname to `127.0.0.2`** in `/etc/hosts`.
  Anything that resolves "itself" by name gets loopback, not its Tailscale IP.
- **git as root on a user's repo** fails with "dubious ownership"; run git as
  the repo's owner (`su - <user> -c 'git …'`).
- **Tailscale tags replace a device's user identity.** Keep personal laptops
  untagged; tag unattended machines. Tags must be in the policy's `tagOwners`.
- **Shell on atlas:** zsh (no word-splitting of `$VAR`; use arrays), GNU `sed`
  (`sed -i` without `''`).
