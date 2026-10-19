{
  config,
  lib,
  hostPlatform,
  ...
}:
# Nextcloud 32 from the official image (nextcloud:32-apache) with MariaDB, Redis and
# Collabora Online (office.vanwaaij.com) for richdocuments, as containers on the
# `nextcloud` Docker network.
#
# Follows Main's ~/nextcloud/docker-compose.yml (itself the nextcloud/docker README's
# "Base version - apache" with MariaDB, Redis and a cron container), and Collabora's
# CODE Docker instructions (sdk.collaboraonline.com, "CODE Docker image") for the
# collabora container. Main's Traefik labels are the router's `nextcloud` route here.
#
# html, config and custom_apps are local (/var/lib/prod/nextcloud), the user data is
# the TrueNAS copy Main uses, /store/nextcloud/data (www-data, 33, as in the image).
#
# Secrets: one env file, 1Password Homelab `nextcloud-config` field `env`, with
# MYSQL_ROOT_PASSWORD, MYSQL_PASSWORD and REDIS_HOST_PASSWORD (and, for a first
# install only, NEXTCLOUD_ADMIN_USER / NEXTCLOUD_ADMIN_PASSWORD).
#
# Two Nextclouds on one data directory: until `live`, nothing here runs background
# jobs (no cron container), and the app only starts once config/config.php exists
# (copied from Main), so the image never installs a fresh instance onto the shared
# data directory.
let
  cfg = config.homelab.nextcloud;
  lan = config.homelab.lan;
  secretPaths = config.services.onepassword-secrets.secretPaths;

  host = "nextcloud.vanwaaij.com";
  officeHost = "office.vanwaaij.com";
  officePort = 9980;
  state = "/var/lib/prod/nextcloud";
  network = "nextcloud";
  image = "nextcloud:32-apache";

  # The app's and cron's mounts (Main's, with local paths under `state`).
  appVolumes = [
    "${state}/html:/var/www/html"
    "/store/nextcloud/data:/var/www/html/data"
    "${state}/config:/var/www/html/config"
    "${state}/custom_apps:/var/www/html/custom_apps"
  ];
  appEnvironment = {
    MYSQL_HOST = "nextcloud-db";
    MYSQL_DATABASE = "nextcloud";
    MYSQL_USER = "nextcloud";
    REDIS_HOST = "nextcloud-redis";
    NEXTCLOUD_TRUSTED_DOMAINS = lib.concatStringsSep " " (
      [ host ] ++ lib.optional (lan.address != null) lan.address
    );
    PHP_MEMORY_LIMIT = "1G";
    PHP_UPLOAD_LIMIT = "16G";
    APACHE_BODY_LIMIT = "0";
    # Behind the router (Traefik terminates TLS).
    TRUSTED_PROXIES = "10.0.10.110";
    OVERWRITEPROTOCOL = "https";
    OVERWRITEHOST = host;
  };
  envFiles = [ secretPaths.nextcloudEnv ];
