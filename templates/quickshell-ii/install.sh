#!/usr/bin/env bash
# Overlay for the end-4 shell: two sidebar quick toggles for the GPU passthrough setup (docs/windows-vm.md).
#   vmGpu        "Windows VM"    one button: start/stop the win11 VM on the RTX 4070; from the HDMI monitor session it restarts the desktop once
#   gpuSession   "HDMI monitor"  switch between the HDMI monitor session and the iGPU-only session (the same restart, windows come back)
# Copies the QML files over ~/.config/quickshell/ii and registers the types (chooser entries + availableToggleTypes). Idempotent;
# the two patched shell files are saved once as *.orig next to them. They then show up unused in the sidebar's edit mode.
# Also replaces upstream's GameModeToggle.qml (adds: drop the custom blur/translucency rule, performance power profile)
# and fixes the venv shebang of two dots scripts for dash (see below).
# Rollback: restore the *.orig files and delete the new .qml files.
set -euo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
QS="${QS_DIR:-$HOME/.config/quickshell/ii}"
# Replaced upstream files are saved once as *.orig before the copy. bar/Workspaces.qml: every app on a workspace gets its icon
# (the workspace grows by one icon per distinct app) instead of only the biggest window's.
for f in modules/ii/bar/Workspaces.qml; do
  [ -e "$QS/$f" ] && [ ! -e "$QS/$f.orig" ] && cp -p "$QS/$f" "$QS/$f.orig"
done
cp -r "$HERE/modules" "$QS/"
TQ="$QS/modules/ii/sidebarRight/quickToggles"
python3 - "$TQ" <<'PY'
import sys, re, os
tq = sys.argv[1]
chooser = f"{tq}/androidStyle/AndroidToggleDelegateChooser.qml"
panel = f"{tq}/AndroidQuickPanel.qml"
block = '''    DelegateChoice { roleValue: "%s"; %s {
        required property int index
        required property var modelData
        buttonIndex: root.startingIndex + index
        buttonData: modelData
        editMode: root.editMode
        expandedSize: modelData.size > 1
        baseCellWidth: root.baseCellWidth
        baseCellHeight: root.baseCellHeight
        cellSpacing: root.spacing
        cellSize: modelData.size
    } }

'''
s = open(chooser).read()
if 'roleValue: "vmGpu"' not in s:
    if not os.path.exists(chooser + ".orig"): open(chooser + ".orig", "w").write(s)
    anchor = '    DelegateChoice { roleValue: "gameMode"'
    assert anchor in s
    s = s.replace(anchor, block % ("vmGpu", "AndroidVmGpuToggle") + block % ("gpuSession", "AndroidGpuSessionToggle") + anchor, 1)
    open(chooser, "w").write(s); print("chooser patched")
p = open(panel).read()
if '"vmGpu"' not in p:
    if not os.path.exists(panel + ".orig"): open(panel + ".orig", "w").write(p)
    assert '"antiFlashbang"]' in p
    p = p.replace('"antiFlashbang"]', '"antiFlashbang", "vmGpu", "gpuSession"]', 1)
    open(panel, "w").write(p); print("types patched")
PY
# Ubuntu's /bin/sh is dash, which has no `source`: the dots' venv shebang (`/bin/sh -c "source <venv>/bin/activate && exec
# python ..."`) dies with "source: not found". That broke HyprlandConfig (game mode never applied its keywords) and the
# material color generator. Use POSIX `.` instead; the originals are saved once as *.orig.
for f in "$QS/scripts/hyprland/hyprconfigurator.py" "$QS/scripts/colors/generate_colors_material.py"; do
  [ -f "$f" ] || continue
  if head -1 "$f" | grep -q '"source\\_'; then
    [ -e "$f.orig" ] || cp -p "$f" "$f.orig"
    sed -i '1s/"source\\_/".\\_/' "$f"; echo "shebang fixed (dash): $f"
  fi
done
# Brightness keys with hold acceleration (phase 96): add `adjustBrightness(percent)` + IPC `brightness adjust <percent>` to the shell's
# Brightness service; the original is saved once as *.orig. The key script is scripts/brightness-accel.sh.
python3 - "$QS/services/Brightness.qml" <<'PY'
import sys, os
p = sys.argv[1]; s = open(p).read()
if "adjustBrightness" not in s:
    if not os.path.exists(p + ".orig"): open(p + ".orig", "w").write(s)
    fn = '''    // Hold-acceleration: signed percent step from the brightness keys (scripts/brightness-accel.sh)
    function adjustBrightness(percent: int): void {
        if (percent > 0) {
            if (Hyprsunset.gamma !== 100) {
                Hyprsunset.setGamma(Math.min(100, Hyprsunset.gamma + percent));
                return;
            }
            const focusedName = Hyprland.focusedMonitor.name;
            const monitor = monitors.find(m => focusedName === m.screen.name);
            if (monitor)
                monitor.setBrightness(monitor.brightness + percent / 100);
        } else if (percent < 0) {
            const focusedName = Hyprland.focusedMonitor.name;
            const monitor = monitors.find(m => focusedName === m.screen.name);
            if (monitor && monitor.brightness > 0)
                monitor.setBrightness(monitor.brightness + percent / 100);
            else
                Hyprsunset.setGamma(Hyprsunset.gamma + percent);
        }
    }

'''
    s = s.replace("    // External trigger points\n", fn + "    // External trigger points\n", 1)
    s = s.replace("        function decrement() {", "        function adjust(percent: int): void {\n            root.adjustBrightness(percent);\n        }\n\n        function decrement() {", 1)
    open(p, "w").write(s); print("Brightness.qml patched")
