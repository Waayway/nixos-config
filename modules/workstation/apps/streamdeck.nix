args@{
  upkgs,
  tools,
  ...
}:
# The Stream Deck: Bitfocus Companion, which turns its buttons into actions (MangoHud's
# mangoapp settings, Discord, music). Not in the stable nixpkgs yet, so it comes from
# nixpkgs-unstable (`upkgs`). The package is the headless build: a Node process with a web
# UI on http://localhost:8000, where you set up buttons and pages. It runs as a user
# service, started at login. The Stream Deck needs permission to its USB
# and hidraw nodes: the rule gives it to the logged-in user (uaccess); replug the deck
# after the first switch.
tools.mkAppCategory args {
  name = "streamdeck";
  apps = {
    companion = {
      linux = [ upkgs.bitfocus-companion ];
      linuxConfig = {
        services.udev.extraRules = ''
          # Elgato Stream Deck (all models, vendor 0fd9)
          SUBSYSTEM=="usb", ATTRS{idVendor}=="0fd9", TAG+="uaccess"
          KERNEL=="hidraw*", ATTRS{idVendor}=="0fd9", TAG+="uaccess"
        '';

        systemd.user.services.bitfocus-companion = {
          description = "Bitfocus Companion (Stream Deck)";
          wantedBy = [ "default.target" ];
          environment.COMPANION_ADMIN_PORT = "8000";
          serviceConfig = {
            ExecStart = "${upkgs.bitfocus-companion}/bin/bitfocus-companion";
            Restart = "on-failure";
            RestartSec = 5;
          };
        };
      };
    };
  };
}
