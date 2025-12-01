#!/bin/sh

hyprctl reload

MONITORS=$(hyprctl monitors -j | jq -r '.[] | .name')

if [ $MONITORS == "eDP-1" ]; then
	echo "Only laptop display"
else
	echo "More displays connected"
	hyprctl keyword monitor eDP-1,disable
fi

eww kill && eww open bar


