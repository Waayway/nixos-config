# tools.monitoringTargetsFrom { nixosConfigurations }
#
# Every configuration's monitoring data, keyed by configuration name:
# `{ address, logBudgetMB, targets, declaredBy }`. Configurations without the
# `homelab.monitoring` option, with `agent.enable = false` or without a
# `homelab.lan.address` are skipped, so a host that leaves the flake or turns its agent
# off vanishes from targets, tenants and alerts. Used as
# `tools.monitoringTargetsFrom { inherit lib; } { … }` (`tools/default.nix` imports the
# file as-is).
{ lib }:
{
  nixosConfigurations ? { },
}:
let
  usable =
    c:
    c.config ? homelab
    && c.config.homelab ? monitoring
    && c.config.homelab.monitoring.agent.enable
    && (c.config.homelab.lan.address or null) != null;
in
lib.mapAttrs (cname: c: {
  address = c.config.homelab.lan.address;
  logBudgetMB = c.config.homelab.monitoring.agent.logBudgetMB;
  targets = c.config.homelab.monitoring.targets;
  declaredBy = cname;
}) (lib.filterAttrs (_: usable) nixosConfigurations)
