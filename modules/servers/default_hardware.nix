{
  hostPlatform,
  modulesPath,
  serverOptions,
  lib,
  ...
}:
{
  config = lib.optional (hostPlatform.isLinux && hostPlatform.isServer) (
    lib.optional (serverOptions.useDefaultHardware && serverOptions.isHomeServer) {
      imports = [ (modulesPath + "/profiles/qemu-guest.nix") ];

      boot.initrd.availableKernelModules = [
        "virtio_pci"
        "virtio_blk"
        "virtio_net"
        "virtio_scsi"
      ];
      boot.kernelModules = [ "kvm-amd" ];

      fileSystems."/" = {
        device = "/dev/disk/by-label/nixos";
        fsType = "ext4";
      };
    }
    // lib.optional (serverOptions.netInterface != false) {
      networking.useDHCP = false;

      networking.interfaces.ens18.ipv4.addresses = [
        {
          address = serverOptions.netInteface.ip;
          prefixLength = serverOptions.netInteface.prefixLength;
        }
      ];

      networking.defaultGateway = "10.0.10.1";
      networking.nameservers = [
        "10.0.10.1"
        "1.1.1.1"
      ];
    }
  );
}
