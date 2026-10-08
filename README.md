## Waayway's Nix Config V3

This is v3 of my config. See other branches or links below for the other versions

For other versions see:
- [v1](https://github.com/Waayway/nixos-config/tree/v1)
- [v2](https://github.com/Waayway/nixos-config/tree/v2)

WARNING: This config is not final. See v2 for that. but im still experimenting with some features and making it to a 1.0 version

### Why NixOS

#### Bazzite

I recently switched to bazzite from windows for gaming. This is mostly because i couldn't get the performance i wanted on Nix with Hyprland in the past. 

Bazzite is generally a good distro/OS but... 

I hate it for terminal. It works great for everything except developing which is generally why i wanted to switch to linux in the first place. 

And NixOS worked the best out of all distros i have tried in the past. 

#### NixOS

I discovered Nixos somewhere in 2023 And basically loved it from the start. 99% of what i needed to do was a package and i didn't have to work with an AUR which i had to fumble with every other week. 

Nixos has been very stable for me with minimal problems and with a possibility to explore some more devops.



### Installing a new Mac (e.g. atlas)

Checklist, in order. Replace `atlas` with the host name.

#### Before the first switch

1. **macOS setup:** create the account named in the host file (`thijsvanwaaij` for atlas); nix-darwin can't create or rename the main user.
2. **Command line tools:**
   ```sh
   xcode-select --install
   ```
3. **Start the Xcode download now** (App Store) if the host has `hardware.thermalforge.enable`: the ThermalForge formula compiles from source and needs the full Xcode app, and the download takes a while. You don't have to wait for it — see step 7.
4. **Nix:** the official multi-user installer (not Determinate Nix — this repo manages `nix.*` itself), then open a new terminal:
   ```sh
   sh <(curl -L https://nixos.org/nix/install)
   ```
5. **Full Disk Access** for your terminal (System Settings → Privacy & Security → Full Disk Access). Activation writes `com.apple.universalaccess` (reduce transparency/motion) and macOS blocks that otherwise.
6. **Clone:**
   ```sh
   git clone https://github.com/Waayway/nixos-waayway ~/.flake
   ```
7. **Xcode not finished yet?** Turn ThermalForge off for now (don't commit this) so it doesn't stop the switch:
   ```sh
   sed -i '' 's/hardware.thermalforge.enable = true;/hardware.thermalforge.enable = false;/' ~/.flake/hosts/workstations/atlas.nix
   ```

#### First switch

8. Run the first switch (later switches: `sudo darwin-rebuild switch --flake ~/.flake#atlas`):
   ```sh
   sudo nix --extra-experimental-features 'nix-command flakes' run nix-darwin/nix-darwin-26.05#darwin-rebuild -- switch --flake ~/.flake#atlas
   ```
   - The Homebrew step downloads every cask (~8–10 GB with Microsoft 365 and Android Studio) one after another and takes a long time. `.pkg` installers (Microsoft 365, 1Password, Tailscale, Elgato, OneDrive) ask for your password.
   - Existing dotfiles are kept as `*.before-nix`.
   - atlas sets `workstation.homebrew.removeUndeclared = "zap"`: casks/brews that aren't declared are removed (with their app data) on every switch. Other Macs default to `"keep"`.
9. **If the switch stops partway** (e.g. `brew bundle failed!`): fix the cause and run it again. Activation runs system settings → Homebrew → ThermalForge setup → home-manager, so when Homebrew fails, **home-manager never runs**: no zsh config, starship prompt, Ghostty config or `~/.aerospace.toml` until a switch gets through.

#### After the switch

10. **Log out and back in** once, so Dock, Finder, keyboard and scroll-direction settings are fully applied. Open a new Ghostty window: you should get the starship prompt and the `lsd`/`bat`/`z` aliases.
11. **Approve the permission prompts:**
    - AeroSpace → Accessibility (open it once from /Applications; it starts at login afterwards).
    - Terminal → control "System Events" (used to set a random wallpaper from `wallpapers/` on each switch).
12. **ThermalForge:** once Xcode has finished, accept its license, undo step 7 and switch again. The switch builds ThermalForge, runs `thermalforge install` (fan daemon + /Applications/ThermalForge.app) and starts it at login.
    ```sh
    sudo xcodebuild -license accept
    git -C ~/.flake checkout hosts/workstations/atlas.nix
    sudo darwin-rebuild switch --flake ~/.flake#atlas
    ```
13. **Sign in by hand:** 1Password, Microsoft 365, OneDrive, Google Drive, Tailscale. For git over HTTPS: `gh auth login`.
14. **Finder sidebar:** favorites from `darwin.finderSidebar` are only added once their folders exist. After Google Drive has synced and your repos are cloned, switch once more.
15. **Secrets:** copy the host's age key to `~/.config/sops/age/keys.txt` (or create one, see below) before the host uses sops secrets.
16. **Handoff** is turned off by the config, but it works both ways: also turn it off on your other Macs/iPhone (System Settings → General → AirDrop & Handoff), or apps from them keep showing up as "Open on …" in ⌘-Tab.
17. **Manual installs** (no cask): MacUtil.

#### Notes

- atlas runs macOS 27: Homebrew is pinned to 7.0.8+, the first release that knows macOS 27. Brew 6+ also requires third-party taps to be trusted (done in the config: `trusted = true`).
- The Finder sidebar helper and some `defaults` keys (Liquid Glass, Spotlight) were verified on macOS 26; if one stops applying on 27 it's skipped instead of failing the switch.

#### Host files vs. modules

Host files stay thin: identity, which modules/categories are enabled, and a few per-host values. Apps are grouped in cross-platform categories under `modules/apps/` (`workstation.apps.<category>.enable`); a host can switch single apps off with `workstation.apps.<category>.<app>.enable = false`. macOS settings shared by every Mac live in `modules/darwin/` (`defaults.nix`, `spotlight.nix`, `system.nix`). On every Mac a random picture from `wallpapers/` becomes the desktop on each switch (`darwin.wallpaper` to pin one); macOS asks once to allow controlling System Events.

#### Adding sops secrets to a Mac

Darwin hosts don't declare secrets yet. To onboard one:

1. Generate the age key (`age-keygen` ships in the `age` package, but isn't its main program, so use `nix shell`):
   ```sh
   mkdir -p ~/.config/sops/age
   nix shell nixpkgs#age -c age-keygen -o ~/.config/sops/age/keys.txt
   ```
   It prints `Public key: age1…`. To show it again later:
   ```sh
   nix shell nixpkgs#age -c age-keygen -y ~/.config/sops/age/keys.txt
   ```
2. Add that public key to `.sops.yaml`: a new `&host_<name>` entry under `keys:` and a reference in each `creation_rules` group the host should read.
3. On a machine that can already decrypt, re-encrypt for the new key, then commit and pull on the Mac:
   ```sh
   export SOPS_AGE_KEY_FILE=~/.config/sops/age/keys.txt  # sops on macOS defaults to ~/Library/Application Support/sops/age/
   nix shell nixpkgs#sops -c sops updatekeys secrets/*.yaml
   ```
   Empty placeholder files (no `sops:` block) are skipped; only files with content need re-encrypting.
