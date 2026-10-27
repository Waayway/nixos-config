{
  pkgs,
  lib,
  color,
  hostPlatform,
  ...
}:
lib.optionalAttrs hostPlatform.isLinux (
  let
    palette = lib.filterAttrs (n: _: n != "name") color;
  in
  {
    # * GTK
    gtk = {
      enable = true;
      theme = {
        name = "Tokyonight-Dark";
        package = pkgs.tokyonight-gtk-theme;
      };
      iconTheme = {
        name = "Papirus-Dark";
        package = pkgs.papirus-icon-theme;
      };
      cursorTheme = {
        name = "Rose-Pine";
        package = pkgs.rose-pine-cursor;
      };
    };

    # The palette (tools/color.nix) for the hand-written configs in
    # ~/.config/hypr and ~/.config/quickshell, which are links into the repo
    # and can't hold generated files.
    xdg.configFile = {
      # Hyprland: dofile(), values are hex without '#'.
      "theme/colors.lua".text = ''
        return {
        ${lib.concatStrings (lib.mapAttrsToList (n: v: "  ${n} = \"${v}\",\n") palette)}}
      '';
      # hyprlock/hypridle/hyprpaper: `source =` it, use as rgb($blue).
      "theme/colors.conf".text = lib.concatStrings (lib.mapAttrsToList (n: v: "\$${n} = ${v}\n") palette);
      # Quickshell: values with '#'.
      "theme/colors.json".text = builtins.toJSON (lib.mapAttrs (_: v: "#${v}") palette);
    };
  }
)
