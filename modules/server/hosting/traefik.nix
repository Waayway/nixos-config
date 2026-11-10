# The app-hosting node's front door (docs/plans/2026-11-10-lodestar-hosting-platform-design.md).
# A sibling of homelab/router, not a generalisation of it: its own Traefik, tailnet only for
# now. Each route is published as a Tailscale Service (`svc:<servicePrefix><name>`) that
# Tailscale terminates TLS for and forwards to Traefik's loopback entrypoint, which routes by
# Host header. Traefik also watches /var/lib/traefik/dynamic, so a branch deployment can add
# or drop a route by writing or deleting a file there, without a rebuild. NixOS only.
{
  config,
  lib,
  pkgs,
  hostPlatform,
  ...
}:
let
  cfg = config.hosting.traefik;
  dynamicDir = "${config.services.traefik.dataDir}/dynamic";
  entryPoint = "127.0.0.1:8080";
  format = pkgs.formats.toml { };

  host = name: "${cfg.servicePrefix}${name}.${cfg.tailnetDomain}";

  staticRoutes = format.generate "00-static-routes.toml" {
    http = {
      routers = lib.mapAttrs (name: _: {
        rule = "Host(`${host name}`)";
        entryPoints = [ "tailnet" ];
        service = name;
      }) cfg.routes;
      services = lib.mapAttrs (_: r: {
        loadBalancer.servers = [ { url = r.backend; } ];
      }) cfg.routes;
    };
  };
in
lib.optionalAttrs hostPlatform.isLinux {
  options.hosting.traefik = {
    enable = lib.mkEnableOption "the hosting node's Traefik, published on the tailnet";

    servicePrefix = lib.mkOption {
      type = lib.types.str;
      default = "";
      description = "Prefix for Tailscale Service names (`svc:<servicePrefix><route>`).";
    };

    tailnetDomain = lib.mkOption {
      type = lib.types.str;
      default = "tail41ca60.ts.net";
      description = "The tailnet's MagicDNS domain; a service answers on `<servicePrefix><route>.<tailnetDomain>`.";
    };

    routes = lib.mkOption {
      default = { };
      description = "Always-on routes, each also published as a Tailscale Service.";
      type = lib.types.attrsOf (
        lib.types.submodule {
          options.backend = lib.mkOption {
            type = lib.types.str;
            example = "http://127.0.0.1:8000";
            description = "Where Traefik forwards requests for this route.";
          };
        }
      );
    };
  };

  config = lib.mkIf cfg.enable {
    services.traefik = {
      enable = true;
      # A full static file: the module's own one always sets `providers.file.filename`, which
      # cannot be combined with the watched `directory`.
      staticConfigFile = format.generate "traefik.toml" {
        global = {
          checkNewVersion = false;
          sendAnonymousUsage = false;
        };
        log.level = "INFO";
        # Loopback only: reached through the Tailscale Services (tcp:443 -> here).
        entryPoints.tailnet.address = entryPoint;
        providers.file = {
          directory = dynamicDir;
          watch = true;
        };
      };
    };

    # The Nix-declared routes sit in the watched directory next to whatever the agent writes.
    systemd.tmpfiles.rules = [
      "d '${dynamicDir}' 0775 traefik traefik - -"
      "L+ '${dynamicDir}/00-static-routes.toml' - - - - ${staticRoutes}"
    ];

    services.tailscale.serve = lib.mkIf (cfg.routes != { }) {
      enable = true;
      services = lib.mapAttrs' (
        name: _:
        lib.nameValuePair "${cfg.servicePrefix}${name}" {
          # http:// makes Tailscale terminate TLS with the node's own certificate.
          endpoints."tcp:443" = "http://${entryPoint}";
        }
      ) cfg.routes;
    };

    # `serve set-config` fails while the node is logged out: retry until it's in.
    systemd.services.tailscale-serve = lib.mkIf config.services.tailscale.serve.enable {
      after = [
        "tailscaled.service"
        "tailscaled-autoconnect.service"
      ];
      serviceConfig = {
        Restart = "on-failure";
        RestartSec = "10s";
      };
      unitConfig.StartLimitIntervalSec = 0;
    };
  };
}
