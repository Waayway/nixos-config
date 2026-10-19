# Front-door routes for backends this flake doesn't manage yet (Rocky/Debian VMs),
# ported from Main's Traefik (~/traefik/dynamic/*.yml and Nextcloud's Docker labels).
# When a backend moves to NixOS, its route moves to that service's module as
# `homelab.routes.<name>`. Immich and BlueMap aren't routed (dead today).
{
  config,
  lib,
  hostPlatform,
  ...
}:
lib.optionalAttrs hostPlatform.isLinux {
  config = lib.mkIf config.homelab.router.enable {
    homelab.router.extraRoutes = {
      nextcloud = {
        tailnet.address = "100.76.170.121";
        host = "nextcloud.vanwaaij.com";
        backend = "http://10.0.10.100:8080";
        # Main's `nextcloud-chain`: CalDAV/CardDAV redirect, then security headers.
        middlewares = {
          caldav.redirectRegex = {
            permanent = true;
            regex = "^https://(.*)/.well-known/ca(l|rd)dav";
            replacement = "https://$1/remote.php/dav/";
          };
          headers.headers = {
            stsSeconds = 31536000;
            stsIncludeSubdomains = true;
            stsPreload = true;
            forceSTSHeader = true;
            customFrameOptionsValue = "SAMEORIGIN";
            contentTypeNosniff = true;
            browserXssFilter = true;
            referrerPolicy = "same-origin";
          };
        };
      };

      jellyfin = {
        tailnet.address = "100.84.78.44";
        host = "jellyfin.vanwaaij.com";
        backend = "http://10.0.10.120:8096";
      };

      archipelago = {
        tailnet.address = "100.101.152.250";
        host = "ap.vanwaaij.com";
        backend = "http://10.0.10.201:8080";
        basicAuth.usersFile = config.services.onepassword-secrets.secretPaths.archipelagoBasicAuth;
      };

      # The dashboard, tailnet only.
      traefik = {
        tailnet.address = "100.113.51.101";
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
