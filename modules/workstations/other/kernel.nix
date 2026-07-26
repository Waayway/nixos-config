{
  pkgs,
  lib,
  ...
}:
let
  inherit (pkgs.stdenv) hostPlatform;
in
{
  config = lib.optional hostPlatform.isLinux {
    boot.kernelPackages = pkgs.linuxPackages_latest;
  };
}
