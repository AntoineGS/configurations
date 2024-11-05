local wezterm = require("wezterm")
local mux = wezterm.mux
local act = wezterm.action
local config = wezterm.config_builder()
local launch_menu = {}

wezterm.on("gui-startup", function()
	local tab, pane, window = mux.spawn_window({})
	window:gui_window():maximize()
end)

---config.color_scheme = "Hardcode"
config.font = wezterm.font("JetBrainsMono Nerd Font")
config.font_size = 14
config.use_dead_keys = false
config.scrollback_lines = 5000
config.adjust_window_size_when_changing_font_size = false
config.hide_tab_bar_if_only_one_tab = true
config.window_frame = {
	font = wezterm.font({ family = "Noto Sans", weight = "Regular" }),
}
config.leader = { key = "a", mods = "CTRL", timeout_milliseconds = 1000 }
config.keys = {
	{ key = "d", mods = "CTRL|SHIFT", action = act.ShowDebugOverlay },
	{ key = "l", mods = "ALT", action = act.ShowLauncher },
	{ key = "w", mods = "CTRL|SHIFT", action = act.CloseCurrentPane({ confirm = false }) },
	{ key = "h", mods = "CTRL|SHIFT", action = act.ActivatePaneDirection("Left") },
	{ key = "j", mods = "CTRL|SHIFT", action = act.ActivatePaneDirection("Down") },
	{ key = "k", mods = "CTRL|SHIFT", action = act.ActivatePaneDirection("Up") },
	{ key = "l", mods = "CTRL|SHIFT", action = act.ActivatePaneDirection("Right") },
	{ key = "h", mods = "CTRL|SHIFT|ALT", action = act.AdjustPaneSize({ "Left", 5 }) },
	{ key = "j", mods = "CTRL|SHIFT|ALT", action = act.AdjustPaneSize({ "Down", 5 }) },
	{ key = "k", mods = "CTRL|SHIFT|ALT", action = act.AdjustPaneSize({ "Up", 5 }) },
	{ key = "l", mods = "CTRL|SHIFT|ALT", action = act.AdjustPaneSize({ "Right", 5 }) },
	{ key = "s", mods = "LEADER", action = act.SplitHorizontal({ domain = "CurrentPaneDomain" }) },
	{ key = "v", mods = "LEADER", action = act.SplitVertical({ domain = "CurrentPaneDomain" }) },

	--- Ignores
	{ key = "LeftArrow", mods = "CTRL|SHIFT|ALT", action = act.DisableDefaultAssignment },
	{ key = "RightArrow", mods = "CTRL|SHIFT|ALT", action = act.DisableDefaultAssignment },
	{ key = "UpArrow", mods = "CTRL|SHIFT|ALT", action = act.DisableDefaultAssignment },
	{ key = "DownArrow", mods = "CTRL|SHIFT|ALT", action = act.DisableDefaultAssignment },
	{ key = "LeftArrow", mods = "CTRL|SHIFT", action = act.DisableDefaultAssignment },
	{ key = "RightArrow", mods = "CTRL|SHIFT", action = act.DisableDefaultAssignment },
	{ key = "UpArrow", mods = "CTRL|SHIFT", action = act.DisableDefaultAssignment },
	{ key = "DownArrow", mods = "CTRL|SHIFT", action = act.DisableDefaultAssignment },
}

if wezterm.target_triple == "x86_64-pc-windows-msvc" then
	config.default_prog = { "nu", "" }
	config.window_decorations = "RESIZE"

	table.insert(launch_menu, {
		label = "PowerShell",
		args = { "powershell.exe", "-NoLogo" },
	})

	table.insert(launch_menu, {
		label = "Pwsh",
		args = { "pwsh.exe", "-NoLogo" },
	})

	table.insert(launch_menu, {
		label = "Ubuntu",
		args = { "ubuntu.exe", "" },
	})
---config.inactive_pane_hsb = {
---saturation = 0.8
---brightness = 0.7
---}
else
end
table.insert(launch_menu, config.launch_menu)
config.launch_menu = launch_menu

return config
