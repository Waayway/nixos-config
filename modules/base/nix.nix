{
  lib,
  pkgs,
  user,
  ...
}:
{
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

      nix.gc.automatic = lib.mkDefault true;
      nix.gc.options = lib.mkDefault "--delete-older-than 7d";
    }
    # `nix.gc.dates` is the NixOS (systemd timer) form. nix-darwin uses
    # `nix.gc.interval` (launchd attrset) — set in modules/workstations/darwin/nix.nix.
    (lib.optional pkgs.stdenv.hostPlatform.isLinux {
      nix.gc.dates = lib.mkDefault "weekly";
    })
  ];
}
