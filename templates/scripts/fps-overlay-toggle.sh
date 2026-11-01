#!/bin/sh
# Toggle Hyprland's debug overlay (per-monitor FPS / frame time / render time).
if [ "$(hyprctl getoption debug:overlay | sed -n 's/^bool: //p')" = "true" ]; then
    new=false
else
    new=true
fi
hyprctl eval "hl.config({ debug = { overlay = $new } })"
