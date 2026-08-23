{
  inputs,
  lib,
  hostPlatform,
  user,
  ...
}:
{
  imports = lib.optional hostPlatform.isDarwin [
    inputs.nix-homebrew.darwinModules.nix-homebrew
  ];

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

      # Do NOT remove formulae/casks that aren't listed here. Manual installs
      # from before this flake was introduced stay intact; migrate them into
      # nixpkgs (or into the lists below) incrementally.
      onActivation = {
        autoUpdate = true;
        upgrade = true;
        cleanup = "none";
      };

      taps = [
        "nikitabobko/tap" # aerospace
      ];

      # CLI formulae are NOT declared here — they are installed via nixpkgs.
      # See modules/darwin/packages.nix and modules/workstations/programming/*.
      brews = [ ];

      # Casks only for GUI/macOS apps that are NOT in nixpkgs for darwin.
      # GUI apps that ARE in nixpkgs live in modules/darwin/apps.nix.
      casks = [
        "aerospace" # tiling WM (from nikitabobko/tap)
        "codex" # OpenAI Codex desktop
        "focusrite-control-2" # proprietary audio interface driver
        "jordanbaird-ice" # menu bar manager
        "db-browser-for-sqlite"
        "pgadmin4"
        "spotify" # uncertain aarch64-darwin support in nixpkgs
        "ghostty" # settings are still managed by the home-manager module
      ];
    };
  };
}
