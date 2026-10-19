# Evaluation check of the identity module (modules/identity/kanidm.nix) on router-test
# (`homelab.identity = { enable = true; domain = "id-test.vanwaaij.com"; acmeStaging = true; }`):
# the Kanidm container and its server.toml, the provisioning and policy oneshots, the
# rendered kanidm-provision state, the ACME certificate, and evaluation failing for a
# member missing from `homelab.people` and for an app in both the flake and extraAccess.
{
  pkgs,
  lib,
  nixosConfigurations,
}:
let
  host = nixosConfigurations.router-test;
  cfg = host.config;
  id = cfg.homelab.identity;
  domain = "id-test.vanwaaij.com";
  c = cfg.virtualisation.oci-containers.containers.kanidm;
  s = id.serverSettings;
  state = id.provisionState;
  provision = cfg.systemd.services.kanidm-provision;
  policy = cfg.systemd.services.kanidm-policy;
  has = lib.hasInfix;
  ok = v: (builtins.tryEval (builtins.deepSeq v v)).success;

  extend = m: (host.extendModules { modules = [ m ]; }).config.homelab.identity.access;
  unknown = extend {
    homelab.identity.extraAccess.wiki.members = [
      "thijs"
      "nobody"
    ];
  };
  overlap = extend {
    homelab.identity.extraAccess.clash = { };
    homelab.access.clash = { };
  };
in
# the container
assert lib.hasPrefix "kanidm/server:1.11.2@sha256:" c.image;
assert c.ports == [ "10.0.10.230:8443:8443" ];
assert lib.elem "/var/lib/identity/kanidm:/data" c.volumes;
assert lib.elem "/store/kanidm:/backup" c.volumes;
assert lib.elem "/var/lib/acme/${domain}:/var/lib/acme/${domain}:ro" c.volumes;
assert lib.any (v: lib.hasSuffix "-kanidm-server.toml:/data/server.toml:ro" v) c.volumes;
assert lib.any (
  v: lib.hasSuffix "override.css:/hpkg/override.css:ro" v && lib.hasPrefix "/nix/store/" v
) c.volumes;
assert lib.elem "/store/kanidm" cfg.systemd.services.docker-kanidm.unitConfig.RequiresMountsFor;
# server.toml
assert s.version == "2";
assert s.domain == domain;
assert s.origin == "https://${domain}";
assert s.bindaddress == "[::]:8443";
assert s.db_path == "/data/kanidm.db";
assert s.tls_chain == "/var/lib/acme/${domain}/fullchain.pem";
assert s.tls_key == "/var/lib/acme/${domain}/key.pem";
assert
  s.online_backup == {
    path = "/backup";
    schedule = "00 22 * * *";
    versions = 7;
  };
# ACME (Cloudflare DNS-01, staging on the test VM) and the firewall
assert cfg.security.acme.certs.${domain}.dnsProvider == "cloudflare";
assert has "acme-staging-v02" cfg.security.acme.certs.${domain}.server;
assert cfg.security.acme.certs.${domain}.credentialFiles ? CF_DNS_API_TOKEN_FILE;
assert lib.elem "acme-${domain}.service" cfg.systemd.services.docker-kanidm.after;
assert lib.elem 8443 cfg.networking.firewall.interfaces.ens18.allowedTCPPorts;
# kanidm-provision: after the container, on every start of it and on config change
assert lib.elem "docker-kanidm.service" provision.after;
assert lib.elem "docker-kanidm.service" provision.partOf;
assert lib.elem "docker-kanidm.service" provision.wantedBy;
assert provision.restartTriggers != [ ];
assert provision.serviceConfig.Type == "oneshot";
assert has "docker exec kanidm /sbin/kanidmd scripting recover-account -c /data/server.toml"
  provision.script;
assert has "KANIDM_PROVISION_IDM_ADMIN_TOKEN=$(recover idm_admin)" provision.script;
assert has "--no-auto-remove" provision.script;
assert has "-kanidm-provision-1.3.0/bin/kanidm-provision --no-auto-remove" provision.script;
# the state: people, groups, OAuth2 clients
assert
  state.persons.thijs == {
    displayName = "Thijs van Waaij";
    mailAddresses = [ "thijs@vanwaaij.com" ];
  };
assert state.groups.admins.members == [ "thijs" ];
assert state.groups.proxmox-users.members == [ "thijs" ];
assert state.groups.archipelago-users.members == [ "thijs" ];
assert
  state.systems.oauth2.proxmox.scopeMaps == {
    proxmox-users = [
      "openid"
      "email"
      "profile"
      "groups"
    ];
  };
assert !(state.systems.oauth2 ? archipelago);
# origins without a path get Kanidm's trailing slash (else every provisioning run rewrites them)
assert state.systems.oauth2.proxmox.originLanding == "https://pve.tail41ca60.ts.net:8006/";
assert lib.all (lib.hasSuffix "/") state.systems.oauth2.proxmox.originUrl;
assert
  state.systems.oauth2.oauth2-proxy.originUrl == [ "https://auth-test.vanwaaij.com/oauth2/callback" ];
assert
  lib.attrNames state.systems.oauth2.oauth2-proxy.scopeMaps == [
    "archipelago-users"
    "backrest-users"
    "traefik-users"
    "truenas-users"
  ];
# kanidm-policy: tools image, account policy, display name, logo
assert lib.elem "kanidm-provision.service" policy.after;
assert lib.elem "docker-kanidm.service" policy.partOf;
assert has "kanidm/tools:1.11.2@sha256:" policy.script;
assert has "account-policy credential-type-minimum idm_all_persons mfa" policy.script;
assert has "account-policy enable admins" policy.script;
assert has "account-policy credential-type-minimum admins passkey" policy.script;
assert has "system domain set-displayname" policy.script;
assert has "vanwaaij.com" policy.script;
assert has "system domain set-image" policy.script;
# failures
assert !ok unknown;
assert !ok (lib.attrNames unknown);
assert !ok overlap;
assert ok id.access;
pkgs.runCommand "identity" { } "touch $out"
