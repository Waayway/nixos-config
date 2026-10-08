args@{ pkgs, user, ... }:
import ../../lib/mkAppCategory.nix args {
  name = "utilities";
  apps = {
    _1password = {
      linuxConfig = {
        programs._1password.enable = true;
        programs._1password-gui = {
          enable = true;
          # CLI integration and system auth need PolKit on some desktops (e.g. Plasma).
          polkitPolicyOwners = [ user.name ];
        };
      };
      darwinCasks = [ "1password" ];
    };
    # Linux: the tailscale daemon lives in modules/networking/tailscale.nix.
    tailscale.darwinCasks = [ "tailscale-app" ];
    stream-deck.darwinCasks = [ "elgato-stream-deck" ];
    fragments.linux = [ pkgs.fragments ];
    calculator.linux = [ pkgs.gnome-calculator ];
    handbrake.linux = [ pkgs.handbrake ];
    gparted.linux = [ pkgs.gparted ];
  };
}
