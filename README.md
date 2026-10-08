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

1. Run macOS setup and create the account named in the host file (`thijsvanwaaij` for atlas), then install the command line tools:
   ```sh
   xcode-select --install
   ```
2. Install Nix with the official multi-user installer (not Determinate Nix — this repo manages `nix.*` itself):
   ```sh
   sh <(curl -L https://nixos.org/nix/install)
   ```
3. Give your terminal **Full Disk Access** (System Settings → Privacy & Security). The first activation writes `com.apple.universalaccess` (reduce transparency/motion), which macOS blocks otherwise.
4. Clone and switch:
   ```sh
   git clone https://github.com/Waayway/nixos-waayway ~/.flake
   sudo nix --extra-experimental-features 'nix-command flakes' run nix-darwin/nix-darwin-26.05#darwin-rebuild -- switch --flake ~/.flake#atlas
   ```
   Existing dotfiles are kept as `*.before-nix`. On atlas Homebrew runs with `cleanup = "zap"`: casks/brews that aren't declared get removed on every switch.
5. Afterwards, rebuild with `sudo darwin-rebuild switch --flake ~/.flake#atlas`.

Manual installs on atlas: Xcode, MacUtil.

Finder sidebar favorites (`darwin.finderSidebar`) are added on each switch once their folders exist, so after Google Drive has synced and repos are cloned, switch once more. atlas runs macOS 27: Homebrew is pinned to 7.0.8+ (first release that knows macOS 27). The sidebar helper and some `defaults` keys (Liquid Glass, Spotlight) were verified on macOS 26; if one stops applying on 27, it's skipped rather than failing the switch. Sign in to 1Password, Microsoft 365, Google Drive, OneDrive and Tailscale by hand.

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
