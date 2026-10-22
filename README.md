# ubuntu-hyprland

My Ubuntu + Hyprland setup. Right now it holds one thing: the music-reactive top bar for the end-4 ("ii") Quickshell shell.

## Bar (bar/)
The whole bar is drawn by one fragment shader. At rest it is the plain rounded bar; while music plays, the top and bottom edges ripple with the system audio (cava) and stay inside the bar's own box. The mouse over the bar calms it so it stays clickable. No frames are drawn when nothing plays.

- `./bar/install_bar.sh` patches `~/.config/quickshell/ii/modules/ii/bar/BarContent.qml` (original saved once as `BarContent.qml.orig`; all or nothing if the shell was updated upstream). Needs `cava`.
- `./bar/bar_style.sh siri|liquid|bars|aurora|ripple|calm` switches the look live (default `ripple`, stored in `~/.config/bar-morph/style`).
- `./bar/fix_activewindow.sh` makes the active-window widget show the focused app again with a single monitor.
- `./bar/shaders/build.sh` recompiles the shader with Qt's `qsb` (the `.qsb` is committed, so you only need this after editing the `.frag`; keep it GLSL 120 / ES safe: no arrays, no bit ops).
- Rollback: copy `BarContent.qml.orig` back over `BarContent.qml` and delete `BarMorph.qml`, `cava_morph.conf` and `bar_morph.*.frag.qsb` from that folder.
