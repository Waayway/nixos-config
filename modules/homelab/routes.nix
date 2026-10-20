# Front-door routes for backends this flake doesn't manage yet (Rocky/Debian VMs),
# ported from Main's Traefik (~/traefik/dynamic/*.yml and Nextcloud's Docker labels).
# When a backend moves to NixOS, its route moves to that service's module as
# `homelab.routes.<name>` (Nextcloud, Jellyfin, Immich: modules/services/). BlueMap
# isn't routed (dead today).
#
# Also the identity route, named after its host's first label (`id`, on router-test
# `id-test`): Kanidm, passed through as TLS (it serves its own certificate). The
# sign-in gate's route (`auth`) comes with the gate (modules/homelab/router/default.nix).
#
# Archipelago, TrueNAS and the Traefik dashboard sit behind the sign-in gate
# (`auth.gate`; their access is in modules/identity/access.nix). TrueNAS still has its
# own login behind it. Rollback per site: `auth.gate = false` (Archipelago: plus
# `basicAuth.usersFile` from the 1Password item `archipelago-basic-auth`, field
# `htpasswd`, which is kept).
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
        auth.gate = true;
      };

      archipelago = {
        host = "ap.vanwaaij.com";
        backend = "http://10.0.10.201:8080";
        auth.gate = true;
      };

      # The dashboard, tailnet only.
      traefik = {
        host = "traefik.vanwaaij.com";
        backend = "api@internal";
        public = false;
        auth.gate = true;
      };
    };
  };
}
