{ umport, ... }:
{
  imports = umport {
    # Skip categories that don't exist (yet) so listing them is harmless.
    paths = builtins.filter builtins.pathExists [
      ./apps
      ./backup
      ./boot
      ./console
      ./darwin
      ./desktop
      ./development
      ./editor
      ./gaming
      ./hardware
      ./homelab
      ./locale
      ./lodestar
      ./networking
      ./nix
      ./packages
      ./secrets
      ./security
      ./shell
      ./system
      ./truenas
      ./users
      ./vm-specific
    ];
    recursive = true;
    includeHome = false;
  };
}
