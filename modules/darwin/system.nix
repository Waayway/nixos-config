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
        AppleInterfaceStyle = lib.mkDefault "Dark";
        InitialKeyRepeat = lib.mkDefault 30;
        KeyRepeat = lib.mkDefault 2;
        ApplePressAndHoldEnabled = lib.mkDefault false;
        NSAutomaticCapitalizationEnabled = lib.mkDefault true;
        NSAutomaticPeriodSubstitutionEnabled = lib.mkDefault true;
        "com.apple.swipescrolldirection" = lib.mkDefault false;
      };
      dock = {
        autohide = lib.mkDefault true;
        show-recents = lib.mkDefault false;
        tilesize = lib.mkDefault 58;
        largesize = lib.mkDefault 16;
        magnification = lib.mkDefault false;
      };
      finder = {
        ShowStatusBar = lib.mkDefault false;
        FXPreferredViewStyle = lib.mkDefault "Nlsv";
        ShowExternalHardDrivesOnDesktop = lib.mkDefault true;
        ShowHardDrivesOnDesktop = lib.mkDefault false;
        ShowRemovableMediaOnDesktop = lib.mkDefault true;
      };
      trackpad = {
        Clicking = lib.mkDefault false;
        TrackpadRightClick = lib.mkDefault true;
        TrackpadThreeFingerDrag = lib.mkDefault false;
      };
    };

    # Touch-ID for sudo
    security.pam.services.sudo_local.touchIdAuth = true;
  };
}
