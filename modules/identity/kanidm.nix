{
  config,
  lib,
  pkgs,
  tools,
  inputs,
  hostPlatform,
  ...
}:
# Kanidm (`homelab.identity`) from its official image, kanidm/server, with the
# homelab's branding: override.css mounted over the image's /hpkg/override.css, and
# the display name and logo set through the CLI (kanidm/tools image).
#
# Who exists and who may use what is Nix: `homelab.people` and every configuration's
# `homelab.access` (collected with `tools.accessFrom`) plus `extraAccess` (apps outside
# NixOS, modules/identity/access.nix) are rendered into a kanidm-provision state
# (`provisionState`): every person, a group `admins` and a group `<app>-users` per
# app, an OAuth2 client per app with `oidc`, and `oauth2-proxy` (the router's sign-in
# gate) whose scope maps admit every gated app's group. `kanidm-provision` applies it
# after every start of the container and on every change; `--no-auto-remove`, so
# what exists only in Kanidm is never deleted. Two consequences: the members of
# `admins` and every `<app>-users` group are overwritten from Nix on every run
# (kanidm-provision's `overwriteMembers` default; members added in Kanidm by hand are
# removed), and an app removed from access keeps its group, OAuth2 client and scope
# map in Kanidm until deleted there by hand.
#
# No admin password is stored anywhere: each run gets a fresh one from the container
# (`kanidmd scripting recover-account`, over its admin socket) and passes it on in
# kanidm-provision's environment or on the tools container's stdin only. Break-glass
# is the same command on the host. Kanidm generates the OAuth2 client secrets (the
# official image can't take provisioned ones); scripts/kanidm-oauth2-secret.sh
# copies one into 1Password with `kanidm-oauth2-basic-secret` (installed here).
#
# Provisioning talks to the LAN address with `--accept-invalid-certs`: the traffic
# never leaves the host, and on a test VM the certificate is from Let's Encrypt
# staging (untrusted). Data: /var/lib/identity/kanidm; online backups (daily, 7
# kept) to /store/kanidm. Upgrades go one minor at a time (renovate.json).
let
  cfg = config.homelab.identity;
  lan = config.homelab.lan;
  docker = lib.getExe config.virtualisation.docker.package;
  accessType = tools.accessType { inherit lib; };

  serverImage = "kanidm/server:1.11.2@sha256:e45f00bd354c1fc1c06a4be484b4e87b094c431e78280f1d19e911815e63efb5";
  toolsImage = "kanidm/tools:1.11.2@sha256:144783fc589ac9611f6149f54f95d0d9472c1bf6078e7ed5781be441bcca7d24";

  dataDir = "/var/lib/identity/kanidm";
  backupDir = "/store/kanidm";
  certDir = "/var/lib/acme/${cfg.domain}";
  url = "https://${lan.address}:8443";
  defaultScopes = [
    "openid"
    "email"
    "profile"
    "groups"
  ];

  # --- access: the flake's plus extraAccess -----------------------------------
  # This configuration's own access from this evaluation (so it holds under
  # extendModules too), every other one's from the flake.
  fromFlake = tools.accessFrom { inherit lib; } {
    nixosConfigurations = inputs.self.nixosConfigurations // {
      ${config.networking.hostName} = { inherit config; };
    };
  };
  extra = lib.mapAttrs (_: a: a // { declaredBy = "homelab.identity.extraAccess"; }) cfg.extraAccess;
  overlap = lib.attrNames (lib.intersectAttrs fromFlake extra);
  unknownExtra = lib.filterAttrs (_: ms: ms != [ ]) (
    lib.mapAttrs (_: a: lib.filter (m: !(config.homelab.people ? ${m})) a.members) cfg.extraAccess
  );
  access =
    assert lib.assertMsg (overlap == [ ])
      "homelab.identity: apps in both homelab.access and homelab.identity.extraAccess: ${toString overlap}";
    assert lib.assertMsg (unknownExtra == { })
      "homelab.identity.extraAccess: members missing from homelab.people: ${
        lib.concatStringsSep "; " (
          lib.mapAttrsToList (n: ms: "app '${n}' lists ${toString ms}") unknownExtra
        )
      }";
    assert lib.assertMsg (
      !(access' ? oauth2-proxy)
    ) "homelab.identity: `oauth2-proxy` is the sign-in gate's client; rename the app";
    access';
  access' = fromFlake // extra;

  # --- the kanidm-provision state (github.com/oddlama/kanidm-provision#json-schema)
  title = s: lib.toUpper (lib.substring 0 1 s) + lib.substring 1 (-1) s;
  # Kanidm stores an origin without a path with a trailing slash; kanidm-provision
  # compares strings, so without it every run would "update" the origin again.
  withSlash = u: if builtins.match "[a-z]+://[^/]+" u != null then u + "/" else u;
  people = config.homelab.people;
  provisionState = {
    persons = lib.mapAttrs (_: p: {
      inherit (p) displayName;
      mailAddresses = [ p.email ];
    }) people;

    groups = {
      admins.members = lib.attrNames (lib.filterAttrs (_: p: p.admin) people);
    }
    // lib.mapAttrs' (app: a: lib.nameValuePair "${app}-users" { inherit (a) members; }) access;

    systems.oauth2 =
      lib.mapAttrs (app: a: {
        displayName = title app;
        originUrl = map withSlash a.oidc.originUrls;
        originLanding = withSlash a.oidc.originLanding;
        scopeMaps."${app}-users" = a.oidc.scopes;
      }) (lib.filterAttrs (_: a: a.oidc != null) access)
      // {
        oauth2-proxy = {
          displayName = "Sign-in gate";
          originUrl = [ "https://${cfg.gateHost}/oauth2/callback" ];
          originLanding = "https://${cfg.gateHost}/";
          scopeMaps = lib.mapAttrs' (app: _: lib.nameValuePair "${app}-users" defaultScopes) (
            lib.filterAttrs (_: a: a.gate) access
          );
        };
      };
  };
  stateFile = pkgs.writeText "kanidm-provision-state.json" (builtins.toJSON provisionState);

  # --- server.toml ------------------------------------------------------------
  serverSettings = {
    version = "2";
    bindaddress = "[::]:8443";
    db_path = "/data/kanidm.db";
    inherit (cfg) domain;
    origin = "https://${cfg.domain}";
    tls_chain = "${certDir}/fullchain.pem";
    tls_key = "${certDir}/key.pem";
    online_backup = {
      path = "/backup";
      schedule = "00 22 * * *";
      versions = 7;
    };
  };
  serverToml = (pkgs.formats.toml { }).generate "kanidm-server.toml" serverSettings;

  # --- shared shell -----------------------------------------------------------
  # Wait until the server answers (the container's unit is up before kanidmd is).
  waitForKanidm = ''
    for i in $(seq 1 60); do
      if curl --silent --fail --insecure --max-time 2 ${url}/status >/dev/null; then
        break
      fi
      if [ "$i" -eq 60 ]; then
        echo "Kanidm did not answer on ${url} within two minutes" >&2
        exit 1
      fi
      sleep 2
    done
  '';
  # `recover <account>`: a fresh password for a builtin account, on stdout (capture
  # it, never print it). The scripting interface prints one JSON line
  # {"status":"ok","output":"<password>"}.
  recoverFn = ''
    recover() {
      local out pw
      out=$(docker exec kanidm /sbin/kanidmd scripting recover-account -c /data/server.toml "$1")
      pw=$(jq -rR 'fromjson? | select(.status? == "ok") | .output' <<<"$out" | head -n 1)
      if [ -z "$pw" ]; then
        echo "kanidm: could not recover $1" >&2
        return 1
      fi
      printf '%s' "$pw"
    }
  '';
  # `toolsRun <script>`: a shell command running <script> in the tools image against
  # the server. The caller pipes in two lines, idm_admin's and admin's password (the
  # second may be empty); the container reads them into IDM_ADMIN_PASSWORD and
  # ADMIN_PASSWORD from stdin, so they are never on a command line or in the
  # container's environment (`docker inspect`).
  toolsRun = script: ''
    docker run -i --rm --network host \
      -e KANIDM_URL=${url} -e KANIDM_ACCEPT_INVALID_CERTS=true \
      -v ${./branding/logo.svg}:/branding/logo.svg:ro \
      --entrypoint /bin/sh ${toolsImage} -euc ${
        lib.escapeShellArg (
          ''
            IFS= read -r IDM_ADMIN_PASSWORD
            IFS= read -r ADMIN_PASSWORD || true
          ''
          + script
        )
      }'';
  shellPath = [
    config.virtualisation.docker.package
    pkgs.curl
    pkgs.jq
    pkgs.coreutils
  ];

  policyScript = ''
    KANIDM_PASSWORD="$IDM_ADMIN_PASSWORD" kanidm login -D idm_admin >/dev/null
    kanidm group account-policy credential-type-minimum idm_all_persons mfa -D idm_admin
    kanidm group account-policy enable admins -D idm_admin
    kanidm group account-policy credential-type-minimum admins passkey -D idm_admin
    KANIDM_PASSWORD="$ADMIN_PASSWORD" kanidm login -D admin >/dev/null
    kanidm system domain set-displayname ${lib.escapeShellArg cfg.displayName} -D admin
    kanidm system domain set-image /branding/logo.svg -D admin
  '';

  # On the host, for scripts/kanidm-oauth2-secret.sh: prints one OAuth2 client's
  # basic secret (stdout only, for a pipe).
  basicSecret = pkgs.writeShellApplication {
    name = "kanidm-oauth2-basic-secret";
    runtimeInputs = shellPath;
    text = ''
      if [ "$#" -ne 1 ]; then
        echo "usage: kanidm-oauth2-basic-secret <client>" >&2
        exit 2
      fi
      ${recoverFn}
      IDM_ADMIN_PASSWORD=$(recover idm_admin)
      # shellcheck disable=SC2016 # expanded in the container
      printf '%s\n\n' "$IDM_ADMIN_PASSWORD" | ${toolsRun ''
        KANIDM_PASSWORD="$IDM_ADMIN_PASSWORD" kanidm login -D idm_admin >/dev/null
        kanidm system oauth2 show-basic-secret "$1" -D idm_admin
      ''} sh "$1"
    '';
  };
