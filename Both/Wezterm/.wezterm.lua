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
config.font = wezterm.font("JetBrainsMono Nerd Font", { weight = "Bold" })
config.font_size = 11
config.use_dead_keys = true
config.scrollback_lines = 5000
config.adjust_window_size_when_changing_font_size = false
config.hide_tab_bar_if_only_one_tab = false
config.tab_max_width = 100
config.window_frame = {
	font = wezterm.font({ family = "JetBrainsMono Nerd Font", weight = "Bold" }),
	active_titlebar_bg = "#282c34",
	inactive_titlebar_bg = "#282c34",
}
config.leader = { key = "b", mods = "CTRL", timeout_milliseconds = 5000 }
config.keys = {
	-- Send C-b to the terminal when pressing C-b twice
	{ key = "b", mods = "LEADER|CTRL", action = act.SendKey({ key = "b", mods = "CTRL" }) },

	-- Windows (tmux: c, n, p, number, w, ,, &)
	{ key = "c", mods = "LEADER", action = act.SpawnTab("CurrentPaneDomain") },
	{ key = "c", mods = "LEADER|SHIFT", action = act.ShowLauncherArgs({ flags = "LAUNCH_MENU_ITEMS|DOMAINS" }) },
	{ key = "n", mods = "LEADER", action = act.ActivateTabRelative(1) },
	{ key = "p", mods = "LEADER", action = act.ActivateTabRelative(-1) },
	{ key = "n", mods = "LEADER|SHIFT", action = act.MoveTabRelative(1) },
	{ key = "p", mods = "LEADER|SHIFT", action = act.MoveTabRelative(-1) },
	{ key = "1", mods = "LEADER", action = act.ActivateTab(0) },
	{ key = "2", mods = "LEADER", action = act.ActivateTab(1) },
	{ key = "3", mods = "LEADER", action = act.ActivateTab(2) },
	{ key = "4", mods = "LEADER", action = act.ActivateTab(3) },
	{ key = "5", mods = "LEADER", action = act.ActivateTab(4) },
	{ key = "6", mods = "LEADER", action = act.ActivateTab(5) },
	{ key = "7", mods = "LEADER", action = act.ActivateTab(6) },
	{ key = "8", mods = "LEADER", action = act.ActivateTab(7) },
	{ key = "9", mods = "LEADER", action = act.ActivateTab(8) },
	{ key = "w", mods = "LEADER", action = act.ShowTabNavigator },
	{
		key = ",",
		mods = "LEADER",
		action = act.PromptInputLine({
			description = "Rename tab",
			action = wezterm.action_callback(function(window, _, line)
				if line then
					window:active_tab():set_title(line)
				end
			end),
		}),
	},
	{ key = "&", mods = "LEADER|SHIFT", action = act.CloseCurrentTab({ confirm = true }) },

	-- Panes (tmux: %, ", o, x, z, arrow keys, hjkl)
	{ key = "%", mods = "LEADER|SHIFT", action = act.SplitHorizontal({ domain = "CurrentPaneDomain" }) },
	{ key = '"', mods = "LEADER|SHIFT", action = act.SplitVertical({ domain = "CurrentPaneDomain" }) },
	{ key = "o", mods = "LEADER", action = act.ActivatePaneDirection("Next") },
	{ key = "x", mods = "LEADER", action = act.CloseCurrentPane({ confirm = true }) },
	{ key = "z", mods = "LEADER", action = act.TogglePaneZoomState },
	{ key = "h", mods = "LEADER", action = act.ActivatePaneDirection("Left") },
	{ key = "j", mods = "LEADER", action = act.ActivatePaneDirection("Down") },
	{ key = "k", mods = "LEADER", action = act.ActivatePaneDirection("Up") },
	{ key = "l", mods = "LEADER", action = act.ActivatePaneDirection("Right") },
	{ key = "LeftArrow", mods = "LEADER", action = act.ActivatePaneDirection("Left") },
	{ key = "DownArrow", mods = "LEADER", action = act.ActivatePaneDirection("Down") },
	{ key = "UpArrow", mods = "LEADER", action = act.ActivatePaneDirection("Up") },
	{ key = "RightArrow", mods = "LEADER", action = act.ActivatePaneDirection("Right") },

	-- Pane resizing (tmux: C-arrow / M-arrow)
	{ key = "H", mods = "LEADER|SHIFT", action = act.AdjustPaneSize({ "Left", 5 }) },
	{ key = "J", mods = "LEADER|SHIFT", action = act.AdjustPaneSize({ "Down", 5 }) },
	{ key = "K", mods = "LEADER|SHIFT", action = act.AdjustPaneSize({ "Up", 5 }) },
	{ key = "L", mods = "LEADER|SHIFT", action = act.AdjustPaneSize({ "Right", 5 }) },

	-- Copy mode (tmux: [ and custom y)
	{ key = "[", mods = "LEADER", action = act.ActivateCopyMode },
	{ key = "y", mods = "LEADER", action = act.ActivateCopyMode },

	-- Paste (tmux: ])
	{ key = "]", mods = "LEADER", action = act.PasteFrom("Clipboard") },

	-- vim-tmux-navigator: Ctrl+hjkl without leader for seamless pane navigation
	{ key = "h", mods = "CTRL", action = act.ActivatePaneDirection("Left") },
	{ key = "j", mods = "CTRL", action = act.ActivatePaneDirection("Down") },
	{ key = "k", mods = "CTRL", action = act.ActivatePaneDirection("Up") },
	{ key = "l", mods = "CTRL", action = act.ActivatePaneDirection("Right") },

	-- Popup terminal (tmux: C-b C-p spawns a zoomed split)
	{
		key = "p",
		mods = "LEADER|CTRL",
		action = act.Multiple({
			act.SplitVertical({ domain = "CurrentPaneDomain" }),
			act.TogglePaneZoomState,
		}),
	},

	-- Misc
	{ key = "d", mods = "CTRL|SHIFT", action = act.ShowDebugOverlay },
	{ key = "l", mods = "ALT", action = act.ShowLauncher },

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
	-- WezTerm auto-discovers WSL distros as domains,
	-- so splits/new tabs inherit the correct distro.
	config.wsl_domains = wezterm.default_wsl_domains()

	table.insert(launch_menu, {
		label = "Pwsh",
		args = { "pwsh.exe", "-NoLogo" },
	})

	table.insert(launch_menu, {
		label = "Command Prompt",
		args = { "cmd.exe" },
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

-- vi copy-mode keys to match tmux vi-mode bindings
config.key_tables = {
	copy_mode = {
		{ key = "v", mods = "NONE", action = act.CopyMode({ SetSelectionMode = "Cell" }) },
		{ key = "v", mods = "CTRL", action = act.CopyMode({ SetSelectionMode = "Block" }) },
		{
			key = "y",
			mods = "NONE",
			action = act.Multiple({
				act.CopyTo("ClipboardAndPrimarySelection"),
				act.CopyMode("Close"),
			}),
		},
		{ key = "Escape", mods = "NONE", action = act.CopyMode("Close") },
		{ key = "q", mods = "NONE", action = act.CopyMode("Close") },
		{ key = "h", mods = "NONE", action = act.CopyMode("MoveLeft") },
		{ key = "j", mods = "NONE", action = act.CopyMode("MoveDown") },
		{ key = "k", mods = "NONE", action = act.CopyMode("MoveUp") },
		{ key = "l", mods = "NONE", action = act.CopyMode("MoveRight") },
		{ key = "w", mods = "NONE", action = act.CopyMode("MoveForwardWord") },
		{ key = "b", mods = "NONE", action = act.CopyMode("MoveBackwardWord") },
		{ key = "e", mods = "NONE", action = act.CopyMode("MoveForwardWordEnd") },
		{ key = "0", mods = "NONE", action = act.CopyMode("MoveToStartOfLine") },
		{ key = "$", mods = "SHIFT", action = act.CopyMode("MoveToEndOfLineContent") },
		{ key = "^", mods = "SHIFT", action = act.CopyMode("MoveToStartOfLineContent") },
		{ key = "g", mods = "NONE", action = act.CopyMode("MoveToScrollbackTop") },
		{ key = "G", mods = "SHIFT", action = act.CopyMode("MoveToScrollbackBottom") },
		{ key = "u", mods = "CTRL", action = act.CopyMode({ MoveByPage = -0.5 }) },
		{ key = "d", mods = "CTRL", action = act.CopyMode({ MoveByPage = 0.5 }) },
		{ key = "V", mods = "SHIFT", action = act.CopyMode({ SetSelectionMode = "Line" }) },
		{ key = "/", mods = "NONE", action = act.CopyMode("EditPattern") },
		{ key = "n", mods = "NONE", action = act.CopyMode("NextMatch") },
		{ key = "N", mods = "SHIFT", action = act.CopyMode("PriorMatch") },
	},
}

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

-- One Dark palette (matching tmux-onedark-theme)
local onedark = {
	black = "#282c34",
	white = "#abb2bf",
	green = "#98c379",
	blue = "#61afef",
	yellow = "#e5c07b",
	red = "#e06c75",
	visual_grey = "#3e4452",
	comment_grey = "#5c6370",
}

wezterm.on("format-tab-title", function(tab, _, _, _, _, max_width)
	local edge_background = onedark.black
	local background
	local foreground

	if tab.is_active then
		background = onedark.green
		foreground = onedark.black
	else
		background = onedark.visual_grey
		foreground = onedark.white
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
