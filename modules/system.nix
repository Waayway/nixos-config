{ umport, ... }:
{
  imports = umport {
    # Skip categories that don't exist (yet) so listing them is harmless.
    paths = builtins.filter builtins.pathExists [
      ./apps
      ./boot
      ./console
      ./darwin
      ./desktop
      ./development
      ./editor
      ./gaming
      ./hardware
      ./locale
      ./networking
      ./nix
      ./packages
      ./secrets
      ./security
      ./shell
      ./system
      ./users
      ./vm-specific
    ];
    recursive = true;
    includeHome = false;
  };
}
