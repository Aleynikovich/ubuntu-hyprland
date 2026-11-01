#!/usr/bin/env bash
# Screen idle behaviour: fade-dim then screen off (battery vs AC), never auto-lock or suspend; Super+L locks and blanks the screen.
# Why: the dots' hypridle locks at 5 min and suspends at 15, and the NVIDIA panel wakes slowly from that. Instead: on battery the screen fades down
#   from 20 s and turns off at 60 s; on AC the fade starts at 4m50 and the screen turns off at 10 min. Any key or mouse move undoes it.
#   hypridle can't branch on the power source, so each listener calls templates/scripts/idle-power.sh, which only acts for the matching source.
# Rollback: restore the listener blocks in ~/.config/hypr/hypridle.conf from ~/.config/hypr/hypridle.conf.bak-idle; remove the "Super+L" block from ~/.config/hypr/custom/keybinds.lua
set -euo pipefail
source "$(dirname "$0")/../lib/common.sh"

step "idle-power script"
install -Dm755 "$(dirname "$0")/../templates/scripts/idle-power.sh" ~/.config/hypr/custom/scripts/idle-power.sh

step "hypridle listeners"
IDLE="$HOME/.config/hypr/hypridle.conf"
[ -f "$IDLE" ] || die "$IDLE not found (run phase 50 first)"
if grep -q idle-power.sh "$IDLE"; then echo "listeners already present"; else
  cp "$IDLE" "$IDLE.bak-idle"
  python3 - "$IDLE" <<'PY'
import re, sys
p = sys.argv[1]
s = re.sub(r'\nlistener \{.*?\n\}\n', '\n', open(p).read(), flags=re.S).rstrip() + "\n\n"
S = '~/.config/hypr/custom/scripts/idle-power.sh'
for t, a, w in [(20, 'dim', 'bat'), (60, 'off', 'bat'), (290, 'dim', 'ac'), (600, 'off', 'ac')]:
    s += f"listener {{\n    timeout = {t}\n    on-timeout = {S} {a} {w}\n    on-resume = {S} resume\n}}\n\n"
s += "# Never auto-lock or suspend. A 10 s fade starts at 20 s on battery / 4m50 on AC, screen off at 60 s / 10 min (idle-power.sh checks the source).\n"
open(p, 'w').write(s)
PY
  pkill -x hypridle || true; (setsid hypridle >/dev/null 2>&1 &)
fi

step "Super+L: lock, then screen off"
BINDS="$HOME/.config/hypr/custom/keybinds.lua"
if grep -q 'SUPER + L"' "$BINDS" 2>/dev/null; then echo "bind already present"; else
  cat >> "$BINDS" <<'EOF2'

-- Super+L: lock, then turn the screen off (any key wakes it to the lock screen). Replaces the dots' plain lock bind.
hl.unbind("SUPER + L")
hl.bind("SUPER + L", hl.dsp.exec_cmd("loginctl lock-session; sleep 1; hyprctl dispatch 'hl.dsp.dpms({ action = \"disable\" })'"), { description = "Session: Lock" })
EOF2
fi
ok "Idle dim/off active now (hypridle restarted); Super+L bind applies after a Hyprland reload."
