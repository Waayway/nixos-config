# The app-hosting node's front door (docs/plans/2026-11-10-lodestar-hosting-platform-design.md).
# A sibling of homelab/router, not a generalisation of it: its own Traefik, tailnet only for
# now. Each route is published as a Tailscale Service (`svc:<servicePrefix><name>`) that
# Tailscale terminates TLS for and reverse-proxies to Traefik's loopback entrypoint (TLS with
# Traefik's default self-signed cert, hence https+insecure), which routes by Host header. Traefik also watches /var/lib/traefik/dynamic, so a branch deployment can add
# or drop a route by writing or deleting a file there, without a rebuild. NixOS only.
#
# `public.enable` (off by default) adds the internet-facing side for apps served from this
# host's own public IP (design D7: HTTP-01 certificates from Let's Encrypt on this Traefik,
# not the homelab router's DNS-01 wildcard):
#   - entrypoints `web` (:80, redirects to https; the ACME HTTP-01 challenge is answered
#     first by Traefik's internal router) and `websecure` (:443, TLS from the `letsencrypt`
#     resolver); tcp 80 and 443 open in the firewall, nothing else;
#   - per `public.sites.<name>`: a `Host(...)` router to `backend`, one
#     `Host(...) && PathPrefix(...)` router per `pathPrefixes` entry (so `/api` goes straight
#     to an app's backend), and optional basic auth (an htpasswd file from 1Password via
#     opnix, never in the store) with `exemptPaths` routed around it;
#   - those routers live in `01-public-routes.toml` in the watched directory, next to the
#     tailnet ones, which stay as they are.
{
  config,
  lib,
  pkgs,
  hostPlatform,
  ...
}:
let
  cfg = config.hosting.traefik;
  pub = cfg.public;
  dynamicDir = "${config.services.traefik.dataDir}/dynamic";
  entryPoint = "127.0.0.1:8443";
  format = pkgs.formats.toml { };
  secretPaths = config.services.onepassword-secrets.secretPaths;

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

  resolver = "letsencrypt";
  letsEncryptStaging = "https://acme-staging-v02.api.letsencrypt.org/directory";

  # `/api/tickets/webhook` -> `api-tickets-webhook` (router and service names).
  slug =
    p:
    let
      s = lib.concatStringsSep "-" (
        lib.filter (x: x != "") (lib.splitString "-" (lib.replaceStrings [ "/" "." "_" ] [ "-" "-" "-" ] p))
      );
    in
    if s == "" then "root" else s;

  # opnix wants camelCase secret names: orakel-staging -> hostingTraefikAuthOrakelStaging.
  camel =
    s:
    lib.concatMapStrings (w: lib.toUpper (builtins.substring 0 1 w) + builtins.substring 1 (-1) w) (
      lib.splitString "-" s
    );
  authSecret = name: "hostingTraefikAuth${camel name}";
  hasAuth = site: site.basicAuth.usersReference != null;
  authSites = lib.filterAttrs (_: hasAuth) pub.sites;

  prefixService = name: pre: "${name}-${slug pre}";

  # An exempt path goes to the backend of the longest `pathPrefixes` entry it falls under,
  # else to the site's own backend.
  serviceFor =
    name: site: path:
    let
      matching = lib.filter (pre: lib.hasPrefix pre path) (lib.attrNames site.pathPrefixes);
      longest = lib.foldl' (
        a: b: if lib.stringLength b > lib.stringLength a then b else a
      ) (lib.head matching) matching;
    in
    if matching == [ ] then name else prefixService name longest;

  # Priorities as in the legacy compose stack: exemptions (100) over prefixes (75) over the
  # site's catch-all (50), whatever the rule lengths. TLS comes from the entrypoint.
  siteRouters =
    name: site:
    let
      hostRule = "Host(`${site.host}`)";
      base = {
        entryPoints = [ "websecure" ];
      }
      // lib.optionalAttrs (hasAuth site) { middlewares = [ "${name}-auth" ]; };
    in
    {
      ${name} = base // {
        rule = hostRule;
        service = name;
        priority = 50;
      };
    }
    // lib.mapAttrs' (
      pre: _:
      lib.nameValuePair (prefixService name pre) (
        base
        // {
          rule = "${hostRule} && PathPrefix(`${pre}`)";
          service = prefixService name pre;
          priority = 75;
        }
      )
    ) site.pathPrefixes
    // lib.optionalAttrs (hasAuth site) (
      lib.listToAttrs (
        map (
          path:
          lib.nameValuePair "${name}-open-${slug path}" {
            entryPoints = [ "websecure" ];
            rule = "${hostRule} && Path(`${path}`)";
            service = serviceFor name site path;
            priority = 100;
          }
        ) site.basicAuth.exemptPaths
      )
    );

  siteServices =
    name: site:
    {
      ${name}.loadBalancer.servers = [ { url = site.backend; } ];
    }
    // lib.mapAttrs' (
      pre: backend:
      lib.nameValuePair (prefixService name pre) { loadBalancer.servers = [ { url = backend; } ]; }
    ) site.pathPrefixes;

  publicRoutes = format.generate "01-public-routes.toml" {
    http = {
      routers = lib.concatMapAttrs siteRouters pub.sites;
      services = lib.concatMapAttrs siteServices pub.sites;
    }
    // lib.optionalAttrs (authSites != { }) {
      middlewares = lib.mapAttrs' (
        name: site:
        lib.nameValuePair "${name}-auth" {
          basicAuth = {
            usersFile = secretPaths.${authSecret name};
            realm = site.basicAuth.realm;
            # The app never sees the credentials.
            removeHeader = true;
          };
        }
      ) authSites;
    };
  };

  siteType = lib.types.submodule (
    { name, ... }:
    {
      options = {
        host = lib.mkOption {
          type = lib.types.str;
          example = "hetorakeltheater.nl";
          description = "The public hostname (`Host(...)`); its certificate comes from Let's Encrypt (HTTP-01).";
        };
        backend = lib.mkOption {
          type = lib.types.str;
          example = "http://127.0.0.1:3000";
          description = "Where requests that match no `pathPrefixes` entry go.";
        };
        pathPrefixes = lib.mkOption {
          type = lib.types.attrsOf lib.types.str;
          default = { };
          example = {
            "/api" = "http://127.0.0.1:8080";
          };
          description = "`PathPrefix(...)` -> backend, ahead of `backend`. The prefix is passed on, not stripped.";
        };
        basicAuth = {
          usersReference = lib.mkOption {
            type = lib.types.nullOr lib.types.str;
            default = null;
            example = "op://Homelab/${name}/htpasswd";
            description = ''
              1Password reference (opnix) of an htpasswd file (`user:$apr1$…` or bcrypt lines)
              that guards the whole site. Fetched to a root-only path owned by traefik, never
              in the store. null: no basic auth.
            '';
          };
          exemptPaths = lib.mkOption {
            type = lib.types.listOf lib.types.str;
            default = [ ];
            example = [ "/api/tickets/webhook" ];
            description = "Exact paths (`Path(...)`) reachable without the basic auth, e.g. a payment provider's webhook.";
          };
          realm = lib.mkOption {
            type = lib.types.str;
            default = name;
            description = "The basic-auth realm the browser shows.";
          };
        };
        probePaths = lib.mkOption {
          type = lib.types.listOf lib.types.str;
          default = [ "/" ];
          description = ''
            Paths the monitor's blackbox exporter probes as `https://<host><path>` (any 2xx
            after redirects is up; the certificate's expiry is watched too). Behind basic
            auth, list an exempt path. `[ ]`: not probed. Collected flake-wide with
            `tools.publicSitesFrom` (modules/server/monitoring/exporters.nix).
          '';
        };
      };
    }
  );
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

    public = {
      enable = lib.mkEnableOption "public `web` (80) and `websecure` (443) entrypoints with Let's Encrypt (HTTP-01) certificates, for `public.sites`";

      acme = {
        email = lib.mkOption {
          type = lib.types.str;
          example = "hostmaster@example.org";
          description = "Contact address for the Let's Encrypt account (expiry warnings).";
        };
        storage = lib.mkOption {
          type = lib.types.str;
          default = "${config.services.traefik.dataDir}/acme.json";
          defaultText = lib.literalExpression ''"''${config.services.traefik.dataDir}/acme.json"'';
          description = "Where Traefik keeps the ACME account and certificates (state, not the store).";
        };
        staging = lib.mkOption {
          type = lib.types.bool;
          default = false;
          description = ''
            Use Let's Encrypt's staging CA (untrusted certificates, generous rate limits) for a
            rehearsal. Switching back: delete `acme.storage`, or Traefik keeps serving the
            staging certificates until they are due for renewal.
          '';
        };
      };

      sites = lib.mkOption {
        type = lib.types.attrsOf siteType;
        default = { };
        description = "Public sites by name (the name prefixes the Traefik routers and services).";
      };
    };
  };

  config = lib.mkIf cfg.enable (
    lib.mkMerge [
      {
        services.traefik = {
          enable = true;
          # A full static file: the module's own one always sets `providers.file.filename`, which
          # cannot be combined with the watched `directory`.
          staticConfigFile = format.generate "traefik.toml" (
            {
              global = {
                checkNewVersion = false;
                sendAnonymousUsage = false;
              };
              log.level = "INFO";
              # Loopback only: reached through the Tailscale Services (tcp:443 -> here). TLS on
              # every router of this entrypoint (also the agent-written ones), with Traefik's
              # default self-signed certificate: only Tailscale's proxy sees it.
              entryPoints = {
                tailnet = {
                  address = entryPoint;
                  http.tls = { };
                };
              }
              // lib.optionalAttrs pub.enable {
                # Forwarded headers from the internet are not trusted (Traefik's default): it
                # sets X-Forwarded-For/X-Real-Ip from the client's address itself, which the
                # apps' rate limiters key on.
                web = {
                  address = ":80";
                  http.redirections.entryPoint = {
                    to = "websecure";
                    scheme = "https";
                    permanent = true;
                  };
                };
                websecure = {
                  address = ":443";
                  http.tls.certResolver = resolver;
                };
              };
              providers.file = {
                directory = dynamicDir;
                watch = true;
              };
            }
            // lib.optionalAttrs pub.enable {
              certificatesResolvers.${resolver}.acme = {
                inherit (pub.acme) email storage;
                httpChallenge.entryPoint = "web";
              }
              // lib.optionalAttrs pub.acme.staging { caServer = letsEncryptStaging; };
            }
          );
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
              # The target's scheme sets both sides (cmd/tailscale/cli/serve_v2.go): http://
              # serves plain HTTP on :443; https+insecure:// terminates TLS with the Service's
              # certificate and proxies to Traefik's self-signed TLS. tls-terminated-tcp:// would
              # hand Traefik plain TCP, but 1.104.6's set-config rejects it for a host:port
              # ("supported schemes: [tcp unix]"), and Traefik can't listen on a unix socket.
              endpoints."tcp:443" = "https+insecure://${entryPoint}";
            }
          ) cfg.routes;
        };

        # tailscale-serve ordering: modules/server/networking/tailscale-serve.nix.
      }

      (lib.mkIf pub.enable {
        assertions = [
          {
            assertion = lib.all (s: s.basicAuth.exemptPaths == [ ] || hasAuth s) (lib.attrValues pub.sites);
            message = "hosting.traefik.public.sites: exemptPaths without basicAuth.usersReference mean nothing.";
          }
        ];

        networking.firewall.allowedTCPPorts = [
          80
          443
        ];

        systemd.tmpfiles.rules = [
          "L+ '${dynamicDir}/01-public-routes.toml' - - - - ${publicRoutes}"
        ];

        # htpasswd files for the basic auth: read by Traefik itself (usersFile).
        services.onepassword-secrets.secrets = lib.mapAttrs' (
          name: site:
          lib.nameValuePair (authSecret name) {
            reference = site.basicAuth.usersReference;
            owner = "traefik";
            mode = "0400";
            services = [ "traefik" ];
          }
        ) authSites;
      })
    ]
  );
}
