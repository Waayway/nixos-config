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
    homelab.nextcloud.enable = true;
    homelab.jellyfin = {
      enable = true;
      configDir = "/store/jellyfin-test/config";
    };
    homelab.immich.enable = true;
  };

  config = { ... }: { };
}
