{
  config,
  lib,
  hostPlatform,
  ...
}:
let
  cfg = config.darwin.wallpaper;
in
{
  options.darwin.wallpaper = lib.mkOption {
    type = lib.types.str;
    default = "random";
    example = "evening-sky.png";
    description = ''
      macOS desktop picture: a file name from ~/.wallpapers (the repo's
      wallpapers/ folder), or "random" to pick a new one on every switch.
    '';
  };

  config = {
    # Used by Hyprland's wallpaper scripts and the macOS picker below.
    home.file.".wallpapers".source = ../../wallpapers;
  }
  // lib.optionalAttrs hostPlatform.isDarwin {
    # Sets the picture on every display. macOS asks once for permission to
    # let the terminal control "System Events".
    home.activation.wallpaper = lib.hm.dag.entryAfter [ "linkGeneration" ] ''
      dir="$HOME/.wallpapers"
      ${
        if cfg == "random" then
          ''pic="$(/usr/bin/find -L "$dir" -maxdepth 1 -type f | /usr/bin/sort -R | /usr/bin/head -n 1)"''
        else
          ''pic="$dir/${cfg}"''
      }
      if [ -f "$pic" ]; then
        run /usr/bin/osascript -e "tell application \"System Events\" to tell every desktop to set picture to POSIX file \"$pic\"" || true
      fi
    '';
  };
}
