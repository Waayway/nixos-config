# The monitoring agent on every server: node_exporter (metrics the monitor VM scrapes),
# Alloy (ships the journal to the monitor's Loki), and firewall rules that open each
# exporter port to the monitor VM only. Off with `homelab.monitoring.agent.enable = false`.
{
  config,
  lib,
  hostPlatform,
  ...
}:
let
  cfg = config.homelab.monitoring;
  textfileDir = "/var/lib/node-exporter-textfile";
  ports = lib.unique (lib.mapAttrsToList (_: t: t.port) cfg.targets);
  rule =
    action: port:
    "iptables -w ${action} nixos-fw -p tcp -s ${cfg.serverAddress} --dport ${toString port} -j nixos-fw-accept";
in
lib.optionalAttrs hostPlatform.isLinux {
  config = lib.mkIf cfg.agent.enable {
    homelab.monitoring.targets.node.port = 9100;

    services.prometheus.exporters.node = {
      enable = true;
      port = 9100;
      # Reachable from the monitor only, see the firewall rules below.
      openFirewall = false;
      enabledCollectors = [
        "systemd"
        "processes"
      ];
      extraFlags = [ "--collector.textfile.directory=${textfileDir}" ];
    };

    # Other modules drop `*.prom` files here (timers that report job results).
    systemd.tmpfiles.rules = [ "d ${textfileDir} 0755 root root -" ];

    services.alloy.enable = true;
    environment.etc."alloy/config.alloy".text = ''
      loki.source.journal "journal" {
        forward_to    = [loki.process.journal.receiver]
        max_age       = "12h"
        relabel_rules = loki.relabel.journal.rules
      }

      loki.relabel "journal" {
        forward_to = []
        rule {
          source_labels = ["__journal__systemd_unit"]
          target_label  = "unit"
        }
        rule {
          source_labels = ["__journal_priority"]
          target_label  = "priority"
        }
      }

      // Debug (priority 7) is dropped here, before it costs bandwidth or budget.
      loki.process "journal" {
        forward_to = [loki.write.monitor.receiver]
        // stage.drop reads the extracted map, which holds no labels; match on the label.
        stage.match {
          selector = "{priority=\"7\"}"
          action   = "drop"
        }
      }

      loki.write "monitor" {
        endpoint {
          url     = "http://${cfg.serverAddress}:3100/loki/api/v1/push"
          headers = { "X-Scope-OrgID" = "${config.networking.hostName}" }
        }
        external_labels = { host = "${config.networking.hostName}" }
      }
    '';

    networking.firewall.extraCommands = lib.concatMapStringsSep "\n" (rule "-A") ports;
    networking.firewall.extraStopCommands = lib.concatMapStringsSep "\n" (
      p: "${rule "-D" p} || true"
    ) ports;
  };
}