in
lib.optionalAttrs hostPlatform.isLinux {
  options.homelab.nextcloud = {
    enable = lib.mkEnableOption "Nextcloud with MariaDB, Redis and Collabora Online (containers)";
    live = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = ''
        Serve the public hosts and run background jobs. Off: public hosts show the
        maintenance page and there is no nextcloud-cron container.
      '';
    };
  };

  config = lib.mkIf cfg.enable {
    assertions = [
      {
        assertion = lan.address != null;
        message = "homelab.nextcloud needs homelab.lan.address (the host file's netInterface.ip).";
      }
    ];

    homelab.containers.enable = true;

    services.onepassword-secrets.secrets.nextcloudEnv = {
      reference = "op://Homelab/nextcloud-config/env";
      mode = "0400";
      owner = "root";
      services = [
        "docker-nextcloud-app"
        "docker-nextcloud-db"
        "docker-nextcloud-redis"
      ]
      ++ lib.optional cfg.live "docker-nextcloud-cron";
    };

    virtualisation.oci-containers.containers = lib.mkMerge [
      {
        nextcloud-db = {
          image = "mariadb:11.4";
          networks = [ network ];
          # Main's tuning.
          cmd = [
            "--transaction-isolation=READ-COMMITTED"
            "--log-bin=binlog"
            "--binlog-format=ROW"
            "--innodb-buffer-pool-size=512M"
            "--innodb-log-file-size=128M"
            "--innodb-flush-log-at-trx-commit=2"
            "--innodb-flush-method=O_DIRECT"
            "--max-connections=200"
          ];
          volumes = [ "${state}/db:/var/lib/mysql" ];
          environment = {
            MYSQL_DATABASE = "nextcloud";
            MYSQL_USER = "nextcloud";
            # Upgrade the system tables after a MariaDB update (Main's 10.7 data).
            MARIADB_AUTO_UPGRADE = "1";
          };
          environmentFiles = envFiles;
        };

        # Password from the env file, so through a shell; the image's entrypoint
        # still drops to the redis user. Cache and locking only: no persistence.
        nextcloud-redis = {
          image = "redis:7-alpine";
          networks = [ network ];
          entrypoint = "sh";
          cmd = [
            "-c"
            ''exec docker-entrypoint.sh redis-server --requirepass "$REDIS_HOST_PASSWORD" --maxmemory 256mb --maxmemory-policy allkeys-lru --save ""''
          ];
          environmentFiles = envFiles;
        };

        nextcloud-app = {
          inherit image;
          networks = [ network ];
          ports = [ "${lan.address}:80:80" ];
          volumes = appVolumes;
          environment = appEnvironment;
          environmentFiles = envFiles;
          dependsOn = [
            "nextcloud-db"
            "nextcloud-redis"
          ];
        };

        # Collabora Online behind the router: Traefik terminates TLS, coolwsd speaks
        # plain HTTP and builds its URLs for https://office.vanwaaij.com.
        collabora = {
          image = "collabora/code:26.04.5.1.1";
          networks = [ network ];
          ports = [ "${lan.address}:${toString officePort}:${toString officePort}" ];
          environment = {
            aliasgroup1 = "https://${host}";
            server_name = officeHost;
            extra_params = "--o:ssl.enable=false --o:ssl.termination=true";
            DONT_GEN_SSL_CERT = "true";
            dictionaries = "en_GB en_US nl";
          };
        };
      }

      (lib.mkIf cfg.live {
        nextcloud-cron = {
          inherit image;
          networks = [ network ];
          entrypoint = "/cron.sh";
          volumes = appVolumes;
          environment = appEnvironment;
          environmentFiles = envFiles;
          dependsOn = [ "nextcloud-app" ];
        };
      })
    ];

    systemd.services.docker-nextcloud-app.unitConfig.ConditionPathExists = "${state}/config/config.php";

    systemd.tmpfiles.settings.nextcloud =
      lib.genAttrs
        [
          "${state}/html"
          "${state}/config"
          "${state}/custom_apps"
        ]
        (_: {
          d = {
            mode = "0750";
            user = "33";
            group = "33";
          };
        });

    homelab.containers.dumps.nextcloud = {
      container = "nextcloud-db";
      command = ''MYSQL_PWD="$MYSQL_ROOT_PASSWORD" mariadb-dump -u root --single-transaction --routines --triggers nextcloud'';
    };

    networking.firewall.interfaces.${lan.interface}.allowedTCPPorts = [
      80
      officePort
    ];

    homelab.routes = {
      nextcloud = {
        inherit host;
        backend = "http://${lan.address}:80";
        maintenance = !cfg.live;
        # Main's `nextcloud-chain`: CalDAV/CardDAV redirect, then security headers.
        middlewares = {
          caldav.redirectRegex = {
            permanent = true;
            regex = "^https://(.*)/.well-known/ca(l|rd)dav";
            replacement = "https://$1/remote.php/dav/";
          };
          headers.headers = {
            stsSeconds = 31536000;
            stsIncludeSubdomains = true;
            stsPreload = true;
            forceSTSHeader = true;
            customFrameOptionsValue = "SAMEORIGIN";
            contentTypeNosniff = true;
            browserXssFilter = true;
            referrerPolicy = "same-origin";
          };
        };
      };
      office = {
        host = officeHost;
        backend = "http://${lan.address}:${toString officePort}";
        maintenance = !cfg.live;
      };
    };

    lodestar.links.nextcloud = {
      title = "Nextcloud";
      group = "Apps";
      description = "Files, contacts and documents";
      icon = "nextcloud";
      url = "https://${host}";
      check.url = "http://${lan.address}/status.php";
    };
  };
}
