{
  config,
  lib,
  pkgs,
  hostPlatform,
  ...
}:
# Games on a workstation (`programs.games.enable`): Steam with Proton-GE, Gamescope,
# Heroic (Epic, GOG, Amazon) and MangoHud. ScopeBuddy (scopebuddy.nix) starts Gamescope
# for them; the system tuning that goes with it, the CachyOS-style part, is in tuning.nix. Workstation only; docs/gaming.md has the why.
lib.optionalAttrs hostPlatform.isLinux {
  options.programs.games = {
    enable = lib.mkEnableOption "Steam, Heroic and the gaming tuning (modules/workstation/games/)";
  };

  config = lib.mkIf (config.programs.games.enable && !hostPlatform.isServer) {
    programs.steam = {
      enable = true;
      # Steam Remote Play and copying games over the LAN.
      remotePlay.openFirewall = true;
      localNetworkGameTransfers.openFirewall = true;
      # The "Steam (Gamescope)" session and `gamescope -- %command%` launch options.
      gamescopeSession.enable = true;
      protontricks.enable = true;
      # Pick "GE-Proton" per game in Steam's compatibility settings; Valve's Proton stays
      # the default.
      extraCompatPackages = [ pkgs.proton-ge-bin ];
    };

    # Gamescope itself is started by ScopeBuddy (scopebuddy.nix). No capSysNice: a
    # capability wrapper does not survive Steam's sandbox, and scx plus ananicy already
    # take care of the priorities.
    programs.gamescope.enable = true;

    environment.systemPackages = with pkgs; [
      heroic
      # `mangohud %command%` in a launch option: FPS, frametime graph, CPU/GPU load.
      mangohud
    ];
  };
}
