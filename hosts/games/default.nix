{
  system   = "x86_64-linux";
  user     = { name = "waayway"; fullname = "Thijs van Waaij"; };

  isServer    = true;
  isLaptop    = false;
  isFramework = false;
  hardware-profiles = [ ];

  tags = [ "tag:games" ];

  # Presence of `deploy` makes flake.nix emit a `deploy.nodes.games` entry
  # for deploy-rs. SSH key path is on the macbook (apollo).
  deploy = {
    ip     = "10.0.10.201";
    sshKey = "/Users/thijsvw/.ssh/proxmox-vms_rsa";
  };

  config = { ... }: {
    imports = [
      ./hardware.nix
      ./networking.nix
      # Same nixvim build as the workstations, so `nvim` matches my setup.
      ../../modules/workstations/terminal/neovim.nix
    ];

    # Basic container host.
    virtualisation.docker.enable           = true;
    virtualisation.docker.autoPrune.enable = true;
  };
}
