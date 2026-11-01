-- Personal binds (phase 50 installs this when the file is empty; phases 55/96/98 append their own blocks)
hl.bind("CTRL+SUPER+ALT+Slash", hl.dsp.exec_cmd("xdg-open ~/.config/hypr/custom/keybinds.lua"), {description = "Edit user keybinds"} )

hl.bind("SUPER + SHIFT + E",
	hl.dsp.exec_cmd("dolphin --new-window",
		{ floating = true, size = { "1200", "800" }, move = { "(cursor_x-window_w*.5)", "(cursor_y-window_h*.5)" } }),
	{ description = "App: Floating Dolphin" })
hl.bind("SUPER + SHIFT + Return",
	hl.dsp.exec_cmd(
		HOME .. "/.local/kitty.app/bin/kitty --class floating-kitty --override initial_window_width=160c --override initial_window_height=40c",
		{ floating = true, move = { "(cursor_x-window_w*.5)", "(cursor_y-window_h*.5)" } }),
	{ description = "App: Floating Kitty" })

-- Send window to workspace n: SUPER+SHIFT+n instead of the dots' SUPER+ALT+n (moved from hyprland/keybinds.lua, which dots updates overwrite)
for i = 1, 10 do
    hl.unbind("SUPER + ALT + " .. (i % 10))
    hl.bind("SUPER + SHIFT + " .. (i % 10), function()
        hl.dispatch(hl.dsp.window.move({ workspace = workspace_in_group(i), follow = false }))
    end, { description = "Window: Send to workspace " .. i })
end
