{
  config,
  lib,
  pkgs,
  hostPlatform,
  ...
}:
lib.optionalAttrs hostPlatform.isLinux {
  # Applies where the host turns on NixOS's own `hardware.bluetooth.enable`
  # (host file `options.hardware.bluetooth.enable`); never sets it itself.
  config = lib.mkIf (!hostPlatform.isServer && config.hardware.bluetooth.enable) {
    boot.kernelModules = [ "btusb" ];

    hardware.bluetooth = {
      powerOnBoot = true;
      settings = {
        General = {
          #Enable = "Source,Sink,Media,Socket";
          Experimental = true;
          FastConnectable = true;
        };
        Policy = {
          AutoEnable = true;
        };
      };
    };
    services.blueman.enable = true;

    systemd.user.services.mpris-proxy = {
      enable = true;
    };
    environment.systemPackages = with pkgs; [ blueman ];
  };
}
