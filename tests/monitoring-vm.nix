# VM test of the monitoring stack (modules/server/monitoring/*.nix): a `monitor` node
# (Prometheus, Loki, Grafana), an `agent` node (node_exporter + Alloy) and a bystander
# `other`. Proves scraping, log shipping per tenant, the daily log budget (a 1 MB budget
# blown by a flood, then nothing accepted), Grafana's provisioning (data sources, and the
# Loki tenant header read through `$__file{}`), the monitor-data disk, and the firewall
# (exporters open to the monitor only, Loki to monitored hosts only, Prometheus on
# loopback). Run on a Linux builder with KVM:
#   nix build --no-link -L .#checks.x86_64-linux.monitoring-vm
#
# The real modules are imported, except secrets.nix (opnix/1Password): the secrets are
# test files. `server.hosts` is set by hand (no flake to collect from), and the one flake
# value exporters.nix reads (the router's extra routes, for the blackbox job) is stubbed.
{
  pkgs,
  lib,
  tools,
}:
let
  dir = ../modules/server/monitoring;
  monitoringModules = map (f: dir + "/${f}") (
    lib.filter (f: lib.hasSuffix ".nix" f && f != "secrets.nix") (lib.attrNames (builtins.readDir dir))
  );

  adminPassword = "test-admin-password";

  common = {
    imports = monitoringModules ++ [
      ../modules/server/homelab/lan.nix
      ../modules/server/homelab/routes-option.nix
      ../modules/server/homelab/access-option.nix
      # Comes from the lodestar flake on real hosts.
      {
        options.lodestar.links = lib.mkOption {
          type = lib.types.attrsOf lib.types.anything;
          default = { };
        };
      }
    ];
    homelab.lan.interface = "eth1";
    environment.systemPackages = [
      pkgs.curl
      pkgs.jq
    ];
  };
