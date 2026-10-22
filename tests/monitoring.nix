# Evaluation check of the monitoring agent (modules/server/monitoring/agent.nix) on the
# real hosts: node_exporter and Alloy on a server, firewall open to the monitor only,
# nothing on router-test (agent off) or the Macs.
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
# darwin: the options exist, nothing else
assert !atlas.homelab.monitoring.agent.enable;
pkgs.runCommand "monitoring" { } "touch $out"
