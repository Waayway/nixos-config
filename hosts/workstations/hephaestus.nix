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
    # The Steam Controller's mouse in desktop mode on Hyprland (steam-controller.nix).
    programs.games.steamController.enable = true;
    # Steam without the blur: Hyprland draws XWayland at real pixels and Steam scales itself
    # to match the primary monitor, the Acer at scale 2 (steam-scaling.nix).
    programs.games.steamScale = 2;
    # Started with the Hyprland session (modules/workstation/desktop/hyprland/autostart.nix):
    # Steam in the tray, and High Tide (TIDAL) on the music workspace.
    workstation.autostart = [
      "steam -silent"
      "high-tide"
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
          "compress=zstd:1"
        ];
      };

      fileSystems."/swap" = {
        device = "/dev/disk/by-uuid/8fcbec72-7472-47c8-9a05-ee8a2c8699f0";
        fsType = "btrfs";
        # No compression here: btrfs cannot compress a swapfile.
        options = [ "subvol=@swap" ];
      };

      fileSystems."/home" = {
        device = "/dev/disk/by-uuid/8fcbec72-7472-47c8-9a05-ee8a2c8699f0";
        fsType = "btrfs";
        options = [
          "subvol=@home"
          "noatime"
          "compress=zstd:1"
        ];
      };

      fileSystems."/nix" = {
        device = "/dev/disk/by-uuid/8fcbec72-7472-47c8-9a05-ee8a2c8699f0";
        fsType = "btrfs";
        options = [
          "subvol=@nix"
          "noatime"
          "compress=zstd:1"
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

      # Compression (compress=zstd:1) is only on the boot drive above, on purpose: add it to
      # another drive's options by hand if it should have it too.
      #
      # The other drives. `nofail` and a short device timeout so a missing drive never holds
      # up the boot. Each is a whole btrfs filesystem with no subvolumes; after the first
      # mount, `sudo chown waayway: <mountpoint>` once so your user can write to it.
      # Steam: add /mnt/games as a library folder (Steam, Settings, Storage); Proton needs a
      # Linux filesystem (ext4, btrfs, xfs), not NTFS, for the compatdata of a game.
      fileSystems."/mnt/bep" = {
        # nvme2n1p1, 1.8T NVMe
        device = "/dev/disk/by-uuid/746eb8f9-52ab-4578-b17d-9dc1de235d14";
        fsType = "btrfs";
        options = [
          "nofail"
          "noatime"
          "x-systemd.device-timeout=5s"
        ];
      };

      fileSystems."/mnt/games" = {
        # sda1, 1.1T SATA
        device = "/dev/disk/by-uuid/9b29a20d-e671-4b37-bdf5-2d488577b179";
        fsType = "btrfs";
        options = [
          "nofail"
          "noatime"
          "x-systemd.device-timeout=5s"
        ];
      };

      # The Windows disks (sdb, nvme1n1) are not mounted. They share the same filesystem
      # UUIDs, so by-uuid cannot tell them apart; use /dev/disk/by-id/ if one is ever needed.
    };

}
