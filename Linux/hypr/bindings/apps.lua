-- App launchers. The `##` escape for `#` in URLs is unnecessary in Lua strings
-- (no comment parsing on strings), but we don't have any such URLs here anyway.

local hostname_pipe = io.popen("hostname")
local hostname = hostname_pipe and hostname_pipe:read("*l") or ""
if hostname_pipe then
	hostname_pipe:close()
end

hl.bind(
	"SUPER + RETURN",
	hl.dsp.exec_cmd("uwsm-app -- env HERDR_NAV_PASSTHROUGH_RE='^(shell-picker|fzf)$' xdg-terminal-exec herdr"),
	{ description = "Terminal" }
)
hl.bind(
	"SUPER + SHIFT + RETURN",
	hl.dsp.exec_cmd("uwsm-app -- xdg-terminal-exec"),
	{ description = "Terminal (no tmux)" }
)
hl.bind(
	"SUPER + ALT + Y",
	hl.dsp.exec_cmd(
		[[launch-or-focus org.maximized.yazi "uwsm-app -- xdg-terminal-exec --app-id=org.maximized.yazi -e yazi"]]
	),
	{ description = "File manager" }
)
hl.bind(
	"SUPER + ALT + G",
	hl.dsp.exec_cmd(
		[[launch-or-focus org.maximized.lazygit "uwsm-app -- xdg-terminal-exec --app-id=org.maximized.lazygit -e lazygit"]]
	),
	{ description = "Git client" }
)
hl.bind("SUPER + ALT + M", hl.dsp.exec_cmd("launch-or-focus teams-for-linux"), { description = "MS Teams" })
hl.bind(
	"SUPER + ALT + B",
	hl.dsp.exec_cmd(
		[[launch-or-focus brave-browser "uwsm app -- brave --enable-features=UseOzonePlatform --ozone-platform=wayland --enable-wayland-ime"]]
	),
	{ description = "Browser" }
)
hl.bind("SUPER + ALT + N", hl.dsp.exec_cmd("launch-editor"), { description = "Editor" })
hl.bind("SUPER + ALT + D", hl.dsp.exec_cmd("launch-tui-large lazydocker"), { description = "Docker" })
hl.bind(
	"SUPER + ALT + O",
	hl.dsp.exec_cmd([[launch-or-focus obsidian "uwsm app -- obsidian -disable-gpu --enable-wayland-ime"]]),
	{ description = "Obsidian" }
)
hl.bind("SUPER + ALT + SLASH", hl.dsp.exec_cmd("uwsm app -- 1password"), { description = "Passwords" })
if hostname == "antoinews-linux" then
	hl.bind("SUPER + ALT + R", hl.dsp.exec_cmd("uwsm app -- gtk-launch asbru-cm"), { description = "Asbru" })
else
	hl.bind(
		"SUPER + ALT + R",
		hl.dsp.exec_cmd("uwsm app -- gtk-launch org.remmina.Remmina"),
		{ description = "Remmina" }
	)
end
hl.bind(
	"SUPER + ALT + S",
	hl.dsp.exec_cmd([[launch-or-focus signal "uwsm app -- signal-desktop"]]),
	{ description = "Signal" }
)
hl.bind(
	"SUPER + ALT + P",
	hl.dsp.exec_cmd([[launch-or-focus 1password "uwsm app -- 1password"]]),
	{ description = "1Password" }
)
hl.bind(
	"SUPER + CTRL + P",
	hl.dsp.exec_cmd("uwsm app -- 1password --quick-access"),
	{ description = "1Password Quick Access" }
)
