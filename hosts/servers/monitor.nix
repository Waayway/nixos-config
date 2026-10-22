{
  system = "x86_64-linux";
  user = {
    name = "monitor";
    fullname = "Monitor";
  };

  type = "server";
  useDefaultHardware = true;
  isHomeServer = true;

  netInterface = {
    ip = "10.0.10.140";
    prefixLength = 24;
  };

  tags = [ "tag:monitor" ];

  fleet = true;

  # Prometheus, Loki and Grafana (modules/server/monitoring/); every server's agent
  # reports here. Data on its own disk, mounted at /var/lib/monitoring.
  options = {
    homelab.monitoring.server.enable = true;
    # Rollout: no alerts to Healthchecks until every agent reports and the pre-flight
    # checks pass (docs/plans/2026-10-22-monitoring-plan.md, Task 10 step 7).
    homelab.monitoring.server.healthchecks.enable = false;
  };

  config = { ... }: { };
}
