#!/usr/bin/env bash
# Started by Hyprland (lua/autostart.lua): waits for awww-daemon, then a new
# wallpaper every 5 minutes.

INTERVAL=300
DIR="$(dirname "$0")"

until awww query >/dev/null 2>&1; do sleep 0.2; done

while true; do
  bash "$DIR/wallpaper-random.sh"
  sleep "$INTERVAL"
done
