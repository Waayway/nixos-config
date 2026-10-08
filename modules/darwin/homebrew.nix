{
  config,
  inputs,
  lib,
  hostPlatform,
  user,
  ...
}:
{
  options.workstation.homebrew.removeUndeclared = lib.mkOption {
    type = lib.types.enum [
      "keep"
      "uninstall"
      "zap"
    ];
    default = "keep";
    description = ''
      What a switch does with Homebrew casks/brews that aren't declared in
      this repo:
        keep      leave them installed (safe for machines with manual installs)
        uninstall remove them, keep their app data and preferences
        zap       remove them including app data, caches and preferences
    '';
  };

  imports = lib.optionals hostPlatform.isDarwin [ inputs.nix-homebrew.darwinModules.nix-homebrew ];

  config = lib.optionalAttrs hostPlatform.isDarwin {
    # nix-homebrew adopts any pre-existing /opt/homebrew install instead of
    # erroring out, and leaves manually-installed taps/formulae alone.
    nix-homebrew = {
      enable = true;
      enableRosetta = true;
      user = user.name;
      autoMigrate = true;
      mutableTaps = true;
    };

    homebrew = {
      enable = true;

      onActivation = {
        autoUpdate = true;
        upgrade = true;
        cleanup =
          {
            keep = "none";
            uninstall = "uninstall";
            zap = "zap";
          }
          .${config.workstation.homebrew.removeUndeclared};
      };

      taps = [
        "nikitabobko/tap" # aerospace
      ];

      # CLIs come from nixpkgs (modules/packages, modules/darwin/packages.nix,
      # modules/development). Apps come from the workstation.apps categories
      # (modules/apps). Only the always-on Mac basics are listed here.
      casks = [
        "aerospace" # tiling WM (from nikitabobko/tap)
        "jordanbaird-ice" # menu bar manager
        "ghostty" # settings are managed by the home-manager module
      ];
    };
  };
}
