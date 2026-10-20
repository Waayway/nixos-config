# The router's sign-in gate: oauth2-proxy (official image) on 127.0.0.1:4180, a
# client of Kanidm (`oauth2-proxy`, provisioned by modules/identity/kanidm.nix) on
# the identity host (`homelab.router.identityHost`). On only with
# `homelab.router.gate.enable` (by default: some route is gated); otherwise the router
# has no Docker, container or gate secrets. Routes with `auth.gate` ask it through
# Traefik's forwardAuth (`/?allowed_groups=<route>-users@<domain>`, default.nix),
# which also redirects to the sign-in; its own pages (callback) are the route named
# after the gate host (`auth`, `auth-test`). OIDC discovery and token calls go to the
# router's own Traefik (:443), which passes the identity host through to Kanidm. The
# session cookie is set on the parent domain (`.vanwaaij.com`, SameSite=Lax), so one
# sign-in covers every gated site, and `rd` redirects only within it. A test router
# (servicePrefix set) uses its own cookie name and 1Password items.
#
# The client secret (copied out of Kanidm by scripts/kanidm-oauth2-secret.sh) and the
# cookie secret come from 1Password (`kanidm-oauth2-oauth2-proxy[-test]`,
# `oauth2-proxy-cookie[-test]`); the container fails until both files exist and
# opnix starts it once they do. While
# it's down, gated routes fail closed (forwardAuth errors) and others are unaffected.
# NixOS only.
{
  config,
  lib,
  pkgs,
  hostPlatform,
  ...
}:
let
  cfg = config.homelab.router;
  id = cfg.identity;
  secrets = config.services.onepassword-secrets.secretPaths;

  image = "quay.io/oauth2-proxy/oauth2-proxy:v7.15.5@sha256:8498b0d0ef0a7b29686414000a08aee467f02d0299c9ed1e006a8f33fc017916";

  # A test router (servicePrefix set) uses its own 1Password items and cookie.
  suffix = lib.optionalString (cfg.servicePrefix != "") "-test";
  # "id.vanwaaij.com" -> "vanwaaij.com"
  parentDomain = lib.concatStringsSep "." (lib.tail (lib.splitString "." id.domain));

  # The container runs as this user, which owns the two secret files.
  uid = 4180;
in
lib.optionalAttrs hostPlatform.isLinux {
  config = lib.mkIf (cfg.enable && cfg.gate.enable) {
    homelab.containers.enable = true;

    users.users.oauth2-proxy = {
      isSystemUser = true;
      group = "oauth2-proxy";
      inherit uid;
    };
    users.groups.oauth2-proxy.gid = uid;

    services.onepassword-secrets.secrets = {
      oauth2ProxyClientSecret = {
        reference = "op://Homelab/kanidm-oauth2-oauth2-proxy${suffix}/credential";
        mode = "0400";
        owner = "oauth2-proxy";
        services = [ "docker-oauth2-proxy" ];
      };
      oauth2ProxyCookieSecret = {
        reference = "op://Homelab/oauth2-proxy-cookie${suffix}/credential";
        mode = "0400";
        owner = "oauth2-proxy";
        services = [ "docker-oauth2-proxy" ];
      };
    };

    virtualisation.oci-containers.containers.oauth2-proxy = {
      inherit image;
      user = "${toString uid}:${toString uid}";
      volumes = [
        "${secrets.oauth2ProxyClientSecret}:/secrets/client-secret:ro"
        "${secrets.oauth2ProxyCookieSecret}:/secrets/cookie-secret:ro"
      ];
      extraOptions = [
        # Listens on the host's loopback only (--http-address).
        "--network=host"
        # The router's own Traefik (:443), which passes the identity host's name
        # through to Kanidm; Kanidm itself listens on 8443 only.
        "--add-host=${id.domain}:127.0.0.1"
      ];
      cmd = [
        "--http-address=127.0.0.1:4180"
        "--provider=oidc"
        "--provider-display-name=${id.domain}"
        "--oidc-issuer-url=https://${id.domain}/oauth2/openid/oauth2-proxy"
        "--client-id=oauth2-proxy"
        "--client-secret-file=/secrets/client-secret"
        "--cookie-secret-file=/secrets/cookie-secret"
        "--code-challenge-method=S256"
        "--scope=openid email profile groups"
        "--oidc-groups-claim=groups"
        "--email-domain=*"
        "--redirect-url=https://${id.gateHost}/oauth2/callback"
        "--reverse-proxy=true"
        "--trusted-proxy-ip=127.0.0.1/32"
        "--set-xauthrequest=true"
        "--skip-provider-button=true"
        "--cookie-name=_oauth2_proxy${lib.replaceStrings [ "-" ] [ "_" ] suffix}"
        "--cookie-domain=.${parentDomain}"
        "--cookie-secure=true"
        "--cookie-samesite=lax"
        "--whitelist-domain=.${parentDomain}"
        # forwardAuth only; nothing is proxied.
        "--upstream=static://202"
      ]
      # A test Kanidm has a Let's Encrypt staging certificate.
      ++ lib.optional id.acmeStaging "--ssl-insecure-skip-verify=true";
    };

    # Without the files Docker would create directories in their place, so the unit
    # fails until opnix has written them. Failing (not a ConditionPathExists skip)
    # matters: opnix only try-restarts units on a secret change, a no-op for an
    # inactive unit, but starts *failed* ones after a successful run.
    systemd.services.docker-oauth2-proxy.serviceConfig.ExecStartPre = lib.mkBefore [
      "${pkgs.coreutils}/bin/test -f ${secrets.oauth2ProxyClientSecret} -a -f ${secrets.oauth2ProxyCookieSecret}"
    ];
  };
}
