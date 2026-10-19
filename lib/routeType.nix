# The type of one front-door route: `homelab.routes.<name>` and the elements of
# `homelab.router.extraRoutes`. Used as `tools.routeType { inherit lib; }`.
{ lib }:
lib.types.submodule {
  options = {
    host = lib.mkOption {
      type = lib.types.str;
      example = "nextcloud.vanwaaij.com";
      description = "Fully qualified host name the route answers on.";
    };
    backend = lib.mkOption {
      type = lib.types.addCheck lib.types.str (
        b: lib.hasPrefix "http://" b || lib.hasPrefix "https://" b || b == "api@internal"
      );
      example = "http://10.0.10.100:8080";
      description = ''
        Where Traefik forwards to: an `http://` or `https://` URL, or the literal
        `api@internal` (Traefik's own dashboard).
      '';
    };
    public = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Whether the route is also reachable from the internet.";
    };
    tailnet = {
      enable = lib.mkOption {
        type = lib.types.bool;
        default = true;
        description = "Whether the route is published on the tailnet as a Tailscale Service.";
      };
      address = lib.mkOption {
        type = lib.types.nullOr lib.types.str;
        default = null;
        description = "The Tailscale Service IP, filled in after the Service exists.";
      };
    };
    basicAuth.usersFile = lib.mkOption {
      type = lib.types.nullOr lib.types.str;
      default = null;
      description = "Path to a file of htpasswd lines; null means no basic auth.";
    };
    middlewares = lib.mkOption {
      type = lib.types.attrsOf lib.types.anything;
      default = { };
      description = ''
        Traefik `http.middlewares` entries added for this route (named
        `<route>-<key>`) and attached to both of its routers, for whatever the
        fields above cannot express.
      '';
    };
  };
}
