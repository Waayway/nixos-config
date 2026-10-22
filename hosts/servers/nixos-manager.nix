{
  system = "x86_64-linux";
  user = {
    name = "manager";
    fullname = "Nixos Manager";
  };

  type = "server";
  useDefaultHardware = true;
  isHomeServer = true;

  netInterface = {
    ip = "10.0.10.170";
    prefixLength = 24;
  };

  tags = [ "tag:manager" ];

  fleet = true;

  # No options: terminal/neovim are always on (no enable options declared).
  options = {
    services.lodestar-server = {
      enable = true;
      # Last known tailnet IP (`tailscale status`): confirm at bootstrap.
      listenAddress = "100.92.102.84";
    };
    # TrueNAS as code (modules/server/truenas/) and the restic backups driven from here
    # (modules/server/backup/).
    truenas.enable = true;
    backup.restic.enable = true;
  };

  config = { ... }: { };
}
