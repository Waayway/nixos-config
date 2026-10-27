{
  config,
  pkgs,
  lib,
  hostPlatform,
  ...
}:
lib.optionalAttrs hostPlatform.isLinux {
  # ~/.config/hypr is the repo folder itself (a link into ~/.flake, not the
  # store): edit config/*.lua and `hyprctl reload`, no switch needed.
  # Home-manager's own Hyprland module stays off; it would write hyprland.lua.
  xdg.configFile."hypr".source =
    config.lib.file.mkOutOfStoreSymlink "${config.home.homeDirectory}/.flake/modules/workstation/desktop/hyprland/config";

  # Hyprland's Lua API stubs at a fixed path for config/.luarc.json (lua-ls).
  xdg.dataFile."hypr/stubs".source = "${pkgs.hyprland}/share/hypr/stubs";
}