in
lib.optionalAttrs hostPlatform.isLinux {
  options.homelab.identity = {
    enable = lib.mkEnableOption "Kanidm (official image), provisioned from Nix";

    domain = lib.mkOption {
      type = lib.types.str;
      example = "id.vanwaaij.com";
      description = "Kanidm's domain; the origin is https://<domain>. Permanent once users exist.";
    };

    acmeStaging = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = "Get the certificate from Let's Encrypt staging (untrusted, no rate limits).";
    };

    displayName = lib.mkOption {
      type = lib.types.str;
      default = "vanwaaij.com";
      description = "The name shown on the login page and in the apps list.";
    };

    gateHost = lib.mkOption {
      type = lib.types.str;
      default =
        let
          m = builtins.match "id(-[^.]+)?\\.(.+)" cfg.domain;
        in
        if m == null then
          "auth.${cfg.domain}"
        else
          "auth${lib.optionalString (lib.elemAt m 0 != null) (lib.elemAt m 0)}.${lib.elemAt m 1}";
      defaultText = lib.literalMD "`auth.vanwaaij.com` for `id.vanwaaij.com`, `auth-test.…` for `id-test.…`";
      description = "Host of the router's sign-in gate (oauth2-proxy); its callback is the `oauth2-proxy` client's redirect.";
    };

    extraAccess = lib.mkOption {
      type = lib.types.attrsOf accessType;
      default = { };
      description = "Access to apps outside NixOS, as `homelab.access` (modules/identity/access.nix).";
    };

    access = lib.mkOption {
      type = lib.types.attrsOf lib.types.raw;
      readOnly = true;
      description = ''
        Every app's access: the flake's `homelab.access` (with `declaredBy`) and
        `extraAccess`. Evaluation fails on an app in both, and on a member missing from
        `homelab.people`.
      '';
    };

    provisionState = lib.mkOption {
      type = lib.types.raw;
      readOnly = true;
      internal = true;
      description = "The kanidm-provision state rendered from `access` and `homelab.people`.";
    };

    serverSettings = lib.mkOption {
      type = lib.types.raw;
      readOnly = true;
      internal = true;
      description = "Kanidm's server.toml.";
    };
  };

  config = lib.mkMerge [
    {
      homelab.identity = {
        inherit access provisionState serverSettings;
      };
    }

    (lib.mkIf cfg.enable {
      assertions = [
        {
          assertion = lan.address != null;
          message = "homelab.identity needs homelab.lan.address (the host file's netInterface.ip).";
        }
      ];

      homelab.containers.enable = true;

      virtualisation.oci-containers.containers.kanidm = {
        image = serverImage;
        ports = [ "${lan.address}:8443:8443" ];
        volumes = [
          "${dataDir}:/data"
          "${serverToml}:/data/server.toml:ro"
          "${backupDir}:/backup"
          "${certDir}:${certDir}:ro"
          "${./branding/override.css}:/hpkg/override.css:ro"
        ];
      };

      systemd.services.docker-kanidm = {
        # The certificate (self-signed until Let's Encrypt's arrives) must exist.
        wants = [ "acme-${cfg.domain}.service" ];
        after = [ "acme-${cfg.domain}.service" ];
      };

      systemd.tmpfiles.settings.identity.${dataDir}.d = {
        mode = "0700";
        user = "root";
        group = "root";
      };

      systemd.services.kanidm-provision = {
        description = "Provision Kanidm's people, groups and OAuth2 clients from Nix";
        after = [ "docker-kanidm.service" ];
        requires = [ "docker-kanidm.service" ];
        # Again on every (re)start of the container, and on every change of the state.
        partOf = [ "docker-kanidm.service" ];
        wantedBy = [
          "multi-user.target"
          "docker-kanidm.service"
        ];
        restartTriggers = [ stateFile ];
        path = shellPath;
        serviceConfig = {
          Type = "oneshot";
          RemainAfterExit = true;
        };
        script = ''
          set -euo pipefail
          ${waitForKanidm}
          ${recoverFn}
          KANIDM_PROVISION_IDM_ADMIN_TOKEN=$(recover idm_admin)
          export KANIDM_PROVISION_IDM_ADMIN_TOKEN
          ${lib.getExe pkgs.kanidm-provision} --no-auto-remove --accept-invalid-certs \
            --url ${url} --state ${stateFile}
        '';
      };

      # Account policy, display name and logo; every command sets a value, so reruns
      # change nothing. `admin` (domain settings) and `idm_admin` (account policy).
      systemd.services.kanidm-policy = {
        description = "Set Kanidm's account policy, display name and logo";
        after = [ "kanidm-provision.service" ];
        requires = [ "kanidm-provision.service" ];
        partOf = [ "docker-kanidm.service" ];
        wantedBy = [
          "multi-user.target"
          "docker-kanidm.service"
        ];
        restartTriggers = [
          (pkgs.writeText "kanidm-policy" policyScript)
          ./branding/logo.svg
        ];
        path = shellPath;
        serviceConfig = {
          Type = "oneshot";
          RemainAfterExit = true;
        };
        script = ''
          set -euo pipefail
          ${waitForKanidm}
          ${recoverFn}
          IDM_ADMIN_PASSWORD=$(recover idm_admin)
          ADMIN_PASSWORD=$(recover admin)
          printf '%s\n%s\n' "$IDM_ADMIN_PASSWORD" "$ADMIN_PASSWORD" | ${toolsRun policyScript}
        '';
      };

      environment.systemPackages = [ basicSecret ];

      # The certificate via Cloudflare DNS-01, readable by the container (root).
      # Kanidm re-reads it on SIGHUP.
      security.acme = {
        acceptTerms = true;
        certs.${cfg.domain} = {
          email = "thijs@vanwaaij.com";
          dnsProvider = "cloudflare";
          dnsResolver = "1.1.1.1:53";
          credentialFiles.CF_DNS_API_TOKEN_FILE =
            config.services.onepassword-secrets.secretPaths.identityCloudflareDnsToken;
          server = lib.mkIf cfg.acmeStaging "https://acme-staging-v02.api.letsencrypt.org/directory";
          postRun = "${docker} kill --signal=HUP kanidm >/dev/null 2>&1 || true";
        };
      };

      # Same token as the router's (Zone:DNS:Edit on vanwaaij.com), read by root.
      services.onepassword-secrets.secrets.identityCloudflareDnsToken = {
        reference = "op://Homelab/cloudflare-dns-token/credential";
        mode = "0400";
        owner = "root";
        services = [ "acme-order-renew-${cfg.domain}" ];
      };

      networking.firewall.interfaces.${lan.interface}.allowedTCPPorts = [ 8443 ];
    })
  ];
}
