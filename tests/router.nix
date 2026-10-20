# Evaluation check of the router (modules/homelab/router/) on router-test, whose
# identity is its own test Kanidm (`id-test.vanwaaij.com`): the identity route passed
# through as TCP, the sign-in gate (oauth2-proxy container, `auth-test` route) and a
# gated route's middlewares, tailnet-only routes with an insecure backend, and
# evaluation failing for a gated route without an access entry and for a route with
# both a backend and a passthrough.
{
  pkgs,
  lib,
  nixosConfigurations,
}:
let
  host = nixosConfigurations.router-test;
  cfg = host.config;
  dyn = cfg.services.traefik.dynamicConfigOptions;
  http = dyn.http;
  tcp = dyn.tcp;
  gate = cfg.virtualisation.oci-containers.containers.oauth2-proxy;
  has = lib.hasInfix;
  ok = v: (builtins.tryEval (builtins.deepSeq v v)).success;

  extend = m: (host.extendModules { modules = [ m ]; }).config;
  traefikOf = c: c.services.traefik.dynamicConfigOptions;
  failedAssertions = c: lib.filter (a: !a.assertion) c.assertions;

  # archipelago has an access entry with gate = true (modules/identity/access.nix)
  # (and drop its basic auth, which can't be combined with the gate)
  gateArchipelago = {
    homelab.router.extraRoutes.archipelago = {
      auth.gate = true;
      basicAuth.usersFile = lib.mkForce null;
    };
  };
  gated = traefikOf (extend gateArchipelago);
  gateAndBasicAuth = extend {
    homelab.router.extraRoutes.archipelago.auth.gate = true;
  };
  # no access entry at all
  noAccess = traefikOf (extend {
    homelab.router.extraRoutes.wiki = {
      host = "wiki.vanwaaij.com";
      backend = "http://10.0.10.9:80";
      auth.gate = true;
    };
  });
  # an access entry, but not behind the gate (proxmox signs in with OIDC)
  notGateAccess = traefikOf (extend {
    homelab.router.extraRoutes.proxmox = {
      host = "pve.vanwaaij.com";
      backend = "https://10.0.10.50:8006";
      auth.gate = true;
    };
  });
  both = extend {
    homelab.router.extraRoutes.both = {
      host = "both.vanwaaij.com";
      backend = "http://10.0.10.9:80";
      passthrough = "10.0.10.9:443";
    };
  };
  neither = extend {
    homelab.router.extraRoutes.neither.host = "neither.vanwaaij.com";
  };
  gatedPassthrough = extend {
    homelab.router.extraRoutes.id-test.auth.gate = true;
  };
in
# the identity route: TLS passthrough to Kanidm on both entrypoints
assert
  tcp.routers.id-test-public == {
    rule = "HostSNI(`id-test.vanwaaij.com`)";
    entryPoints = [ "public" ];
    service = "id-test";
    tls.passthrough = true;
  };
assert tcp.routers.id-test-tailnet.entryPoints == [ "tailnet" ];
assert tcp.routers.id-test-tailnet.tls.passthrough;
assert tcp.services.id-test.loadBalancer.servers == [ { address = "10.0.10.230:8443"; } ];
assert !(http.routers ? id-test-public);
assert !(http.services ? id-test);
# the gate's own route
assert http.routers.auth-test-public.rule == "Host(`auth-test.vanwaaij.com`)";
assert http.routers.auth-test-public.middlewares == [ ];
assert http.services.auth-test.loadBalancer.servers == [ { url = "http://127.0.0.1:4180"; } ];
# tailnet-only routes; TrueNAS's self-signed backend
assert !(http.routers ? truenas-public);
assert http.routers.truenas-tailnet.rule == "Host(`truenas.vanwaaij.com`)";
assert
  http.services.truenas == {
    loadBalancer = {
      servers = [ { url = "https://10.0.10.130"; } ];
      serversTransport = "insecure-backend";
    };
  };
assert http.serversTransports.insecure-backend.insecureSkipVerify;
assert !(http.routers ? backrest-public);
assert http.services.backrest.loadBalancer.servers == [ { url = "http://100.92.102.84:9898"; } ];
assert !(http.services.backrest.loadBalancer ? serversTransport);
# only the echo route is gated on router-test; the other routes are unchanged
assert
  lib.attrNames (lib.filterAttrs (_: r: lib.any (lib.hasSuffix "-gate") r.middlewares) http.routers)
  == [
    "whoami-test-public"
    "whoami-test-tailnet"
  ];
assert http.routers.whoami-test-public.middlewares == [ "whoami-test-gate" ];
assert http.routers.whoami-test-public.rule == "Host(`whoami-test.vanwaaij.com`)";
assert http.routers.archipelago-public.middlewares == [ "archipelago-auth" ];
# a gated route: forwardAuth on oauth2-proxy's proxy endpoint (it redirects to the
# sign-in itself), with the per-route group check; no errors middleware, so a 401
# from the backend reaches the client untouched
assert gated.http.routers.archipelago-public.middlewares == [ "archipelago-gate" ];
assert
  gated.http.routers.archipelago-tailnet.middlewares
  == gated.http.routers.archipelago-public.middlewares;
