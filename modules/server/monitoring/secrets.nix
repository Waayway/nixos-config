# The monitor VM's secrets from 1Password (vault Homelab, via opnix). Each lands in
# `homelab.monitoring.server.secrets.<name>` (a file path), the only thing the other
# monitoring modules read. A secret is declared only when the monitor is on and the
# part that uses it is enabled.
#
# Owners are the consuming service's user, or root (0400) when systemd reads the file
# (`EnvironmentFile`, `LoadCredential`). Declared without `services`: the consuming
# module adds its unit with `services.onepassword-secrets.secrets.<name>.services`
# when it exists (Grafana, Task 5/6; pve exporter, healthchecks-sync, truenas-pools,
# the loki budget timer, Task 5 to 9):
#   grafanaAdminPassword, grafanaOidcSecret  owner `grafana` (read by `$__file{}`)
#   pveEnv, healthchecksPingEnv              root, as EnvironmentFile
#   healthchecksApiKey, healthchecksReadonlyKey, healthchecksProject, truenasKey
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

  # name = { reference, owner, when }
  defs = {
    grafanaAdminPassword = {
      reference = "op://Homelab/grafana-admin/password";
      owner = "grafana";
      when = enabled;
    };
    grafanaOidcSecret = {
      reference = "op://Homelab/kanidm-oauth2-grafana/credential";
      owner = "grafana";
      when = enabled;
    };
    pveEnv = {
      reference = "op://Homelab/pve-monitoring-token/env";
      owner = "root";
      when = enabled && cfg.pve.enable;
    };
    healthchecksPingEnv = {
      reference = "op://Homelab/healthchecks-ping-key/env";
      owner = "root";
      when = hc;
    };
    healthchecksApiKey = {
      reference = "op://Homelab/healthchecks-api-key/credential";
      owner = "root";
      when = hc;
    };
    healthchecksReadonlyKey = {
      reference = "op://Homelab/healthchecks-readonly-key/credential";
      owner = "root";
      when = hc;
    };
    healthchecksProject = {
      reference = "op://Homelab/healthchecks-project/uuid";
      owner = "root";
      when = hc;
    };
    # The same 1Password item as truenas-reconcile's `truenasAutomationKey`
    # (modules/server/truenas/truenas.nix); the monitor has no truenas module.
    truenasKey = {
      reference = "op://Homelab/truenas-automation/private key?ssh-format=openssh";
      owner = "root";
      when = enabled && cfg.truenas.enable;
    };
  };
  active = lib.filterAttrs (_: d: d.when) defs;
in
lib.optionalAttrs hostPlatform.isLinux {
  config = lib.mkIf enabled {
    services.onepassword-secrets.secrets = lib.mapAttrs (_: d: {
      inherit (d) reference owner;
      mode = "0400";
    }) active;

    homelab.monitoring.server.secrets = lib.mapAttrs (n: _: lib.mkDefault secretPaths.${n}) active;
  };
}
