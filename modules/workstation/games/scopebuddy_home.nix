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
#
# VRR: SCB_AUTO_VRR asks wlr-randr whether adaptive sync is on *at launch*, but Hyprland
# runs the monitors with vrr = 2 (only while something is fullscreen, games.lua), so at
# launch it reads off and gamescope never gets --adaptive-sync. It is passed always
# instead: gamescope then asks for VRR and Hyprland grants it once the window is
# fullscreen; on a monitor without VRR the flag does nothing.
#
# gamemode: the conf is sourced after scopebuddy has put Steam's %command% in $command, so
# the conf can prefix it with gamemoderun (programs.gamemode, games/tuning.nix). Launch
# options stay `scb -- %command%`.
#
# HDR: SCB_AUTO_HDR reads the desktop's HDR state, which on Hyprland is a stub (1.5.0) and
# would be off anyway (the desktop stays SDR). So HDR follows the monitor instead:
# monitor_policy.lua writes primary-monitor-hdr (1 for monitors with `hdr = true` in
# monitors.lua) and then gamescope gets --hdr-enabled and DXVK/VKD3D get DXVK_HDR=1, so
# games offer their HDR option. Hyprland switches the monitor to HDR while the fullscreen
# gamescope asks for it (render.cm_auto_hdr). `SCB_HDR=0 scb -- %command%` turns it off
# for one game. No vk-hdr-layer or ENABLE_HDR_WSI: Mesa has it built in, and the layer
# breaks gamescope.
lib.optionalAttrs hostPlatform.isLinux {
  config = lib.mkIf (osConfig != null && (osConfig.programs.games.enable or false)) {
    xdg.configFile."scopebuddy/scb.conf".text = ''
      # Managed by NixOS (modules/workstation/games/scopebuddy_home.nix). Per-game
      # settings go in ~/.config/scopebuddy/AppID/<steam appid>.conf, which is sourced after
      # this file and is not managed.

      hypr="''${XDG_RUNTIME_DIR:-/run/user/$(id -u)}/hypr"
      primary="$(cat "$hypr/primary-monitor" 2>/dev/null || true)"
      hdr="''${SCB_HDR:-$(cat "$hypr/primary-monitor-hdr" 2>/dev/null || echo 0)}"

      if [ -n "$primary" ]; then
        SCB_AUTO_RES=1
        SCB_AUTO_HDR=1
        SCB_AUTO_VRR=0
        SCB_GAMESCOPE_ARGS="--mangoapp -f -O $primary --adaptive-sync"
        if [ "$hdr" = 1 ]; then
          SCB_GAMESCOPE_ARGS="$SCB_GAMESCOPE_ARGS --hdr-enabled"
          export DXVK_HDR=1
        fi
      else
        SCB_AUTO_RES=0
        SCB_AUTO_HDR=0
        SCB_AUTO_VRR=0
        SCB_GAMESCOPE_ARGS="--mangoapp -f"
      fi

      # gamemode for every game; it wraps the game inside gamescope, not gamescope itself.
      if command -v gamemoderun >/dev/null; then
        command="gamemoderun $command"
      fi
    '';
  };
}
