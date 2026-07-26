{
  lib,
  hostPlatform,
  umport,
  ...
}:
{
  warnings =
    [ ] ++ lib.optional hostPlatform.isServer [ "HOME MANAGER SHOULD NOT BE USED WITH A SERVER" ];

  imports = umport {
    paths = [
      ./other
      ./gaming
      ./desktop
      ./terminal
      ./programming
      ./applications
    ];
    recursive = true;
    includeHome = true;
  };
}
