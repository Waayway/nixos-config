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
      type = lib.types.nullOr (
        lib.types.addCheck lib.types.str (
          b: lib.hasPrefix "http://" b || lib.hasPrefix "https://" b || b == "api@internal"
        )
      );
      default = null;
      example = "http://10.0.10.100:8080";
      description = ''
        Where Traefik forwards to: an `http://` or `https://` URL, or the literal
        `api@internal` (Traefik's own dashboard). Exactly one of `backend` and
        `passthrough` is set.
      '';
    };
    passthrough = lib.mkOption {
      type = lib.types.nullOr lib.types.str;
      default = null;
      example = "10.0.10.111:8443";
      description = ''
        `host:port` to pass the TLS connection to unopened (a TCP router on the
        host's SNI): the backend serves its own certificate. No HTTP middlewares,
        maintenance page, basic auth or gate apply.
      '';
    };
    insecureBackend = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = "Don't verify the certificate of an `https://` backend (self-signed appliances).";
    };
    backendServerName = lib.mkOption {
      type = lib.types.nullOr lib.types.str;
      default = null;
      example = "id.vanwaaij.com";
      description = ''
        Name an `https://` backend given by address is checked against (and sent as
        SNI): the name on its certificate. Null uses the backend URL's host.
      '';
    };
    auth.gate = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = ''
        Put the router's sign-in gate (oauth2-proxy) in front of the route: only
        members of `<route>-users` in Kanidm get through. The route's name must be an
        app in `homelab.identity.access` with `gate = true`, or evaluation fails.
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
    };
    maintenance = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = ''
        Serve the maintenance page (HTTP 503) on the route's public router instead
        of the app; the tailnet router keeps going to the app.
      '';
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
