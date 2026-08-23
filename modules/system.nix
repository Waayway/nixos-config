{ umport, ... }:
{
  imports = umport {
    paths = [
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
