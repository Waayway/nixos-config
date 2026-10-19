# The router's tailnet side: each tailnet route is published as a Tailscale Service
# (`svc:<servicePrefix><name>`, tcp:443 -> Traefik's tailnet entrypoint), and the
# machine advertises the LAN subnet and acts as an exit node. NixOS only.
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
in
lib.optionalAttrs hostPlatform.isLinux {
  config = lib.mkIf cfg.enable {
    services.tailscale = {
      # "server" turns on IP forwarding, needed for the subnet route and exit node.
      useRoutingFeatures = "server";
      extraSetFlags = [
        "--advertise-routes=10.0.10.0/24"
        "--advertise-exit-node"
      ];
      # The module adds the `svc:` prefix itself.
      serve.services = lib.mapAttrs' (
        name: _:
        lib.nameValuePair "${cfg.servicePrefix}${name}" {
          endpoints."tcp:443" = "tcp://127.0.0.1:8443";
        }
      ) published;
    };

    warnings = lib.mapAttrsToList (
      name: _:
      "homelab.router: tailnet route `${name}` has no tailnet.address, so split DNS can't resolve it yet"
    ) (lib.filterAttrs (_: r: r.tailnet.address == null) published);
  };
}
