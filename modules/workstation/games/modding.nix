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
# opens it. BG3 runs the Windows build under Proton, with three Limo deployers (paths under
# compatdata/1086940/pfx/drive_c/users/steamuser/AppData/Local/Larian Studios/Baldur's Gate 3):
# a Case Matching Deployer for .pak mods into Mods/, one for bin/ and Data/ mods (Script
# Extender, NativeModLoader, loose textures) into the game folder, and a Baldurs Gate 3
# Deployer (source Mods/, target PlayerProfiles/Public) that writes the load order to
# modsettings.lsx. ~/limo/bg3-loadorder.py sets these up and orders the mods.
lib.optionalAttrs hostPlatform.isLinux {
  config = lib.mkIf (config.programs.games.enable && !hostPlatform.isServer) {
    environment.systemPackages = [ pkgs.limo ];
  };
}
