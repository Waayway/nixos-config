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
  # Not a Proxmox VM: no useDefaultHardware/netInterface, and the partition
  # scheme follows the NixOS wiki's Hetzner Cloud guide
  # (https://wiki.nixos.org/wiki/Install_NixOS_on_Hetzner_Cloud), not the
  # Proxmox single-ext4-root pattern: MBR, a separate /boot (ext4, legacy
  # BIOS boot), a real swap partition, then / on the rest. Network comes from
  # Hetzner's own DHCP (the repo default), Tailscale carries fleet/admin
  # traffic once enrolled. `tag:hestia` still needs adding to the Tailscale
  # policy's tagOwners (owned by tag:nixos) before it can actually join with
  # this tag.
  options = { };

  config =
    { lib, modulesPath, ... }:
    {
      imports = [ (modulesPath + "/profiles/qemu-guest.nix") ];

      bootloader = "grub";
      boot.loader.grub.device = lib.mkForce "/dev/sda";
      boot.initrd.availableKernelModules = [
        "ahci"
        "xhci_pci"
        "virtio_pci"
        "virtio_scsi"
        "sd_mod"
        "sr_mod"
        "ext4"
      ];
      services.qemuGuest.enable = true;

      fileSystems."/" = {
        device = "/dev/disk/by-label/nixos";
        fsType = "ext4";
      };
      fileSystems."/boot" = {
        device = "/dev/disk/by-label/boot";
        fsType = "ext4";
      };

      swapDevices = [ { device = "/dev/disk/by-label/swap"; } ];
    };
}
