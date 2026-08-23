{
  lib,
  config,
  hostPlatform,
  ...
}:
let
  bootloader = config.bootloader;
in
{
  options.bootloader = lib.mkOption {
    default = "systemd-boot";
    description = "Which booloader to use for this config";
    type = lib.types.str;
  };

  config = lib.optionalAttrs hostPlatform.isLinux (
    lib.mkIf (bootloader == "grub") {

      # Proxmox VMs ship as BIOS-boot with a single ext4 root partition (no EFI,
      # no separate /boot). nixos-generators' `proxmox` format installs GRUB i386-pc
      # on the disk. We match that here so future generations continue to install
      # GRUB to the right device.
      boot.loader.grub = {
        enable = true;
        device = "/dev/vda";
        configurationLimit = 10;
      };
    }
    // lib.mkIf (bootloader == "systemd-boot") {
      boot.loader.systemd-boot = {
        enable = true;
        configurationLimit = lib.mkDefault 10;
        consoleMode = lib.mkDefault "max";
      };

      boot.loader.efi.canTouchEfiVariables = true;
    }
  );
}
