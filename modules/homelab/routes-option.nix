# `homelab.routes.<name>`: front-door routes this configuration contributes. A plain
# data option (configures nothing), present on every host and collected flake-wide
# with `tools.routesFrom`; the router module turns the result into Traefik,
# Tailscale and DNS config.
{ lib, tools, ... }:
{
  options.homelab.routes = lib.mkOption {
    type = lib.types.attrsOf (tools.routeType { inherit lib; });
    default = { };
    description = "Routes the front-door router publishes for services on this configuration.";
  };
}
