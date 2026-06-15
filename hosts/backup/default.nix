{
  system   = "x86_64-linux";
  user     = { name = "backup"; fullname = "Backup VM"; };

  isServer    = true;
  isLaptop    = false;
  isFramework = false;
  hardware-profiles = [ ];

  tags = [ "tag:backup" ];

  # Presence of `deploy` makes flake.nix emit a `deploy.nodes.backup` entry
  # for deploy-rs. SSH key path is on the macbook (apollo) — see the
  # `nixos-server-config` README for how it was generated.
  deploy = {
    ip     = "10.0.10.150";
    sshKey = "/Users/thijsvw/.ssh/proxmox-vms_rsa";
  };

  config = { ... }: {
    imports = [
      ./hardware.nix
      ./networking.nix
      ../../modules/services/backrest.nix
    ];
  };
}
