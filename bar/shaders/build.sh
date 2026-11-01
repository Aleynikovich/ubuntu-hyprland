#!/usr/bin/env bash
# Compiles the bar shader to bar_morph.frag.qsb (needs Qt's qsb: it is in ~/.local/opt/hyprland/qt/*/gcc_64/bin or on PATH).
set -euo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
QSB="$(command -v qsb || ls ~/.local/opt/hyprland/qt/*/gcc_64/bin/qsb | tail -1)"
"$QSB" --glsl "100 es,120,150,330,440" --hlsl 50 --msl 12 -o "$HERE/bar_morph.frag.qsb" "$HERE/bar_morph.frag"
echo "built bar_morph.frag.qsb"
