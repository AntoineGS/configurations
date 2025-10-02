local wezterm = require("wezterm")
local act = wezterm.action
local config = wezterm.config_builder()
local launch_menu = {}
-- local tabline = wezterm.plugin.require("https://github.com/michaelbrusegard/tabline.wez")
local is_windows = wezterm.target_triple == "x86_64-pc-windows-msvc"

--wezterm.on("gui-startup", function(cmd)
--	local _, _, window = mux.spawn_window(cmd or {})
--	window:gui_window():maximize()
--end)

config.inactive_pane_hsb = {
	saturation = 0.8,
	brightness = 0.7,
}

config.enable_wayland = false

if is_windows then
	config.window_background_opacity = 0.5
	config.win32_system_backdrop = "Mica"
else
	config.window_background_opacity = 0.98
end

---config.tab_bar_at_bottom = true
config.window_decorations = "RESIZE"
config.color_scheme = "One Dark (Gogh)"
config.font = wezterm.font("JetBrainsMono Nerd Font")
config.font_size = 13
config.use_dead_keys = true
config.scrollback_lines = 5000
config.adjust_window_size_when_changing_font_size = false
config.hide_tab_bar_if_only_one_tab = true
config.tab_max_width = 100
config.window_frame = {
	font = wezterm.font({ family = "JetBrainsMono Nerd Font", weight = "Regular" }),
}
-- config.leader = { key = "a", mods = "CTRL", timeout_milliseconds = 1000 }
config.keys = {
	{ key = "d", mods = "CTRL|SHIFT", action = act.ShowDebugOverlay },
	{ key = "l", mods = "ALT", action = act.ShowLauncher },
	{ key = "w", mods = "CTRL|SHIFT", action = act.CloseCurrentPane({ confirm = false }) },
	-- { key = "h", mods = "CTRL|SHIFT", action = act.ActivatePaneDirection("Left") },
	-- { key = "j", mods = "CTRL|SHIFT", action = act.ActivatePaneDirection("Down") },
	-- { key = "k", mods = "CTRL|SHIFT", action = act.ActivatePaneDirection("Up") },
	-- { key = "l", mods = "CTRL|SHIFT", action = act.ActivatePaneDirection("Right") },
	-- { key = "h", mods = "CTRL|SHIFT|ALT", action = act.AdjustPaneSize({ "Left", 5 }) },
	-- { key = "j", mods = "CTRL|SHIFT|ALT", action = act.AdjustPaneSize({ "Down", 5 }) },
	-- { key = "k", mods = "CTRL|SHIFT|ALT", action = act.AdjustPaneSize({ "Up", 5 }) },
	-- { key = "l", mods = "CTRL|SHIFT|ALT", action = act.AdjustPaneSize({ "Right", 5 }) },
	-- { key = "h", mods = "LEADER", action = act.SplitHorizontal({ domain = "CurrentPaneDomain" }) },
	-- { key = "v", mods = "LEADER", action = act.SplitVertical({ domain = "CurrentPaneDomain" }) },
	-- {
	-- 	key = "_",
	-- 	mods = "CTRL|SHIFT",
	-- 	action = wezterm.action_callback(function(window, pane)
	-- 		window:restore()
	-- 	end),
	-- },
	-- {
	-- 	key = "+",
	-- 	mods = "CTRL|SHIFT",
	-- 	action = wezterm.action_callback(function(window, pane)
	-- 		window:maximize()
	-- 	end),
	-- },

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

config.default_prog = { "nu", "" }

if is_windows then
	table.insert(launch_menu, {
		label = "Pwsh",
		args = { "pwsh.exe", "-NoLogo" },
	})

	table.insert(launch_menu, {
		label = "Ubuntu",
		args = { "nu.exe", "-c ubuntu.exe" },
	})
else
end

table.insert(launch_menu, config.launch_menu)

-- local tab_info = {
-- 	"index",
-- 	{ "process" },
-- 	{ "parent", padding = 0, max_length = 50 },
-- 	"/",
-- 	{ "cwd", padding = { left = 0, right = 1 }, max_length = 100 },
-- 	{ "  " },
-- 	-- function(tab)
-- 	-- 	return tab.active_pane.current_working_dir or ""
-- 	-- end,
-- }
-- tabline.setup({
-- 	options = {
-- 		icons_enabled = true,
-- 		theme = "One Dark (Gogh)",
-- 		color_overrides = {},
-- 		section_separators = {
-- 			left = wezterm.nerdfonts.pl_left_hard_divider,
-- 			right = wezterm.nerdfonts.pl_right_hard_divider,
-- 		},
-- 		component_separators = {
-- 			left = wezterm.nerdfonts.pl_left_soft_divider,
-- 			right = wezterm.nerdfonts.pl_right_soft_divider,
-- 		},
-- 		tab_separators = {
-- 			left = wezterm.nerdfonts.pl_left_hard_divider,
-- 			right = wezterm.nerdfonts.pl_right_hard_divider,
-- 		},
-- 	},
-- 	sections = {
-- 		--tabline_a = { "mode" },
-- 		tabline_a = {},
-- 		tabline_b = {},
-- 		-- tabline_b = { "workspace" },
-- 		tabline_c = {},
-- 		tab_active = tab_info,
-- 		tab_inactive = tab_info,
-- 		-- tab_inactive = { "index", { "process", padding = { left = 0, right = 1 } } },
-- 		-- tabline_x = { "ram", "cpu" },
-- 		-- tabline_y = { "datetime", "battery" },
-- 		-- tabline_z = { "hostname" },
-- 		tabline_x = {},
-- 		tabline_y = {},
-- 		tabline_z = { "cwd" },
-- 	},
-- 	extensions = {},
-- })

config.launch_menu = launch_menu
-- tabline.apply_to_config(config)
local SOLID_LEFT_ARROW = wezterm.nerdfonts.ple_left_half_circle_thick
local SOLID_RIGHT_ARROW = wezterm.nerdfonts.ple_right_half_circle_thick

local function tab_title(tab_info)
	local title = tab_info.tab_title
	if title and #title > 0 then
		return title
	end
	return tab_info.active_pane.title
end

local color_schemes = wezterm.color.get_builtin_schemes()
local scheme = color_schemes[config.color_scheme]

wezterm.on("format-tab-title", function(tab, _, _, _, _, max_width)
	local edge_background = scheme.background
	local background = scheme.background
	local foreground = scheme.foreground

	if tab.is_active then
		background = "#C576DA"
		foreground = "#000000"
	end

	local edge_foreground = background
	local title = tab_title(tab)
	title = wezterm.truncate_right(title, max_width - 2)

	return {
		{ Background = { Color = edge_background } },
		{ Foreground = { Color = edge_foreground } },
		{ Text = SOLID_LEFT_ARROW },
		{ Background = { Color = background } },
		{ Foreground = { Color = foreground } },
		{ Text = title },
		{ Background = { Color = edge_background } },
		{ Foreground = { Color = edge_foreground } },
		{ Text = SOLID_RIGHT_ARROW },
	}
end)

return config
