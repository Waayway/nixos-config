{
  system = "x86_64-linux";
  user = {
    name = "waayway";
    fullname = "Thijs van Waaij";
  };

  type = "desktop";

  options = {
    hardware = {
      bluetooth.enable = true;
      profiles = [
        "common-cpu-amd"
        "common-cpu-amd-pstate"
        "common-gpu-amd"
        "common-pc"
        "common-pc-ssd"
      ];
    };
    workstation = {
      terminal.enable = true;
      neovim.enable = true;
      desktop = {
        kde.enable = false;
        hyprland.enable = true;
      };
    };
    server = { };
  };

  config =
    { ... }:
    {
      boot.initrd.availableKernelModules = [
        "nvme"
        "xhci_pci"
        "ahci"
        "thunderbolt"
        "uas"
        "usbhid"
        "sd_mod"
      ];
      boot.initrd.kernelModules = [ ];
      boot.kernelModules = [ "kvm-amd" ];
      boot.extraModulePackages = [ ];

      fileSystems."/" = {
        device = "/dev/disk/by-uuid/dfe31e44-f9db-455f-8b21-81069556c572";
        fsType = "ext4";
      };

      fileSystems."/boot" = {
        device = "/dev/disk/by-uuid/657C-8CCB";
        fsType = "vfat";
        options = [
          "fmask=0077"
          "dmask=0077"
        ];
      };

      swapDevices = [ ];

    };

}
