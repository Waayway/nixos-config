#!/bin/sh

MONITOR_NUM=$(($1 - 1))

MONITOR_NAME=$(hyprctl monitors -j | jq -r ".[$MONITOR_NUM] | .name")

hyprctl dispatch movecurrentworkspacetomonitor $MONITOR_NAME

