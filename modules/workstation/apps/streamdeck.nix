args@{
  upkgs,
  tools,
  ...
}:
# The Stream Deck: Bitfocus Companion, which turns its buttons into actions (MangoHud's
# mangoapp settings, Discord, music). Not in the stable nixpkgs, and nixpkgs-unstable is
# still on 5.0.5, so companion_lib.nix packages the current release on top of unstable's
# tooling (`upkgs`). The package is the headless build: a Node process with a web
# UI on http://localhost:8000, where you set up buttons and pages. It runs as a user
# service, started at login. The Stream Deck needs permission to its USB
# and hidraw nodes: the rule gives it to the logged-in user (uaccess); replug the deck
# after the first switch.
let
  companion = upkgs.callPackage ./companion_lib.nix { };
in
tools.mkAppCategory args {
  name = "streamdeck";
  apps = {
    companion = {
      linux = [ companion ];
      linuxConfig = {
        services.udev.extraRules = ''
          # Elgato Stream Deck (all models, vendor 0fd9)
          SUBSYSTEM=="usb", ATTRS{idVendor}=="0fd9", TAG+="uaccess"
          KERNEL=="hidraw*", ATTRS{idVendor}=="0fd9", TAG+="uaccess"
        '';

        systemd.user.services.bitfocus-companion = {
          description = "Bitfocus Companion (Stream Deck)";
          wantedBy = [ "default.target" ];
          serviceConfig = {
            # The web UI listens on every interface by default; only this machine needs it.
            ExecStart = "${companion}/bin/bitfocus-companion --admin-address 127.0.0.1 --admin-port 8000";
            Restart = "on-failure";
            RestartSec = 5;
          };
        };
      };
    };
  };
}
