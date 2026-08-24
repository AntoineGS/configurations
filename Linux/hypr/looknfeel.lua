-- Configure the default Hyprland look'n'feel

local activeBorderColor = "rgb(cba6f7)"
local inactiveBorderColor = "rgba(595959aa)"

-- https://wiki.hypr.land/Configuring/Variables/#general
hl.config({
	general = {
		gaps_in = -1,
		gaps_out = 0,
		border_size = 1,

		col = {
			active_border = activeBorderColor,
			inactive_border = inactiveBorderColor,
		},

		resize_on_border = false,
		allow_tearing = false,
		layout = "dwindle",
	},
})

-- https://wiki.hypr.land/Configuring/Variables/#decoration
hl.config({
	decoration = {
		rounding = 0,

		shadow = {
			enabled = false,
			range = 2,
			render_power = 3,
			color = "rgba(1a1a1aee)",
		},

		blur = {
			enabled = true,
			size = 5,
			passes = 3,
			special = true,
			brightness = 0.70,
			contrast = 0.80,
		},
	},
})

-- Vicinae overlay blur
hl.layer_rule({
	name = "layerrule-1",
	match = { namespace = "vicinae" },
	blur = true,
	ignore_alpha = 0,
})

-- https://wiki.hypr.land/Configuring/Variables/#group
hl.config({
	group = {
		col = {
			border_active = activeBorderColor,
			border_inactive = inactiveBorderColor,
			border_locked_active = activeBorderColor,
			border_locked_inactive = inactiveBorderColor,
		},

		groupbar = {
			font_size = 12,
			font_family = "monospace",
			font_weight_active = "ultraheavy",
			font_weight_inactive = "normal",

			indicator_height = 0,
			indicator_gap = 5,
			height = 22,
			gaps_in = 5,
			gaps_out = 0,

			text_color = "rgb(ffffff)",
			text_color_inactive = "rgba(ffffff90)",
			col = {
				active = "rgba(00000040)",
				inactive = "rgba(00000020)",
			},

			gradients = true,
			gradient_rounding = 0,
			gradient_round_only_edges = false,
		},
	},
})

-- https://wiki.hypr.land/Configuring/Variables/#animations
hl.config({ animations = { enabled = true } })

hl.curve("easeOutQuint", { type = "bezier", points = { { 0.23, 1 }, { 0.32, 1 } } })
hl.curve("easeInOutCubic", { type = "bezier", points = { { 0.65, 0.05 }, { 0.36, 1 } } })
hl.curve("linear", { type = "bezier", points = { { 0, 0 }, { 1, 1 } } })
hl.curve("almostLinear", { type = "bezier", points = { { 0.5, 0.5 }, { 0.75, 1 } } })
hl.curve("quick", { type = "bezier", points = { { 0.15, 0 }, { 0.1, 1 } } })

-- Smooth bezier curves
hl.curve("smoothOut", { type = "bezier", points = { { 0.36, 0 }, { 0.66, -0.56 } } })
hl.curve("smoothIn", { type = "bezier", points = { { 0.25, 1 }, { 0.5, 1 } } })
hl.curve("overshot", { type = "bezier", points = { { 0.05, 0.9 }, { 0.1, 1.05 } } })
hl.curve("softSnap", { type = "bezier", points = { { 0.2, 0.8 }, { 0.2, 1 } } })
hl.curve("gentleFade", { type = "bezier", points = { { 0.4, 0 }, { 0.2, 1 } } })

hl.animation({ leaf = "global", enabled = true, speed = 10, bezier = "default" })
hl.animation({ leaf = "windows", enabled = true, speed = 4.79, bezier = "easeOutQuint" })
hl.animation({ leaf = "fade", enabled = true, speed = 3.03, bezier = "quick" })
hl.animation({ leaf = "layersIn", enabled = true, speed = 4, bezier = "easeOutQuint", style = "fade" })
hl.animation({ leaf = "layersOut", enabled = true, speed = 1.5, bezier = "linear", style = "fade" })
hl.animation({ leaf = "fadeLayersIn", enabled = true, speed = 1.79, bezier = "almostLinear" })
hl.animation({ leaf = "fadeLayersOut", enabled = true, speed = 1.39, bezier = "almostLinear" })

-- Window open/close
hl.animation({ leaf = "windowsIn", enabled = true, speed = 5, bezier = "overshot", style = "popin 80%" })
hl.animation({ leaf = "windowsOut", enabled = true, speed = 4, bezier = "smoothOut", style = "popin 80%" })
hl.animation({ leaf = "windowsMove", enabled = true, speed = 4, bezier = "softSnap" })

-- Fading
hl.animation({ leaf = "fadeIn", enabled = true, speed = 3, bezier = "smoothIn" })
hl.animation({ leaf = "fadeOut", enabled = true, speed = 3, bezier = "smoothOut" })
hl.animation({ leaf = "fadeSwitch", enabled = true, speed = 5, bezier = "gentleFade" })
hl.animation({ leaf = "fadeDim", enabled = true, speed = 5, bezier = "gentleFade" })

-- Border color transition (the .conf defined "border" twice; the second value wins, so we emit only that one)
hl.animation({ leaf = "border", enabled = true, speed = 8, bezier = "softSnap" })
hl.animation({ leaf = "borderangle", enabled = true, speed = 30, bezier = "smoothIn" })

-- Workspace switching (slide effect)
hl.animation({ leaf = "workspaces", enabled = true, speed = 5, bezier = "overshot", style = "slidevert" })
hl.animation({ leaf = "specialWorkspace", enabled = true, speed = 5, bezier = "overshot", style = "slidevert" })

-- Layer animations
hl.animation({ leaf = "layers", enabled = true, speed = 4, bezier = "softSnap", style = "fade" })
hl.animation({ leaf = "fadeLayers", enabled = true, speed = 4, bezier = "gentleFade" })

-- See https://wiki.hypr.land/Configuring/Layouts/Dwindle-Layout/ for more
hl.config({
	dwindle = {
		preserve_split = true,
		force_split = 2, -- Always split on the right
	},
})

-- See https://wiki.hypr.land/Configuring/Layouts/Master-Layout/ for more
hl.config({
	master = {
		new_status = "master",
	},
})

-- https://wiki.hypr.land/Configuring/Variables/#misc
hl.config({
	misc = {
		disable_hyprland_logo = true,
		disable_splash_rendering = true,
		focus_on_activate = true,
		anr_missed_pings = 3,
		on_focus_under_fullscreen = 1,
	},
})

-- https://wiki.hypr.land/Configuring/Variables/#cursor
hl.config({
	cursor = {
		hide_on_key_press = true,
		warp_on_change_workspace = 1,
	},
})

-- Auto toggle scratchpad on switching workspace from scratchpad
hl.config({
	binds = {
		hide_special_on_workspace_change = true,
	},
})

-- Style Gum confirm to match terminal theme
hl.env("GUM_CONFIRM_PROMPT_FOREGROUND", "6") -- Cyan
hl.env("GUM_CONFIRM_SELECTED_FOREGROUND", "0") -- Black
hl.env("GUM_CONFIRM_SELECTED_BACKGROUND", "2") -- Green
hl.env("GUM_CONFIRM_UNSELECTED_FOREGROUND", "7") -- White
hl.env("GUM_CONFIRM_UNSELECTED_BACKGROUND", "8") -- Dark grey

-- Terminal transparency (controlled by Hyprland so SUPER+Backspace toggle works)
hl.window_rule({
	match = { tag = "terminal" },
	opacity = "0.90 1",
})
