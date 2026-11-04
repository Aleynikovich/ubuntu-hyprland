

-- Rice: blurred, translucent terminals (foot: foot.ini `alpha`; kitty: kitty.conf `background_opacity`)
-- Skipped while Quickshell game mode is on (it creates this flag file, then runs `hyprctl reload`)
if not is_file_exists(HOME .. "/.local/state/hypr-gamemode") then
    hl.window_rule({match = { class = ".*" }, no_blur = false, opacity = 0.96})
end
hl.window_rule({match = { class = "^floating-kitty$" }, float = true})
-- Isaac Sim (XWayland + NVIDIA): opaque, no blur. Tiled (float rule removed 2026-10-21; it was added because Isaac
-- went black when the tiler resized it: if that comes back, re-add float + center + size here)
hl.window_rule({match = { class = "^Isaac Sim.*$" }, no_blur = true, opacity = 1.0})
hl.window_rule({match = { class = "^looking-glass-client*$" }, no_blur = true, opacity = 1.0})
-- VM display (virt-viewer, X11 or Wayland): opaque, no blur, and Hyprland keeps its shortcuts (Super+F to leave fullscreen) while the VM has focus. (No "immediate"/tearing: it showed artifacts whenever the screen was not being recorded, i.e. when frames were not forced through the compositor.) The 96% opacity + blur rule above would re-blur a 3200x2000 live picture every frame.
hl.window_rule({match = { class = "^[Vv]irt-viewer$" }, no_blur = true, opacity = 1.0, no_shortcuts_inhibit = true})
hl.window_rule({match = { class = "^vivaldi-stable*$" }, no_blur = true, opacity = 1})
-- Bar: lets blur apply even when the bar is quite transparent (default 0.6 cuts blur below that)
hl.layer_rule({ match = { namespace = "bar[0-9]*" }, ignore_alpha = 0.1})
hl.layer_rule({ match = { namespace = "barcorner.*" }, ignore_alpha = 0.1})


-- Moved from hyprland/rules.lua (overwritten by dots updates): sidebars fade instead of sliding
hl.layer_rule({ match = { namespace = "sideleft.*" }, animation = "fade"})
hl.layer_rule({ match = { namespace = "sideright.*" }, animation = "fade"})
-- Automatic shell content is only 10% opaque. Upstream's 0.79 alpha cutoff skips its blur;
-- blur all visible sidebar pixels while leaving fully transparent margins clear.
hl.layer_rule({ match = { namespace = "quickshell:sidebarRight" }, animation = "fade", blur = true, ignore_alpha = 0.01})
hl.layer_rule({ match = { namespace = "quickshell:sidebarLeft" }, animation = "fade", blur = true, ignore_alpha = 0.01})

-- All panels and overlays blur the actual windows underneath, including both sidebars and the AI panel.
hl.layer_rule({ match = { namespace = ".*" }, xray = false})
