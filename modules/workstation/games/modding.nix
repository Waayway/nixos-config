{
  config,
  lib,
  pkgs,
  hostPlatform,
  ...
}:
# Game modding on a workstation with games (`programs.games.enable`). Limo is the mod
# manager (BG3 and others): native, open source, NexusMods API (updates, downloads) and
# LOOT. Its desktop entry handles nxm:// links, so "Mod Manager Download" on NexusMods
# opens it. BG3 runs the Windows build under Proton; point Limo's BG3 deployer at
# compatdata/1086940/pfx/drive_c/users/steamuser/AppData/Local/Larian Studios/Baldur's Gate 3/.
lib.optionalAttrs hostPlatform.isLinux {
  config = lib.mkIf (config.programs.games.enable && !hostPlatform.isServer) {
    environment.systemPackages = [ pkgs.limo ];
  };
}
