{
  config,
  lib,
  inputs,
  ...
}:
{

  options.hardware.profiles = lib.mkOption {
    default = [ ];
  };

  imports = map (name: inputs.nixos-hardware.nixosModules.${name}) config.hardware.profiles;
}
