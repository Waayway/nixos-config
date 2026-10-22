{
  modulesPath,
  lib,
  pkgs,
  ...
}:
# Base image for new Proxmox VMs (`nix build .#proxmox-template`).
#
# The `proxmox` format from nixos-generators handles the bootloader and the
# partition layout (BIOS, ext4 root labelled `nixos`), which is what
# modules/server/proxmox/proxmox-guest.nix expects once a VM is switched to its
# real host config. This image is self-contained on purpose: the repo's
# module tree needs the specialArgs that lib/mkSystem.nix provides, so the
# image only carries what's needed to log in and run the first switch:
#   - qemu-guest profile + guest agent (Proxmox can read the VM's IP)
#   - DHCP via systemd-networkd on whatever interface comes up
#   - flakes, a bootstrap user `nixos` with the proxmox-vms key, root via
#     the break-glass key only
#   - optionally the opnix token (below), so the first switch to a server
#     config can fetch its secrets from 1Password right away
let
  proxmoxKey = builtins.readFile ../modules/server/users/proxmox-vms_rsa.pub;
  breakGlassKey = builtins.readFile ../modules/server/users/break-glass-root_ed25519.pub;

  # The opnix service-account token is never in this (public) repo. A build
  # opts in with an impure build that names a file holding it, e.g. on
  # nixos-manager, which already has the token (as the repo's owner; root
  # trips git's "dubious ownership"):
  #   sudo install -m 0400 -o "$USER" /etc/opnix-token /tmp/opnix-token
  #   OPNIX_TOKEN_FILE=/tmp/opnix-token nix build --impure .#proxmox-template
  #   rm /tmp/opnix-token
  # Pure evaluation (flake check, other machines) sees "" and leaves it out.
  # The token then sits in the build host's Nix store, the image and every
  # clone.
  opnixTokenFile = builtins.getEnv "OPNIX_TOKEN_FILE";
  opnixToken =
    if opnixTokenFile == "" then
      null
    else
      builtins.path {
        path = opnixTokenFile;
        name = "opnix-token";
      };
in
{
  imports = [ (modulesPath + "/profiles/qemu-guest.nix") ];

  networking.hostName = "nixos-template";
  # The proxmox image ships systemd-networkd (cloud-init); let networkd do
  # DHCP too, so dhcpcd and networkd never manage the same interface.
  networking.useNetworkd = true;
  networking.useDHCP = lib.mkForce true;
  # One link with an address is enough; waiting for every link held sshd back
  # about two minutes on first boot.
  systemd.network.wait-online.anyInterface = true;

  services.qemuGuest.enable = true;

  nix.settings = {
    experimental-features = [
      "nix-command"
      "flakes"
    ];
    trusted-users = [
      "root"
      "nixos"
    ];
  };

  services.openssh = {
    enable = true;
    settings = {
      PasswordAuthentication = false;
      KbdInteractiveAuthentication = false;
      PermitRootLogin = "prohibit-password";
    };
  };

  # Bootstrap user — replaced by the per-host user on the first switch.
  users.users.nixos = {
    isNormalUser = true;
    extraGroups = [ "wheel" ];
    openssh.authorizedKeys.keys = [ proxmoxKey ];
  };
  security.sudo.wheelNeedsPassword = false;

  users.users.root.hashedPassword = "!";
  users.users.root.openssh.authorizedKeys.keys = [ breakGlassKey ];

  environment.systemPackages = [ pkgs.git ];

  # A plain file, not environment.etc: NixOS removes its own /etc entries on
  # the first switch to a config that doesn't declare them, and opnix
  # (modules/server/secrets/opnix.nix) expects the token to stay. Never overwrites.
  system.activationScripts.opnixToken = lib.mkIf (opnixToken != null) ''
    if [ ! -s /etc/opnix-token ]; then
      install -m 0600 -o root -g root ${opnixToken} /etc/opnix-token
    fi
  '';

  system.stateVersion = "26.05";

  # Host keys come from NixOS (sshd-keygen) on first boot. cloud-init's own
  # ssh module raced it and regenerated the keys whenever Proxmox handed out a
  # new instance-id (any `qm set` on the VM).
  services.cloud-init.settings = {
    ssh_deletekeys = false;
    ssh_genkeytypes = [ ];
  };

  # Proxmox's default vCPU lacks SSE4.1: the 1Password SDK inside opnix then
  # runs its WebAssembly core interpreted, 88 s per fetch instead of 4 s.
  proxmox.qemuExtraConf.cpu = "host";
  proxmox.qemuConf.name = "nixos-template";
  proxmox.qemuConf.cores = 2;
  proxmox.qemuConf.memory = 2048;
}