assert
  gated.http.middlewares.archipelago-gate.forwardAuth == {
    address = "http://127.0.0.1:4180/?allowed_groups=archipelago-users@id-test.vanwaaij.com";
    authResponseHeaders = [
      "X-Auth-Request-User"
      "X-Auth-Request-Email"
    ];
    # also strips client-sent X-Auth-Request-* headers
    authResponseHeadersRegex = "^X-Auth-Request-";
  };
assert lib.all (m: !(m ? errors)) (lib.attrValues gated.http.middlewares);
assert failedAssertions gateAndBasicAuth != [ ];
# a gated route without (gate) access fails evaluation; so do malformed routes
assert !ok noAccess.http;
assert !ok notGateAccess.http;
assert failedAssertions both != [ ];
assert failedAssertions neither != [ ];
assert failedAssertions gatedPassthrough != [ ];
assert failedAssertions cfg == [ ];
# oauth2-proxy: official image, pinned, loopback only, secrets from files
assert lib.hasPrefix "quay.io/oauth2-proxy/oauth2-proxy:v7." gate.image;
assert has "@sha256:" gate.image;
assert lib.elem "--network=host" gate.extraOptions;
assert lib.elem "--add-host=id-test.vanwaaij.com:127.0.0.1" gate.extraOptions;
assert lib.all (f: lib.elem f gate.cmd) [
  "--http-address=127.0.0.1:4180"
  "--provider=oidc"
  "--oidc-issuer-url=https://id-test.vanwaaij.com/oauth2/openid/oauth2-proxy"
  "--client-id=oauth2-proxy"
  "--client-secret-file=/secrets/client-secret"
  "--cookie-secret-file=/secrets/cookie-secret"
  "--code-challenge-method=S256"
  "--redirect-url=https://auth-test.vanwaaij.com/oauth2/callback"
  "--reverse-proxy=true"
  "--set-xauthrequest=true"
  "--cookie-domain=.vanwaaij.com"
  "--whitelist-domain=.vanwaaij.com"
  "--oidc-groups-claim=groups"
  "--cookie-name=_oauth2_proxy_test"
  "--cookie-samesite=lax"
];
# test Kanidm has a staging certificate
assert lib.elem "--ssl-insecure-skip-verify=true" gate.cmd;
assert
  cfg.services.onepassword-secrets.secrets.oauth2ProxyClientSecret.reference
  == "op://Homelab/kanidm-oauth2-oauth2-proxy-test/credential";
assert
  cfg.services.onepassword-secrets.secrets.oauth2ProxyCookieSecret.reference
  == "op://Homelab/oauth2-proxy-cookie-test/credential";
assert cfg.virtualisation.docker.enable;
# router-test turns the gate on explicitly (no gated route yet)
assert cfg.homelab.router.gate.enable;
# the real router without gated routes: the identity route, but no gate, no Docker,
# no gate secrets, no auth route
assert
  let
    prod = nixosConfigurations.router.config;
    p = prod.services.traefik.dynamicConfigOptions;
  in
  !prod.homelab.router.gate.enable
  && p.tcp.services.id.loadBalancer.servers == [ { address = "10.0.10.111:8443"; } ]
  && !(prod.virtualisation.oci-containers.containers ? oauth2-proxy)
  && !prod.virtualisation.docker.enable
  && !(prod.services.onepassword-secrets.secrets ? oauth2ProxyClientSecret)
  && !(prod.services.onepassword-secrets.secrets ? oauth2ProxyCookieSecret)
  && !(p.http.routers ? auth-public)
  && !(prod.services.tailscale.serve.services ? auth);
# the real router once a route is gated: the gate turns on by itself; production
# identity, no insecure skip, plain cookie name
assert
  let
    prod = (nixosConfigurations.router.extendModules { modules = [ gateArchipelago ]; }).config;
    c = prod.virtualisation.oci-containers.containers.oauth2-proxy;
    p = prod.services.traefik.dynamicConfigOptions;
  in
  prod.homelab.router.gate.enable
  && p.tcp.services.id.loadBalancer.servers == [ { address = "10.0.10.111:8443"; } ]
  && p.http.services.auth.loadBalancer.servers == [ { url = "http://127.0.0.1:4180"; } ]
  && lib.elem "--add-host=id.vanwaaij.com:127.0.0.1" c.extraOptions
  && lib.elem "--oidc-issuer-url=https://id.vanwaaij.com/oauth2/openid/oauth2-proxy" c.cmd
  && lib.elem "--cookie-name=_oauth2_proxy" c.cmd
  && !(lib.elem "--ssl-insecure-skip-verify=true" c.cmd)
  &&
    prod.services.onepassword-secrets.secrets.oauth2ProxyClientSecret.reference
    == "op://Homelab/kanidm-oauth2-oauth2-proxy/credential";
pkgs.runCommand "router" { } "touch $out"
