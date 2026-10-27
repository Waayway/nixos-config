{
  config,
  lib,
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
    # Pair and connect: Adwaita Bluetooth (GTK4/libadwaita, made for tiling
    # WMs); its daemon runs as a user service. Opened from the Quickshell bar.
    services.adw-bluetooth.enable = true;

    systemd.user.services.mpris-proxy = {
      enable = true;
    };
  };
}
