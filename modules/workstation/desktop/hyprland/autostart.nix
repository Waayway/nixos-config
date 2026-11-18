{
  config,
  lib,
  hostPlatform,
  ...
}:
# Programs a host starts with its Hyprland session, as one command per line in
# /etc/hypr/autostart, which hyprland/config/lua/autostart.lua runs when Hyprland starts.
# The Hyprland config is shared by every workstation, so what only one of them starts
# (Steam and the music player on the gaming PC) is declared in that host's Nix config:
#
#   workstation.autostart = [ "steam -silent" "high-tide" ];
#
# Changing the list needs a switch; the file is read at the next login.
lib.optionalAttrs hostPlatform.isLinux {
  options.workstation.autostart = lib.mkOption {
    type = lib.types.listOf lib.types.str;
    default = [ ];
    example = [ "steam -silent" ];
    description = "Shell commands started with the Hyprland session.";
  };

  config = lib.mkIf (!hostPlatform.isServer) {
    environment.etc."hypr/autostart".text = lib.concatMapStrings (
      c: c + "\n"
    ) config.workstation.autostart;
  };
}
