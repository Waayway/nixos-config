args@{ pkgs, tools, ... }:
tools.mkAppCategory args {
  name = "browsers";
  apps = {
    firefox = {
      linuxConfig = {
        programs.firefox.enable = true;
        # Tools that look at $BROWSER instead of the MIME defaults (browsers_home.nix).
        environment.sessionVariables.BROWSER = "firefox";
      };
      darwinCasks = [ "firefox" ];
    };
    chromium = {
      linux = [ pkgs.ungoogled-chromium ];
      darwinCasks = [ "ungoogled-chromium" ]; # not packaged for darwin in nixpkgs
    };
  };
}
