{
  config,
  lib,
  pkgs,
  hostPlatform,
  ...
}:
# The Steam Controller (2026) in Steam's desktop mode on Hyprland. Steam cannot create its
# virtual mouse under Wayland there, so the trackpad cursor is invisible or dead as soon as
# Steam runs (ValveSoftware/steam-for-linux#13185, hyprwm/Hyprland#14426). The workaround
# everyone uses is extest, which turns Steam's X11 input events into uinput events; the
# NixOS wiki adds hidapi to Steam's environment for this controller. udev rules and the
# uinput module come from programs.steam through hardware.steam-hardware already.
#
# Known problems of the workaround, from that issue: the trackpads stop while Steam's
# settings or Steam Input menu is open, and one report says a controller update made Steam
# crash when the controller turns on (with a hand-built extest, not this one). If Steam
# misbehaves, switch it off: the mouse comes back when Steam is closed, the controller
# keeps working in games either way.
lib.optionalAttrs hostPlatform.isLinux {
  options.programs.games.steamController.enable =
    lib.mkEnableOption "the extest workaround for the Steam Controller's mouse on Wayland";

  config = lib.mkIf (config.programs.games.enable && config.programs.games.steamController.enable) {
    programs.steam = {
      extest.enable = true;
      extraPackages = [ pkgs.hidapi ];
    };
  };
}
