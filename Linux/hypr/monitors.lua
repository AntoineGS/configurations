-- Monitor + persistent-workspace + default-workspace-rule definitions.
-- Replaces monitors.conf.tmpl (was rendered by tidydots based on hostname).
-- See https://wiki.hypr.land/Configuring/Basics/Monitors/

hl.env("GDK_SCALE", "1")

local hostname_pipe = io.popen("hostname")
local hostname = hostname_pipe and hostname_pipe:read("*l") or ""
if hostname_pipe then
	hostname_pipe:close()
end

if hostname == "omarchbook" then
	-- Laptop: built-in display, mirror any external monitor (TV/HDMI).
	-- External pinned to 1920x1080@60 to match the laptop panel.
	-- SUPER+E toggles "takeover" mode via scripts/toggle-external-takeover.sh.
	hl.monitor({ output = "eDP-1", mode = "preferred", position = "auto", scale = 1 })
	hl.monitor({ output = "", mode = "1920x1080@60", position = "auto", scale = 1, mirror = "eDP-1" })
elseif hostname == "antoinews-linux" then
	hl.monitor({ output = "DP-1", mode = "1920x1080@60", position = "1920x0", scale = 1 })
	hl.monitor({ output = "DP-2", mode = "1920x1080@60", position = "0x0", scale = 1 })
	hl.monitor({ output = "", mode = "preferred", position = "auto", scale = 1 })

	hl.workspace_rule({ workspace = "2", monitor = "DP-2", layout = "dwindle", persistent = true, default = true })
	hl.workspace_rule({ workspace = "5", monitor = "DP-2", layout = "dwindle", persistent = true })
	hl.workspace_rule({ workspace = "8", monitor = "DP-2", layout = "dwindle", persistent = true })
	hl.workspace_rule({ workspace = "3", monitor = "DP-1", layout = "dwindle", persistent = true, default = true })
	hl.workspace_rule({ workspace = "6", monitor = "DP-1", layout = "dwindle", persistent = true })
	hl.workspace_rule({ workspace = "9", monitor = "DP-1", layout = "dwindle", persistent = true })
	hl.workspace_rule({ workspace = "10", monitor = "DP-1", layout = "dwindle", persistent = true })

	hl.window_rule({ name = "windowrule-1", match = { class = "org.wezfurlong.wezterm" }, workspace = "5" })
	hl.window_rule({ name = "windowrule-2", match = { class = "com.mitchellh.ghostty" }, workspace = "5" })
	hl.window_rule({ name = "windowrule-3", match = { class = "brave-browser" }, workspace = "8" })
	hl.window_rule({ name = "windowrule-4", match = { class = "org.float-large.yazi" }, workspace = "10" })
elseif hostname == "DESKTOP-E07VTRN" then
	-- Desktop: 1080p side displays around a 4K center display at 1.5x scale.
	hl.monitor({ output = "HDMI-A-1", mode = "1920x1080@60", position = "0x180", scale = 1 })
	hl.monitor({
		output = "DP-3",
		mode = "3840x2160@143.85",
		position = "1920x0",
		scale = 1.5,
		bitdepth = 10,
		cm = "srgb",
	})
	hl.monitor({ output = "DP-2", mode = "1920x1080@60", position = "4480x180", scale = 1 })
	hl.monitor({ output = "", mode = "preferred", position = "auto", scale = 1 })

	-- Keep workspace layouts pinned to dwindle so they cannot silently drift into master/scrolling.
	hl.workspace_rule({ workspace = "1", monitor = "HDMI-A-1", layout = "dwindle", persistent = true, default = true })
	hl.workspace_rule({ workspace = "2", monitor = "DP-3", layout = "dwindle", persistent = true, default = true })
	hl.workspace_rule({ workspace = "3", monitor = "DP-2", layout = "dwindle", persistent = true, default = true })
	hl.workspace_rule({ workspace = "4", monitor = "HDMI-A-1", layout = "dwindle", persistent = true })
	hl.workspace_rule({ workspace = "5", monitor = "DP-3", layout = "dwindle", persistent = true })
	hl.workspace_rule({ workspace = "6", monitor = "DP-2", layout = "dwindle", persistent = true })
	hl.workspace_rule({ workspace = "7", monitor = "HDMI-A-1", layout = "dwindle", persistent = true })
	hl.workspace_rule({ workspace = "8", monitor = "DP-3", layout = "dwindle", persistent = true })
	hl.workspace_rule({ workspace = "9", monitor = "DP-2", layout = "dwindle", persistent = true })
	hl.workspace_rule({ workspace = "10", monitor = "DP-2", layout = "dwindle", persistent = true })

	-- Default workspace for applications
	hl.window_rule({ name = "windowrule-1", match = { class = "teams-for-linux" }, workspace = "1" })
	hl.window_rule({ name = "windowrule-2", match = { class = "signal" }, workspace = "1" })
	hl.window_rule({ name = "windowrule-3", match = { class = "obsidian" }, workspace = "4" })
	hl.window_rule({ name = "windowrule-4", match = { class = "org.wezfurlong.wezterm" }, workspace = "5" })
	hl.window_rule({ name = "windowrule-5", match = { class = "com.mitchellh.ghostty" }, workspace = "5" })
	hl.window_rule({ name = "windowrule-7", match = { class = "brave-browser" }, workspace = "7" })
	hl.window_rule({ name = "windowrule-8", match = { class = "org.float-large.yazi" }, workspace = "10" })
else
	-- Unknown hosts: prefer the active output without assuming connector names.
	hl.monitor({ output = "", mode = "preferred", position = "auto", scale = 1 })
end