PY
# Desk app icons (phase 55): Vivaldi app windows have classes like vivaldi-linear.app__<path>-Default, which the icon guesser can't
# place, so the bar's workspaces showed a generic icon. Map each desk app's class to its desk-<app> icon (installed by phase 55).
# Hosts as in scripts/desk-app.sh. The original is saved once as *.orig.
python3 - "$QS/services/AppSearch.qml" <<'PY'
import sys, os
p = sys.argv[1]; s = open(p).read()
if "desk-app.sh" not in s:
    if not os.path.exists(p + ".orig"): open(p + ".orig", "w").write(s)
    apps = [("app\\.slack\\.com", "slack"), ("web\\.whatsapp\\.com", "whatsapp"), ("mail\\.google\\.com", "gmail"),
            ("linear\\.app", "linear"), ("www\\.notion\\.so", "notion")]
    block = "        // Desk apps (scripts/desk-app.sh): Vivaldi app windows -> their desk-<app> icon\n" + "".join(
        '        { "regex": /^vivaldi-%s__.*$/, "replace": "desk-%s" },\n' % a for a in apps)
    anchor = "    property var regexSubstitutions: [\n"
    assert anchor in s
    s = s.replace(anchor, anchor + block, 1)
    open(p, "w").write(s); print("AppSearch.qml patched")
PY
# SUPER tap vs hold: releasing SUPER opened the overview even after holding it to read the workspace numbers. Only a tap shorter than
# the numbers' delay (bar.autoHide.showWhenPressingSuper.delay, at least 250 ms as in bar/Workspaces.qml) opens it now. Patched from
# the *.orig (saved once), so a changed patch replaces the old one.
python3 - "$QS/modules/ii/overview/Overview.qml" <<'PY'
import sys, os
p = sys.argv[1]; s = open(p).read()
if "superPressedAt" in s and os.path.exists(p + ".orig"): s = open(p + ".orig").read()
if "superPressedAt" not in s:
    if not os.path.exists(p + ".orig"): open(p + ".orig", "w").write(s)
    old = '''        name: "searchToggleRelease"
        description: "Toggles search on release"

        onPressed: {
            GlobalStates.superReleaseMightTrigger = true;
        }

        onReleased: {
            if (!GlobalStates.superReleaseMightTrigger) {
                GlobalStates.superReleaseMightTrigger = true;
                return;
            }
'''
    new = '''        name: "searchToggleRelease"
        description: "Toggles search on release"
        // When SUPER went down. This bind (SUPER + SUPER_L) only reports the release, so the press comes from the workspaceNumber
        // shortcut (GlobalStates.superDown), which fires on key down.
        property real superPressedAt: 0
        property bool superDown: GlobalStates.superDown
        onSuperDownChanged: if (superDown) superPressedAt = Date.now()

        onPressed: {
            GlobalStates.superReleaseMightTrigger = true;
        }

        onReleased: {
            if (!GlobalStates.superReleaseMightTrigger) {
                GlobalStates.superReleaseMightTrigger = true;
                return;
            }
            // Held long enough to show the workspace numbers: that was a look, not a tap
            const hold = Config.options?.bar.autoHide.showWhenPressingSuper;
            if (hold?.enable && superPressedAt > 0 && Date.now() - superPressedAt >= Math.max(hold.delay, 250))
                return;
'''
    assert old in s
    s = s.replace(old, new, 1)
    open(p, "w").write(s); print("Overview.qml patched")
PY
# Put the buttons in the sidebar layout (two cells each) when the layout does not have them yet; config backed up once.
CFG="$HOME/.config/illogical-impulse/config.json"
if [ -f "$CFG" ]; then
  python3 - "$CFG" <<'PY'
import json, sys, os, shutil
p = sys.argv[1]
raw = open(p).read(); c = json.loads(raw)
t = c.get("sidebar", {}).get("quickToggles", {}).get("android", {}).get("toggles")
if t is not None:
    have = {x["type"] for x in t}
    new = [x for x in ("vmGpu", "gpuSession") if x not in have]
    if new:
        if not os.path.exists(p + ".pre-vmgpu"): shutil.copy2(p, p + ".pre-vmgpu")
        t.extend({"size": 2, "type": x} for x in new)
        open(p, "w").write(json.dumps(c, indent=4, ensure_ascii=False) + ("\n" if raw.endswith("\n") else ""))
        print("added to the sidebar layout:", ", ".join(new))
PY
fi
echo "quick toggles installed in $QS"
