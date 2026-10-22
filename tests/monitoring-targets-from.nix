# Evaluation check of `tools.monitoringTargetsFrom` over stub configurations built from
# modules/server/monitoring/options.nix and modules/server/homelab/lan.nix: address,
# defaults and targets, and configurations with the agent off, without the option or
# without a LAN address left out.
{
  pkgs,
  lib,
  tools,
}:
let
  monitoringTargetsFrom = tools.monitoringTargetsFrom { inherit lib; };
  stub =
    ip: extra:
    lib.evalModules {
      specialArgs = {
        inherit tools;
        hostPlatform = {
          isServer = true;
          isLinux = true;
        };
        serverOptions = lib.optionalAttrs (ip != null) { netInterface.ip = ip; };
      };
      modules = [
        ../modules/server/monitoring/options.nix
        ../modules/server/homelab/lan.nix
        extra
      ];
    };
  noOption = lib.evalModules {
    modules = [ { options.unrelated = lib.mkOption { default = 1; }; } ];
  };

  r = monitoringTargetsFrom {
    nixosConfigurations = {
      alpha = stub "10.0.10.1" { homelab.monitoring.targets.node.port = 9100; };
      off = stub "10.0.10.2" { homelab.monitoring.agent.enable = false; };
      noip = stub null { };
      plain = noOption;
    };
  };
in
assert r.alpha.address == "10.0.10.1";
assert r.alpha.logBudgetMB == 200;
assert r.alpha.targets.node.port == 9100;
assert r.alpha.targets.node.path == "/metrics";
assert r.alpha.declaredBy == "alpha";
assert lib.attrNames r == [ "alpha" ];
pkgs.runCommand "monitoring-targets-from" { } "touch $out"
