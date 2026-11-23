#!/usr/bin/env bash
# Fades to a random picture from ~/.wallpapers (awww), skipping the current one.
# Called by wallpaper-rotate.sh and SUPER+SHIFT+F12.

WALLPAPER_DIR="$HOME/.wallpapers"
STATE_FILE="${XDG_CACHE_HOME:-$HOME/.cache}/current_wallpaper"

CURRENT_WALL=""
[ -f "$STATE_FILE" ] && CURRENT_WALL="$(cat "$STATE_FILE")"

# -L: ~/.wallpapers is a symlink into the Nix store.
WALLPAPER="$(
  find -L "$WALLPAPER_DIR" -type f \
    \( -iname '*.jpg' -o -iname '*.jpeg' -o -iname '*.png' -o -iname '*.webp' -o -iname '*.jxl' \) \
    ! -path "$CURRENT_WALL" |
  shuf -n 1
)"

[ -z "$WALLPAPER" ] && exit 1

awww img "$WALLPAPER" \
  --resize crop \
  --transition-type fade \
  --transition-duration 2 \
  --transition-fps 60
printf '%s\n' "$WALLPAPER" > "$STATE_FILE"
