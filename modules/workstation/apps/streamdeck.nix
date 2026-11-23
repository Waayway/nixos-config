args@{
  upkgs,
  tools,
  inputs,
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
  # Our own modules (mangohud, linux-media), loaded through --extra-module-path.
  companionModules = upkgs.callPackage ./companion-modules_lib.nix {
    src = inputs.companion-modules;
  };
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
          # Companion writes its own udev rules to ~/.config/companion-nodejs/udev-rules and
          # nags (Surfaces page) until they're copied to /etc/udev/rules.d, which NixOS
          # manages. The uaccess rules above already cover the deck; with a sync command
          # set, Companion runs it instead of comparing files, and `true` does nothing.
          environment.COMPANION_SYNC_UDEV_RULES_COMMAND = "true";
          serviceConfig = {
            # The web UI listens on every interface by default; only this machine needs it.
            ExecStart = "${companion}/bin/bitfocus-companion --admin-address 127.0.0.1 --admin-port 8000 --extra-module-path ${companionModules}";
            Restart = "on-failure";
            RestartSec = 5;
          };
        };
      };
    };
  };
}
