args@{ pkgs, ... }:
import ../../lib/mkAppCategory.nix args {
  name = "editors";
  apps = {
    vscodium = {
      linux = [ pkgs.vscodium ];
      darwinPkgs = [ pkgs.vscodium ];
    };
    zed.darwinCasks = [ "zed" ];
    cursor.darwinCasks = [ "cursor" ];
    android-studio = {
      linux = [ pkgs.android-studio ];
      darwinCasks = [ "android-studio" ];
    };
  };
}
