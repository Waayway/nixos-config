# Evaluation check of the router (modules/server/homelab/router/) on router-test, whose
# identity is its own test Kanidm (`id-test.vanwaaij.com`): the identity route (an
# HTTP route re-encrypted to Kanidm, checked against its name), a passthrough route, the sign-in gate (oauth2-proxy container, `auth-test` route) and a
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
  gate = cfg.virtualisation.oci-containers.containers.oauth2-proxy;
  has = lib.hasInfix;
  ok = v: (builtins.tryEval (builtins.deepSeq v v)).success;

  extend = m: (host.extendModules { modules = [ m ]; }).config;
  traefikOf = c: c.services.traefik.dynamicConfigOptions;
  failedAssertions = c: lib.filter (a: !a.assertion) c.assertions;

  # archipelago, traefik, truenas and backrest are gated (modules/server/homelab/routes.nix,
  # modules/server/backup/backrest.nix); basic auth can't be combined with the gate
  gateAndBasicAuth = extend {
    homelab.router.extraRoutes.archipelago.basicAuth.usersFile = "/run/htpasswd";
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
  passthrough = traefikOf (extend {
    homelab.router.extraRoutes.pt = {
      host = "pt.vanwaaij.com";
      passthrough = "10.0.10.9:443";
    };
  });
  gatedPassthrough = extend {
    homelab.router.extraRoutes.pt = {
      host = "pt.vanwaaij.com";
      passthrough = "10.0.10.9:443";
      auth.gate = true;
    };
  };
  serverNameOnHttp = extend {
    homelab.router.extraRoutes.plain = {
      host = "plain.vanwaaij.com";
      backend = "http://10.0.10.9:80";
      backendServerName = "plain.vanwaaij.com";
    };
  };
in
# the identity route: an HTTP route on both entrypoints, re-encrypted to Kanidm and
# checked against its name (staging certificate here, so not verified)
assert http.routers.id-test-public.rule == "Host(`id-test.vanwaaij.com`)";
assert http.routers.id-test-tailnet.entryPoints == [ "tailnet" ];
assert
  http.services.id-test.loadBalancer == {
    servers = [ { url = "https://10.0.10.230:8443"; } ];
    serversTransport = "id-test-backend";
  };
assert
  http.serversTransports.id-test-backend == {
    serverName = "id-test.vanwaaij.com";
    insecureSkipVerify = true;
  };
# no passthrough route left: no tcp section (Traefik rejects an empty `[tcp.routers]`)
assert !(dyn ? tcp);
# a passthrough route: TCP routers on the host's SNI
assert
  passthrough.tcp.routers.pt-public == {
    rule = "HostSNI(`pt.vanwaaij.com`)";
    entryPoints = [ "public" ];
    service = "pt";
    tls.passthrough = true;
  };
assert passthrough.tcp.routers.pt-tailnet.tls.passthrough;
assert passthrough.tcp.services.pt.loadBalancer.servers == [ { address = "10.0.10.9:443"; } ];
assert !(passthrough.http.routers ? pt-public);
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
# gated on router-test: the echo route plus archipelago, traefik, truenas and
# backrest; the other routes are unchanged
assert
  lib.attrNames (lib.filterAttrs (_: r: lib.any (lib.hasSuffix "-gate") r.middlewares) http.routers)
  == [
    "archipelago-public"
    "archipelago-tailnet"
    "backrest-tailnet"
    "traefik-tailnet"
    "truenas-tailnet"
    "whoami-test-public"
    "whoami-test-tailnet"
  ];
assert http.routers.whoami-test-public.middlewares == [ "whoami-test-gate" ];
assert http.routers.whoami-test-public.rule == "Host(`whoami-test.vanwaaij.com`)";
assert
  http.routers.nextcloud-public.middlewares == [
    "nextcloud-caldav"
    "nextcloud-headers"
  ];
# Lodestar (nixos-manager): public and on the tailnet, not gated (it logs in itself)
assert http.services.lodestar.loadBalancer.servers == [ { url = "http://10.0.10.170:8081"; } ];
assert http.routers.lodestar-public.rule == "Host(`lodestar.vanwaaij.com`)";
assert http.routers ? lodestar-tailnet;
assert !(lib.any (lib.hasSuffix "-gate") http.routers.lodestar-public.middlewares);
assert !(lib.any (lib.hasSuffix "-gate") http.routers.lodestar-tailnet.middlewares);
assert cfg.homelab.router.routes.lodestar.tailnet.enable;
# Archipelago's basic auth is gone
assert !(http.middlewares ? archipelago-auth);
assert !(cfg.services.onepassword-secrets.secrets ? archipelagoBasicAuth);
# a gated route: forwardAuth on oauth2-proxy's proxy endpoint (it redirects to the
# sign-in itself), with the per-route group check; no errors middleware, so a 401
# from the backend reaches the client untouched
assert http.routers.archipelago-public.middlewares == [ "archipelago-gate" ];
assert http.routers.archipelago-tailnet.middlewares == http.routers.archipelago-public.middlewares;
assert
  http.middlewares.archipelago-gate.forwardAuth == {
    address = "http://127.0.0.1:4180/?allowed_groups=archipelago-users@id-test.vanwaaij.com";
    authResponseHeaders = [
      "X-Auth-Request-User"
      "X-Auth-Request-Email"
    ];
    # also strips client-sent X-Auth-Request-* headers
    authResponseHeadersRegex = "^X-Auth-Request-";
  };
assert lib.all (m: !(m ? errors)) (lib.attrValues http.middlewares);
assert failedAssertions gateAndBasicAuth != [ ];
# a gated route without (gate) access fails evaluation; so do malformed routes
assert !ok noAccess.http;
assert !ok notGateAccess.http;
assert failedAssertions both != [ ];
assert failedAssertions neither != [ ];
assert failedAssertions gatedPassthrough != [ ];
assert failedAssertions serverNameOnHttp != [ ];
assert failedAssertions cfg == [ ];
# oauth2-proxy: official image, pinned, loopback only, secrets from files
assert lib.hasPrefix "quay.io/oauth2-proxy/oauth2-proxy:v7." gate.image;
assert has "@sha256:" gate.image;
# the container fails (so opnix starts it later) rather than being skipped while
# the secret files are missing
assert has "test -f /var/lib/opnix/secrets/oauth2ProxyClientSecret" (
  lib.head cfg.systemd.services.docker-oauth2-proxy.serviceConfig.ExecStartPre
);
assert !(cfg.systemd.services.docker-oauth2-proxy.unitConfig ? ConditionPathExists);
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
  "--trusted-proxy-ip=127.0.0.1/32"
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
assert cfg.homelab.router.gate.enable;
# the real router: the gate is on by itself (gated routes); production identity, no
# insecure skip, plain cookie name, the same four routes gated
assert
  let
    prod = nixosConfigurations.router.config;
    c = prod.virtualisation.oci-containers.containers.oauth2-proxy;
    p = prod.services.traefik.dynamicConfigOptions;
  in
  prod.homelab.router.gate.enable
  &&
    p.http.services.id.loadBalancer == {
      servers = [ { url = "https://10.0.10.111:8443"; } ];
      serversTransport = "id-backend";
    }
  && p.http.serversTransports.id-backend == { serverName = "id.vanwaaij.com"; }
  && p.http.services.auth.loadBalancer.servers == [ { url = "http://127.0.0.1:4180"; } ]
  && lib.elem "--add-host=id.vanwaaij.com:127.0.0.1" c.extraOptions
  && lib.elem "--oidc-issuer-url=https://id.vanwaaij.com/oauth2/openid/oauth2-proxy" c.cmd
  && lib.elem "--cookie-name=_oauth2_proxy" c.cmd
  && !(lib.elem "--ssl-insecure-skip-verify=true" c.cmd)
  &&
    prod.services.onepassword-secrets.secrets.oauth2ProxyClientSecret.reference
    == "op://Homelab/kanidm-oauth2-oauth2-proxy/credential"
  && prod.virtualisation.docker.enable
  && !(prod.services.onepassword-secrets.secrets ? archipelagoBasicAuth)
  &&
    lib.attrNames (lib.filterAttrs (_: r: lib.any (lib.hasSuffix "-gate") r.middlewares) p.http.routers)
    == [
      "archipelago-public"
      "archipelago-tailnet"
      "backrest-tailnet"
      "traefik-tailnet"
      "truenas-tailnet"
    ]
  &&
    p.http.middlewares.truenas-gate.forwardAuth.address
    == "http://127.0.0.1:4180/?allowed_groups=truenas-users@id.vanwaaij.com";
pkgs.runCommand "router" { } "touch $out"
