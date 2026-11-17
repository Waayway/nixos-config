{
  system = "x86_64-linux";
  user = {
    name = "waayway";
    fullname = "Thijs van Waaij";
  };

  type = "desktop";
  # Managed by Lodestar (docs/lodestar.md); workstations follow `unstable`.
  fleet = true;

  options = {
    workstation.apps = {
      browsers.enable = true;
      communication = {
        enable = true;
        telegram.enable = false;
        element.enable = false;
      };
      media.enable = true;
      office.enable = true;
      utilities.enable = true;
      # Bitfocus Companion for the Stream Deck (web UI on http://localhost:8000).
      streamdeck.enable = true;
    };
    # The gaming PC: Steam, Heroic and the CachyOS-style tuning (modules/workstation/games/,
    # docs/gaming.md).
    programs.games.enable = true;
    # Started with the Hyprland session (modules/workstation/desktop/hyprland/autostart.nix):
    # Steam in the tray, and SONE (TIDAL) on the music workspace.
    workstation.autostart = [
      "steam -silent"
      "sone"
    ];
    # TrueNAS at /store and /archive (automounted, boot never waits for it).
    workstation.storage.homelab.enable = true;
    hardware = {
      bluetooth.enable = true;
      amdgpu.extras.enable = true;
      profiles = [
        "common-cpu-amd"
        "common-cpu-amd-pstate"
        "common-gpu-amd"
        "common-pc"
        "common-pc-ssd"
      ];
    };
    home-manager.enable = true;
  };

  config =
    { ... }:
    {
      boot.initrd.availableKernelModules = [
        "nvme"
        "xhci_pci"
        "ahci"
        "thunderbolt"
        "usbhid"
        "usb_storage"
        "uas"
        "sd_mod"
      ];
      boot.initrd.kernelModules = [ ];
      boot.kernelModules = [ "kvm-amd" ];
      boot.extraModulePackages = [ ];

      fileSystems."/" = {
        device = "/dev/disk/by-uuid/8fcbec72-7472-47c8-9a05-ee8a2c8699f0";
        fsType = "btrfs";
        options = [
          "subvol=@root"
          "noatime"
        ];
      };

      fileSystems."/swap" = {
        device = "/dev/disk/by-uuid/8fcbec72-7472-47c8-9a05-ee8a2c8699f0";
        fsType = "btrfs";
        options = [ "subvol=@swap" ];
      };

      fileSystems."/home" = {
        device = "/dev/disk/by-uuid/8fcbec72-7472-47c8-9a05-ee8a2c8699f0";
        fsType = "btrfs";
        options = [
          "subvol=@home"
          "noatime"
        ];
      };

      fileSystems."/nix" = {
        device = "/dev/disk/by-uuid/8fcbec72-7472-47c8-9a05-ee8a2c8699f0";
        fsType = "btrfs";
        options = [
          "subvol=@nix"
          "noatime"
        ];
      };

      fileSystems."/boot" = {
        device = "/dev/disk/by-uuid/4818-6395";
        fsType = "vfat";
        options = [
          "fmask=0077"
          "dmask=0077"
        ];
      };

      swapDevices = [ ];

      # More drives: add each one here, by UUID (`lsblk -f`), with `nofail` so a missing or
      # slow drive never stops the boot, e.g. a games drive:
      #
      # fileSystems."/mnt/games" = {
      #   device = "/dev/disk/by-uuid/<uuid>";
      #   fsType = "ext4";                 # or btrfs/xfs/ntfs3
      #   options = [ "nofail" "noatime" ];
      # };
      #
      # Steam: add /mnt/games as a library folder (Steam, Settings, Storage). Proton needs
      # a Linux filesystem (ext4, btrfs, xfs), not NTFS, for the compatdata of a game.
    };

}
