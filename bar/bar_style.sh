#!/usr/bin/env bash
# Pick the bar's look live: ./bar_style.sh siri|liquid|bars|aurora|ripple|calm   (no argument shows the current one)
F="$HOME/.config/bar-morph/style"
if [ $# -eq 0 ]; then cat "$F" 2>/dev/null || echo ripple; exit 0; fi
case "$1" in
  siri|liquid|bars|aurora|ripple|calm) mkdir -p "$(dirname "$F")"; echo "$1" > "$F"; echo "bar style: $1";;
  *) echo "unknown style '$1' (siri liquid bars aurora ripple calm)" >&2; exit 1;;
esac
