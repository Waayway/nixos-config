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
    };
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
        options = [ "subvol=@root" ];
      };

      fileSystems."/swap" = {
        device = "/dev/disk/by-uuid/8fcbec72-7472-47c8-9a05-ee8a2c8699f0";
        fsType = "btrfs";
        options = [ "subvol=@swap" ];
      };

      fileSystems."/home" = {
        device = "/dev/disk/by-uuid/8fcbec72-7472-47c8-9a05-ee8a2c8699f0";
        fsType = "btrfs";
        options = [ "subvol=@home" ];
      };

      fileSystems."/nix" = {
        device = "/dev/disk/by-uuid/8fcbec72-7472-47c8-9a05-ee8a2c8699f0";
        fsType = "btrfs";
        options = [ "subvol=@nix" ];
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
    };

}
