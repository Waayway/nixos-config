# The monitor VM (`homelab.monitoring.server.enable`): Prometheus scraping every
# agent host's exporters. The targets come from the flake (`tools.monitoringTargetsFrom`):
# one job per target name (`node`, `cadvisor`, `traefik`, …), one static target per
# host, labelled `host = <name>`. Prometheus listens on loopback only; Grafana and the
# timers on this VM are its clients, so no firewall port.
#
# Data lives on the VM's own disk (label `monitor-data`) at /var/lib/monitoring.
# Prometheus uses `stateDir = "monitoring/prometheus"` (relative to /var/lib), so
# systemd's StateDirectory puts it on that mount without a bind mount; Loki gets
# /var/lib/monitoring/loki the same way.
#
# Options declared here exist on every Linux host (data only); secrets.nix fills
# `server.secrets`.
{
  config,
  lib,
  tools,
  inputs,
  hostPlatform,
  ...
}:
let
  cfg = config.homelab.monitoring.server;
  mkSwitch = description: {
    enable = lib.mkOption {
      type = lib.types.bool;
      default = true;
      inherit description;
    };
  };
  secretOption =
    name:
    lib.mkOption {
      type = lib.types.nullOr lib.types.path;
      default = null;
      description = "File holding the ${name} secret; set by secrets.nix, overridden by the VM test.";
    };

  # This configuration's own data from this evaluation (so it holds under
  # extendModules too), every other one's from the flake.
  fromFlake = tools.monitoringTargetsFrom { inherit lib; } {
    nixosConfigurations = inputs.self.nixosConfigurations // {
      ${config.networking.hostName} = { inherit config; };
    };
  };

  # target name -> { host = { address, port, path }; }
  byTarget = lib.foldl' (
    acc: host:
    lib.foldl' (
      a: t:
      a
      // {
        ${t} = (a.${t} or { }) // {
          ${host} = cfg.hosts.${host}.targets.${t} // {
            inherit (cfg.hosts.${host}) address;
          };
        };
      }
    ) acc (lib.attrNames cfg.hosts.${host}.targets)
  ) { } (lib.attrNames cfg.hosts);
  # Same path for every host of a job: Prometheus has one metrics_path per job.
  scrapeConfig = job: hosts: {
    job_name = job;
    metrics_path = (lib.head (lib.attrValues hosts)).path;
    static_configs = lib.mapAttrsToList (host: t: {
      targets = [ "${t.address}:${toString t.port}" ];
      labels = { inherit host; };
    }) hosts;
  };
in
lib.optionalAttrs hostPlatform.isLinux {
  options.homelab.monitoring.server = {
    hosts = lib.mkOption {
      type = lib.types.attrsOf lib.types.raw;
      default = fromFlake;
      defaultText = lib.literalExpression "tools.monitoringTargetsFrom over the flake's nixosConfigurations";
      description = "Hosts to monitor, as `tools.monitoringTargetsFrom` returns them.";
    };
    secrets = lib.mkOption {
      type = lib.types.submodule {
        options = lib.genAttrs [
          "grafanaAdminPassword"
          "grafanaSecretKey"
          "grafanaOidcSecret"
          "pveEnv"
          "healthchecksPingEnv"
          "healthchecksApiKey"
          "healthchecksReadonlyKey"
          "healthchecksProject"
          "truenasKey"
        ] secretOption;
      };
      default = { };
      description = "Paths of the monitor's secrets, by name (filled in by secrets.nix).";
    };
    pve = mkSwitch "Monitor the Proxmox host (exporter, alerts).";
    truenas = mkSwitch "Monitor TrueNAS (Graphite metrics, pool health).";
    healthchecks = mkSwitch "Send alerts through Healthchecks.";
  };

  config = lib.mkIf cfg.enable {
    fileSystems."/var/lib/monitoring" = {
      device = "/dev/disk/by-label/monitor-data";
      fsType = "ext4";
      options = [ "nofail" ];
    };

    services.prometheus = {
      enable = true;
      listenAddress = "127.0.0.1";
      port = 9090;
      stateDir = "monitoring/prometheus";
      extraFlags = [
        "--storage.tsdb.retention.time=90d"
        "--storage.tsdb.retention.size=20GB"
      ];
      scrapeConfigs = lib.mapAttrsToList scrapeConfig byTarget;
    };
  };
}
