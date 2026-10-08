{ hostPlatform, lib, ... }:
{
  # macOS UI defaults for every Mac. Host files can override single keys
  # with lib.mkForce.
  config = lib.optionalAttrs hostPlatform.isDarwin {
    system.defaults = {
      NSGlobalDomain = {
        AppleInterfaceStyle = "Dark";
        AppleICUForce24HourTime = true;
        InitialKeyRepeat = 30;
        KeyRepeat = 2;
        ApplePressAndHoldEnabled = false;
        NSAutomaticCapitalizationEnabled = true;
        NSAutomaticPeriodSubstitutionEnabled = true;
        NSAutomaticWindowAnimationsEnabled = false;
        AppleShowAllExtensions = true;
        AppleShowScrollBars = "Always";
        AppleScrollerPagingBehavior = true; # click in scroll bar jumps to spot
        AppleKeyboardUIMode = 2; # Tab moves through all controls
        "com.apple.swipescrolldirection" = false; # no "natural" scrolling
        "com.apple.keyboard.fnState" = true; # F1-F12 as standard function keys
        "com.apple.springing.enabled" = false;
        "com.apple.trackpad.forceClick" = true;
      };

      dock = {
        autohide = true;
        autohide-delay = 0.0;
        show-recents = false;
        tilesize = 62;
        largesize = 64;
        magnification = true;
        launchanim = false;
        mineffect = "scale";
        minimize-to-application = true;
        wvous-br-corner = 14; # bottom-right hot corner: Quick Note
        persistent-apps = [
          "/Applications/Firefox.app"
          "/Applications/Ghostty.app"
          "/Applications/TIDAL.app"
        ];
      };

      finder = {
        FXPreferredViewStyle = "Nlsv"; # list view
        ShowStatusBar = true;
        ShowPathbar = true;
        FXDefaultSearchScope = "SCcf"; # search the current folder
        FXRemoveOldTrashItems = true; # empty Trash after 30 days
        ShowExternalHardDrivesOnDesktop = true;
        ShowHardDrivesOnDesktop = false;
        ShowRemovableMediaOnDesktop = true;
      };

      trackpad = {
        Clicking = false;
        TrackpadRightClick = true;
        TrackpadThreeFingerDrag = false;
      };

      menuExtraClock.ShowDayOfWeek = true;
      loginwindow.GuestEnabled = false;

      # Tone down Liquid Glass. Writing com.apple.universalaccess needs Full
      # Disk Access for the terminal running darwin-rebuild (see README).
      universalaccess = {
        reduceTransparency = true; # solid instead of glass materials
        reduceMotion = true;
      };

      WindowManager = {
        GloballyEnabled = false; # Stage Manager off
        AppWindowGroupingBehavior = true; # group windows by app (AeroSpace recommends)
        HideDesktop = true; # hide desktop items
        StandardHideWidgets = true;
        EnableStandardClickToShowDesktop = false; # clicking wallpaper doesn't hide windows
        # AeroSpace does the tiling; keep macOS' own tiling out of the way.
        EnableTilingByEdgeDrag = false;
        EnableTopTilingByEdgeDrag = false;
        EnableTiledWindowMargins = false;
      };

      CustomUserPreferences = {
        NSGlobalDomain = {
          NSGlassDiffusionSetting = 0; # Liquid Glass style

          # English UI, Dutch region formats.
          AppleLanguages = [
            "en-US"
            "nl-NL"
          ];
          AppleLocale = "en_US@rg=nlzzzz";

          AppleActionOnDoubleClick = "Fill"; # double-click title bar fills screen
          AppleLiveTextEnabled = false;
          "com.apple.mouse.linear" = true; # no mouse acceleration
          "com.apple.trackpad.scrolling" = 0.3125;
        };

        "com.apple.finder".FXPreferredSearchViewStyle = "Nlsv";

        # Single input source: U.S.
        "com.apple.HIToolbox".AppleEnabledInputSources = [
          {
            InputSourceKind = "Keyboard Layout";
            "KeyboardLayout ID" = 0;
            "KeyboardLayout Name" = "U.S.";
          }
          {
            "Bundle ID" = "com.apple.CharacterPaletteIM";
            InputSourceKind = "Non Keyboard Input Method";
          }
          {
            "Bundle ID" = "com.apple.PressAndHold";
            InputSourceKind = "Non Keyboard Input Method";
          }
        ];

        # Siri and dictation off.
        "com.apple.assistant.support" = {
          "Assistant Enabled" = false;
          "Dictation Enabled" = false;
        };
      };
    };
  };
}
