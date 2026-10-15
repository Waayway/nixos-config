args@{ pkgs, tools, ... }:
tools.mkAppCategory args {
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
