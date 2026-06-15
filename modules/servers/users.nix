{ user, ... }:

let
  proxmoxKey    = builtins.readFile ./proxmox-vms_rsa.pub;
  breakGlassKey = builtins.readFile ./break-glass-root_ed25519.pub;
in {
  users.mutableUsers = false;

  users.users.${user.name} = {
    isNormalUser = true;
    extraGroups  = [ "wheel" ];
    openssh.authorizedKeys.keys = [ proxmoxKey ];
  };

  # Root: password disabled, key-only via the break-glass key.
  # Private key lives in 1Password — NOT on the macbook. Recovery use only.
  users.users.root.hashedPassword               = "!";
  users.users.root.openssh.authorizedKeys.keys  = [ breakGlassKey ];
}
