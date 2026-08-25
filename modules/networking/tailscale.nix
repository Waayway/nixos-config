{ config, lib, tags ? [ ], ... }:

let
  allTags = [ "tag:nixos" ] ++ tags;
in {
  sops.secrets.tailscale_authkey = {
    mode  = "0400";
    owner = "root";
  };

  services.tailscale = {
    enable        = true;
    authKeyFile   = config.sops.secrets.tailscale_authkey.path;
		authKeyParameters = {
			ephemeral = false;
			preauthorized = true;
		};
    extraUpFlags  = [
      "--ssh"
      "--advertise-tags=${lib.concatStringsSep "," allTags}"
    ];
  };
}
