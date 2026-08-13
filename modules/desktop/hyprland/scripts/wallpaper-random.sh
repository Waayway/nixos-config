#!/usr/bin/env bash

WALLPAPER_DIR="$HOME/.wallpapers"
STATE_FILE="${XDG_CACHE_HOME:-$HOME/.cache}/current_wallpaper"

CURRENT_WALL=""
[ -f "$STATE_FILE" ] && CURRENT_WALL="$(cat "$STATE_FILE")"

WALLPAPER="$(
  find "$WALLPAPER_DIR" -type f \
    \( -iname '*.jpg' -o -iname '*.jpeg' -o -iname '*.png' -o -iname '*.webp' -o -iname '*.jxl' \) \
    ! -path "$CURRENT_WALL" |
  shuf -n 1
)"

[ -z "$WALLPAPER" ] && exit 1

hyprctl hyprpaper wallpaper ",$WALLPAPER,cover"
printf '%s\n' "$WALLPAPER" > "$STATE_FILE"
