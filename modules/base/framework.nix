{
  pkgs,
  isFramework,
  ...
}:
let
  inherit (pkgs.stdenv) hostPlatform;
in
{
  # `programs.fw-fanctrl` only exists once the fw-fanctrl module is imported.
  # On darwin (or any non-Framework host) the module isn't loaded, so emit no
  # assignments at all rather than guarded ones.
  hardware.fw-fanctrl =
    if hostPlatform.isLinux then
      {
        enable = true;
        config.defaultStrategy = "medium";
      }
    else
      { };
}
