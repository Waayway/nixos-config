# atlas — work MacBook Pro (M4 Max)
#
# Mirrors the previous work laptop (14m2max, managed by the old ~/.flake).
# Shared darwin defaults live in modules/darwin/*; this file only adds the
# work app set and the settings that differ from apollo.
#
# Not installable declaratively — install by hand:
#   - Xcode (App Store / developer.apple.com)
#   - MacUtil
{
  system = "aarch64-darwin";
  user = {
    name = "thijsvanwaaij";
    fullname = "Thijs van Waaij";
  };

  type = "macbook";

  options = {
    home-manager.enable = true;
  };

  config =
    { pkgs, lib, ... }:
    {
      # First-time bootstrap: back up any existing dotfiles instead of
      # refusing to overwrite.
      home-manager.backupFileExtension = "before-nix";

      home-manager.users.thijsvanwaaij = {
        programs.git.settings.user.email = "thijs@vriend.studio";

        # Finder sidebar Favorites (mirrors 14m2max). Folders that don't exist
        # yet (Drive not synced, repos not cloned) are added on a later switch.
        darwin.finderSidebar = [
          "My Drive/Cuneus"
          "oteny"
          "oteny/rivermen"
          "Desktop"
          "Documents"
          "Downloads"
          "Library/Group Containers/group.com.apple.VoiceMemos.shared/Recordings"
        ];
      };

      # Fresh machine: what's declared here is what's installed.
      homebrew.onActivation.cleanup = "zap";

      # Work laptop: no inbound SSH (shared darwin config enables Remote Login).
      services.openssh.enable = lib.mkForce false;

      networking.applicationFirewall.enable = true;

      # Same as 14m2max: display sleeps after an hour (battery and AC).
      power.sleep.display = 60;

      # Start ThermalForge (fan control) at login.
      launchd.user.agents.thermalforge.serviceConfig = {
        ProgramArguments = [
          "/usr/bin/open"
          "-a"
          "ThermalForge"
        ];
        RunAtLoad = true;
      };

      homebrew.taps = [
        "producerguy/tap" # thermalforge
      ];

      homebrew.brews = [
        "postgresql@16"
        "pgvector"
        "pdf2image"
        "producerguy/tap/thermalforge" # fan control
      ];

      homebrew.casks = [
        # Browsers
        "firefox"
        "ungoogled-chromium"

        # Editors
        "vscodium"
        "cursor"
        "zed"
        "android-studio"

        # AI
        "claude"
        "claude-code"
        "opencode-desktop"
        "lm-studio"
        "ollama-app"

        # Office
        "microsoft-word"
        "microsoft-excel"
        "microsoft-powerpoint"
        "microsoft-outlook"
        "microsoft-onenote"
        "microsoft-teams"
        "onedrive"
        "google-drive"
        "obsidian"

        # Comms / media
        "telegram"
        "tidal"
        "obs"
        "audacity"
        "krita"

        # System
        "1password"
        "tailscale-app"
        "elgato-stream-deck"
      ];

      environment.systemPackages = with pkgs; [
        tmux
        cloudflared
        cocoapods
        coreutils
        just
        jdk17
        poppler-utils
        rclone
        scc
        opencode
        mas
        fzf
        ripgrep
        watch

        # Language servers / formatters
        lua-language-server
        stylua
        nixd
        nixfmt
        emmet-ls
        intelephense
        typescript-language-server
        tailwindcss-language-server
        pyright
      ];

      # Differences from the shared defaults (captured from 14m2max).
      system.defaults = {
        NSGlobalDomain = {
          AppleICUForce24HourTime = true;
          AppleShowAllExtensions = true;
          AppleShowScrollBars = "Always";
          AppleScrollerPagingBehavior = true; # click in scroll bar jumps to spot
          AppleKeyboardUIMode = 2; # Tab moves through all controls
          "com.apple.keyboard.fnState" = true; # F1-F12 as standard function keys
          "com.apple.springing.enabled" = false;
          "com.apple.trackpad.forceClick" = true;
        };
        menuExtraClock.ShowDayOfWeek = true;
        dock = {
          tilesize = 62;
          largesize = 64;
          magnification = true;
          minimize-to-application = true;
          wvous-br-corner = 14; # bottom-right hot corner: Quick Note
        };
        finder = {
          ShowStatusBar = true;
          ShowPathbar = true;
          FXDefaultSearchScope = "SCcf"; # search the current folder
          FXRemoveOldTrashItems = true; # empty Trash after 30 days
        };
        loginwindow.GuestEnabled = false;

        # Tone down Liquid Glass and simplify the UI.
        # NB: writing com.apple.universalaccess needs Full Disk Access for the
        # terminal running darwin-rebuild (see README bootstrap).
        universalaccess = {
          reduceTransparency = true; # solid instead of glass materials
          reduceMotion = true;
        };
        dock = {
          launchanim = false;
          mineffect = "scale";
          autohide-delay = 0.0;
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
        # Liquid Glass style (macOS 26); mirrors 14m2max.
        CustomUserPreferences = {
          NSGlobalDomain = {
            NSGlassDiffusionSetting = 0;
            NSAutomaticWindowAnimationsEnabled = false;

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

          # Spotlight: apps, calculator, developer sources and settings only
          # (mirrors 14m2max). `orderedItems` is the classic category list;
          # EnabledPreferenceRules / DisabledUTTypes are macOS 26's.
          "com.apple.Spotlight" = {
            orderedItems = [
              {
                name = "APPLICATIONS";
                enabled = true;
              }
              {
                name = "MENU_EXPRESSION";
                enabled = true;
              }
              {
                name = "CONTACT";
                enabled = false;
              }
              {
                name = "MENU_CONVERSION";
                enabled = false;
              }
              {
                name = "MENU_DEFINITION";
                enabled = false;
              }
              {
                name = "SOURCE";
                enabled = true;
              }
              {
                name = "DOCUMENTS";
                enabled = false;
              }
              {
                name = "EVENT_TODO";
                enabled = false;
              }
              {
                name = "DIRECTORIES";
                enabled = false;
              }
              {
                name = "FONTS";
                enabled = false;
              }
              {
                name = "IMAGES";
                enabled = false;
              }
              {
                name = "MESSAGES";
                enabled = false;
              }
              {
                name = "MOVIES";
                enabled = false;
              }
              {
                name = "MUSIC";
                enabled = false;
              }
              {
                name = "MENU_OTHER";
                enabled = false;
              }
              {
                name = "PDF";
                enabled = false;
              }
              {
                name = "PRESENTATIONS";
                enabled = false;
              }
              {
                name = "MENU_SPOTLIGHT_SUGGESTIONS";
                enabled = false;
              }
              {
                name = "SPREADSHEETS";
                enabled = false;
              }
              {
                name = "SYSTEM_PREFS";
                enabled = true;
              }
              {
                name = "TIPS";
                enabled = false;
              }
              {
                name = "BOOKMARKS";
                enabled = false;
              }
            ];
            EnabledPreferenceRules = [
              "Custom.relatedContents"
              "System.folders"
              "Domain.IMAGES"
              "Domain.MOVIES"
              "Domain.MUSIC"
              "Domain.PDF"
              "Domain.SPREADSHEETS"
              "FileProvider.com.google.drivefs.fpext/gdrive-110120237501209960764"
              "com.apple.AppStore"
              "com.apple.iBooksX"
              "com.apple.iCal"
              "com.apple.AddressBook"
              "com.apple.Dictionary"
              "com.google.drivefs"
              "com.apple.mail"
              "com.microsoft.Excel"
              "com.microsoft.Outlook"
              "com.microsoft.Powerpoint"
              "com.microsoft.Word"
              "com.apple.Notes"
              "com.microsoft.OneDrive"
              "com.apple.Photos"
              "com.apple.podcasts"
              "com.apple.reminders"
              "com.apple.Safari"
              "com.apple.shortcuts"
              "com.apple.tips"
              "com.apple.VoiceMemos"
            ];
            DisabledUTTypes = [
              "com.adobe.pdf"
              "com.apple.iwork.numbers.numbers"
              "com.apple.iwork.numbers.sffnumbers"
              "com.apple.iwork.numbers.template"
              "com.apple.localized-pdf-bundle"
              "com.apple.protected-mpeg-4-audio"
              "com.apple.quicktime-movie"
              "com.microsoft.excel.sheet.binary.macroenabled"
              "com.microsoft.excel.xls"
              "org.openxmlformats.spreadsheetml.sheet"
              "org.openxmlformats.spreadsheetml.sheet.macroenabled"
              "public.3gpp"
              "public.3gpp2"
              "public.audio"
              "public.image"
              "public.movie"
              "public.mpeg"
              "public.mpeg-4"
              "public.mpeg-4-audio"
              "public.mpeg-video"
              "public.spreadsheet"
            ];
          };
        };
      };
    };
}
