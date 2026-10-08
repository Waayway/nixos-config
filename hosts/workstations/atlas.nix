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
        CustomUserPreferences.NSGlobalDomain.NSGlassDiffusionSetting = 0;
      };
    };
}
