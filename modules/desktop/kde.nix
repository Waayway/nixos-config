{
  pkgs,
  lib,
  config,
  ...
}:
let
  enabled = config.desktop.kde.enable;
in
{
  options.desktop.kde = {
    enable = lib.mkEnableOption "Enable KDE Desktop";
  };

  config = lib.mkIf enabled {
    # Enable the KDE Plasma Desktop Environment.
    services.desktopManager.plasma6.enable = true;
  };
}
