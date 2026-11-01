#!/bin/bash
# Idle stages that depend on the power source, called from hypridle listeners.
#   idle-power.sh dim|off ac|bat   (no-op unless the machine is on that power source)
#   idle-power.sh resume           (undo dim, screen back on; idempotent)
state=/tmp/idle-dim-brightness
fadepid=/tmp/idle-dim-fade.pid
fade_secs=10   # dim ramps down over this long, starting when the listener fires
# The fade runs in its own process group (setsid), so killing the group stops awk, the read loop and sleep together
stop_fade() { [ -e "$fadepid" ] && kill -- -"$(cat "$fadepid")" 2>/dev/null; rm -f "$fadepid"; }
on_ac() { local f; for f in /sys/class/power_supply/*/; do [ "$(cat "$f/type" 2>/dev/null)" = Mains ] && [ "$(cat "$f/online" 2>/dev/null)" = 1 ] && return 0; done; return 1; }
dpms() { hyprctl dispatch "hl.dsp.dpms({ action = \"$1\" })" >/dev/null 2>&1; }
case "$1" in
  dim|off)
    if [ "$2" = ac ]; then on_ac || exit 0; else on_ac && exit 0; fi ;;
esac
case "$1" in
  dim)
    [ -e "$state" ] && exit 0
    cur=$(brightnessctl -m get 2>/dev/null) || exit 0
    echo "$cur" > "$state"
    setsid "$0" fade "$cur" >/dev/null 2>&1 &
    echo $! > "$fadepid" ;;
  fade)
    # The panel only has 100 backlight levels, so step often and ease in/out (smoothstep) to avoid visible jumps
    cur=$2; target=$(( cur / 5 > 0 ? cur / 5 : 1 ))
    awk -v cur="$cur" -v target="$target" -v secs="$fade_secs" 'BEGIN {
      n = secs * 12; last = cur
      for (i = 1; i <= n; i++) {
        t = i / n; e = t * t * (3 - 2 * t)
        v = int(cur - (cur - target) * e + 0.5)
        if (v != last) { print v; last = v; fflush() }
        system("sleep " secs / n)
      }
    }' | while read -r v; do brightnessctl -q set "$v"; done
    rm -f "$fadepid" ;;
  off) dpms disable ;;
  resume)
    stop_fade
    if [ -e "$state" ]; then brightnessctl -q set "$(cat "$state")"; rm -f "$state"; fi
    dpms enable ;;
esac
