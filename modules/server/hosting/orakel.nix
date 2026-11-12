# Orakel Theater on the hosting node (docs/orakel-hosting.md; cut-over runbook BUILD-3):
# production as orakel's default instance (units orakel-backend/-frontend, user orakel,
# /var/lib/orakel, :8080/:3000, `orakel-ctl`, so the runbook's commands stay valid) and
# staging as `instances.staging` (orakel-staging-*, /var/lib/orakel-staging, :8081/:3001,
# `orakel-ctl-staging`), both behind hosting.traefik's public sites.
#
# `services.orakel` comes from the orakel flake's NixOS module, which only the host that
# runs orakel imports (hosts/servers/hestia.nix): the input is a private repository, and
# importing it everywhere would make every host's evaluation fetch it. So this module only
# sets `services.orakel` when that option exists, and asserts that it does when enabled.
#
# Secrets: opnix items in the vault Homelab (the contract with the vault, docs/orakel-hosting.md):
#   orakel-production  env (SECRET_KEY verbatim from the old server, SMTP_PASSWORD,
#                      TURNSTILE_SECRET, TURNSTILE_SITE_KEY; QR_SECRET only if the old server
#                      sets it), mollie-api-key (live key)
#   orakel-staging     env (its own SECRET_KEY, SMTP_PASSWORD, Turnstile keys for the staging
#                      host), mollie-api-key (a Mollie TEST key, test_…), htpasswd (basic auth)
# Root-owned 0400: systemd reads EnvironmentFile and LoadCredential as root, for the units and
# for orakel-ctl's transient units alike.
#
# The ledger-conversion acknowledgement is never set here: the one cut-over boot uses a
# runtime drop-in under /run/systemd/system (runbook Q1, P9/P10).
{
  config,
  lib,
  options,
  pkgs,
  hostPlatform,
  ...
}:
let
  cfg = config.hosting.orakel;
  secretPaths = config.services.onepassword-secrets.secretPaths;
  haveModule = options ? services && options.services ? orakel;

  # Non-secret legacy values (orakel compose.prod.yml:50-54).
  smtp = {
    SMTP_HOST = "h57.mijn.host";
    SMTP_PORT = "587";
    SMTP_USER = "noreply@hetorakeltheater.nl";
    SMTP_FROM_NAME = "Stichting Het Orakel Theater Producties";
    SMTP_FROM_EMAIL = "noreply@hetorakeltheater.nl";
  };

  secret = reference: unit: {
    inherit reference;
    owner = "root";
    mode = "0400";
    # Bare unit names: opnix adds `after`/`wants` on `systemd.services.<this>`.
    services = [ unit ];
  };

  prodSecrets = lib.optionalAttrs cfg.production.enable {
    orakelProductionEnv = secret "op://Homelab/orakel-production/env" "orakel-backend";
    orakelProductionMollie = secret "op://Homelab/orakel-production/mollie-api-key" "orakel-backend";
  };
  stagingSecrets = lib.optionalAttrs cfg.staging.enable {
    orakelStagingEnv = secret "op://Homelab/orakel-staging/env" "orakel-staging-backend";
    orakelStagingMollie = secret "op://Homelab/orakel-staging/mollie-api-key" "orakel-staging-backend";
  };
in
lib.optionalAttrs hostPlatform.isLinux {
  options.hosting.orakel = {
    enable = lib.mkEnableOption "Orakel Theater (production and staging) on this hosting node";

    domain = lib.mkOption {
      type = lib.types.str;
      default = "hetorakeltheater.nl";
      description = "Production's hostname; staging is `staging.<domain>`.";
    };

    production.enable = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = ''
        Run the production instance. Off until the runbook's T-1d step 6 if production must
        not exist before then; staging does not depend on it.
      '';
    };

    staging.enable = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Run the staging instance (runbook Q4: staging stays on this host).";
    };
  };

  config = lib.mkIf cfg.enable (
    lib.mkMerge [
      {
        assertions = [
          {
            assertion = haveModule;
            message = "hosting.orakel needs orakel's NixOS module: imports = [ inputs.orakel.nixosModules.default ] in the host file.";
          }
          {
            assertion = config.hosting.traefik.enable && config.hosting.traefik.public.enable;
            message = "hosting.orakel needs hosting.traefik.public (its public sites).";
          }
        ];

        # sqlite3 for the runbook's `.backup`, integrity checks and the id offset (P8, P11).
        environment.systemPackages = [ pkgs.sqlite ];

        services.onepassword-secrets.secrets = prodSecrets // stagingSecrets;

        hosting.traefik.public.sites = lib.mkMerge [
          (lib.mkIf cfg.production.enable {
            orakel = {
              host = cfg.domain;
              backend = "http://127.0.0.1:3000";
              # Straight to the backend, not through the Next rewrite (runbook F13).
              pathPrefixes."/api" = "http://127.0.0.1:8080";
              probePaths = [
                "/"
                "/api/health"
              ];
            };
          })
          (lib.mkIf cfg.staging.enable {
            orakel-staging = {
              host = "staging.${cfg.domain}";
              backend = "http://127.0.0.1:3001";
              pathPrefixes."/api" = "http://127.0.0.1:8081";
              basicAuth = {
                usersReference = "op://Homelab/orakel-staging/htpasswd";
                # As legacy staging (compose.staging.yml:53-71): the health check and Mollie's
                # webhook stay reachable.
                exemptPaths = [
                  "/api/health"
                  "/api/tickets/webhook"
                ];
                realm = "Orakel staging";
              };
              probePaths = [ "/api/health" ];
            };
          })
        ];
      }

      (lib.optionalAttrs haveModule {
        services.orakel = {
          enable = cfg.production.enable;
          appEnv = "production";
          publicAddress = "https://${cfg.domain}";
          environmentFile = secretPaths.orakelProductionEnv or null;
          mollie.apiKeyFile = secretPaths.orakelProductionMollie or null;
          # On only after the cut-over boot and the backlog pre-check (runbook §5.3).
          schedulerEnabled = false;
          environment = smtp // {
            LOG_LEVEL = "warn";
          };

          instances.staging = {
            enable = cfg.staging.enable;
            # Production mode with the Mollie test key (runbook F9).
            appEnv = "production";
            publicAddress = "https://staging.${cfg.domain}";
            backendPort = 8081;
            frontend.port = 3001;
            environmentFile = secretPaths.orakelStagingEnv or null;
            mollie.apiKeyFile = secretPaths.orakelStagingMollie or null;
            schedulerEnabled = false;
            environment = smtp // {
              LOG_LEVEL = "info";
            };
          };
        };
      })
    ]
  );
}
