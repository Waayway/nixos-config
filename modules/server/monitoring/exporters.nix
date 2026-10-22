# Exporters on the monitor VM (`homelab.monitoring.server.enable`), each with its
# Prometheus job:
#
#   pve          prometheus-pve-exporter (127.0.0.1:9221) asked about the Proxmox host
#                10.0.10.50 with the API token from `secrets.pveEnv`. (`pve.enable`)
#   truenas      graphite_exporter: TrueNAS's Graphite exporter pushes to port 2003
#                (open to 10.0.10.130 only); metrics on 10.0.10.140:9108 (not opened in the firewall), renamed by
#                graphite-mapping.yaml. Plus the `truenas-pools` timer: pool health over
#                SSH (truenas-pools.sh) as the textfile metric `truenas_pool_healthy`.
#                (`truenas.enable`)
#   blackbox     blackbox_exporter (127.0.0.1:9115) probing `https://<host>/` of every
#                front-door route (flake routes without router-test's, plus the router's
#                `extraRoutes`), by name through the tailnet's split DNS. Redirects are
#                followed and any 2xx counts as up, so a sign-in redirect is "up".
#   healthchecks Healthchecks.io's metrics endpoint, authorised with the read-only API
#                key. The URL holds the project UUID, which is a secret in 1Password, so
#                Prometheus gets it through a file_sd file that prometheus.service writes
#                at start (ExecStartPre, as root) into /run/healthchecks-sd.
#                (`healthchecks.enable`)
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
  cfg = config.homelab.monitoring.server;
  secrets = cfg.secrets;
  mapAttrsToList = lib.mapAttrsToList;

  pveAddress = "10.0.10.50";
  truenasAddress = "10.0.10.130";
  textfileDir = "/var/lib/node-exporter-textfile";
  sdDir = "/run/healthchecks-sd";

  # Routes as the router serves them, minus router-test's: the flake's `homelab.routes`
  # and the router's `extraRoutes` (backends the flake doesn't manage).
  routes =
    tools.routesFrom { inherit lib; } {
      nixosConfigurations = lib.removeAttrs inputs.self.nixosConfigurations [ "router-test" ];
    }
    // inputs.self.nixosConfigurations.router.config.homelab.router.extraRoutes;

  blackboxConfig = builtins.toFile "blackbox.yml" (
    builtins.toJSON {
      modules.http_2xx = {
        prober = "http";
        timeout = "10s";
        # valid_status_codes empty means any 2xx, after redirects.
        http = {
          follow_redirects = true;
          valid_status_codes = [ ];
          preferred_ip_protocol = "ip4";
        };
      };
    }
  );

  # Drops the comment lines of the YAML file, which is JSON otherwise.
  mapping = builtins.fromJSON (
    lib.concatStringsSep "\n" (
      lib.filter (l: !lib.hasPrefix "#" l) (
        lib.splitString "\n" (builtins.readFile ./graphite-mapping.yaml)
      )
    )
  );

  # An exporter that is asked about a target: /probe-style job going through localhost.
  viaExporter = exporter: {
    relabel_configs = [
      {
        source_labels = [ "__address__" ];
        target_label = "__param_target";
      }
      {
        source_labels = [ "__param_target" ];
        target_label = "instance";
      }
      {
        target_label = "__address__";
        replacement = exporter;
      }
    ];
  };

  poolsScript = pkgs.writeShellApplication {
    name = "truenas-pools";
    runtimeInputs = [
      pkgs.openssh
      pkgs.jq
      pkgs.coreutils
    ];
    text = builtins.readFile ./truenas-pools.sh;
  };

  graphiteRule =
    action: proto:
    "iptables -w ${action} nixos-fw -p ${proto} -s ${truenasAddress} --dport 2003 -j nixos-fw-accept";
  graphiteRules =
    action:
    lib.concatMapStringsSep "\n" (graphiteRule action) [
      "tcp"
      "udp"
    ];

  healthchecksSd = pkgs.writeShellScript "healthchecks-sd" ''
    # Missing UUID (secret not fetched yet): no targets, Prometheus still starts.
    uuid=$(${pkgs.coreutils}/bin/cat ${secrets.healthchecksProject} 2>/dev/null | ${pkgs.coreutils}/bin/tr -d '[:space:]') || uuid=""
    tmp=$(${pkgs.coreutils}/bin/mktemp ${sdDir}/.sd.XXXXXX)
    if [ -n "$uuid" ]; then
      ${pkgs.jq}/bin/jq -n --arg p "/projects/$uuid/metrics/" \
        '[{targets: ["healthchecks.io"], labels: {__metrics_path__: $p}}]' >"$tmp"
    else
      echo '[]' >"$tmp"
    fi
    ${pkgs.coreutils}/bin/chmod 0640 "$tmp"
    ${pkgs.coreutils}/bin/chgrp prometheus "$tmp"
    ${pkgs.coreutils}/bin/mv "$tmp" ${sdDir}/targets.json
  '';
