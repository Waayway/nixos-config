{
  lib,
  config,
  ...
}:
{
  # `programs.fw-fanctrl` only exists once the fw-fanctrl module is imported.
  # On darwin (or any non-Framework host) the module isn't loaded, so emit no
  # assignments at all rather than guarded ones.
  options.hardware.fw-fanctrl = {
    enable = lib.mkEnableOption "Enable FW Fanctrl";
  };

  config = lib.mkIf config.hardware.fw-fanctrl.enable {
    hardware.fw-fanctrl = {
      enable = true;
      config.defaultStrategy = "medium";
    };
  };
}
