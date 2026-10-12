{
  lib,
  modulesPath,
  hostPlatform,
  serverOptions ? { },
  ...
}:
lib.optionalAttrs
  (
    hostPlatform.isLinux && hostPlatform.isServer && (serverOptions.useDefaultHardware or null) == true
  )
  {
    # Matches the nixos-generators `proxmox` format the VMs are built from.
    imports = [ (modulesPath + "/profiles/qemu-guest.nix") ];

    fileSystems."/" = {
      device = "/dev/disk/by-label/nixos";
      fsType = "ext4";
      autoResize = true;
    };

    boot.loader.grub.device = "/dev/vda";
    boot.growPartition = true;
    services.qemuGuest.enable = true;
  }
