{ lib, user, ... }:
{
  nixpkgs.config.allowUnfree = lib.mkForce true;

  # nix-darwin can either manage nix itself or defer to an existing install
  # (e.g. the Determinate installer). Keep it enabled by default; flip to
  # `false` in the host config if there is a pre-existing daemon conflict.
  nix.enable = true;

  nix.settings.trusted-users = [
    "root"
    user.name
  ];

  nix.settings.experimental-features = [
    "nix-command"
    "flakes"
  ];

  nix.gc = {
    automatic = lib.mkDefault true;
    interval = { Weekday = 0; Hour = 3; Minute = 0; };
    options = lib.mkDefault "--delete-older-than 7d";
  };

  nix.optimise.automatic = true;
}
