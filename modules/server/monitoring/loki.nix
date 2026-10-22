# Loki on the monitor VM (`homelab.monitoring.server.enable`): every machine is a tenant
# (Alloy sends `X-Scope-OrgID = <host name>`), 14 days retention, and a hard daily log
# budget per machine: the loki-budget timer asks Prometheus how many bytes each tenant
# was accepted in the last 24h (received minus rate-limited discards) and, over `logBudgetMB`, writes a near-zero rate limit for it
# into Loki's runtime config (reloaded every 10s), so Loki rejects its pushes until the
# window drops below budget (loki-budget.sh). The result is also a textfile metric,
# `loki_budget_exceeded{tenant}`, for the alerts.
#
# Data lives under /var/lib/monitoring/loki (the monitor-data disk); without that disk
# Loki does not start rather than filling the root disk. Port 3100 is open to the
# addresses of the monitored hosts only.
{
  config,
  lib,
  pkgs,
  hostPlatform,
  ...
}:
let
  cfg = config.homelab.monitoring.server;
  dataDir = "/var/lib/monitoring/loki";
  runtimeFile = "${dataDir}/runtime.yaml";
  textfile = "/var/lib/node-exporter-textfile/loki-budget.prom";

  budgetScript = pkgs.writeShellApplication {
    name = "loki-budget";
    runtimeInputs = [
      pkgs.curl
      pkgs.jq
      pkgs.coreutils
      pkgs.gawk
    ];
    text = builtins.readFile ./loki-budget.sh;
  };

  addresses = lib.unique (lib.mapAttrsToList (_: h: h.address) cfg.hosts);
  rule =
    action: addr: "iptables -w ${action} nixos-fw -p tcp -s ${addr} --dport 3100 -j nixos-fw-accept";
in
lib.optionalAttrs hostPlatform.isLinux {
  config = lib.mkIf cfg.enable {
    services.loki = {
      enable = true;
      inherit dataDir;
      configuration = {
        auth_enabled = true;
        server = {
          http_listen_address = "0.0.0.0";
          http_listen_port = 3100;
          grpc_listen_address = "127.0.0.1";
          grpc_listen_port = 9096;
        };
        common = {
          path_prefix = dataDir;
          replication_factor = 1;
          ring = {
            instance_addr = "127.0.0.1";
            kvstore.store = "inmemory";
          };
          storage.filesystem = {
            chunks_directory = "${dataDir}/chunks";
            rules_directory = "${dataDir}/rules";
          };
        };
        schema_config.configs = [
          {
            from = "2024-01-01";
            store = "tsdb";
            object_store = "filesystem";
            schema = "v13";
            index = {
              prefix = "index_";
              period = "24h";
            };
          }
        ];
        compactor = {
          working_directory = "${dataDir}/compactor";
          retention_enabled = true;
          delete_request_store = "filesystem";
        };
        limits_config = {
          retention_period = "336h";
          ingestion_rate_mb = 1;
          ingestion_burst_size_mb = 4;
        };
        runtime_config = {
          file = runtimeFile;
          period = "10s";
        };
        # Queries across tenants (Grafana's all-tenants view).
        querier.multi_tenant_queries_enabled = true;
        analytics.reporting_enabled = false;
      };
    };

    systemd.services.loki = {
      # No data disk, no Loki.
      unitConfig.RequiresMountsFor = "/var/lib/monitoring";
      serviceConfig = {
        StateDirectory = "monitoring/loki";
        # Loki refuses to start without its runtime config file.
        ExecStartPre = "+${pkgs.writeShellScript "loki-runtime-init" ''
          [ -e ${runtimeFile} ] || echo 'overrides: {}' > ${runtimeFile}
        ''}";
      };
    };

    systemd.services.prometheus.unitConfig.RequiresMountsFor = "/var/lib/monitoring";

    services.prometheus.scrapeConfigs = [
      {
        job_name = "loki";
        static_configs = [ { targets = [ "127.0.0.1:3100" ]; } ];
      }
    ];

    systemd.services.loki-budget = {
      description = "Enforce the daily log budget per machine";
      after = [ "prometheus.service" ];
      environment = {
        PROM_URL = "http://127.0.0.1:9090";
        BUDGETS = builtins.toJSON (lib.mapAttrs (_: h: h.logBudgetMB) cfg.hosts);
        RUNTIME_FILE = runtimeFile;
        TEXTFILE = textfile;
      };
      serviceConfig = {
        Type = "oneshot";
        ExecStart = lib.getExe budgetScript;
      };
    };
    systemd.timers.loki-budget = {
      wantedBy = [ "timers.target" ];
      timerConfig.OnCalendar = "*:0/5";
    };

    networking.firewall.extraCommands = lib.concatMapStringsSep "\n" (rule "-A") addresses;
    networking.firewall.extraStopCommands = lib.concatMapStringsSep "\n" (
      a: "${rule "-D" a} || true"
    ) addresses;
  };
}
