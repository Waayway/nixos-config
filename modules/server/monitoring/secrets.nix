# The monitor VM's secrets from 1Password (vault Homelab, via opnix). Each lands in
# `homelab.monitoring.server.secrets.<name>` (a file path), the only thing the other
# monitoring modules read. A secret is declared only when the monitor is on and the
# part that uses it is enabled.
#
# Owners are the consuming service's user, or root (0400) when systemd reads the file
# (`EnvironmentFile`, `LoadCredential`). `services` lists the units that read a secret
# (restarted when it changes); units that come with later modules (healthchecks-sync)
# are added there:
#   grafanaAdminPassword, grafanaSecretKey,
#   grafanaOidcSecret                        owner `grafana` (read by `$__file{}`)
#   pveEnv, healthchecksPingEnv              root, as EnvironmentFile
#   healthchecksReadonlyKey                  prometheus (credentials_file)
#   healthchecksApiKey, healthchecksProject, truenasKey
#                                            root, as LoadCredential / read by a root timer
{
  config,
  lib,
  hostPlatform,
  ...
}:
let
  cfg = config.homelab.monitoring.server;
  secretPaths = config.services.onepassword-secrets.secretPaths;
  enabled = cfg.enable;
  hc = enabled && cfg.healthchecks.enable;

  # name = { reference, owner, services ? [ ], when }
  defs = {
    grafanaAdminPassword = {
      reference = "op://Homelab/grafana-admin/password";
      owner = "grafana";
      services = [ "grafana.service" ];
      when = enabled;
    };
    # Grafana's own signing/encryption key (NixOS 26.05 has no default any more): the
    # field `secret-key` of the grafana-admin item, any long random string.
    grafanaSecretKey = {
      reference = "op://Homelab/grafana-admin/secret-key";
      owner = "grafana";
      services = [ "grafana.service" ];
      when = enabled;
    };
    grafanaOidcSecret = {
      reference = "op://Homelab/kanidm-oauth2-grafana/credential";
      owner = "grafana";
      services = [ "grafana.service" ];
      when = enabled;
    };
    pveEnv = {
      reference = "op://Homelab/pve-monitoring-token/env";
      owner = "root";
      services = [ "prometheus-pve-exporter.service" ];
      when = enabled && cfg.pve.enable;
    };
    healthchecksPingEnv = {
      reference = "op://Homelab/healthchecks-ping-key/env";
      owner = "root";
      services = [ "grafana.service" ];
      when = hc;
    };
    healthchecksApiKey = {
      reference = "op://Homelab/healthchecks-api-key/credential";
      owner = "root";
      services = [ "healthchecks-sync.service" ];
      when = hc;
    };
    healthchecksReadonlyKey = {
      reference = "op://Homelab/healthchecks-readonly-key/credential";
      # Prometheus reads it itself (`authorization.credentials_file`).
      owner = "prometheus";
      services = [ "prometheus.service" ];
      when = hc;
    };
    healthchecksProject = {
      reference = "op://Homelab/healthchecks-project/uuid";
      owner = "root";
      services = [ "prometheus.service" ];
      when = hc;
    };
    # The same 1Password item as truenas-reconcile's `truenasAutomationKey`
    # (modules/server/truenas/truenas.nix); the monitor has no truenas module.
    truenasKey = {
      reference = "op://Homelab/truenas-automation/private key?ssh-format=openssh";
      owner = "root";
      services = [ "truenas-pools.service" ];
      when = enabled && cfg.truenas.enable;
    };
  };
  active = lib.filterAttrs (_: d: d.when) defs;
in
lib.optionalAttrs hostPlatform.isLinux {
  config = lib.mkIf enabled {
    services.onepassword-secrets.secrets = lib.mapAttrs (_: d: {
      inherit (d) reference owner;
      services = d.services or [ ];
      mode = "0400";
    }) active;

    homelab.monitoring.server.secrets = lib.mapAttrs (n: _: lib.mkDefault secretPaths.${n}) active;

    # A unit that reads a secret starts after opnix has written it: on a fresh VM, or
    # when a secret is added, it otherwise starts first, finds no file and hits its
    # start limit. `wants`, not `requires`: offline, opnix fails but keeps its files.
    systemd.services =
      lib.genAttrs
        (lib.unique (
          map (lib.removeSuffix ".service") (lib.concatMap (d: d.services or [ ]) (lib.attrValues active))
        ))
        (_: {
          after = [ "opnix-secrets.service" ];
          wants = [ "opnix-secrets.service" ];
        });
  };
}
