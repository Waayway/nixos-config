# Lodestar agent (github:Waayway/lodestar, module imported in lib/mkSystem.nix and
# lib/mkDarwin.nix) on every host whose host file says `fleet = true;`. The channel
# comes from the host file (`channel = ...`), default by folder: servers stable,
# workstations unstable. See docs/lodestar.md.
{
  lib,
  fleet,
  user,
  ...
}:
{
  config = lib.mkIf fleet.member {
    services.lodestar-agent = {
      enable = true;
      user = user.name;
      inherit (fleet) channel;
      managerHost = "nixos-manager";
      repoUrl = "https://github.com/Waayway/nixos-config";
    };
  };
}
