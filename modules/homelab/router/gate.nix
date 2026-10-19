# The router's sign-in gate: oauth2-proxy (official image) on 127.0.0.1:4180, a
# client of Kanidm (`oauth2-proxy`, provisioned by modules/identity/kanidm.nix) on
# the identity host (`homelab.router.identityHost`). Routes with `auth.gate` ask it
# through Traefik's forwardAuth (`/oauth2/auth?allowed_groups=<route>-users@<domain>`,
# default.nix); its own pages (sign-in, callback) are the route named after the gate
# host (`auth`, `auth-test`; modules/homelab/routes.nix). The session cookie is set on
# the parent domain (`.vanwaaij.com`), so one sign-in covers every gated site, and
# `rd` redirects only within it. A test gate gets its own cookie name, so its cookie
# doesn't clash with the real one.
#
# The client secret (copied out of Kanidm by scripts/kanidm-oauth2-secret.sh) and the
# cookie secret come from 1Password (`kanidm-oauth2-oauth2-proxy[-test]`,
# `oauth2-proxy-cookie[-test]`); the container starts once both files exist. While
# it's down, gated routes fail closed (forwardAuth errors) and others are unaffected.
# NixOS only.
{
  config,
  lib,
  hostPlatform,
  ...
}:
let
  cfg = config.homelab.router;
  id = cfg.identity;
  secrets = config.services.onepassword-secrets.secretPaths;

  image = "quay.io/oauth2-proxy/oauth2-proxy:v7.15.5@sha256:8498b0d0ef0a7b29686414000a08aee467f02d0299c9ed1e006a8f33fc017916";

  # "id" -> "", "id-test" -> "-test": the 1Password items and cookie of a test gate.
  suffix = lib.removePrefix "id" (lib.head (lib.splitString "." id.domain));
  # "id.vanwaaij.com" -> "vanwaaij.com"
  parentDomain = lib.concatStringsSep "." (lib.tail (lib.splitString "." id.domain));

  # The container runs as this user, which owns the two secret files.
  uid = 4180;
in
lib.optionalAttrs hostPlatform.isLinux {
  config = lib.mkIf cfg.enable {
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
        # Straight to Kanidm, not through the router's own front door.
        "--add-host=${id.domain}:${id.address}"
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
        "--set-xauthrequest=true"
        "--skip-provider-button=true"
        "--cookie-name=_oauth2_proxy${lib.replaceStrings [ "-" ] [ "_" ] suffix}"
        "--cookie-domain=.${parentDomain}"
        "--cookie-secure=true"
        "--whitelist-domain=.${parentDomain}"
        # forwardAuth only; nothing is proxied.
        "--upstream=static://202"
      ]
      # A test Kanidm has a Let's Encrypt staging certificate.
      ++ lib.optional id.acmeStaging "--ssl-insecure-skip-verify=true";
    };

    # Without the files Docker would create directories in their place; wait for
    # opnix instead (it restarts the container once it has written them).
    systemd.services.docker-oauth2-proxy.unitConfig.ConditionPathExists = [
      secrets.oauth2ProxyClientSecret
      secrets.oauth2ProxyCookieSecret
    ];

    # The errors middleware's target (default.nix).
    services.traefik.dynamicConfigOptions.http.services.oauth2-proxy.loadBalancer.servers = [
      { url = "http://127.0.0.1:4180"; }
    ];
  };
}
