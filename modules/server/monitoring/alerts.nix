# Alerts on the monitor VM (`homelab.monitoring.server.enable` and
# `server.healthchecks.enable`): Grafana-managed rules, one Healthchecks.io check per
# rule, so the phone gets one notification per kind of problem (docs/plans/
# 2026-10-22-monitoring-design.md, section G).
#
# - `checks` below is the one list: every entry with an `expr` becomes an alert rule
#   (label `hc`), a webhook contact point on `https://hc-ping.com/$HC_PING_KEY/<slug>`
#   (Grafana fills in the env var from the ping-key env file, systemd's EnvironmentFile
#   of grafana.service), a route in the notification policy, and a Healthchecks check
#   (`healthchecks-sync`). The watchdog always fires and pings every minute; the
#   `truenas` check has no rule: TrueNAS' own alert service posts to its /fail URL.
# - A rule's query returns series only while the condition holds (a comparison), so the
#   condition is "any value" and no data means fine. Webhook bodies carry
#   `"status":"firing"` / `"status":"resolved"`, which the checks filter on
#   (healthchecks-sync.sh).
# - Provisioning files interpolate `$VAR`, so no rule text uses a Grafana `$labels`
#   template; the summaries are plain text.
# - An alert without an `hc` label (none exists) would go to the root receiver, the
#   host-down check: a visible failure instead of a lost alert.
{
  config,
  lib,
  pkgs,
  hostPlatform,
  ...
}:
let
  cfg = config.homelab.monitoring.server;
  enabled = cfg.enable && cfg.healthchecks.enable;
  year = 31536000;

  # hc = check name without the `homelab-` prefix. grace is the check's grace (seconds).
  # `filter` = the check only reacts to the firing/resolved keywords.
  checks = [
    {
      hc = "host-down";
      name = "Host down";
      expr = ''up{job="node"} == 0'';
      for = "3m";
      summary = "A host's node exporter has been unreachable for 3 minutes";
    }
    {
      hc = "vm-down";
      name = "VM down";
      expr = ''pve_up{id=~"qemu/.*"} == 0 and on(id) pve_onboot_status == 1'';
      for = "5m";
      summary = "A VM that starts on boot is not running";
    }
    {
      hc = "disk-full";
      name = "Disk almost full";
      expr = ''(1 - node_filesystem_avail_bytes{fstype!~"tmpfs|nfs.*"} / node_filesystem_size_bytes > 0.85) or (pve_disk_usage_bytes{id=~"storage/.*"} / pve_disk_size_bytes{id=~"storage/.*"} > 0.85)'';
      for = "10m";
      summary = "A filesystem or Proxmox storage is more than 85% full";
    }
    {
      hc = "failed-unit";
      name = "Failed unit";
      expr = ''node_systemd_unit_state{state="failed"} == 1'';
      for = "5m";
      summary = "A systemd unit has been failed for 5 minutes";
    }
    {
      hc = "route-down";
      name = "Route down";
      expr = "probe_success == 0";
      for = "3m";
      summary = "A route does not answer the blackbox probe";
    }
    {
      hc = "truenas-pool";
      name = "TrueNAS pool";
      expr = "truenas_pool_healthy == 0";
      for = "1m";
      summary = "A TrueNAS pool is not healthy";
    }
    {
      hc = "log-budget";
      name = "Log budget hit";
      expr = "loki_budget_exceeded == 1";
      for = "0s";
      summary = "A host used up its daily log budget; its logs are dropped";
    }
    {
      hc = "memory";
      name = "Memory pressure";
      expr = "node_memory_MemAvailable_bytes / node_memory_MemTotal_bytes < 0.10";
      for = "15m";
      summary = "A host has less than 10% memory available";
    }
    {
      hc = "watchdog";
      name = "Watchdog";
      expr = "vector(1)";
      for = "0s";
      summary = "Always firing: if the pings stop, the monitor or its network is down";
      timeout = 300;
      grace = 300;
      filter = false;
      repeat = "1m";
    }
    {
      hc = "truenas";
      name = "TrueNAS alerts";
      filter = false;
    }
  ];

  withDefaults =
    c:
    {
      timeout = year;
      grace = 60;
      filter = true;
      repeat = "4h";
    }
    // c;
  all = map withDefaults checks;
  rules = lib.filter (c: c ? expr) all;
  slug = c: "homelab-${c.hc}";

  syncChecks = map (c: {
    slug = slug c;
    inherit (c) timeout grace filter;
    name = "Homelab: ${c.name}";
  }) all;
  syncJson = builtins.toJSON syncChecks;

  rule = c: {
    uid = "homelab-${c.hc}";
    title = c.name;
    condition = "C";
    data = [
      {
        refId = "A";
        relativeTimeRange = {
          from = 600;
          to = 0;
        };
        datasourceUid = "prometheus";
        model = {
          refId = "A";
          expr = c.expr;
          instant = true;
          intervalMs = 1000;
          maxDataPoints = 43200;
        };
      }
      {
        refId = "B";
        datasourceUid = "__expr__";
        model = {
          refId = "B";
          type = "reduce";
          expression = "A";
          reducer = "last";
          settings.mode = "dropNN";
        };
      }
      {
        refId = "C";
        datasourceUid = "__expr__";
        model = {
          refId = "C";
          type = "threshold";
          expression = "B";
          conditions = [
            {
              evaluator = {
                type = "gt";
                params = [ (-1) ];
              };
            }
          ];
        };
      }
    ];
    noDataState = "OK";
    execErrState = if c.hc == "watchdog" then "Alerting" else "KeepLast";
    "for" = c.for;
    labels.hc = c.hc;
    annotations.summary = c.summary;
    isPaused = false;
  };

  contactPoint = c: {
    orgId = 1;
    name = slug c;
    receivers = [
      {
        uid = slug c;
        type = "webhook";
        disableResolveMessage = false;
        settings = {
          url = "https://hc-ping.com/$HC_PING_KEY/${slug c}";
          httpMethod = "POST";
        };
      }
    ];
  };

  route = c: {
    receiver = slug c;
    object_matchers = [
      [
        "hc"
        "="
        c.hc
      ]
    ];
    group_interval = "1m";
    repeat_interval = c.repeat;
  };

  syncScript = pkgs.writeShellApplication {
    name = "healthchecks-sync";
    runtimeInputs = [
      pkgs.curl
      pkgs.jq
      pkgs.coreutils
    ];
    text = builtins.readFile ./healthchecks-sync.sh;
  };
