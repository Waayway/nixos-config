{
  hardware-profiles = [
    "common-cpu-amd"
    "common-cpu-amd-pstate"
    "common-gpu-amd"
    "common-pc"
    "common-pc-ssd"
  ];

  isServer = false;
  isLaptop = false;
  isFramework = false;

  options = {
    desktop = {
      kde.enable = false;
    };
    bluetooth.enable = true;
  };

  config =
    { ... }:
    {
	boot.initrd.availableKernelModules = [ "nvme" "xhci_pci" "ahci" "thunderbolt" "uas" "usbhid" "sd_mod" ];
	boot.initrd.kernelModules = [ ];
	boot.kernelModules = [ "kvm-amd" ];
	boot.extraModulePackages = [ ];

	fileSystems."/" =
	  { device = "/dev/disk/by-uuid/dfe31e44-f9db-455f-8b21-81069556c572";
	      fsType = "ext4";
	    };

	  fileSystems."/boot" =
	    { device = "/dev/disk/by-uuid/657C-8CCB";
	      fsType = "vfat";
	      options = [ "fmask=0077" "dmask=0077" ];
	    };

	  swapDevices = [ ];

    };

}
