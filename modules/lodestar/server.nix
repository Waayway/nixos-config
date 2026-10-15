# Defaults for the Lodestar server (dashboard and control plane) on the host that
# enables it (nixos-manager; its host file sets `enable` and `listenAddress`). The
# managed hosts are every configuration in this flake that runs the agent. NixOS only.
{
  config,
  lib,
  inputs,
  hostPlatform,
  ...
}:
lib.optionalAttrs hostPlatform.isLinux {
  config = lib.mkIf config.services.lodestar-server.enable {
    # The dashboard itself on its Services tab; not probed (it would only report itself).
    lodestar.links.lodestar = {
      title = "Lodestar";
      group = "Infrastructure";
      description = "Fleet manager";
      url = "http://${config.services.lodestar-server.listenAddress}:${toString config.services.lodestar-server.listenPort}";
      check.enable = false;
    };

    services.lodestar-server = {
      hosts = inputs.lodestar.lib.hostsFrom {
        inherit (inputs.self) nixosConfigurations darwinConfigurations;
      };
      # Services tab: every `lodestar.links` in the flake (service modules,
      # modules/homelab/links.nix).
      links = inputs.lodestar.lib.linksFrom {
        inherit (inputs.self) nixosConfigurations darwinConfigurations;
      };
      repoUrl = lib.mkDefault "https://github.com/Waayway/nixos-config";
      pushUrl = lib.mkDefault "git@github.com:Waayway/nixos-config";
      # Write deploy key for promote: open item, see docs/lodestar.md.
      deployKeyFile = lib.mkDefault null;
      allowedUsers = lib.mkDefault [ "Waayway@github" ];
      allowedTags = lib.mkDefault [
        "tag:nixos"
        "tag:personal"
        "tag:fleet"
      ];
      # promote keeps the module default: unstable -> stable.
    };
  };
}