in
lib.optionalAttrs hostPlatform.isLinux {
  config = lib.mkIf enabled {
    services.grafana.provision.alerting = {
      rules.settings = {
        apiVersion = 1;
        groups = [
          {
            orgId = 1;
            name = "homelab";
            folder = "Homelab";
            interval = "1m";
            rules = map rule rules;
          }
        ];
      };
      contactPoints.settings = {
        apiVersion = 1;
        contactPoints = map contactPoint rules;
      };
      policies.settings = {
        apiVersion = 1;
        policies = [
          {
            orgId = 1;
            receiver = slug (lib.head rules);
            group_by = [
              "alertname"
              "host"
            ];
            group_wait = "10s";
            group_interval = "1m";
            repeat_interval = "4h";
            routes = map route rules;
          }
        ];
      };
    };

    systemd.services.grafana.serviceConfig.EnvironmentFile = cfg.secrets.healthchecksPingEnv;

    systemd.services.healthchecks-sync = {
      description = "Create and update the Healthchecks.io checks of the alerts";
      wantedBy = [ "multi-user.target" ];
      wants = [ "network-online.target" ];
      after = [ "network-online.target" ];
      restartTriggers = [ syncJson ];
      environment = {
        HC_API_KEY_FILE = cfg.secrets.healthchecksApiKey;
        CHECKS = syncJson;
      };
      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
        ExecStart = lib.getExe syncScript;
      };
    };
  };
}
