{
  config,
  pkgs,
  lib,
  hostPlatform,
  ...
}:
lib.optionalAttrs hostPlatform.isLinux {
  # Bar and notifications (replaces eww and swaync). Started by Hyprland
  # (hyprland/config/lua/autostart.lua). ~/.config/quickshell is the repo
  # folder itself, so edits apply live (Quickshell reloads on save).
  home.packages = [ pkgs.quickshell ];

  xdg.configFile."quickshell".source =
    config.lib.file.mkOutOfStoreSymlink "${config.home.homeDirectory}/.flake/modules/workstation/desktop/quickshell/config";
}
