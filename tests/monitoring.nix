# Evaluation check of the monitoring agent (modules/server/monitoring/agent.nix) on the
# real hosts: node_exporter and Alloy on a server, firewall open to the monitor only,
# nothing on router-test (agent off) or the Macs. Also the monitor host: Prometheus with
# scrape jobs collected from the flake, and its secrets.
{
  pkgs,
  lib,
  nixosConfigurations,
  darwinConfigurations,
}:
let
  prod = nixosConfigurations.prod.config;
  test = nixosConfigurations.router-test.config;
  router = nixosConfigurations.router.config;
  atlas = darwinConfigurations.atlas.config;
  node = prod.services.prometheus.exporters.node;
  alloy = prod.environment.etc."alloy/config.alloy".text;
  fw = prod.networking.firewall;
  has = lib.hasInfix;
  monitor = nixosConfigurations.monitor.config;
  prom = monitor.services.prometheus;
  loki = monitor.services.loki;
  job = n: lib.findFirst (j: j.job_name == n) null prom.scrapeConfigs;
  targetsOf = n: lib.concatMap (s: s.targets) (job n).static_configs;
  labelsOf = n: map (s: s.labels) (job n).static_configs;
  secrets = monitor.homelab.monitoring.server.secrets;
  opn = monitor.services.onepassword-secrets.secrets;
  exp = monitor.services.prometheus.exporters;
  bb = builtins.fromJSON (builtins.readFile exp.blackbox.configFile);
  mapping = builtins.fromJSON (
    lib.concatStringsSep "\n" (
      lib.filter (l: !lib.hasPrefix "#" l) (
        lib.splitString "\n" (builtins.readFile ../modules/server/monitoring/graphite-mapping.yaml)
      )
    )
  );
  units = monitor.systemd;
  probes = targetsOf "blackbox";
