#!/usr/bin/env bash
# The end-4 bar's active-window widget looks the monitor up as HyprlandData.monitors[<hyprland monitor id>], but that is a list position: once an external monitor
# is unplugged the laptop screen has id 1 at position 0 and the widget falls back to "Desktop / Workspace 1" instead of the focused app.
# This searches the list by id instead. Idempotent; ActiveWindow.qml is saved once as ActiveWindow.qml.orig. Rollback: cp ActiveWindow.qml.orig ActiveWindow.qml
set -euo pipefail
F="${QS_DIR:-$HOME/.config/quickshell/ii}/modules/ii/bar/ActiveWindow.qml"
python3 - "$F" <<'PY'
import os, sys
f = sys.argv[1]
s = open(f).read()
old = "HyprlandData.monitors[root.monitor?.id]?.activeWorkspace.id"
new = "(HyprlandData.monitors.find(m => m.id === root.monitor?.id))?.activeWorkspace.id"
if new in s:
    print("already fixed"); raise SystemExit
if s.count(old) != 1:
    raise SystemExit("fix_activewindow.sh: NOT patching, the line was not found (the shell was updated?)")
if not os.path.exists(f + ".orig"):
    open(f + ".orig", "w").write(s)
tmp = f + f".new.{os.getpid()}"
open(tmp, "w").write(s.replace(old, new, 1))
os.replace(tmp, f)
print("patched ActiveWindow.qml: the focused app shows again with one monitor")
PY
