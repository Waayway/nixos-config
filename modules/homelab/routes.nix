# Front-door routes for backends this flake doesn't manage yet (Rocky/Debian VMs),
# ported from Main's Traefik (~/traefik/dynamic/*.yml and Nextcloud's Docker labels).
# When a backend moves to NixOS, its route moves to that service's module as
# `homelab.routes.<name>` (Nextcloud, Jellyfin, Immich: modules/services/). BlueMap
# isn't routed (dead today).
#
# Also the identity route, named after its host's first label (`id`, on router-test
# `id-test`): Kanidm, passed through as TLS (it serves its own certificate). The
# sign-in gate's route (`auth`) comes with the gate (modules/homelab/router/default.nix).
{
  config,
  lib,
  hostPlatform,
  ...
}:
let
  id = config.homelab.router.identity;
  label = host: lib.head (lib.splitString "." host);
in
lib.optionalAttrs hostPlatform.isLinux {
  config = lib.mkIf config.homelab.router.enable {
    homelab.router.extraRoutes = {
      ${label id.domain} = {
        host = id.domain;
        passthrough = "${id.address}:8443";
      };

      # Self-signed certificate on the appliance; tailnet only.
      truenas = {
        host = "truenas.vanwaaij.com";
        backend = "https://10.0.10.130";
        insecureBackend = true;
        public = false;
      };

      archipelago = {
        host = "ap.vanwaaij.com";
        backend = "http://10.0.10.201:8080";
        basicAuth.usersFile = config.services.onepassword-secrets.secretPaths.archipelagoBasicAuth;
      };

      # The dashboard, tailnet only.
      traefik = {
        host = "traefik.vanwaaij.com";
        backend = "api@internal";
        public = false;
      };
    };

    services.onepassword-secrets.secrets.archipelagoBasicAuth = {
      reference = "op://Homelab/archipelago-basic-auth/htpasswd";
      mode = "0400";
      owner = "traefik";
      services = [ "traefik" ];
    };
  };
}
