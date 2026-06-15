{ modulesPath, lib, ... }: {
  # The `proxmox` format from nixos-generators handles bootloader and
  # partition layout. We layer on:
  #   - qemu-guest profile: virtio drivers + qemu-guest-agent (so Proxmox
  #     can read the VM's IP and the agent socket works)
  #   - networking.useDHCP = true: proxmox-image defaults it to false and
  #     expects cloud-init or per-interface DHCP; we don't know the
  #     interface name at build time, so force the legacy global flag on.
  #   - base nix settings + hardened SSH + bootstrap user/key.
  imports = [
    (modulesPath + "/profiles/qemu-guest.nix")
    ../modules/base/nix.nix
    ../modules/base/openssh.nix
    ../modules/servers/openssh.nix
    ../modules/servers/users.nix
  ];

  # Bootstrap user — replaced by per-host user on first deploy.
  _module.args.user = { name = "nixos"; fullname = "Bootstrap"; };

  networking.hostName = "nixos-template";
  networking.useDHCP  = lib.mkForce true;
  system.stateVersion = "26.05";

  services.qemuGuest.enable = true;

  proxmox.qemuConf.name   = "nixos-template";
  proxmox.qemuConf.cores  = 2;
  proxmox.qemuConf.memory = 2048;
}
