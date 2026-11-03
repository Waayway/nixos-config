args@{
  pkgs,
  user,
  tools,
  ...
}:
tools.mkAppCategory args {
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
      darwinCasks = [
        "1password"
        "1password-cli"
      ];
    };
    # Linux: the tailscale daemon lives in modules/common/networking/tailscale.nix.
    # greedy: the cask updates itself, so `brew bundle` skips it unless told otherwise; this
    # keeps every Mac on the release the Linux hosts get (Lodestar shows it as up to date).
    tailscale.darwinCasks = [
      {
        name = "tailscale-app";
        greedy = true;
      }
    ];
    stream-deck.darwinCasks = [ "elgato-stream-deck" ];
    fragments.linux = [ pkgs.fragments ];
    calculator.linux = [ pkgs.gnome-calculator ];
    handbrake.linux = [ pkgs.handbrake ];
    gparted.linux = [ pkgs.gparted ];
  };
}
