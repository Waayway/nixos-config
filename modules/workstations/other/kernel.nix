{
  pkgs,
  lib,
  hostPlatform,
  ...
}:
{
  config = lib.optional hostPlatform.isLinux {
    boot.kernelPackages = pkgs.linuxPackages_latest;
  };
}