in
{
  name = "monitoring-vm";

  node.specialArgs = {
    inherit tools;
    hostPlatform = {
      isLinux = true;
      isDarwin = false;
      isServer = true;
    };
    # exporters.nix collects routes from the flake and the router's extraRoutes.
    inputs.self.nixosConfigurations.router.config.homelab = {
      routes = { };
      # grafana.nix allows its port from the router only; node `other` plays the router
      # (the test driver numbers agent, monitor, other as .1, .2, .3, asserted below).
      lan.address = "192.168.1.3";
      router.extraRoutes = { };
    };
    # grafana.nix also finds the Lodestar server (its link check) in the flake.
    inputs.self.nixosConfigurations.lodestar.config = {
      services.lodestar-server.enable = true;
      homelab.lan.address = "192.168.1.4";
    };
    serverOptions = { };
  };

  nodes = {
    monitor =
      { config, nodes, ... }:
      {
        imports = [ common ];
        virtualisation.memorySize = 2048;
        virtualisation.cores = 2;

        homelab.lan.address = config.networking.primaryIPAddress;
        homelab.monitoring = {
          serverAddress = config.networking.primaryIPAddress;
          server = {
            enable = true;
            pve.enable = false;
            truenas.enable = false;
            healthchecks.enable = false;
            hosts = {
              agent = {
                address = nodes.agent.networking.primaryIPAddress;
                logBudgetMB = 1;
                targets.node = {
                  port = 9100;
                  path = "/metrics";
                };
              };
              monitor = {
                address = config.networking.primaryIPAddress;
                logBudgetMB = 200;
                targets.node = {
                  port = 9100;
                  path = "/metrics";
                };
              };
            };
            secrets = {
              grafanaAdminPassword = pkgs.writeText "grafana-admin-password" adminPassword;
              grafanaSecretKey = pkgs.writeText "grafana-secret-key" "test-secret-key-0123456789abcdef";
              grafanaOidcSecret = pkgs.writeText "grafana-oidc-secret" "test-oidc-secret";
            };
          };
        };

        # Faster than the 1m default, so the budget query sees the flood within seconds.
        services.prometheus.globalConfig.scrape_interval = "5s";

        # The data disk. qemu-vm replaces `fileSystems` with `virtualisation.fileSystems`,
        # so the module's entry is restated here (same device by label, same options), and
        # an empty second disk gets the `monitor-data` label before the mount waits for it.
        # Not derived from `config.fileSystems`: that is the VM override itself (circular).
        virtualisation.emptyDiskImages = [ 1024 ];
        virtualisation.fileSystems."/var/lib/monitoring" = {
          device = "/dev/disk/by-label/monitor-data";
          fsType = "ext4";
          options = [ "nofail" ];
        };
        systemd.services.format-monitor-data = {
          unitConfig.DefaultDependencies = false;
          requires = [ "dev-vdb.device" ];
          after = [ "dev-vdb.device" ];
          before = [ "var-lib-monitoring.mount" ];
          wantedBy = [ "local-fs.target" ];
          path = [
            pkgs.e2fsprogs
            pkgs.util-linux
            pkgs.systemd
          ];
          serviceConfig = {
            Type = "oneshot";
            RemainAfterExit = true;
          };
          script = ''
            blkid /dev/vdb || mkfs.ext4 -q -L monitor-data /dev/vdb
            udevadm trigger --settle /dev/vdb
          '';
        };
      };

    agent =
      { nodes, ... }:
      {
        imports = [ common ];
        homelab.monitoring.serverAddress = nodes.monitor.networking.primaryIPAddress;
        # The flood is ~4000 journal lines; journald's default rate limit would drop most
        # of them before Alloy sees them.
        services.journald.rateLimitBurst = 0;
      };

    other = {
      environment.systemPackages = [ pkgs.curl ];
    };
  };

  testScript =
    { nodes, ... }:
    let
      agentIp = nodes.agent.networking.primaryIPAddress;
      monitorIp = nodes.monitor.networking.primaryIPAddress;
      otherIp = nodes.other.networking.primaryIPAddress;
    in
    ''
      import shlex

      def loki(q, tenant="agent"):
          return (
              f"curl -sfG -H 'X-Scope-OrgID: {tenant}' "
              + "--data-urlencode " + shlex.quote("query=" + q) + " "
              + "--data-urlencode since=1h "
              + "localhost:3100/loki/api/v1/query_range"
          )

      def push(tenant, host, line):
          # HTTP status of a direct push to Loki as `tenant`.
          body = (
              "jq -nc --arg ts \"$(date +%s%N)\" "
              + "'{streams: [{stream: {host: \"HOST\", job: \"budget-probe\"}, values: [[$ts, \"LINE\"]]}]}'"
          ).replace("HOST", host).replace("LINE", line)
          return (
              body
              + " | curl -s -o /dev/null -w '%{http_code}' -H 'Content-Type: application/json' "
              + "-H 'X-Scope-OrgID: " + tenant + "' --data-binary @- localhost:3100/loki/api/v1/push"
          )

      def prom(q):
          return (
              "curl -sfG --data-urlencode " + shlex.quote("query=" + q) + " "
              + "localhost:9090/api/v1/query"
          )

      start_all()

      with subtest("monitor-data disk is mounted by label"):
          monitor.wait_for_unit("var-lib-monitoring.mount")
          monitor.succeed("findmnt -n -o LABEL /var/lib/monitoring | grep -qx monitor-data")

      with subtest("services start"):
          monitor.wait_for_unit("prometheus.service")
          monitor.wait_for_unit("loki.service")
          monitor.wait_for_unit("grafana.service")
          monitor.wait_for_open_port(9090)
          monitor.wait_for_open_port(3100)
          monitor.wait_for_open_port(3000)
          agent.wait_for_unit("prometheus-node-exporter.service")
          agent.wait_for_unit("alloy.service")
          agent.wait_for_open_port(9100)
          # Prometheus and Loki keep their data on the data disk.
          monitor.succeed("findmnt -n -o TARGET -T /var/lib/monitoring/prometheus | grep -qx /var/lib/monitoring")
          monitor.succeed("findmnt -n -o TARGET -T /var/lib/monitoring/loki | grep -qx /var/lib/monitoring")

      with subtest("prometheus scrapes the agent and the monitor"):
          for host in ["agent", "monitor"]:
              monitor.wait_until_succeeds(
                  prom('up{host="' + host + '",job="node"}')
                  + " | jq -e '.data.result[0].value[1] == \"1\"'",
                  timeout=120,
              )

      with subtest("agent logs reach its loki tenant"):
          agent.succeed("logger -t mtest hello-monitoring")
          monitor.wait_until_succeeds(
              loki('{host="agent"} |= "hello-monitoring"') + " | jq -e '.data.result | length > 0'",
              timeout=60,
          )
          # Another tenant does not see them.
          monitor.succeed(
              loki('{host="agent"} |= "hello-monitoring"', tenant="monitor")
              + " | jq -e '.data.result | length == 0'"
          )

      with subtest("grafana: health, provisioned data sources, loki tenants via $__file"):
          monitor.succeed("curl -sf localhost:3000/api/health | jq -e '.database == \"ok\"'")
          monitor.succeed(
              "curl -sf -u admin:${adminPassword} localhost:3000/api/datasources "
              + "| jq -e '[.[].uid] | contains([\"prometheus\", \"loki\"])'"
          )
          # Through Grafana's data source proxy: the X-Scope-OrgID header is the tenant
          # list from the file, so Loki answers with the agent's labels.
          monitor.wait_until_succeeds(
              "curl -sf -u admin:${adminPassword} "
              + "localhost:3000/api/datasources/proxy/uid/loki/loki/api/v1/label/host/values "
              + "| jq -e '.data | index(\"agent\") != null'",
              timeout=60,
          )

      with subtest("log budget blocks a flooding host"):
          agent.succeed("head -c 3000000 /dev/urandom | base64 -w 1000 | logger -t flood")
          monitor.wait_until_succeeds(
              "systemctl start loki-budget && grep -q '^  agent:' /var/lib/monitoring/loki/runtime.yaml",
              timeout=180,
          )
          monitor.succeed(
              "grep -qx 'loki_budget_exceeded{tenant=\"agent\"} 1' /var/lib/node-exporter-textfile/loki-budget.prom"
          )
          monitor.succeed(
              "grep -qx 'loki_budget_exceeded{tenant=\"monitor\"} 0' /var/lib/node-exporter-textfile/loki-budget.prom"
          )
          monitor.fail("grep -q '^  monitor:' /var/lib/monitoring/loki/runtime.yaml")
          # Loki rereads its runtime config every 10s; then it rejects the agent tenant's
          # pushes (429) and still accepts another tenant's (204).
          monitor.wait_until_succeeds(push("agent", "agent", "probe-blocked") + " | grep -qx 429", timeout=30)
          monitor.succeed(push("monitor", "budget-probe", "probe-allowed") + " | grep -qx 204")
          monitor.wait_until_succeeds(
              loki('{host="budget-probe"} |= "probe-allowed"', tenant="monitor")
              + " | jq -e '.data.result | length > 0'",
              timeout=60,
          )
          monitor.wait_until_succeeds(
              prom('loki_discarded_bytes_total{reason="rate_limited",tenant="agent"} > 0')
              + " | jq -e '.data.result | length > 0'",
              timeout=60,
          )
          agent.succeed("logger -t mtest after-budget")
          monitor.sleep(30)
          monitor.succeed(
              loki('{host="agent"} |= "after-budget"') + " | jq -e '.data.result | length == 0'"
          )

      with subtest("firewall"):
          # Prometheus listens on loopback only: the bind itself, and from outside.
          monitor.succeed("test \"$(ss -ltnH 'sport = :9090' | awk '{print $4}' | sort -u)\" = 127.0.0.1:9090")
          agent.fail("curl -sf --max-time 3 http://${monitorIp}:9090/")
          # Exporters: the monitor only.
          monitor.succeed("curl -sf --max-time 3 http://${agentIp}:9100/metrics >/dev/null")
          other.fail("curl -sf --max-time 3 http://${agentIp}:9100/metrics")
          # Loki: monitored hosts only (any HTTP answer counts as reachable).
          agent.succeed("curl -s -o /dev/null --max-time 3 http://${monitorIp}:3100/ready")
          other.fail("curl -s -o /dev/null --max-time 3 http://${monitorIp}:3100/ready")
          # Grafana: the router's address only (node `other` stands in for it).
          assert "${otherIp}" == "192.168.1.3", "router stand-in address changed"
          agent.fail("curl -sf --max-time 3 http://${monitorIp}:3000/api/health")
          other.succeed("curl -sf --max-time 3 http://${monitorIp}:3000/api/health")
    '';
}
