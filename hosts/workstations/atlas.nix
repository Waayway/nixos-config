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
    { pkgs, ... }:
    {
      # First-time bootstrap: back up any existing dotfiles instead of
      # refusing to overwrite.
      home-manager.backupFileExtension = "before-nix";

      home-manager.users.thijsvanwaaij.programs.git.settings.user.email = "thijs@vriend.studio";

      # Fresh machine: what's declared here is what's installed.
      homebrew.onActivation.cleanup = "zap";

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
        "betterdisplay"
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
        NSGlobalDomain.AppleICUForce24HourTime = true;
        dock = {
          tilesize = 62;
          largesize = 64;
          magnification = true;
        };
        finder.ShowStatusBar = true;
        loginwindow.GuestEnabled = false;

        # Tone down Liquid Glass and simplify the UI.
        # NB: writing com.apple.universalaccess needs Full Disk Access for the
        # terminal running darwin-rebuild (see README bootstrap).
        universalaccess = {
          reduceTransparency = true; # solid instead of glass materials
          reduceMotion = true;
        };
        NSGlobalDomain.NSAutomaticWindowAnimationsEnabled = false;
        dock = {
          launchanim = false;
          mineffect = "scale";
          autohide-delay = 0.0;
        };
        WindowManager = {
          StandardHideWidgets = true;
          EnableStandardClickToShowDesktop = false; # clicking wallpaper doesn't hide windows
          # AeroSpace does the tiling; keep macOS' own tiling out of the way.
          EnableTilingByEdgeDrag = false;
          EnableTopTilingByEdgeDrag = false;
          EnableTiledWindowMargins = false;
        };
        # Liquid Glass style (macOS 26); mirrors 14m2max.
        CustomUserPreferences = {
          NSGlobalDomain.NSGlassDiffusionSetting = 0;

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
