{
  config,
  lib,
  pkgs,
  hostPlatform,
  ...
}:
# Nextcloud 32 on its own nginx (port 80) with MariaDB and Redis, plus Collabora
# Online (office.vanwaaij.com) for richdocuments. Config and apps stay on local disk
# (/var/lib/nextcloud); the user data is the TrueNAS copy Main used, at
# /store/nextcloud/data, owned by uid/gid 33 (Main's www-data).
#
# `live = false`: the public routes show the maintenance page, the tailnet ones go
# here, and nothing runs that would touch the shared data on its own (cron timer
# off; the app store is off for good, apps come from nixpkgs).
let
  cfg = config.homelab.nextcloud;
  lan = config.homelab.lan;
  secretPaths = config.services.onepassword-secrets.secretPaths;

  host = "nextcloud.vanwaaij.com";
  officeHost = "office.vanwaaij.com";
  dataDir = "/store/nextcloud/data";
  dumpDir = "/store/db-dumps/nextcloud";
  officePort = 9980;

  # Units that read the data directory or the secrets.
  units = [
    "nextcloud-setup"
    "nextcloud-update-db"
    "nextcloud-cron"
    "phpfpm-nextcloud"
  ];
in
lib.optionalAttrs hostPlatform.isLinux {
  options.homelab.nextcloud = {
    enable = lib.mkEnableOption "Nextcloud with MariaDB, Redis and Collabora Online";
    live = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = ''
        Serve the public hosts and run background jobs. Off: public hosts show the
        maintenance page and nextcloud-cron does not run.
      '';
    };
  };

  config = lib.mkIf cfg.enable {
    assertions = [
      {
        assertion = !config.services.disnix.enable;
        message = ''
          homelab.nextcloud pins the nextcloud user and group to 33 (nixpkgs reserves
          33 for disnix) so the data on TrueNAS stays owned as it was on Main
          (www-data, 33). Disnix cannot run on this host.
        '';
      }
    ];

    # Main runs 32 and the import has to stay on that major; nixpkgs marks 32 EOL.
    # Upgrade to 33 after the cutover (one major at a time).
    homelab.insecurePackages = [ "nextcloud-32." ];

    users.users.nextcloud.uid = 33;
    users.groups.nextcloud.gid = 33;

    services.onepassword-secrets.secrets = {
      # JSON with Main's instanceid, passwordsalt and secret.
      nextcloudSecrets = {
        reference = "op://Homelab/nextcloud-config/secrets";
        mode = "0400";
        owner = "root";
        services = units;
      };
      # Only used by the first install; the database import replaces the users.
      nextcloudAdminpass = {
        reference = "op://Homelab/nextcloud-config/adminpass";
        mode = "0400";
        owner = "root";
        services = [ "nextcloud-setup" ];
      };
    };

    services.nextcloud = {
      enable = true;
      package = pkgs.nextcloud32;
      hostName = host;
      # Config, app data from nixpkgs: local. User data: `settings.datadirectory`.
      datadir = "/var/lib/nextcloud";
      database.createLocally = true;
      configureRedis = true;
      config = {
        dbtype = "mysql";
        # The first install's admin, a name no account on Main has (the install
        # runs against the shared data directory); the database import replaces it.
        adminuser = "prod-setup";
        adminpassFile = secretPaths.nextcloudAdminpass;
      };
      secretFile = secretPaths.nextcloudSecrets;
      appstoreEnable = false;
      extraApps = {
        inherit (pkgs.nextcloud32Packages.apps)
          calendar
          contacts
          pantry
          richdocuments
          ;
      };
      extraAppsEnable = true;
      settings = {
        datadirectory = dataDir;
        # The LAN address too, for Lodestar's check.
        trusted_domains = lib.optional (lan.address != null) lan.address;
        trusted_proxies = [ "10.0.10.110" ];
        overwriteprotocol = "https";
      };
    };

    systemd.timers.nextcloud-cron.enable = cfg.live;

    systemd.services = lib.mkMerge [
      (lib.genAttrs units (_: {
        unitConfig.RequiresMountsFor = [ dataDir ];
      }))
      { mysql-backup.unitConfig.RequiresMountsFor = [ dumpDir ]; }
    ];

    services.mysqlBackup = {
      enable = true;
      databases = [ "nextcloud" ];
      location = dumpDir;
      calendar = "01:30";
      singleTransaction = true;
    };

    # Collabora Online behind the router: Traefik terminates TLS, coolwsd speaks
    # plain HTTP and builds its URLs for https://office.vanwaaij.com.
    services.collabora-online = {
      enable = true;
      port = officePort;
      aliasGroups = [ { host = "https://${host}"; } ];
      settings = {
        server_name = officeHost;
        ssl = {
          enable = false;
          termination = true;
        };
      };
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
