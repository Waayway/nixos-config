{
  lib,
  pkgs,
  isFramework,
  ...
}:
let
  active = pkgs.stdenv.hostPlatform.isLinux && isFramework;
in
# `programs.fw-fanctrl` only exists once the fw-fanctrl module is imported.
# On darwin (or any non-Framework host) the module isn't loaded, so emit no
# assignments at all rather than guarded ones.

{
  config = lib.optionalAttrs active {
    hardware.fw-fanctrl = {
      enable = true;
      config.defaultStrategy = "medium";
    };
  };
}
