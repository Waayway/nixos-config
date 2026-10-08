{
  lib,
  hostPlatform,
  user,
  ...
}:
{
  # mkMerge, not `//`: a shallow `//` would let the platform attrset's `nix`
  # key replace the shared `nix.settings`/`nix.gc` above.
  config = lib.mkMerge [
    {
      nixpkgs.config.allowUnfree = lib.mkForce true;

      nix.settings.trusted-users = [ user.name ];
      nix.settings.experimental-features = [
        "nix-command"
        "flakes"
      ];
      nix.settings.auto-optimise-store = true;

      nix.channel.enable = false;

      nix.gc = {
        automatic = lib.mkDefault true;
        options = lib.mkDefault "--delete-older-than 7d";
      };
    }
    # `nix.gc.dates` is the NixOS (systemd timer) form; nix-darwin uses
    # `nix.gc.interval` (launchd attrset).
    (
      if hostPlatform.isLinux then
        {
          nix.gc.dates = lib.mkDefault "weekly";
        }
      else if hostPlatform.isDarwin then
        {
          nix.gc.interval = lib.mkDefault {
            Hour = 0;
            Minute = 0;
            Weekday = 7;
          };
        }
      else
        { }
    )
  ];
}
