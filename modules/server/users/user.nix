{
  user,
  hostPlatform,
  lib,
  ...
}:
let
  proxmoxKey = builtins.readFile ./proxmox-vms_rsa.pub;
  breakGlassKey = builtins.readFile ./break-glass-root_ed25519.pub;
in
lib.optionalAttrs hostPlatform.isLinux {
  config = lib.mkMerge [
    {
      users.users.${user.name} = {
        openssh.authorizedKeys.keys = lib.optional hostPlatform.isServer proxmoxKey;
        # Servers keep the user's systemd instance running without a login
        # session. Otherwise a switch (e.g. a Lodestar apply) can hit it while it
        # stops after the last SSH session closed, and user activation fails.
        linger = hostPlatform.isServer;
      };
    }
    # Root's break-glass key, on servers only.
    # Private key lives in 1Password, NOT on the macbook. Recovery use only.
    (lib.mkIf hostPlatform.isServer {
      users.users.root.openssh.authorizedKeys.keys = [ breakGlassKey ];
    })
  ];
}
