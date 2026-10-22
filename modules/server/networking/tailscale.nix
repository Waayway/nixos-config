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
    # Servers join unattended with the tagged auth key from 1Password
    # (modules/server/secrets/opnix.nix). A tag replaces the device's user identity,
    # so workstations (laptops, desktop) stay untagged and are logged in once
    # by hand (`sudo tailscale up --ssh`); they then belong to Waayway@github.
    config = lib.mkIf hostPlatform.isServer {
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
        # mkAfter keeps "--ssh" (common/networking/tailscale.nix) first.
        extraUpFlags = lib.mkAfter [ "--advertise-tags=${lib.concatStringsSep "," allTags}" ];
      };
    };
  }
)
