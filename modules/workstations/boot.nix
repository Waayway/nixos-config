{ lib, hostPlatform, ... }:
{
  config = lib.optional hostPlatform.isLinux {
    boot.loader.systemd-boot = {
      enable = true;
      configurationLimit = lib.mkDefault 10;
      consoleMode = lib.mkDefault "max";
    };

    boot.loader.efi.canTouchEfiVariables = true;
  };
}
