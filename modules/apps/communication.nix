args@{ pkgs, ... }:
import ../../lib/mkAppCategory.nix args {
  name = "communication";
  apps = {
    discord = {
      linux = [ pkgs.discord ];
      darwinPkgs = [ pkgs.discord ];
    };
    telegram = {
      linux = [ pkgs.telegram-desktop ];
      darwinCasks = [ "telegram" ];
    };
    element = {
      linux = [ pkgs.element-desktop ];
      darwinCasks = [ "element" ]; # nixpkgs darwin build is flaky on aarch64
    };
  };
}
