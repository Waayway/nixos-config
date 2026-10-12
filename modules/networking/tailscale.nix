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

      # Servers join unattended with the tagged auth key from sops. A tag
      # replaces the device's user identity, so workstations (laptops,
      # desktop) stay untagged and are logged in once by hand
      # (`sudo tailscale up --ssh`); they then belong to Waayway@github.
      (lib.mkIf hostPlatform.isServer {
        sops.secrets.tailscale_authkey = {
          mode = "0400";
          owner = "root";
        };

        services.tailscale = {
          authKeyFile = config.sops.secrets.tailscale_authkey.path;
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
