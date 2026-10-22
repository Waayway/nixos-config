# Lodestar agent (github:Waayway/lodestar, module imported in lib/mkSystem.nix and
# lib/mkDarwin.nix) on every host whose host file says `fleet = true;`. The channel
# comes from the host file (`channel = ...`), default by folder: servers stable,
# workstations unstable. On the Macs the agent is signed with one shared certificate
# (lodestar-agent-signing.pem); opnix fetches its private key, the 1Password document
# "Lodestar Agent Signing Key" (Homelab). See docs/lodestar.md.
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

        # opnix runs as a launchd daemon after activation, which signs: the first
        # switch fetches the key, the next one signs.
        services.onepassword-secrets = {
          enable = true;
          tokenFile = "/etc/opnix-token";
          users = [ user.name ];
          secrets.lodestarSigningKey = {
            reference = "op://Homelab/Lodestar Agent Signing Key/key.pem";
            kind = "file";
            path = "/var/lib/lodestar-agent/signing/key.pem";
            mode = "0600";
          };
        };
      })
    ]
  );
}
