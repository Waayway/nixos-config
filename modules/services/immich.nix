{
  config,
  lib,
  hostPlatform,
  ...
}:
# Immich with its own PostgreSQL and Redis (the NixOS module's defaults) and machine
# learning on the CPU. Media on TrueNAS at /store/immich-v2; nightly database dump to
# /store/db-dumps/immich.
let
  cfg = config.homelab.immich;
  lan = config.homelab.lan;
  host = "immich.vanwaaij.com";
  port = 2283;
  media = "/store/immich-v2";
  dumpDir = "/store/db-dumps/immich";
in
lib.optionalAttrs hostPlatform.isLinux {
  options.homelab.immich = {
    enable = lib.mkEnableOption "Immich";
    live = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = "Serve the public host; off, it shows the maintenance page.";
    };
  };

  config = lib.mkIf cfg.enable {
    # nixpkgs 26.05 marks Immich 2.x EOL (3.x is in 26.11); the plan stays on 2.7
    # until the NixOS release that ships 3.x.
    homelab.insecurePackages = [ "immich-2." ];

    services.immich = {
      enable = true;
      mediaLocation = media;
      host = "0.0.0.0";
      inherit port;
      machine-learning.enable = true;
    };

    services.postgresqlBackup = {
      enable = true;
      databases = [ "immich" ];
      location = dumpDir;
    };

    systemd.services = {
      immich-server.unitConfig.RequiresMountsFor = [ media ];
      postgresqlBackup-immich.unitConfig.RequiresMountsFor = [ dumpDir ];
    };

    networking.firewall.interfaces.${lan.interface}.allowedTCPPorts = [ port ];

    homelab.routes.immich = {
      inherit host;
      backend = "http://${lan.address}:${toString port}";
      maintenance = !cfg.live;
    };

    lodestar.links.immich = {
      title = "Immich";
      group = "Media";
      description = "Photos and videos";
      icon = "immich";
      url = "https://${host}";
      check.url = "http://${lan.address}:${toString port}";
    };
  };
}
