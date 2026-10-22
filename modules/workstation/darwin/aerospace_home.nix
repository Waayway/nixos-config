{ lib, hostPlatform, ... }:
lib.optionalAttrs hostPlatform.isDarwin {
  # AeroSpace itself is installed by the `aerospace` cask (modules/darwin/homebrew.nix).
  home.file.".aerospace.toml".source = ./aerospace.toml;
}
