{
  hostPlatform,
  modulesPath,
  serverOptions,
  lib,
  ...
}:
{
  imports =
    if
      (
        hostPlatform.isLinux
        && hostPlatform.isServer
        && serverOptions.useDefaultHardware
        && serverOptions.isHomeServer
      )
    then
      [
        (modulesPath + "/profiles/qemu-guest.nix")
      ]
    else
      [ ];

  config = lib.optionalAttrs (hostPlatform.isLinux && hostPlatform.isServer) (
    { }
    // (lib.optionalAttrs (serverOptions.useDefaultHardware && serverOptions.isHomeServer) {

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
    })
    // (lib.optionalAttrs (serverOptions.netInterface != false) {
      networking.useDHCP = false;

      networking.interfaces.ens18.ipv4.addresses = [
        {
          address = serverOptions.netInterface.ip;
          prefixLength = serverOptions.netInterface.prefixLength;
        }
      ];

      networking.defaultGateway = "10.0.10.1";
      networking.nameservers = [
        "10.0.10.1"
        "1.1.1.1"
      ];
    })
  );
}
