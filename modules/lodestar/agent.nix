# Lodestar agent (github:Waayway/lodestar, module imported in lib/mkSystem.nix and
# lib/mkDarwin.nix) on every host whose host file says `fleet = true;`. The channel
# comes from the host file (`channel = ...`), default by folder: servers stable,
# workstations unstable. On the Macs the agent is signed with one shared certificate
# (lodestar-agent-signing.pem); its private key is the 1Password document
# "Lodestar Agent Signing Key" (Personal), placed once per Mac. See docs/lodestar.md.
{
  lib,
  fleet,
  user,
  hostPlatform,
  ...
}:
{
  config = lib.mkIf fleet.member (
    lib.mkMerge [
      {
        services.lodestar-agent = {
          enable = true;
          user = user.name;
          inherit (fleet) channel;
          managerHost = "nixos-manager";
          repoUrl = "https://github.com/Waayway/nixos-config";
        };
      }
      (lib.optionalAttrs hostPlatform.isDarwin {
        services.lodestar-agent.macos.stableSigning.certificate =
          builtins.readFile ./lodestar-agent-signing.pem;
      })
    ]
  );
}
