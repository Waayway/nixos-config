# apollo — personal MacBook Pro 14"
#
# Hardware:
#   Model:    MacBook Pro 14" (MacBookPro18,3, MKGR3N/A)
#   Chip:     Apple M1 Pro — 8 cores (6 performance + 2 efficiency)
#   Memory:   16 GB
#   OS:       macOS 26.3.1 (build 25D2128)
#
# Shared darwin defaults (dock, finder, trackpad, etc.) live in
# modules/darwin/system.nix and mirror the real settings on this machine.
# Put host-specific overrides in `config` below.
{
  system = "aarch64-darwin";
  user = {
    name = "thijsvw";
    fullname = "Thijs van Waaij";
  };

  type = "macbook";

  hardware-profiles = [ ];

  options = { };

  config =
    { ... }:
    {
      # Apple Virtualization Linux builder — lets Linux derivations build
      # locally (used by the nixos-server-config flake). On Apple Silicon
      # the VM is aarch64 NixOS; binfmt-qemu lets it also build x86_64
      # (Proxmox VMs are x86_64).
      nix.linux-builder.enable = true;
      nix.linux-builder.systems = [
        "aarch64-linux"
        "x86_64-linux"
      ];
      nix.linux-builder.config = {
        boot.binfmt.emulatedSystems = [ "x86_64-linux" ];
      };

      # First-time bootstrap: back up any existing dotfiles instead of
      # refusing to overwrite. Remove after first successful switch if you
      # want strict overwrite behavior.
      home-manager.backupFileExtension = "before-nix";

      # Host-specific darwin settings go here. Example overrides:
      #
      #   system.defaults.dock.tilesize = 56;
      #   homebrew.casks = [ "some-extra-cask" ];
    };
}
