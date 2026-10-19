# The front-door router (`homelab.router`): Traefik for every route in the flake.
#
# Routes are every configuration's `homelab.routes` (collected with
# `tools.routesFrom`) plus `homelab.router.extraRoutes` (backends this flake doesn't
# manage, modules/homelab/routes.nix); the merged set is `homelab.router.routes`.
# Each route gets a router on the `public` entrypoint (:443, from the internet) when
# `public`, and one on the `tailnet` entrypoint (127.0.0.1:8443, behind the Tailscale
# Service) when `tailnet.enable`. The `tailnet` entrypoint sets `X-Homelab-Via:
# tailnet`; the `public` one removes any such header a client sent. One Let's Encrypt
# wildcard for vanwaaij.com via Cloudflare DNS-01 covers both. NixOS only.
{
  config,
  lib,
  pkgs,
  tools,
  inputs,
  hostPlatform,
  ...
}:
let
  cfg = config.homelab.router;
  routeType = tools.routeType { inherit lib; };

  fromFlake = tools.routesFrom { inherit lib; } { inherit (inputs.self) nixosConfigurations; };
  extra = lib.mapAttrs (_: r: r // { declaredBy = config.networking.hostName; }) cfg.extraRoutes;
  clashes = lib.attrNames (lib.intersectAttrs fromFlake extra);

  tls = {
    certResolver = "cloudflare";
    domains = [
      {
        main = "vanwaaij.com";
        sans = [ "*.vanwaaij.com" ];
      }
    ];
  };

  # Traefik dynamic config for one route: its routers, service and middlewares.
  routeConfig =
    name: r:
    let
      own = lib.mapAttrs' (k: v: lib.nameValuePair "${name}-${k}" v) r.middlewares;
      auth = lib.optionalAttrs (r.basicAuth.usersFile != null) {
        "${name}-auth".basicAuth.usersFile = r.basicAuth.usersFile;
      };
      router = entryPoint: {
        rule = "Host(`${r.host}`)";
        entryPoints = [ entryPoint ];
        service = if r.backend == "api@internal" then "api@internal" else name;
        middlewares = lib.attrNames auth ++ lib.attrNames own;
      };
    in
    {
      routers =
        lib.optionalAttrs r.public { "${name}-public" = router "public"; }
        // lib.optionalAttrs r.tailnet.enable { "${name}-tailnet" = router "tailnet"; };
      services = lib.optionalAttrs (r.backend != "api@internal") {
        ${name}.loadBalancer.servers = [ { url = r.backend; } ];
      };
      middlewares = auth // own;
    };

  perRoute = lib.mapAttrsToList routeConfig cfg.routes;
  collect = key: lib.foldl' (a: b: a // b.${key}) { } perRoute;
in
lib.optionalAttrs hostPlatform.isLinux {
  options.homelab.router = {
    enable = lib.mkEnableOption "the front-door router (Traefik)";

    acmeStaging = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = "Get certificates from Let's Encrypt staging (untrusted, no rate limits).";
    };

    servicePrefix = lib.mkOption {
      type = lib.types.str;
      default = "";
      example = "test-";
      description = "Prefix for the Tailscale Service names, so a test router doesn't clash with the real one.";
    };

    tailnetServices = lib.mkOption {
      type = lib.types.nullOr (lib.types.listOf lib.types.str);
      default = null;
      description = "Route names to publish as Tailscale Services; null means every route with `tailnet.enable`.";
    };

    extraRoutes = lib.mkOption {
      type = lib.types.attrsOf routeType;
      default = { };
      description = "Routes declared on the router itself, for backends this flake doesn't manage.";
    };

    echo = {
      enable = lib.mkEnableOption "a whoami echo service routed as `whoami-test`";
      tailnetAddress = lib.mkOption {
        type = lib.types.nullOr lib.types.str;
        default = null;
        description = "The Tailscale Service IP of `whoami-test`, filled in after the Service exists.";
      };
    };

    routes = lib.mkOption {
      type = lib.types.attrsOf lib.types.anything;
      readOnly = true;
      default = fromFlake // extra;
      defaultText = lib.literalMD "every configuration's `homelab.routes` and `extraRoutes`";
      description = ''
        Every route the router serves: `homelab.routes` from all configurations in
        the flake plus `extraRoutes`, each with `declaredBy` (the configuration that
        declared it). A name in both is an error.
      '';
    };
  };

  config = lib.mkIf cfg.enable (
    lib.mkMerge [
      {
        assertions = [
          {
            assertion = clashes == [ ];
            message = "homelab.router.extraRoutes: route names also declared in homelab.routes: ${toString clashes}";
          }
        ];

        services.traefik = {
          enable = true;

          staticConfigOptions = {
            api.dashboard = true;

            entryPoints = {
              web = {
                address = ":80";
                http.redirections.entryPoint = {
                  to = "public";
                  scheme = "https";
                };
              };
              public = {
                address = ":443";
                http = {
                  inherit tls;
                  middlewares = [ "strip-marker@file" ];
                };
              };
              # Reached only through the Tailscale Services (tcp:443 -> 127.0.0.1:8443).
              tailnet = {
                address = "127.0.0.1:8443";
                http = {
                  inherit tls;
                  middlewares = [ "tailnet-marker@file" ];
                };
              };
            };

            certificatesResolvers.cloudflare.acme = {
              email = "thijs@vanwaaij.com";
              storage = "/var/lib/traefik/acme.json";
              dnsChallenge = {
                provider = "cloudflare";
                # Check propagation against public DNS, not the LAN's (as on Main).
                resolvers = [
                  "1.1.1.1:53"
                  "8.8.8.8:53"
                ];
              };
            }
            // lib.optionalAttrs cfg.acmeStaging {
              caServer = "https://acme-staging-v02.api.letsencrypt.org/directory";
            };
          };

          dynamicConfigOptions = {
            http = {
              routers = collect "routers";
              services = collect "services";
              middlewares = collect "middlewares" // {
                # An empty value removes the header.
                strip-marker.headers.customRequestHeaders.X-Homelab-Via = "";
                tailnet-marker.headers.customRequestHeaders.X-Homelab-Via = "tailnet";
              };
            };
            # TLS defaults as on Main (dynamic/tls.yml).
            tls.options.default = {
              minVersion = "VersionTLS12";
              cipherSuites = [
                "TLS_ECDHE_RSA_WITH_AES_128_GCM_SHA256"
                "TLS_ECDHE_RSA_WITH_AES_256_GCM_SHA384"
                "TLS_ECDHE_ECDSA_WITH_AES_128_GCM_SHA256"
                "TLS_ECDHE_ECDSA_WITH_AES_256_GCM_SHA384"
              ];
            };
          };
        };

        # Cloudflare token for DNS-01 (Zone:DNS:Edit on vanwaaij.com); lego reads `_FILE`.
        services.onepassword-secrets.secrets.cloudflareDnsToken = {
          reference = "op://Homelab/cloudflare-dns-token/credential";
          mode = "0400";
          owner = "traefik";
          services = [ "traefik" ];
        };
        systemd.services.traefik.environment.CF_DNS_API_TOKEN_FILE =
          config.services.onepassword-secrets.secretPaths.cloudflareDnsToken;

        networking.firewall.allowedTCPPorts = [
          80
          443
        ];

        # Only the real router lists the dashboard: a test router (servicePrefix set)
        # would declare the same link id.
        lodestar.links = lib.mkIf (cfg.servicePrefix == "") {
          traefik = {
            title = "Traefik";
            group = "Infrastructure";
            description = "Front-door router";
            icon = "traefikproxy";
            url = "https://traefik.vanwaaij.com/dashboard/";
          };
        };
      }

      (lib.mkIf cfg.echo.enable {
        # whoami listens on every address; only loopback may talk to it.
        systemd.services.whoami = {
          description = "whoami echo service for router tests";
          wantedBy = [ "multi-user.target" ];
          after = [ "network.target" ];
          serviceConfig = {
            ExecStart = "${lib.getExe pkgs.whoami} -port 8099";
            DynamicUser = true;
            IPAddressAllow = "localhost";
            IPAddressDeny = "any";
            Restart = "on-failure";
          };
        };

        homelab.router.extraRoutes.whoami-test = {
          host = "whoami-test.vanwaaij.com";
          backend = "http://127.0.0.1:8099";
          tailnet.address = cfg.echo.tailnetAddress;
        };
      })
    ]
  );
}
