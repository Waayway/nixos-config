{
  lib,
  modulesPath,
  hostPlatform,
  serverOptions ? { },
  ...
}:
let
  enabled =
    hostPlatform.isLinux && hostPlatform.isServer && (serverOptions.useDefaultHardware or null) == true;
  net = serverOptions.netInterface or null;
  gateway = if net != null then net.gateway or "10.0.10.1" else null;
in
lib.optionalAttrs enabled {
  # Matches the nixos-generators `proxmox` format the VMs are built from
  # (template/proxmox.nix).
  imports = [ (modulesPath + "/profiles/qemu-guest.nix") ];

  config = lib.mkMerge [
    {
      fileSystems."/" = {
        device = "/dev/disk/by-label/nixos";
        fsType = "ext4";
        autoResize = true;
      };

      # BIOS + single ext4 root, no ESP: GRUB on the disk (modules/boot/boot.nix).
      bootloader = "grub";
      boot.growPartition = true;
      services.qemuGuest.enable = true;
    }

    # A host file's `netInterface = { ip; prefixLength; gateway?; }` pins the
    # VM to that LAN address (gateway/DNS default to the LAN router). Without
    # it the VM keeps the repo default (NetworkManager + DHCP).
    (lib.mkIf (net != null) {
      networking.networkmanager.enable = lib.mkForce false;
      networking.useDHCP = lib.mkForce false;
      networking.useNetworkd = true;
      systemd.network.networks."10-lan" = {
        # The NIC only (virtio-net, ens18 on the template). `Type = "ether"` alone also
        # matches Docker's veth pairs: networkd then gave every container veth the
        # LAN address and pulled it off its bridge, cutting the containers off.
        matchConfig = {
          Type = "ether";
          Name = "en*";
        };
        address = [ "${net.ip}/${toString net.prefixLength}" ];
        gateway = [ gateway ];
        dns = [ gateway ];
      };
    })
  ];
}
