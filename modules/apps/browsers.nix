args@{ pkgs, ... }:
import ../../lib/mkAppCategory.nix args {
  name = "browsers";
  apps = {
    firefox = {
      linuxConfig.programs.firefox.enable = true;
      darwinCasks = [ "firefox" ];
    };
    chromium = {
      linux = [ pkgs.ungoogled-chromium ];
      darwinCasks = [ "ungoogled-chromium" ]; # not packaged for darwin in nixpkgs
    };
  };
}
