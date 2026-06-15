{
  lib,
  isLinux,
  isFramework,
  inputs,
  ...
}:
let
  active = isLinux && isFramework;
in
# `programs.fw-fanctrl` only exists once the fw-fanctrl module is imported.
# On darwin (or any non-Framework host) the module isn't loaded, so emit no
# assignments at all rather than guarded ones.
{
  imports = lib.optionals active [ inputs.fw-fanctrl.nixosModules.default ];
} // lib.optionalAttrs active {
  programs.fw-fanctrl = {
    enable = true;
    config.defaultStrategy = "medium";
  };
}
