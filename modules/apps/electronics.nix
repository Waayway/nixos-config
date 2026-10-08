args@{ pkgs, ... }:
import ../../lib/mkAppCategory.nix args {
  name = "electronics";
  apps = {
    arduino = {
      linux = [ pkgs.arduino-ide ];
      darwinCasks = [ "arduino-ide" ];
    };
    kicad = {
      linux = [ pkgs.kicad ];
      darwinCasks = [ "kicad" ];
    };
  };
}
