{
  system = "x86_64-linux";
  user = {
    name = "hestia";
    fullname = "Hestia";
  };

  type = "server";

  tags = [ "tag:hestia" ];

  fleet = true;

  # Hetzner Cloud CX23 (2 vCPU shared, 4 GB RAM, 40 GB disk) — the app-hosting
  # platform node (docs/plans/2026-11-10-lodestar-hosting-platform-design.md).
  # Not a Proxmox VM: no useDefaultHardware/netInterface. Disk is /dev/sda
  # (Proxmox VMs are /dev/vda), network comes from Hetzner's own DHCP (the
  # repo default), Tailscale carries fleet/admin traffic once enrolled.
  # `tag:hestia` still needs adding to the Tailscale policy's tagOwners
  # (owned by tag:nixos) before it can actually join with this tag.
  options = { };

  config =
    { lib, modulesPath, ... }:
    {
      imports = [ (modulesPath + "/profiles/qemu-guest.nix") ];

      bootloader = "grub";
      boot.loader.grub.device = lib.mkForce "/dev/sda";
      boot.growPartition = true;
      services.qemuGuest.enable = true;

      fileSystems."/" = {
        device = "/dev/disk/by-label/nixos";
        fsType = "ext4";
        autoResize = true;
      };

      swapDevices = [
        {
          device = "/var/swap";
          size = 2048;
        }
      ];
    };
}
