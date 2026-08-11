{
  pkgs,
  lib,
  hostPlatform,
  ...
}:
{
  config = lib.optionalAttrs hostPlatform.isLinux {
    boot.kernelPackages = pkgs.linuxPackages_latest;
  };
}
