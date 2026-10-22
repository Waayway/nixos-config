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
  job = n: lib.findFirst (j: j.job_name == n) null prom.scrapeConfigs;
  targetsOf = n: lib.concatMap (s: s.targets) (job n).static_configs;
  labelsOf = n: map (s: s.labels) (job n).static_configs;
  secrets = monitor.homelab.monitoring.server.secrets;
  opn = monitor.services.onepassword-secrets.secrets;
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
# the monitor is not the monitor on other hosts
assert !prod.homelab.monitoring.server.enable;
# darwin: the options exist, nothing else
assert !atlas.homelab.monitoring.agent.enable;
pkgs.runCommand "monitoring" { } "touch $out"
