{
  system = "x86_64-linux";
  user = {
    name = "prod";
    fullname = "Production";
  };

  type = "server";
  useDefaultHardware = true;
  isHomeServer = true;

  netInterface = {
    ip = "10.0.10.100";
    prefixLength = 24;
  };

  tags = [ "tag:prod" ];

  fleet = true;

  options = {
    homelab.storage.enable = true;
    # Live since the cutover (2026-10-19): the router sends the internet here.
    homelab.nextcloud = {
      enable = true;
      live = true;
    };
    homelab.jellyfin = {
      enable = true;
      live = true;
      configDir = "/store/jellyfin/config";
    };
    homelab.immich = {
      enable = true;
      live = true;
    };
  };

  config = { ... }: { };
}
