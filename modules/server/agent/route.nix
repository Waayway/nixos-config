{
  config,
  lib,
  hostPlatform,
  ...
}:
# The Hermes dashboard at agent.vanwaaij.com: tailnet only (Tailscale Service `agent`
# on the router), behind the router's Kanidm gate (group `agent-users`: Thijs), then
# Hermes's own password (1Password iris-dashboard). Not `hermes.*`: a Service named
# like a device loses its MagicDNS name to it, and the laptop is `hermes`. iris
# accepts the dashboard port from the router only.
let
  h = config.services.hermes-agent;
  lan = config.homelab.lan;
  host = lib.removePrefix "https://" h.settings.dashboard.public_url;
  port = toString h.backend.port;
  rule =
    action: "iptables -w ${action} nixos-fw -p tcp -s 10.0.10.110 --dport ${port} -j nixos-fw-accept";
in
lib.optionalAttrs hostPlatform.isLinux {
  config = lib.mkIf config.homelab.agent.enable {
    homelab.routes.agent = {
      inherit host;
      backend = "http://${lan.address}:${port}";
      public = false;
      auth.gate = true;
    };

    homelab.access.agent = {
      members = [ "thijs" ];
      gate = true;
    };

    networking.firewall.extraCommands = rule "-A";
    networking.firewall.extraStopCommands = "${rule "-D"} || true";

    lodestar.links.agent = {
      title = "Hermes";
      group = "Apps";
      description = "AI agent (Discord bot)";
      url = "https://${host}";
    };
  };
}
