{
  config,
  lib,
  hostPlatform,
  ...
}:
# WhenTo (github.com/When-To/whento, scheduling of recurring events: participants mark
# their availability through shared links, events sync out as iCalendar feeds) from
# the official image, translated from upstream's docker-compose.yml of v2.0.0: app,
# PostgreSQL 16 and Redis 7 on the `whento` network. The app follows the minor track
# `2.0` (homelab.containers.floating); PostgreSQL and Redis are pinned by digest
# (a PostgreSQL major needs a dump and restore, upstream's
# docs/upgrade-postgres-redis.md). The app builds DATABASE_URL and REDIS_URL from the
# DB_* / REDIS_* variables.
#
# State on local disk (/var/lib/prod/whento): the database, and the JWT key pair the
# entrypoint generates on first start (losing it only signs everyone out). The
# database is dumped nightly to /store/db-dumps/whento. Redis holds only rate-limit
# buckets and caches: no volume.
#
# Sign-in is WhenTo's own (password, passkey, TOTP; it has no OIDC), so no Kanidm
# app. The first administrator is created at /bootstrap with the one-time key the
# app prints at start (`sudo docker logs whento 2>&1 | grep -i bootstrap`);
# registration is closed, more accounts come from the admin. No SMTP yet: email
# verification is off, magic links and reminder mails don't go out.
#
# Secrets: one env file, 1Password Homelab `whento-config` field `env`, with
# DB_PASSWORD (app) and POSTGRES_PASSWORD (database), the same value, and
# REDIS_PASSWORD (app, Redis) and REDISCLI_AUTH (Redis' healthcheck), the same value.
let
  cfg = config.homelab.whento;
  lan = config.homelab.lan;
  secretPaths = config.services.onepassword-secrets.secretPaths;

  host = "whento.vanwaaij.com";
  port = 8085;
  state = "/var/lib/prod/whento";
  network = "whento";
  envFiles = [ secretPaths.whentoEnv ];
  # The floating track (the weekly update and renovate.json follow this literal).
  image = "ghcr.io/when-to/whento:2.0";
  db = {
    name = "whento";
    user = "whento";
  };
in
lib.optionalAttrs hostPlatform.isLinux {
  options.homelab.whento = {
    enable = lib.mkEnableOption "WhenTo (containers)";
    live = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = "Serve the public host; off, it shows the maintenance page.";
    };
  };

  config = lib.mkIf cfg.enable {
    assertions = [
      {
        assertion = lan.address != null;
        message = "homelab.whento needs homelab.lan.address (the host file's netInterface.ip).";
      }
    ];

    homelab.containers = {
      enable = true;
      floating = [ image ];
      dumps.whento = {
        container = "whento-postgres";
        command = "pg_dump --clean --if-exists --username=${db.user} ${db.name}";
      };
    };

    services.onepassword-secrets.secrets.whentoEnv = {
      reference = "op://Homelab/whento-config/env";
      mode = "0400";
      owner = "root";
      services = [
        "docker-whento"
        "docker-whento-postgres"
        "docker-whento-redis"
      ];
    };

    virtualisation.oci-containers.containers = {
      whento = {
        inherit image;
        networks = [ network ];
        # The app listens on 8080 in the container (Nextcloud has 8080 on the host).
        ports = [ "${lan.address}:${toString port}:8080" ];
        volumes = [ "${state}/keys:/app/keys" ];
        environment = {
          APP_ENV = "production";
          APP_URL = "https://${host}";
          PORT = "8080";
          DB_HOST = "whento-postgres";
          DB_NAME = db.name;
          DB_USER = db.user;
          REDIS_HOST = "whento-redis";
          JWT_PRIVATE_KEY_PATH = "/app/keys/private.pem";
          JWT_PUBLIC_KEY_PATH = "/app/keys/public.pem";
          CORS_ORIGINS = "https://${host}";
          # The router: the only peer whose X-Forwarded-For counts (per-client rate limits).
          TRUSTED_PROXIES = "10.0.10.110";
          ALLOWED_REGISTER = "false";
          EMAIL_VERIFICATION_ENABLED = "false";
        }
        // lib.optionalAttrs (config.time.timeZone != null) { TZ = config.time.timeZone; };
        environmentFiles = envFiles;
        dependsOn = [
          "whento-postgres"
          "whento-redis"
        ];
        extraOptions = [
          "--security-opt=no-new-privileges:true"
          "--cap-drop=ALL"
        ];
      };

      whento-postgres = {
        image = "postgres:16-alpine@sha256:0cefaabd882e42bcb2a2f3dc56d3ce4770560ba62fd7f197f1a2e008fd5731ab";
        networks = [ network ];
        volumes = [ "${state}/db:/var/lib/postgresql/data" ];
        environment = {
          POSTGRES_DB = db.name;
          POSTGRES_USER = db.user;
        };
        environmentFiles = envFiles;
        extraOptions = [ "--shm-size=128m" ];
      };

      # Upstream's command: the password goes into a config file, not the command line.
      whento-redis = {
        image = "redis:7-alpine@sha256:858f009f9709ce576febc734aa78b8f6d624b82571f9ddb6bda4377c833b3499";
        networks = [ network ];
        user = "redis";
        entrypoint = "sh";
        cmd = [
          "-c"
          ''
            umask 077
            printf 'requirepass "%s"\nmaxmemory 256mb\nmaxmemory-policy allkeys-lru\n' "$REDIS_PASSWORD" > /tmp/redis.conf
            exec redis-server /tmp/redis.conf
          ''
        ];
        environmentFiles = envFiles;
      };
    };

    # The image runs as whento (1000) and writes the key pair here on first start.
    systemd.tmpfiles.settings.whento."${state}/keys".d = {
      mode = "0700";
      user = "1000";
      group = "1000";
    };

    networking.firewall.interfaces.${lan.interface}.allowedTCPPorts = [ port ];

    homelab.routes.whento = {
      inherit host;
      backend = "http://${lan.address}:${toString port}";
      maintenance = !cfg.live;
    };

    lodestar.links.whento = {
      title = "WhenTo";
      group = "Apps";
      description = "Scheduling recurring events";
      url = "https://${host}";
      check.url = "http://${lan.address}:${toString port}/api/health";
    };
  };
}