in
assert node.enable;
assert lib.elem "systemd" node.enabledCollectors;
assert lib.elem "processes" node.enabledCollectors;
assert lib.elem "--collector.textfile.directory=/var/lib/node-exporter-textfile" node.extraFlags;
assert prod.homelab.monitoring.targets.node.port == 9100;
assert has "d /var/lib/node-exporter-textfile" (
  lib.concatStringsSep "\n" prod.systemd.tmpfiles.rules
);
# Alloy: journal to Loki, tenant = host name, debug dropped at the source
assert prod.services.alloy.enable;
assert has "X-Scope-OrgID" alloy;
assert has ''"prod"'' alloy;
assert has "10.0.10.140:3100/loki/api/v1/push" alloy;
assert has "loki.source.journal" alloy;
assert has ''{priority=\"7\"}'' alloy;
assert has "stage.match" alloy;
assert has ''action   = "drop"'' alloy;
# exporter ports: the monitor only, never open to everyone
assert has "-s 10.0.10.140" fw.extraCommands;
assert has "--dport 9100" fw.extraCommands;
assert has "-s 10.0.10.140" fw.extraStopCommands;
assert !(lib.elem 9100 fw.allowedTCPPorts);
assert lib.all (i: !(lib.elem 9100 i.allowedTCPPorts)) (lib.attrValues fw.interfaces);
assert !prod.services.prometheus.exporters.node.openFirewall;
# per-host extras: cAdvisor on prod, Traefik's metrics entrypoint on the router
assert prod.services.cadvisor.enable;
assert prod.services.cadvisor.port == 9101;
assert prod.services.cadvisor.listenAddress == "0.0.0.0";
assert prod.homelab.monitoring.targets.cadvisor.port == 9101;
assert has "--dport 9101" fw.extraCommands;
assert router.services.traefik.staticConfigOptions.metrics.prometheus.entryPoint == "metrics";
assert router.services.traefik.staticConfigOptions.entryPoints.metrics.address == ":8082";
assert router.homelab.monitoring.targets.traefik.port == 8082;
assert has "--dport 8082" router.networking.firewall.extraCommands;
assert has "-s 10.0.10.140" router.networking.firewall.extraCommands;
# a host with the agent off has none of it
assert !test.services.prometheus.exporters.node.enable;
assert !test.services.alloy.enable;
assert !(test.homelab.monitoring.targets ? node);
# the monitor host: Prometheus on loopback, retention, jobs per target name
assert prom.enable;
assert prom.listenAddress == "127.0.0.1";
assert prom.port == 9090;
assert prom.stateDir == "monitoring/prometheus";
assert lib.elem "--storage.tsdb.retention.time=90d" prom.extraFlags;
assert lib.elem "--storage.tsdb.retention.size=20GB" prom.extraFlags;
assert lib.elem "10.0.10.100:9100" (targetsOf "node");
assert lib.elem "10.0.10.140:9100" (targetsOf "node");
assert lib.elem { host = "prod"; } (labelsOf "node");
assert !(lib.any (t: has "10.0.10.230" t) (targetsOf "node"));
# cAdvisor runs wherever Docker does (services/docker.nix): prod, router, identity; not the monitor
assert lib.elem "10.0.10.100:9101" (targetsOf "cadvisor");
assert lib.elem { host = "prod"; } (labelsOf "cadvisor");
assert !(lib.elem "10.0.10.140:9101" (targetsOf "cadvisor"));
assert targetsOf "traefik" == [ "10.0.10.110:8082" ];
assert monitor.fileSystems."/var/lib/monitoring".device == "/dev/disk/by-label/monitor-data";
assert !(lib.elem 9090 monitor.networking.firewall.allowedTCPPorts);
# Loki: multi-tenant, retention and limits, runtime config, budget timer, firewall
assert loki.enable;
assert loki.configuration.auth_enabled;
assert loki.configuration.querier.multi_tenant_queries_enabled;
assert loki.configuration.limits_config.retention_period == "336h";
assert loki.configuration.limits_config.ingestion_rate_mb == 1;
assert loki.configuration.limits_config.ingestion_burst_size_mb == 4;
assert loki.configuration.compactor.retention_enabled;
assert loki.configuration.runtime_config.file == "/var/lib/monitoring/loki/runtime.yaml";
assert loki.configuration.runtime_config.period == "10s";
assert loki.dataDir == "/var/lib/monitoring/loki";
assert loki.configuration.server.http_listen_port == 3100;
assert monitor.systemd.services.loki.unitConfig.RequiresMountsFor == "/var/lib/monitoring";
assert monitor.systemd.services.prometheus.unitConfig.RequiresMountsFor == "/var/lib/monitoring";
assert targetsOf "loki" == [ "127.0.0.1:3100" ];
assert monitor.systemd.timers.loki-budget.timerConfig.OnCalendar == "*:0/5";
assert monitor.systemd.timers.loki-budget.wantedBy == [ "timers.target" ];
assert has ''"prod":200'' monitor.systemd.services.loki-budget.environment.BUDGETS;
assert !(has "router-test" monitor.systemd.services.loki-budget.environment.BUDGETS);
assert
  monitor.systemd.services.loki-budget.environment.TEXTFILE
  == "/var/lib/node-exporter-textfile/loki-budget.prom";
assert has "-s 10.0.10.100" monitor.networking.firewall.extraCommands;
assert has "--dport 3100" monitor.networking.firewall.extraCommands;
assert !(lib.elem 3100 monitor.networking.firewall.allowedTCPPorts);
# secrets: opnix references and paths, gated by the sub-enables
assert opn.grafanaAdminPassword.reference == "op://Homelab/grafana-admin/password";
assert opn.grafanaOidcSecret.owner == "grafana";
assert opn.truenasKey.reference == "op://Homelab/truenas-automation/private key?ssh-format=openssh";
assert secrets.pveEnv == monitor.services.onepassword-secrets.secretPaths.pveEnv;
assert secrets.healthchecksProject != null;
assert
  let
    off = nixosConfigurations.monitor.extendModules {
      modules = [
        {
          homelab.monitoring.server = {
            pve.enable = false;
            truenas.enable = false;
            healthchecks.enable = false;
          };
        }
      ];
    };
  in
  !(off.config.services.onepassword-secrets.secrets ? pveEnv)
  && !(off.config.services.onepassword-secrets.secrets ? truenasKey)
  && !(off.config.services.onepassword-secrets.secrets ? healthchecksApiKey)
  && off.config.homelab.monitoring.server.secrets.pveEnv == null;
# exporters on the monitor: pve, TrueNAS (Graphite), blackbox, Healthchecks
assert exp.pve.enable;
assert exp.pve.listenAddress == "127.0.0.1";
assert exp.pve.port == 9221;
assert exp.pve.environmentFile == secrets.pveEnv;
assert units.services.prometheus-pve-exporter.environment.PVE_VERIFY_SSL == "false";
# graphite_exporter: exactly one of each listen flag (kingpin rejects a repeat), both on
# the monitor's LAN address; metrics port 9108 is not opened in the firewall
assert
  let
    start = units.services.prometheus-graphite-exporter.serviceConfig.ExecStart;
    words = lib.filter (w: w != "") (
      lib.splitString " " (lib.replaceStrings [ "\n" "\\" "=" ] [ " " " " " " ] start)
    );
    valuesOf =
      flag:
      map (i: builtins.elemAt words (i + 1)) (
        lib.filter (i: builtins.elemAt words i == flag) (lib.range 0 (lib.length words - 2))
      );
  in
  valuesOf "--web.listen-address" == [ "10.0.10.140:9108" ]
  && valuesOf "--graphite.listen-address" == [ "10.0.10.140:2003" ]
  && !(has "0.0.0.0" start);
assert (job "pve").metrics_path == "/pve";
assert (job "pve").params.module == [ "default" ];
assert targetsOf "pve" == [ "10.0.10.50" ];
assert (lib.head (job "pve").relabel_configs).target_label == "__param_target";
assert lib.any (
  r: r.target_label or "" == "__address__" && r.replacement == "127.0.0.1:9221"
) (job "pve").relabel_configs;
assert exp.graphite.enable;
assert exp.graphite.graphitePort == 2003;
assert exp.graphite.mappingSettings == mapping;
assert mapping.mappings != [ ];
assert targetsOf "truenas" == [ "10.0.10.140:9108" ];
assert !(lib.elem 9108 monitor.networking.firewall.allowedTCPPorts);
assert !(has "--dport 9108" monitor.networking.firewall.extraCommands);
assert has "-s 10.0.10.130" monitor.networking.firewall.extraCommands;
assert has "--dport 2003" monitor.networking.firewall.extraCommands;
assert !(lib.elem 2003 monitor.networking.firewall.allowedTCPPorts);
assert !(lib.elem 2003 monitor.networking.firewall.allowedUDPPorts);
assert
  !(lib.any (l: has "2003" l && !has "-s 10.0.10.130" l) (
    lib.splitString "\n" monitor.networking.firewall.extraCommands
  ));
assert lib.elem "d /run/healthchecks-sd 0755 root root -" units.tmpfiles.rules;
assert
  has "chmod 0640" (builtins.readFile ../modules/server/monitoring/exporters.nix)
  && has "chgrp prometheus" (builtins.readFile ../modules/server/monitoring/exporters.nix);
assert has "ExecStartPre" (builtins.toJSON (lib.attrNames units.services.prometheus.serviceConfig));
assert units.timers.truenas-pools.timerConfig.OnCalendar == "*:0/5";
assert units.services.truenas-pools.environment.TRUENAS_HOST == "10.0.10.130";
assert units.services.truenas-pools.environment.TRUENAS_USER == "automation";
assert units.services.truenas-pools.environment.TRUENAS_KEY == secrets.truenasKey;
assert
  units.services.truenas-pools.environment.TEXTFILE
  == "/var/lib/node-exporter-textfile/truenas-pools.prom";
assert
  builtins.readFile units.services.truenas-pools.environment.TRUENAS_KNOWN_HOSTS
  == "10.0.10.130 ${nixosConfigurations.nixos-manager.config.truenas.hostKey}\n";
assert exp.blackbox.enable;
assert exp.blackbox.listenAddress == "127.0.0.1";
assert bb.modules.http_2xx.prober == "http";
assert bb.modules.http_2xx.http.follow_redirects;
assert bb.modules.http_2xx.http.valid_status_codes == [ ];
assert (job "blackbox").metrics_path == "/probe";
assert (job "blackbox").params.module == [ "http_2xx" ];
assert lib.elem "https://nextcloud.vanwaaij.com/" probes;
assert lib.elem "https://id.vanwaaij.com/" probes;
assert lib.elem "https://ap.vanwaaij.com/" probes;
assert lib.elem "https://truenas.vanwaaij.com/" probes;
assert !(lib.any (t: has "test" t) probes);
assert lib.elem { route = "archipelago"; } (labelsOf "blackbox");
assert (job "healthchecks").scrape_interval == "2m";
assert (job "healthchecks").authorization.credentials_file == secrets.healthchecksReadonlyKey;
assert (job "healthchecks").scheme == "https";
assert prom.checkConfig == "syntax-only";
assert opn.pveEnv.services == [ "prometheus-pve-exporter.service" ];
assert opn.truenasKey.services == [ "truenas-pools.service" ];
assert
  let
    off = nixosConfigurations.monitor.extendModules {
      modules = [ { homelab.monitoring.server.truenas.enable = false; } ];
    };
    j = lib.findFirst (j: j.job_name == "truenas") null off.config.services.prometheus.scrapeConfigs;
  in
  j == null
  && !(off.config.systemd.timers ? truenas-pools)
  && !off.config.services.prometheus.exporters.graphite.enable;
assert
  let
    off = nixosConfigurations.monitor.extendModules {
      modules = [ { homelab.monitoring.server.pve.enable = false; } ];
    };
  in
  !(lib.any (j: j.job_name == "pve") off.config.services.prometheus.scrapeConfigs)
  && !off.config.services.prometheus.exporters.pve.enable;
# the monitor is not the monitor on other hosts
assert !prod.homelab.monitoring.server.enable;
# darwin: the options exist, nothing else
assert !atlas.homelab.monitoring.agent.enable;
pkgs.runCommand "monitoring" { } "touch $out"
