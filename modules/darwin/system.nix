{
  pkgs,
  currentSystemName,
  hostPlatform,
  lib,
  ...
}:
{
  config = lib.optionalAttrs hostPlatform.isDarwin {
    networking.hostName = currentSystemName;
    networking.computerName = currentSystemName;

    programs.zsh.enable = true;
    environment.shells = with pkgs; [ zsh ];

    environment.variables.EDITOR = "nvim";

    # macOS system defaults. Values mirror what is actually configured on
    # apollo (MacBook Pro 14" M1 Pro) — captured via `defaults read`.
    # Host files can override individual keys.
    system.defaults = {
      NSGlobalDomain = {
        AppleInterfaceStyle = "Dark";
        InitialKeyRepeat = 30;
        KeyRepeat = 2;
        ApplePressAndHoldEnabled = false;
        NSAutomaticCapitalizationEnabled = true;
        NSAutomaticPeriodSubstitutionEnabled = true;
        "com.apple.swipescrolldirection" = false;
      };
      dock = {
        autohide = true;
        show-recents = false;
        tilesize = 58;
        largesize = 16;
        magnification = false;
      };
      finder = {
        ShowStatusBar = false;
        FXPreferredViewStyle = "Nlsv";
        ShowExternalHardDrivesOnDesktop = true;
        ShowHardDrivesOnDesktop = false;
        ShowRemovableMediaOnDesktop = true;
      };
      trackpad = {
        Clicking = false;
        TrackpadRightClick = true;
        TrackpadThreeFingerDrag = false;
      };
    };

    # Touch-ID for sudo
    security.pam.services.sudo_local.touchIdAuth = true;
  };
}