in
lib.optionalAttrs hostPlatform.isLinux {
  config = lib.mkIf cfg.enable (
    lib.mkMerge [
      # Blackbox: every route
      {
        services.prometheus.exporters.blackbox = {
          enable = true;
          listenAddress = "127.0.0.1";
          configFile = blackboxConfig;
        };
        services.prometheus.scrapeConfigs = [
          (
            {
              job_name = "blackbox";
              metrics_path = "/probe";
              params.module = [ "http_2xx" ];
              scrape_interval = "1m";
              static_configs = mapAttrsToList (name: r: {
                targets = [ "https://${r.host}/" ];
                labels.route = name;
              }) routes;
            }
            // viaExporter "127.0.0.1:9115"
          )
        ];
      }

      (lib.mkIf cfg.pve.enable {
        services.prometheus.exporters.pve = {
          enable = true;
          listenAddress = "127.0.0.1";
          environmentFile = secrets.pveEnv;
        };
        # The PVE API has a self-signed certificate.
        systemd.services.prometheus-pve-exporter.environment.PVE_VERIFY_SSL = "false";
        services.prometheus.scrapeConfigs = [
          (
            {
              job_name = "pve";
              metrics_path = "/pve";
              params.module = [ "default" ];
              static_configs = [ { targets = [ pveAddress ]; } ];
            }
            // viaExporter "127.0.0.1:9221"
          )
        ];
      })

      (lib.mkIf cfg.truenas.enable {
        services.prometheus.exporters.graphite = {
          enable = true;
          # The module binds both the metrics (9108) and the Graphite input (2003) to this
          # one address, and graphite_exporter rejects a repeated flag, so no extraFlags.
          # The LAN address, since TrueNAS must reach 2003; the firewall opens 2003 for
          # TrueNAS only and not 9108 at all.
          listenAddress = config.homelab.lan.address;
          graphitePort = 2003;
          mappingSettings = mapping;
        };
        # Port 2003 is privileged.
        systemd.services.prometheus-graphite-exporter.serviceConfig = {
          AmbientCapabilities = [ "CAP_NET_BIND_SERVICE" ];
          CapabilityBoundingSet = [ "CAP_NET_BIND_SERVICE" ];
        };
        services.prometheus.scrapeConfigs = [
          {
            job_name = "truenas";
            static_configs = [ { targets = [ "${config.homelab.lan.address}:9108" ]; } ];
          }
        ];
        networking.firewall.extraCommands = graphiteRules "-A";
        networking.firewall.extraStopCommands =
          lib.replaceStrings [ "\n" ] [ " || true\n" ] (graphiteRules "-D") + " || true";

        systemd.services.truenas-pools = {
          description = "TrueNAS pool health as a textfile metric";
          environment = {
            TRUENAS_HOST = truenasAddress;
            TRUENAS_USER = "automation";
            TRUENAS_KEY = secrets.truenasKey;
            TRUENAS_KNOWN_HOSTS = builtins.toFile "truenas-known-hosts" "${truenasAddress} ${lib.fileContents ../truenas/host-key.pub}\n";
            TEXTFILE = "${textfileDir}/truenas-pools.prom";
          };
          serviceConfig = {
            Type = "oneshot";
            ExecStart = lib.getExe poolsScript;
          };
        };
        systemd.timers.truenas-pools = {
          wantedBy = [ "timers.target" ];
          timerConfig.OnCalendar = "*:0/5";
        };
      })

      (lib.mkIf cfg.healthchecks.enable {
        # promtool would look for the credentials file in the build sandbox.
        services.prometheus.checkConfig = "syntax-only";
        systemd.tmpfiles.rules = [ "d ${sdDir} 0755 root root -" ];
        systemd.services.prometheus.serviceConfig.ExecStartPre = [ "+${healthchecksSd}" ];
        services.prometheus.scrapeConfigs = [
          {
            job_name = "healthchecks";
            scheme = "https";
            scrape_interval = "2m";
            authorization.credentials_file = secrets.healthchecksReadonlyKey;
            file_sd_configs = [
              {
                files = [ "${sdDir}/targets.json" ];
                refresh_interval = "1m";
              }
            ];
          }
        ];
      })
    ]
  );
}
