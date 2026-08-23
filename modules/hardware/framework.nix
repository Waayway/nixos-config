{
  lib,
  config,
  ...
}:
{
  # `programs.fw-fanctrl` only exists once the fw-fanctrl module is imported.
  # On darwin (or any non-Framework host) the module isn't loaded, so emit no
  # assignments at all rather than guarded ones.

  # hardware.fw-fanctrl already exists. so we dont need to make the option. just enable and set default on enabled

  hardware.fw-fanctrl = {
    config.defaultStrategy = "medium";
  };
}
