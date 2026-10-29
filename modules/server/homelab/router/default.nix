# The front-door router (`homelab.router`): Traefik for every route in the flake.
#
# Routes are every configuration's `homelab.routes` (collected with
# `tools.routesFrom`) plus `homelab.router.extraRoutes` (backends this flake doesn't
# manage, modules/server/homelab/routes.nix); the merged set is `homelab.router.routes`.
# Each route gets a router on the `public` entrypoint (:443, from the internet) when
# `public`, and one on the `tailnet` entrypoint (127.0.0.1:8443, behind the Tailscale
# Service) when `tailnet.enable`. The `tailnet` entrypoint sets `X-Homelab-Via:
# tailnet`; the `public` one removes any such header a client sent. One Let's Encrypt
# wildcard for vanwaaij.com via Cloudflare DNS-01 covers both.
#
# A route with `passthrough` gets TCP routers instead (`HostSNI`, TLS passed through
# unopened, on both entrypoints; the Tailscale Service forwards TCP, so SNI arrives
# intact). A route with `auth.gate` gets the sign-in gate (gate.nix): a forwardAuth
# on oauth2-proxy's proxy endpoint, which answers 202 for a signed-in member of
# `<route>-users`, 403 for anyone else signed in, and redirects to the sign-in
# itself (302) when there's no session. No errors middleware, so a 401 from the
# backend reaches the client untouched (no sign-in loop). The route must have an
# access entry with `gate = true` on the identity host (`identityHost`), or
# evaluation fails, and can't also have basic auth. The gate (and its route, named
# after the gate host) is on when any route is gated (`gate.enable`). NixOS only.
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
  flakeHosts = lib.mapAttrsToList (_: r: r.host) fromFlake;
  hostClashes = lib.attrNames (lib.filterAttrs (_: r: lib.elem r.host flakeHosts) extra);

  # The configuration running Kanidm: this one's own evaluation when it is the
  # identity host (router-test), else the flake's.
  idConfig =
    if cfg.identityHost == config.networking.hostName then
      config
    else
      inputs.self.nixosConfigurations.${cfg.identityHost}.config;
  identity = {
    inherit (idConfig.homelab.identity)
      enable
      domain
      gateHost
      acmeStaging
      access
      ;
    address = idConfig.homelab.lan.address;
  };

  # The gate's own route (oauth2-proxy's pages), named after the gate host's first
  # label, while the gate is on. Kept out of `extraRoutes`, whose routes decide
  # whether it is.
  ownRoutes = fromFlake // extra;
  gateRoute = lib.optionalAttrs cfg.gate.enable {
    ${lib.head (lib.splitString "." identity.gateHost)} = cfg.gate.route // {
      declaredBy = config.networking.hostName;
    };
  };

  # Routes that can't be expressed: wrong backend/passthrough combinations.
  malformed = lib.filterAttrs (
    _: r:
    (r.backend == null) == (r.passthrough == null)
    || (
      r.passthrough != null
      && (
        r.maintenance
        || r.basicAuth.usersFile != null
        || r.middlewares != { }
        || r.auth.gate
        || r.insecureBackend
        || r.backendServerName != null
      )
    )
    || (r.backendServerName != null && !(lib.hasPrefix "https://" (toString r.backend)))
    || (r.auth.gate && r.basicAuth.usersFile != null)
  ) cfg.routes;

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
    name: r: if r.passthrough != null then passthroughConfig name r else httpConfig name r;

  passthroughConfig =
    name: r:
    let
      router = entryPoint: {
        rule = "HostSNI(`${r.host}`)";
        entryPoints = [ entryPoint ];
        service = name;
        tls.passthrough = true;
      };
    in
    {
      tcpRouters =
        lib.optionalAttrs r.public { "${name}-public" = router "public"; }
        // lib.optionalAttrs r.tailnet.enable { "${name}-tailnet" = router "tailnet"; };
      tcpServices.${name}.loadBalancer.servers = [ { address = r.passthrough; } ];
    };

  # The gate's middleware for a route; fails unless the identity host lets the
  # route's app through the gate.
  gateMiddlewares =
    name:
    let
      a = identity.access.${name} or null;
    in
    assert lib.assertMsg (a != null && a.gate)
      "homelab.router: route '${name}' has auth.gate but ${cfg.identityHost}'s homelab.identity.access has no app '${name}' with gate = true";
    {
      # The proxy endpoint, not /oauth2/auth: it starts the sign-in itself (the
      # original URL from X-Forwarded-*, `--reverse-proxy`), and forwardAuth hands
      # any non-2xx answer, the 302 included, to the client.
      "${name}-gate".forwardAuth = {
        address = "http://127.0.0.1:4180/?allowed_groups=${name}-users@${identity.domain}";
        authResponseHeaders = [
          "X-Auth-Request-User"
          "X-Auth-Request-Email"
        ];
        # Also removes every X-Auth-Request-* header the client sent.
        authResponseHeadersRegex = "^X-Auth-Request-";
      };
    };

  httpConfig =
    name: r:
    let
      own = lib.mapAttrs' (k: v: lib.nameValuePair "${name}-${k}" v) r.middlewares;
      auth = lib.optionalAttrs (r.basicAuth.usersFile != null) {
        "${name}-auth".basicAuth.usersFile = r.basicAuth.usersFile;
      };
      gate = lib.optionalAttrs r.auth.gate (gateMiddlewares name);
      router = entryPoint: {
        rule = "Host(`${r.host}`)";
        entryPoints = [ entryPoint ];
        service = if r.backend == "api@internal" then "api@internal" else name;
        middlewares = lib.optional r.auth.gate "${name}-gate" ++ lib.attrNames auth ++ lib.attrNames own;
      };
      # While in maintenance the public side shows the local page, with no
      # route middlewares (basic auth would prompt before the page).
      publicRouter =
        if r.maintenance then
          (router "public")
          // {
            service = "maintenance";
            middlewares = [ ];
          }
        else
          router "public";
    in
    {
      routers =
        lib.optionalAttrs r.public { "${name}-public" = publicRouter; }
        // lib.optionalAttrs r.tailnet.enable { "${name}-tailnet" = router "tailnet"; };
      services = lib.optionalAttrs (r.backend != "api@internal") {
        ${name}.loadBalancer = {
          servers = [ { url = r.backend; } ];
        }
        // lib.optionalAttrs (r.backendServerName != null) { serversTransport = "${name}-backend"; }
        // lib.optionalAttrs (r.insecureBackend && r.backendServerName == null) {
          serversTransport = "insecure-backend";
        };
      };
      # A backend by address whose certificate names `backendServerName`.
      serversTransports = lib.optionalAttrs (r.backendServerName != null) {
        "${name}-backend" = {
          serverName = r.backendServerName;
        }
        // lib.optionalAttrs r.insecureBackend { insecureSkipVerify = true; };
      };
      middlewares = gate // auth // own;
    };

  maintenancePage = pkgs.writeTextDir "maintenance.html" ''
    <!doctype html>
    <html lang="en">
    <head>
    <meta charset="utf-8">
    <meta name="viewport" content="width=device-width, initial-scale=1">
    <title>We're working on it</title>
    <style>
    :root { color-scheme: light dark; --bg: #f7f7f5; --fg: #1d1d1b; --muted: #6b6b66; }
    @media (prefers-color-scheme: dark) { :root { --bg: #161616; --fg: #ececea; --muted: #8f8f8a; } }
    body { margin: 0; min-height: 100vh; display: flex; flex-direction: column; align-items: center;
      justify-content: center; background: var(--bg); color: var(--fg);
      font: 18px/1.5 system-ui, -apple-system, sans-serif; text-align: center; padding: 0 16px; box-sizing: border-box; }
    h1 { font-size: 1.6rem; font-weight: 600; margin: 0 0 .5rem; }
    p { margin: 0; color: var(--muted); }
    footer { position: fixed; bottom: 1.5rem; font-size: .85rem; color: var(--muted); }
    </style>
    </head>
    <body>
    <main><h1>We're working on it &mdash; back soon.</h1><p>This page is temporarily unavailable.</p></main>
    <footer>vanwaaij.com</footer>
    </body>
    </html>
  '';

  perRoute = lib.mapAttrsToList routeConfig cfg.routes;
  collect = key: lib.foldl' (a: b: a // (b.${key} or { })) { } perRoute;
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

    tailnetDomain = lib.mkOption {
      type = lib.types.str;
      default = "tail41ca60.ts.net";
      description = "The tailnet's MagicDNS domain; a Tailscale Service answers on `<servicePrefix><route>.<tailnetDomain>`.";
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
    };

    identityHost = lib.mkOption {
      type = lib.types.str;
      default = "identity";
      example = "router-test";
      description = ''
        The configuration running Kanidm (`homelab.identity`). Its domain, gate host,
        address and access give the identity route, the sign-in gate and each gated
        route's group check.
      '';
    };

    gate = {
      enable = lib.mkOption {
        type = lib.types.bool;
        default = lib.any (r: r.auth.gate) (lib.attrValues ownRoutes);
        defaultText = lib.literalMD "whether any route has `auth.gate`";
        description = ''
          The sign-in gate: oauth2-proxy (with Docker and its two secrets, gate.nix)
          and its route. On by itself once a route is gated; a test router turns it
          on to try it.
        '';
      };
      route = lib.mkOption {
        type = routeType;
        internal = true;
        default = {
          host = identity.gateHost;
          backend = "http://127.0.0.1:4180";
        };
        description = "The gate's own route (sign-in, callback), added to `routes` while the gate is on.";
      };
    };

    identity = lib.mkOption {
      type = lib.types.attrsOf lib.types.raw;
      readOnly = true;
      internal = true;
      default = identity;
      description = "`identityHost`'s `homelab.identity` values and LAN address.";
    };

    routes = lib.mkOption {
      type = lib.types.attrsOf lib.types.anything;
      readOnly = true;
      default = ownRoutes // gateRoute;
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
          {
            assertion = hostClashes == [ ];
            message = "homelab.router.extraRoutes: routes whose host a homelab.routes route already serves: ${toString hostClashes}";
          }
          {
            assertion = malformed == { };
            message = "homelab.router: routes need exactly one of backend and passthrough, a passthrough route takes no maintenance, basicAuth, middlewares, auth.gate, insecureBackend or backendServerName, backendServerName needs an https:// backend, and auth.gate excludes basicAuth: ${toString (lib.attrNames malformed)}";
          }
          {
            assertion = identity.enable;
            message = "homelab.router.identityHost: configuration '${cfg.identityHost}' doesn't enable homelab.identity.";
          }
        ];

        homelab.monitoring.targets.traefik.port = 8082;

        services.traefik = {
          enable = true;

          staticConfigOptions = {
            api.dashboard = true;

            # Request and entrypoint metrics for the Grafana Traefik dashboard (grafana.com 17346).
            metrics.prometheus.entryPoint = "metrics";

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
              # Scraped by the monitor only (the agent's firewall rule); not routed.
              metrics.address = ":8082";
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
              services = collect "services" // {
                maintenance.loadBalancer.servers = [ { url = "http://127.0.0.1:8097"; } ];
              };
              middlewares = collect "middlewares" // {
                # An empty value removes the header.
                strip-marker.headers.customRequestHeaders.X-Homelab-Via = "";
                tailnet-marker.headers.customRequestHeaders.X-Homelab-Via = "tailnet";
              };
              serversTransports = collect "serversTransports" // {
                # For backends with `insecureBackend` (self-signed appliances).
                insecure-backend.insecureSkipVerify = true;
              };
            };
            # Only with a passthrough route: Traefik rejects the whole file for an
            # empty `[tcp.routers]` table.
            tcp = lib.mkIf (collect "tcpRouters" != { }) {
              routers = collect "tcpRouters";
              services = collect "tcpServices";
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

        # The maintenance page: every path answers 503, on loopback only.
        services.nginx = {
          enable = true;
          virtualHosts.maintenance = {
            default = true;
            listen = [
              {
                addr = "127.0.0.1";
                port = 8097;
              }
            ];
            root = "${maintenancePage}";
            extraConfig = ''
              add_header Retry-After 3600 always;
              error_page 503 /maintenance.html;
            '';
            locations."/".return = "503";
            locations."= /maintenance.html".extraConfig = "internal;";
          };
        };

        # nginx's service creates /var/log/nginx (LogsDirectory, nginx:nginx 0750).
        # The config check su's to nginx to stat the logs: run before that, on the
        # first switch, it hits the directory still owned by root and fails.
        systemd.services.logrotate-checkconf.after = [ "nginx.service" ];

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
        };
      })
    ]
  );
}
