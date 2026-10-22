{
  lib,
  hostPlatform,
  umport,
  ...
}:
{
  warnings =
    [ ]
    ++ lib.optional hostPlatform.isServer [ "HOME MANAGER SHOULD ALMOST NEVER BE USED ON A SERVER" ];

  imports = umport {
    paths = [
      ./common
      ./workstation
      ./server
    ];
    recursive = true;
    includeHome = true;
  };
}
