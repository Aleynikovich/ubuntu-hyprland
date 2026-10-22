#!/usr/bin/env bash
# Makes the end-4 bar music-reactive: the whole bar silhouette (smooth waveform edges that follow the system audio) is drawn by BarMorph.qml.
# Copies BarMorph.qml, bar_morph.frag.qsb (the shader, built by shaders/build.sh) and cava_morph.conf (the music feed) next to BarContent.qml and patches BarContent.qml (the original is saved once as BarContent.qml.orig and every run patches from it).
# Idempotent. All or nothing: if an anchor is missing (shell updated upstream) nothing is written.
# Rollback: cp BarContent.qml.orig BarContent.qml; delete BarMorph.qml and cava_morph.conf.   Test: QS_DIR=/some/copy ./install_bar.sh
set -euo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BAR="${QS_DIR:-$HOME/.config/quickshell/ii}/modules/ii/bar"
python3 - "$BAR" "$HERE/BarMorph.qml" <<'PY'
import os, sys
bar, morph = sys.argv[1], sys.argv[2]
target = f"{bar}/BarContent.qml"
try:
    cur = open(target).read()
    if "BarMorph" not in cur and not os.path.exists(target + ".orig"):
        open(target + ".orig", "w").write(cur)
    s = open(target + ".orig").read() if os.path.exists(target + ".orig") else cur
except OSError as e:
    raise SystemExit(f"install_bar.sh: cannot read {target}: {e}")
bg = "        border.color: Appearance.colors.colLayer0Border\n    }\n"
col = '        color: Config.options.bar.showBackground ? Appearance.colors.colLayer0 : "transparent"\n'
if s.count(bg) != 1 or s.count(col) != 1:
    raise SystemExit("install_bar.sh: NOT patching, bar background anchors not found in BarContent.qml (the shell was updated?)")
# the bar's rectangular drop shadow would sit under the morphing shape as a dark box: fade it out while the shape is active
shadow = "        anchors.fill: barBackground\n        sourceComponent: StyledRectangularShadow {\n"
if s.count(shadow) != 1:
    raise SystemExit("install_bar.sh: NOT patching, shadow anchor not found in BarContent.qml (the shell was updated?)")
s = s.replace(shadow, "        anchors.fill: barBackground\n        opacity: 1 - morph.morphing  // BarMorph: no box-shaped shadow under a morphing bar\n        sourceComponent: StyledRectangularShadow {\n", 1)
# the bar's own rectangle goes transparent: BarMorph draws the whole bar silhouette (body, border, needles)
s = s.replace(col, '        color: "transparent"  // drawn by BarMorph\n', 1)
s = s.replace(bg, '        border.color: "transparent"\n    }\n    BarMorph { id: morph; bar: barBackground }\n', 1)
# the shape's middle moves down a little while it morphs: move the three sections (left, middle, right) with it so icons and text stay centred in it
for sec in ("barLeftSideMouseArea", "middleSection", "barRightSideMouseArea"):
    a = f"id: {sec}\n"
    if s.count(a) != 1:
        raise SystemExit(f"install_bar.sh: NOT patching, '{a.strip()}' not found in BarContent.qml (the shell was updated?)")
    i = s.index(a); ind = s[s.rindex("\n", 0, i) + 1:i]
    s = s.replace(a, a + f"{ind}transform: Translate {{ y: morph.centerShift }}\n", 1)
tmp = f"{target}.new.{os.getpid()}"
open(tmp, "w").write(s)
os.replace(tmp, target)
# the shader gets a name that carries its content hash: Qt caches shaders by file name, so a changed shader must have a new name to be picked up
import glob, hashlib
shader_src = os.path.join(os.path.dirname(morph), "shaders", "bar_morph.frag.qsb")
blob = open(shader_src, "rb").read()
shader_name = f"bar_morph.{hashlib.sha1(blob).hexdigest()[:8]}.frag.qsb"
for old in glob.glob(f"{bar}/bar_morph.*.frag.qsb"):
    if os.path.basename(old) != shader_name:
        os.remove(old)
open(f"{bar}/{shader_name}", "wb").write(blob)
open(f"{bar}/BarMorph.qml", "w").write(open(morph).read().replace("bar_morph.frag.qsb", shader_name))
open(f"{bar}/cava_morph.conf", "w").write(open(os.path.join(os.path.dirname(morph), "cava_morph.conf")).read())
print("installed: the bar now moves with the music")
PY
