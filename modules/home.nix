{
  lib,
  hostPlatform,
  umport,
  ...
}:
{
  warnings =
    [ ] ++ lib.optional hostPlatform.isServer [ "HOME MANAGER SHOULD ALMOST NEVER BE USED ON A SERVER" ];

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
    includeHome = true;
  };
}
