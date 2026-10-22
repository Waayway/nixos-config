# `homelab.monitoring.*`: plain data options (configure nothing), present on every host
# and collected flake-wide with `tools.monitoringTargetsFrom`; the monitor VM turns the
# result into Prometheus scrape targets, Loki tenants and budgets.
{
  lib,
  hostPlatform,
  ...
}:
{
  options.homelab.monitoring = {
    serverAddress = lib.mkOption {
      type = lib.types.str;
      default = "10.0.10.140";
      description = "LAN address of the monitor VM; agents push logs there and allow it to scrape their exporters.";
    };
    agent.enable = lib.mkOption {
      type = lib.types.bool;
      default = hostPlatform.isServer;
      defaultText = lib.literalExpression "hostPlatform.isServer";
      description = "Whether this host is scraped and ships its logs to the monitor VM.";
    };
    agent.logBudgetMB = lib.mkOption {
      type = lib.types.ints.positive;
      default = 200;
      description = "Log volume this host may send per day, in megabytes.";
    };
    targets = lib.mkOption {
      type = lib.types.attrsOf (
        lib.types.submodule {
          options = {
            port = lib.mkOption {
              type = lib.types.port;
              description = "Port the exporter listens on.";
            };
            path = lib.mkOption {
              type = lib.types.str;
              default = "/metrics";
              description = "HTTP path Prometheus scrapes.";
            };
          };
        }
      );
      default = { };
      description = "Metrics endpoints on this host that the monitor VM scrapes, by exporter name.";
    };
    server.enable = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = "Whether this host is the monitor VM (Prometheus, Loki, Grafana).";
    };
  };
}
