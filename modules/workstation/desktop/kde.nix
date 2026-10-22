{
  pkgs,
  lib,
  config,
  hostPlatform,
  ...
}:
lib.optionalAttrs hostPlatform.isLinux (
  let
    enabled = config.desktop.kde.enable;
  in
  {
    options.desktop.kde = {
      enable = lib.mkEnableOption "Enable KDE Desktop";
    };

    # Never on servers (type = "server").
    config = lib.mkIf (enabled && !hostPlatform.isServer) {
      # Enable the KDE Plasma Desktop Environment.
      services.desktopManager.plasma6.enable = true;
    };
  }
)
