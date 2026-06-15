{ umport, ... }:
{
  imports = [
    ../../base
    ./nix.nix
    ./user.nix
    ./system.nix
    ./packages.nix
    ./apps.nix
    ./homebrew.nix
    ./applications.nix
    ./sops.nix
    # Per-category GUI app bundles. Comment out any group you don't want
    # on a given host, or override `homebrew.casks` / `environment.systemPackages`
    # from the host file to subtract individual entries.
    ./apps/browsers.nix
    ./apps/dev.nix
    ./apps/audio.nix
  ]
  ++ umport {
    paths = [
      ../terminal
      ../programming
    ];
    exclude = [
      ../terminal/sudo.nix
    ];
    recursive = true;
    includeHome = false;
  }
  ++ [
    # Cross-platform apps / services explicitly picked for darwin
    ../applications/communication.nix # discord
    ../other/tailscale.nix
    ../other/fonts.nix
  ];
}
