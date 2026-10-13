{
  config,
  lib,
  tags ? [ ],
  hostPlatform,
  ...
}:
lib.optionalAttrs hostPlatform.isLinux (
  let
    allTags = [ "tag:nixos" ] ++ tags;
  in
  {
    config = lib.mkMerge [
      {
        services.tailscale = {
          enable = true;
          extraUpFlags = [ "--ssh" ];
        };
      }

      # Servers join unattended with the tagged auth key from 1Password
      # (modules/secrets/opnix.nix). A tag replaces the device's user identity,
      # so workstations (laptops, desktop) stay untagged and are logged in once
      # by hand (`sudo tailscale up --ssh`); they then belong to Waayway@github.
      (lib.mkIf hostPlatform.isServer {
        services.onepassword-secrets.secrets.tailscaleAuthKey = {
          reference = "op://Homelab/tailscale-authkey/credential";
          mode = "0400";
          owner = "root";
          services = [ "tailscaled-autoconnect" ];
        };

        services.tailscale = {
          authKeyFile = config.services.onepassword-secrets.secretPaths.tailscaleAuthKey;
          authKeyParameters = {
            ephemeral = false;
            preauthorized = true;
          };
          extraUpFlags = [ "--advertise-tags=${lib.concatStringsSep "," allTags}" ];
        };
      })
    ];
  }
)
