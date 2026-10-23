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
  };

  config = { ... }: { };
}
