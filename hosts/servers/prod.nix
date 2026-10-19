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
    homelab.nextcloud = {
      enable = true;
      # Temporary: Main's exact version while Main still serves the shared data
      # directory (no `occ upgrade` on it); back to the floating 32-apache track after
      # the cutover.
      imageTag = "32.0.8-apache";
    };
    homelab.jellyfin = {
      enable = true;
      configDir = "/store/jellyfin/config";
    };
    homelab.immich.enable = true;
  };

  config = { ... }: { };
}
