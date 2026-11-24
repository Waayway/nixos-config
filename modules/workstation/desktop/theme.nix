{
  config,
  lib,
  hostPlatform,
  ...
}:
# Qt theme for the whole session. theme_home.nix configures qt5ct/qt6ct (Breeze, Tokyo
# Night palette), but home-manager puts QT_QPA_PLATFORMTHEME, QT_STYLE_OVERRIDE and
# QT_PLUGIN_PATH only in the shell's hm-session-vars. Hyprland (started by greetd) doesn't
# source that, so apps started from rofi or the bar came up unthemed (Limo, a Qt5 app).
# NixOS's qt module installs the plugins and sets QT_PLUGIN_PATH through PAM
# (profileRelativeSessionVariables), but its theme variables only in environment.variables
# (login shells), so those two are repeated as session variables. Not with Plasma, which
# brings its own platform theme.
lib.optionalAttrs hostPlatform.isLinux {
  config = lib.mkIf (!hostPlatform.isServer && !config.desktop.kde.enable) {
    qt = {
      enable = true;
      platformTheme = "qt5ct";
      style = "breeze";
    };
    environment.sessionVariables = {
      QT_QPA_PLATFORMTHEME = "qt5ct";
      QT_STYLE_OVERRIDE = "breeze";
    };
  };
}
