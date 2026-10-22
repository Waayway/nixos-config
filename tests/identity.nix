# Evaluation check of the identity module (modules/server/identity/kanidm.nix) on router-test
# (`homelab.identity = { enable = true; domain = "id-test.vanwaaij.com"; acmeStaging = true; }`):
# the Kanidm container and its server.toml, the backups (/store/kanidm here, their own
# NFS share on identity), the provisioning and policy oneshots, the
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
  prod = nixosConfigurations.identity.config;
  pc = prod.virtualisation.oci-containers.containers.kanidm;
  s = id.serverSettings;
  state = id.provisionState;
  provision = cfg.systemd.services.kanidm-provision;
  policy = cfg.systemd.services.kanidm-policy;
  has = lib.hasInfix;
  ok = v: (builtins.tryEval (builtins.deepSeq v v)).success;
  everyone = [
    "thijs"
    "arie"
  ];

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
assert lib.any (v: lib.hasSuffix "-kanidm-branding-fonts:/hpkg/fonts:ro" v) c.volumes;
assert lib.elem "/store/kanidm" cfg.systemd.services.docker-kanidm.unitConfig.RequiresMountsFor;
assert !(cfg.fileSystems ? "/var/lib/identity/backup");
# production (identity): backups on their own NFS share, mounted on first access
assert lib.elem "/var/lib/identity/backup:/backup" pc.volumes;
assert !(lib.any (lib.hasPrefix "/store/") pc.volumes);
assert lib.elem "/var/lib/identity/backup"
  prod.systemd.services.docker-kanidm.unitConfig.RequiresMountsFor;
assert
  prod.fileSystems."/var/lib/identity/backup".device == "10.0.10.130:/mnt/store/authentication";
assert prod.fileSystems."/var/lib/identity/backup".fsType == "nfs";
assert lib.all (o: lib.elem o prod.fileSystems."/var/lib/identity/backup".options) [
  "_netdev"
  "x-systemd.automount"
];
assert
  !(lib.any (lib.hasPrefix "x-systemd.idle-timeout")
    prod.fileSystems."/var/lib/identity/backup".options
  );
assert lib.elem "nfs" (lib.attrNames (lib.filterAttrs (_: v: v) prod.boot.supportedFilesystems));
assert prod.homelab.identity.serverSettings.online_backup.path == "/backup";
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
  state.persons == {
    thijs = {
      displayName = "Thijs";
      mailAddresses = [ "thijs@vanwaaij.com" ];
    };
    arie = {
      displayName = "Arie";
      mailAddresses = [ "arie@vanwaaij.com" ];
    };
  };
# Arie: Nextcloud, Immich and Jellyfin only, not an admin
assert state.groups.admins.members == [ "thijs" ];
assert lib.all (app: state.groups."${app}-users".members == [ "thijs" ]) [
  "archipelago"
  "proxmox"
  "traefik"
  "truenas"
  "backrest"
];
assert lib.all (app: state.groups."${app}-users".members == everyone) [
  "nextcloud"
  "immich"
  "jellyfin"
];
# the apps on prod come from its configuration (tools.accessFrom), with their OIDC clients
assert id.access.nextcloud.declaredBy == "prod";
assert lib.elem "https://jellyfin.vanwaaij.com/sso/OID/redirect/kanidm"
  state.systems.oauth2.jellyfin.originUrl;
assert state.systems.oauth2.jellyfin.preferShortUsername;
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
# Lodestar (declared by nixos-manager): any member may log in, admins act via `admins`
assert state.groups.lodestar-users.members == [ "thijs" ];
assert id.access.lodestar.declaredBy == "nixos-manager";
assert state.systems.oauth2.lodestar.originUrl == [ "https://lodestar.vanwaaij.com/auth/callback" ];
assert state.systems.oauth2.lodestar.preferShortUsername;
assert
  state.systems.oauth2.lodestar.scopeMaps == {
    lodestar-users = [
      "openid"
      "profile"
      "groups"
    ];
  };
assert state.systems.oauth2.lodestar.originLanding == "https://lodestar.vanwaaij.com/";
# origins without a path get Kanidm's trailing slash (else every provisioning run rewrites them)
assert state.systems.oauth2.proxmox.originLanding == "https://pve.tail41ca60.ts.net:8006/";
assert lib.all (lib.hasSuffix "/") state.systems.oauth2.proxmox.originUrl;
assert
  state.systems.oauth2.oauth2-proxy.originUrl == [ "https://auth-test.vanwaaij.com/oauth2/callback" ];
# the gate's client: "Services" in the app list, landing on Lodestar's Services tab, with icons
assert state.systems.oauth2.oauth2-proxy.displayName == "Services";
assert
  state.systems.oauth2.oauth2-proxy.originLanding == "https://lodestar.vanwaaij.com/#/services";
assert lib.hasSuffix "-services.svg" state.systems.oauth2.oauth2-proxy.imageFile;
assert lib.hasSuffix "-proxmox.svg" state.systems.oauth2.proxmox.imageFile;
# reset links on the domain, not the address the CLI talks to
assert lib.any (p: (p.name or "") == "kanidm-reset-link") cfg.environment.systemPackages;
assert
  lib.attrNames state.systems.oauth2.oauth2-proxy.scopeMaps == [
    "archipelago-users"
    "backrest-users"
    "traefik-users"
    "truenas-users"
    "whoami-test-users"
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
