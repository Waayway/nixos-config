{
  # Proxmox VMs ship as BIOS-boot with a single ext4 root partition (no EFI,
  # no separate /boot). nixos-generators' `proxmox` format installs GRUB i386-pc
  # on the disk. We match that here so future generations continue to install
  # GRUB to the right device.
  boot.loader.grub = {
    enable             = true;
    device             = "/dev/vda";
    configurationLimit = 10;
  };
}
