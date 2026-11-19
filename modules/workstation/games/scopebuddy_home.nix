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
# SCB_AUTO_RES, SCB_AUTO_HDR and SCB_AUTO_VRR make ScopeBuddy read the monitor's current
# resolution, HDR and VRR state and pass the matching gamescope flags. On a wlroots-style
# compositor (Hyprland) ScopeBuddy has no notion of a primary monitor and aborts the launch
# with "Primary display not supported" unless gamescope is given `-O <connector>`, so that
# one flag is still needed. It is not hardcoded: hyprland/config/lua/monitor_policy.lua
# publishes the primary monitor's connector in $XDG_RUNTIME_DIR/hypr/primary-monitor, which
# is also where the gaming workspace (and so the gamescope window) lives.
#
# If that file is missing (no Hyprland, or no monitor yet) the auto variables are switched
# off and gamescope starts plain, rather than the game failing to launch.
lib.optionalAttrs hostPlatform.isLinux {
  config = lib.mkIf (osConfig != null && (osConfig.programs.games.enable or false)) {
    xdg.configFile."scopebuddy/scb.conf".text = ''
      # Managed by NixOS (modules/workstation/games/scopebuddy_home.nix). Per-game
      # settings go in ~/.config/scopebuddy/AppID/<steam appid>.conf, which is sourced after
      # this file and is not managed.

      primary="$(cat "''${XDG_RUNTIME_DIR:-/run/user/$(id -u)}/hypr/primary-monitor" 2>/dev/null || true)"

      if [ -n "$primary" ]; then
        SCB_AUTO_RES=1
        SCB_AUTO_HDR=1
        SCB_AUTO_VRR=1
        SCB_GAMESCOPE_ARGS="--mangoapp -f -O $primary"
      else
        SCB_AUTO_RES=0
        SCB_AUTO_HDR=0
        SCB_AUTO_VRR=0
        SCB_GAMESCOPE_ARGS="--mangoapp -f"
      fi
    '';
  };
}
