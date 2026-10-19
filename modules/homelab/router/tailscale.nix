# The router's tailnet side: each tailnet route is published as a Tailscale Service
# (`svc:<servicePrefix><name>`, tcp:443 -> Traefik's tailnet entrypoint). The real
# router (no `servicePrefix`) also advertises the LAN subnet and acts as an exit node;
# a test router doesn't, so it never becomes the tailnet's subnet router. NixOS only.
{
  config,
  lib,
  hostPlatform,
  ...
}:
let
  cfg = config.homelab.router;

  published = lib.filterAttrs (
    name: r: r.tailnet.enable && (cfg.tailnetServices == null || lib.elem name cfg.tailnetServices)
  ) cfg.routes;

  # Only the real router; a test router sets a servicePrefix.
  advertise = cfg.servicePrefix == "";
in
lib.optionalAttrs hostPlatform.isLinux {
  config = lib.mkIf cfg.enable {
    services.tailscale = {
      # "server" turns on IP forwarding, needed for the subnet route and exit node.
      useRoutingFeatures = if advertise then "server" else "none";
      # `tailscale set` keeps flags it isn't given, so a test router clears them
      # explicitly instead of leaving them out.
      extraSetFlags =
        if advertise then
          [
            "--advertise-routes=10.0.10.0/24"
            "--advertise-exit-node"
          ]
        else
          [
            "--advertise-routes="
            "--advertise-exit-node=false"
          ];
      # The module adds the `svc:` prefix itself; it asserts `services` is non-empty.
      serve.enable = published != { };
      serve.services = lib.mapAttrs' (
        name: _:
        lib.nameValuePair "${cfg.servicePrefix}${name}" {
          endpoints."tcp:443" = "tcp://127.0.0.1:8443";
        }
      ) published;
    };

    # `serve set-config` fails while the node is logged out: retry until it's in.
    systemd.services.tailscale-serve = lib.mkIf config.services.tailscale.serve.enable {
      after = [
        "tailscaled.service"
        "tailscaled-autoconnect.service"
      ];
      serviceConfig = {
        Restart = "on-failure";
        RestartSec = "10s";
      };
      unitConfig.StartLimitIntervalSec = 0;
    };
  };
}
