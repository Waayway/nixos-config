{
  config,
  lib,
  hostPlatform,
  ...
}:
# Jellyfin on the official Docker image's layout: its database holds absolute paths
# from that container (`--datadir /config --cachedir /cache`, library at /media), so
# the unit binds the same paths: `configDir` (on TrueNAS) at /config, a local cache
# at /cache and the library /archive/jellyfin read-only at /media. Config is then
# /config/config and logs /config/log, as in the image.
let
  cfg = config.homelab.jellyfin;
  lan = config.homelab.lan;
  host = "jellyfin.vanwaaij.com";
  port = 8096;
  library = "/archive/jellyfin";
  cache = "/var/cache/jellyfin";
in
lib.optionalAttrs hostPlatform.isLinux {
  options.homelab.jellyfin = {
    enable = lib.mkEnableOption "Jellyfin";
    live = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = "Serve the public host; off, it shows the maintenance page.";
    };
    configDir = lib.mkOption {
      type = lib.types.str;
      example = "/store/jellyfin/config";
      description = "The container's /config directory (data, config and logs), bound at /config.";
    };
    gpu = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = "VA-API transcoding on the passed-through AMD GPU (/dev/dri/renderD128).";
    };
  };

  config = lib.mkIf cfg.enable (
    lib.mkMerge [
      {
        services.jellyfin = {
          enable = true;
          # Paths inside the unit's mount namespace (bound below).
          dataDir = "/config";
          cacheDir = "/cache";
        };

        # Only the local cache is a real directory; /config and /cache are bind
        # targets (systemd creates them), and /store must not be touched at boot.
        systemd.tmpfiles.settings.jellyfinDirs = lib.mkForce {
          ${cache}.d = {
            mode = "0700";
            user = "jellyfin";
            group = "jellyfin";
          };
        };

        systemd.services.jellyfin = {
          serviceConfig = {
            BindPaths = [
              "${cfg.configDir}:/config"
              "${cache}:/cache"
            ];
            BindReadOnlyPaths = [ "${library}:/media" ];
          };
          unitConfig.RequiresMountsFor = [
            cfg.configDir
            library
          ];
        };

        networking.firewall.interfaces.${lan.interface}.allowedTCPPorts = [ port ];

        homelab.routes.jellyfin = {
          inherit host;
          backend = "http://${lan.address}:${toString port}";
          maintenance = !cfg.live;
        };

        lodestar.links.jellyfin = {
          title = "Jellyfin";
          group = "Media";
          description = "Media server";
          icon = "jellyfin";
          url = "https://${host}";
          check.url = "http://${lan.address}:${toString port}";
        };
      }

      (lib.mkIf cfg.gpu {
        # Polaris (Radeon Pro WX 7100): Mesa's radeonsi VA-API driver.
        hardware.graphics.enable = true;
        services.jellyfin.hardwareAcceleration = {
          enable = true;
          type = "vaapi";
          device = "/dev/dri/renderD128";
        };
        users.users.jellyfin.extraGroups = [
          "render"
          "video"
        ];
      })
    ]
  );
}
