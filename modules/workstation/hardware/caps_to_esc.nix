{
  pkgs,
  lib,
  hostPlatform,
  ...
}:
# Caps Lock: tap for Escape, hold for Control.
lib.optionalAttrs hostPlatform.isLinux {
  config = lib.mkIf (!hostPlatform.isServer) {
    services.interception-tools =
      let
        itools = pkgs.interception-tools;
        itools-caps = pkgs.interception-tools-plugins.caps2esc;
      in
      {
        enable = true;
        plugins = [ itools-caps ];
        # requires explicit paths: https://github.com/NixOS/nixpkgs/issues/126681
        udevmonConfig = pkgs.lib.mkDefault ''
          - JOB: "${itools}/bin/intercept -g $DEVNODE | ${itools-caps}/bin/caps2esc -m 1 | ${itools}/bin/uinput -d $DEVNODE"
            DEVICE:
              EVENTS:
                EV_KEY: [KEY_CAPSLOCK, KEY_ESC]
        '';
      };
  };
}
// lib.optionalAttrs hostPlatform.isDarwin {
  # Karabiner-Elements does the remap; its config is in caps_to_esc_home.nix.
  # First launch needs a manual approval of its driver extension and Input
  # Monitoring permission in System Settings.
  homebrew.casks = [ "karabiner-elements" ];
}
