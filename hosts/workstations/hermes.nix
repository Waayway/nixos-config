{
  system = "x86_64-linux";
  user = {
    name = "waayway";
    fullname = "Thijs van Waaij";
  };

  hardware-profiles = [ "framework-amd-ai-300-series" ];

  type = "framework13";

  options = {
    desktop = {
      kde.enable = true;
    };
    bluetooth.enable = true;
  };

  config =
    { ... }:
    {
      # Firmware updating service
      services.fwupd.enable = true;

      boot.initrd.kernelModules = [ "amdgpu" ];
      services.xserver.videoDrivers = [ "amdgpu" ];
      boot.initrd.availableKernelModules = [
        "nvme"
        "xhci_pci"
        "thunderbolt"
        "usb_storage"
        "uas"
        "sd_mod"
      ];
      boot.kernelModules = [ "kvm-amd" ];
      fileSystems."/" = {
        device = "/dev/disk/by-uuid/13db84b5-d926-4ef0-a236-5505c84b802e";
        fsType = "ext4";
      };

      fileSystems."/boot" = {
        device = "/dev/disk/by-uuid/E60B-51DA";
        fsType = "vfat";
        options = [
          "fmask=0077"
          "dmask=0077"
        ];
      };

      swapDevices = [
        { device = "/dev/disk/by-uuid/ceb758d5-9c7f-4a89-b5aa-54a6254fc679"; }
      ];

    };
}
