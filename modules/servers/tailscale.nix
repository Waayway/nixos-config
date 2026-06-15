{ config, lib, tags ? [ ], ... }:

let
  allTags = [ "tag:server" ] ++ tags;
in {
  sops.secrets.tailscale_authkey = {
    mode  = "0400";
    owner = "root";
  };

  services.tailscale = {
    enable        = true;
    authKeyFile   = config.sops.secrets.tailscale_authkey.path;
    extraUpFlags  = [
      "--ssh"
      "--advertise-tags=${lib.concatStringsSep "," allTags}"
    ];
  };
}
