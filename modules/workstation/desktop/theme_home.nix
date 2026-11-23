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

    # qt5ct/qt6ct colour scheme: one colour per QPalette role, in the role order
    # WindowText, Button, Light, Midlight, Dark, Mid, Text, BrightText, ButtonText, Base,
    # Window, Shadow, Highlight, HighlightedText, Link, LinkVisited, AlternateBase, NoRole,
    # ToolTipBase, ToolTipText, PlaceholderText, Accent.
    qtColors = roles: "#ff" + lib.concatStringsSep ", #ff" (map (r: color.${r}) roles);
    qtActive = [
      "fg"
      "bg_highlight"
      "fg_gutter"
      "bg_highlight"
      "bg_dark"
      "terminal_black"
      "fg"
      "red"
      "fg"
      "bg_dark"
      "bg"
      "bg_dark"
      "blue0"
      "fg"
      "blue"
      "magenta"
      "bg_highlight"
      "bg"
      "bg_dark"
      "fg"
      "comment"
      "blue"
    ];
    qtDisabled = [
      "comment"
      "bg_highlight"
      "fg_gutter"
      "bg_highlight"
      "bg_dark"
      "terminal_black"
      "comment"
      "red"
      "comment"
      "bg_dark"
      "bg"
      "bg_dark"
      "bg_visual"
      "comment"
      "dark5"
      "dark5"
      "bg_highlight"
      "bg"
      "bg_dark"
      "comment"
      "comment"
      "dark5"
    ];
    qtColorScheme = pkgs.writeText "tokyonight-qtct.conf" ''
      [ColorScheme]
      active_colors=${qtColors qtActive}
      inactive_colors=${qtColors qtActive}
      disabled_colors=${qtColors qtDisabled}
    '';
    qtctSettings = {
      Appearance = {
        style = "Breeze";
        custom_palette = true;
        color_scheme_path = "${qtColorScheme}";
        icon_theme = "Papirus-Dark";
        standard_dialogs = "xdgdesktopportal";
      };
    };
  in
  {
    # * GTK
    gtk = {
      enable = true;
      # Dark preference for apps that ignore the theme: dconf color-scheme = prefer-dark,
      # which xdg-desktop-portal-gtk hands to libadwaita (GTK4, e.g. High Tide) and
      # Electron/Chromium apps as org.freedesktop.appearance color-scheme.
      colorScheme = "dark";
      theme = {
        name = "Tokyonight-Dark";
        package = pkgs.tokyonight-gtk-theme;
      };
      iconTheme = {
        name = "Papirus-Dark";
        package = pkgs.papirus-icon-theme;
      };
    };

    # Cursor for GTK and X11/XWayland (XCURSOR_THEME, XCURSOR_SIZE, ~/.icons/default).
    # Hyprland's own cursor is the hyprcursor in hyprland/config/lua/env.lua; this is the
    # same Rosé Pine design. The theme's name is the folder in the package, not "Rose-Pine".
    # XWayland windows on a host with programs.games.steamScale get a bigger XCURSOR_SIZE
    # from hyprland/config/lua/xwayland.lua (they are drawn at real pixels there).
    home.pointerCursor = {
      name = "BreezeX-RosePine-Linux";
      package = pkgs.rose-pine-cursor;
      size = 32;
      gtk.enable = true;
      x11.enable = true;
    };

    # * Qt: no theme outside Plasma unless one is set. qt6ct/qt5ct as the platform theme
    # (Qt5 and Qt6 apps alike), the Breeze style for KDE's look, and the Tokyo Night
    # palette below instead of Breeze's colours.
    qt = {
      enable = true;
      platformTheme.name = "qtct";
      style.name = "breeze";
      qt5ctSettings = qtctSettings;
      qt6ctSettings = qtctSettings;
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
