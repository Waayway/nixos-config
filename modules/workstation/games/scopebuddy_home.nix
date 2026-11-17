{
  lib,
  osConfig ? null,
  hostPlatform,
  ...
}:
# ScopeBuddy's defaults, ~/.config/scopebuddy/scb.conf (a bash file ScopeBuddy sources).
# Only that file is managed: ScopeBuddy writes its other config files (noscope.conf,
# gamemode.conf, AppID/*.conf for per-game overrides) into the same folder.
#
# gamescope opens as a window on Hyprland, on the workspace that hyprland/config/lua/
# monitor_policy.lua keeps on the primary monitor, so the large one. The primary
# monitor's connector name is published by that policy in $XDG_RUNTIME_DIR/hypr/
# primary-monitor; ScopeBuddy reads that monitor's resolution from it (`-O`, wlr-randr),
# so a 4K monitor gets a 4K gamescope no matter which monitor was last used.
lib.optionalAttrs hostPlatform.isLinux {
  config = lib.mkIf (osConfig != null && (osConfig.programs.games.enable or false)) {
    xdg.configFile."scopebuddy/scb.conf".text = ''
      # Managed by NixOS (modules/workstation/games/scopebuddy_home.nix). Per-game
      # settings go in ~/.config/scopebuddy/AppID/<steam appid>.conf, which is sourced after
      # this file and is not managed.

      primary="$(cat "''${XDG_RUNTIME_DIR:-/run/user/$(id -u)}/hypr/primary-monitor" 2>/dev/null || true)"

      if [ -n "$primary" ]; then
        # Size gamescope to the primary monitor's current mode.
        SCB_AUTO_RES=1
        SCB_GAMESCOPE_ARGS="--mangoapp -f -O $primary"
      else
        # No Hyprland (or no primary yet): plain fullscreen gamescope, no detection.
        SCB_AUTO_RES=0
        SCB_GAMESCOPE_ARGS="--mangoapp -f"
      fi
    '';
  };
}
