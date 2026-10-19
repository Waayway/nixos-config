{
  config,
  lib,
  hostPlatform,
  ...
}:
# Immich v2 from the official images, translated from upstream's docker-compose.yml
# of release v2.7.5 (github.com/immich-app/immich/releases/download/v2.7.5/
# docker-compose.yml, the current v2 release; same as media's /opt/immich): server,
# machine-learning, valkey and Immich's PostgreSQL, the last two pinned to upstream's
# tag + digest. Compose's service names become container names on the `immich`
# network (DB_HOSTNAME / REDIS_HOSTNAME point at them). With `gpu`: QSV transcoding
# (hwaccel.transcoding.yml `quicksync`) and the `-openvino` machine-learning image
# (hwaccel.ml.yml `openvino`), both with /dev/dri, on the Intel Arc A380.
#
# Media at /store/immich-v2 (UPLOAD_LOCATION), Main's old library read-only at
# /mnt/old-library (an external library), database on local disk.
#
# Secrets: one env file, 1Password Homelab `immich-config` field `env`, with
# DB_PASSWORD (server, machine learning) and POSTGRES_PASSWORD (database), the same
# value (upstream's compose maps one onto the other).
let
  cfg = config.homelab.immich;
  lan = config.homelab.lan;
  secretPaths = config.services.onepassword-secrets.secretPaths;

  host = "immich.vanwaaij.com";
  port = 2283;
  state = "/var/lib/prod/immich";
  network = "immich";
  version = "v2";
  envFiles = [ secretPaths.immichEnv ];

  # Upstream's .env, minus the password.
  environment = {
    DB_HOSTNAME = "immich-postgres";
    DB_USERNAME = "postgres";
    DB_DATABASE_NAME = "immich";
    REDIS_HOSTNAME = "immich-redis";
  }
  // lib.optionalAttrs (config.time.timeZone != null) { TZ = config.time.timeZone; };
in
lib.optionalAttrs hostPlatform.isLinux {
  options.homelab.immich = {
    enable = lib.mkEnableOption "Immich (containers)";
    live = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = "Serve the public host; off, it shows the maintenance page.";
    };
    gpu = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = ''
        Use the passed-through Intel Arc A380: QSV transcoding and OpenVINO machine
        learning (`immich-machine-learning:v2-openvino`), both with /dev/dri.
      '';
    };
  };

  config = lib.mkIf cfg.enable {
    assertions = [
      {
        assertion = lan.address != null;
        message = "homelab.immich needs homelab.lan.address (the host file's netInterface.ip).";
      }
    ];

    homelab.containers = {
      enable = true;
      intelGpu = lib.mkIf cfg.gpu true;
      dumps.immich = {
        container = "immich-postgres";
        # Immich's documented backup command.
        command = "pg_dumpall --clean --if-exists --username=${environment.DB_USERNAME}";
      };
    };

    services.onepassword-secrets.secrets.immichEnv = {
      reference = "op://Homelab/immich-config/env";
      mode = "0400";
      owner = "root";
      services = [
        "docker-immich-server"
        "docker-immich-machine-learning"
        "docker-immich-postgres"
      ];
    };

    virtualisation.oci-containers.containers = {
      immich-server = {
        image = "ghcr.io/immich-app/immich-server:${version}";
        networks = [ network ];
        ports = [ "${lan.address}:${toString port}:${toString port}" ];
        volumes = [
          "/store/immich-v2:/data"
          "/etc/localtime:/etc/localtime:ro"
          "/store/immich/library:/mnt/old-library:ro"
        ];
        inherit environment;
        environmentFiles = envFiles;
        devices = lib.optional cfg.gpu "/dev/dri:/dev/dri";
        dependsOn = [
          "immich-redis"
          "immich-postgres"
        ];
      };

      immich-machine-learning = {
        image = "ghcr.io/immich-app/immich-machine-learning:${version}${lib.optionalString cfg.gpu "-openvino"}";
        networks = [ network ];
        volumes = [ "${state}/model-cache:/cache" ];
        inherit environment;
        environmentFiles = envFiles;
        devices = lib.optional cfg.gpu "/dev/dri:/dev/dri";
      };

      immich-redis = {
        image = "docker.io/valkey/valkey:9@sha256:3b55fbaa0cd93cf0d9d961f405e4dfcc70efe325e2d84da207a0a8e6d8fde4f9";
        networks = [ network ];
      };

      immich-postgres = {
        image = "ghcr.io/immich-app/postgres:14-vectorchord0.4.3-pgvectors0.2.0@sha256:bcf63357191b76a916ae5eb93464d65c07511da41e3bf7a8416db519b40b1c23";
        networks = [ network ];
        volumes = [ "${state}/db:/var/lib/postgresql/data" ];
        environment = {
          POSTGRES_USER = environment.DB_USERNAME;
          POSTGRES_DB = environment.DB_DATABASE_NAME;
          POSTGRES_INITDB_ARGS = "--data-checksums";
        };
        environmentFiles = envFiles;
        extraOptions = [ "--shm-size=128m" ];
      };
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
      check.url = "http://${lan.address}:${toString port}/api/server/ping";
    };
  };
}
