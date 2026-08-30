-- Menus
hl.bind("SUPER + SPACE", hl.dsp.exec_cmd("menu"), { description = "Dashboard" })
hl.bind("XF86PowerOff", hl.dsp.exec_cmd("menu system"), { description = "Power menu" })
hl.bind("SUPER + CTRL + K", hl.dsp.exec_cmd("menu-keybindings"), { description = "Show key bindings" })
hl.bind("XF86Calculator", hl.dsp.exec_cmd("menu --calculator"), { description = "Calculator" })
hl.bind("SUPER + CTRL + W", hl.dsp.exec_cmd("desktop-shell-activate"), { description = "Reload top bar" })
hl.bind("SUPER + CTRL + H", hl.dsp.exec_cmd("restart-hyprctl"), { description = "Reload Hyprland" })

-- Aesthetics
hl.bind("SUPER + SHIFT + SPACE", hl.dsp.exec_cmd("toggle-desktop-shell-bar"), { description = "Toggle top bar" })
hl.bind(
	"SUPER + BACKSPACE",
	hl.dsp.window.set_prop({ prop = "opaque", value = "toggle" }),
	{ description = "Toggle window transparency" }
)
hl.bind(
	"SUPER + SHIFT + BACKSPACE",
	hl.dsp.exec_cmd("hyprland-window-gaps-toggle"),
	{ description = "Toggle window gaps" }
)
hl.bind(
	"SUPER + CTRL + BACKSPACE",
	hl.dsp.exec_cmd("hyprland-window-single-square-aspect-toggle"),
	{ description = "Toggle single-window square aspect" }
)

-- Notifications
hl.bind(
	"SUPER + SHIFT + COMMA",
	hl.dsp.exec_cmd("desktop-shell call desktop.notifications dismissAll"),
	{ description = "Dismiss all notifications" }
)
hl.bind(
	"SUPER + CTRL + COMMA",
	hl.dsp.exec_cmd("toggle-notification-silencing"),
	{ description = "Toggle silencing notifications" }
)
hl.bind(
	"SUPER + ALT + COMMA",
	hl.dsp.exec_cmd("desktop-shell call desktop.notifications invokeLast"),
	{ description = "Invoke last notification" }
)
hl.bind(
	"SUPER + SHIFT + ALT + COMMA",
	hl.dsp.exec_cmd("desktop-shell call desktop.notifications restoreLast"),
	{ description = "Restore last notification" }
)
hl.bind(
	"SUPER + CTRL + N",
	hl.dsp.exec_cmd("desktop-shell call desktop.notifications toggleHistory"),
	{ description = "Notification history" }
)

-- Workspaces
hl.bind("SUPER + COMMA", hl.dsp.exec_cmd("hyprland-workspace-rename"), { description = "Rename workspace" })

-- Pacman
hl.bind("SUPER + CTRL + I", hl.dsp.exec_cmd("launch-tui-large pkg-install"), { description = "Install packages" })
hl.bind("SUPER + CTRL + U", hl.dsp.exec_cmd("launch-tui-large update"), { description = "Update system" })
hl.bind("SUPER + CTRL + R", hl.dsp.exec_cmd("launch-tui-large pkg-remove"), { description = "Remove packages" })
hl.bind(
	"SUPER + CTRL + A",
	hl.dsp.exec_cmd("launch-tui-large pkg-aur-install"),
	{ description = "Install AUR packages" }
)

-- Captures
hl.bind("PRINT", hl.dsp.exec_cmd("cmd-screenshot"), { description = "Screenshot" })
hl.bind("SUPER + CTRL + S", hl.dsp.exec_cmd("cmd-screenshot"), { description = "Screenshot" })
hl.bind("ALT + PRINT", hl.dsp.exec_cmd("menu trigger.screenrecord"), { description = "Screenrecording" })
hl.bind("SUPER + PRINT", hl.dsp.exec_cmd("pkill hyprpicker || hyprpicker -a"), { description = "Color picker" })

-- Control panels
hl.bind("SUPER + CTRL + T", hl.dsp.exec_cmd("launch-tui-large btop"), { description = "Top" })

-- Zoom (legacy `hyprctl keyword` rejected by Lua parser; round-trip through `hyprctl eval` + hl.config / hl.get_config)
hl.bind(
	"SUPER + CTRL + Z",
	hl.dsp.exec_cmd([[hyprctl eval 'hl.config({cursor = {zoom_factor = hl.get_config("cursor:zoom_factor") + 1}})']]),
	{ description = "Zoom in" }
)
hl.bind(
	"SUPER + CTRL + ALT + Z",
	hl.dsp.exec_cmd([[hyprctl eval 'hl.config({cursor = {zoom_factor = 1}})']]),
	{ description = "Reset zoom" }
)

-- Lock system
hl.bind("SUPER + CTRL + L", hl.dsp.exec_cmd("lock-screen"), { description = "Lock system" })

-- Display
-- Laptop-only: the takeover script assumes eDP-1 and disables monitors on the desktop.
local hostname_pipe = io.popen("hostname")
local hostname = hostname_pipe and hostname_pipe:read("*l") or ""
if hostname_pipe then
	hostname_pipe:close()
end

if hostname == "omarchbook" then
	hl.bind(
		"SUPER + E",
		hl.dsp.exec_cmd("~/.config/hypr/scripts/toggle-external-takeover.sh"),
		{ description = "Toggle external display takeover" }
	)
end

hl.bind(
	"SUPER + V",
	hl.dsp.exec_cmd("desktop-shell toggle desktop.clipboard '{}'"),
	{ description = "Clipboard history" }
)
hl.bind("SUPER + PERIOD", hl.dsp.exec_cmd("desktop-shell toggle desktop.emojis '{}'"), { description = "Emoji picker" })
