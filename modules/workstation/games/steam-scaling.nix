{
  config,
  lib,
  pkgs,
  hostPlatform,
  ...
}:
# Steam on a scaled monitor, without the blur. Steam only runs through XWayland, and
# Hyprland scales an XWayland window by stretching its bitmap, so on a monitor with scale
# 2 (or 1.6, 2.5) the whole client is soft. The fix has two halves that only work together:
#   - Hyprland stops scaling XWayland windows (xwayland.force_zero_scaling), so they are
#     drawn at the monitor's real pixels: sharp, but at 1x size, which is tiny;
#   - Steam is told to draw its own interface that much bigger
#     (STEAM_FORCE_DESKTOPUI_SCALING).
# The first half is a Hyprland setting, and the Hyprland config is shared by every
# workstation, so it only switches on where this option is set: this module writes
# /etc/hypr/xwayland-zero-scaling, which hyprland/config/lua/xwayland.lua looks for.
#
# Side effects, all hosts with it set: every XWayland-only program is drawn at 1x and is
# tiny (Wayland-native ones, Discord and Firefox among them, are not affected), and
# Proton games started outside gamescope see the monitor's real resolution, which is
# what they should. One scale for all monitors: pick the one you use Steam on.
# Takes a new Hyprland session (log out and in), not just a reload.
lib.optionalAttrs hostPlatform.isLinux {
  options.programs.games.steamScale = lib.mkOption {
    type = lib.types.nullOr lib.types.numbers.positive;
    default = null;
    example = 2;
    description = ''
      Scale of Steam's interface, set to the scale of the monitor Steam is on (the primary
      one in monitors.lua), to make Steam sharp on a scaled monitor. null leaves Steam alone.
    '';
  };

  config =
    lib.mkIf
      (config.programs.games.enable && config.programs.games.steamScale != null && !hostPlatform.isServer)
      {
        programs.steam.package = pkgs.steam.override {
          extraEnv.STEAM_FORCE_DESKTOPUI_SCALING = toString config.programs.games.steamScale;
        };

        # First line: the scale, which xwayland.lua also uses for the XWayland cursor size.
        environment.etc."hypr/xwayland-zero-scaling".text = ''
          ${toString config.programs.games.steamScale}
          Present: hyprland/config/lua/xwayland.lua sets xwayland.force_zero_scaling.
          Written by programs.games.steamScale (modules/workstation/games/steam-scaling.nix).
        '';
      };
}
