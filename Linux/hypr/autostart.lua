-- Autostart processes. Order matches the original autostart.conf exec-once chain.

local hostname_pipe = io.popen("hostname")
local hostname      = hostname_pipe and hostname_pipe:read("*l") or ""
if hostname_pipe then hostname_pipe:close() end

hl.on("hyprland.start", function()
    hl.exec_cmd("uwsm-app -- hypridle")
    hl.exec_cmd("uwsm-app -- mako")
    hl.exec_cmd("uwsm-app -- waybar")
    hl.exec_cmd("uwsm-app -- fcitx5 --disable notificationitem")
    hl.exec_cmd("uwsm-app -- swaybg -i ~/.config/omarchy/current/background -m fill")
    hl.exec_cmd("uwsm-app -- swayosd-server")
    hl.exec_cmd("/usr/lib/polkit-gnome/polkit-gnome-authentication-agent-1")

    -- Slow app launch fix -- set systemd vars
    hl.exec_cmd("systemctl --user import-environment $(env | cut -d'=' -f 1)")
    hl.exec_cmd("dbus-update-activation-environment --systemd --all")

    -- Extra autostart processes
    hl.exec_cmd("hyprpm reload -n")
    hl.exec_cmd("signal")
    hl.exec_cmd("teams-for-linux")

    -- Ensure all persistent workspaces are on correct monitors.
    -- Legacy `hyprctl dispatch <name> <args>` strings are rejected by the Lua parser; route through `hyprctl eval`.
    -- `hl.dsp.*` calls return dispatcher closures — they only fire when wrapped in `hl.dispatch(...)`.
    if hostname == "antoinews-linux" then
        hl.exec_cmd([[sleep 1 && hyprctl eval 'hl.dispatch(hl.dsp.workspace.move({workspace=2, monitor="DP-2"})); hl.dispatch(hl.dsp.workspace.move({workspace=5, monitor="DP-2"})); hl.dispatch(hl.dsp.workspace.move({workspace=8, monitor="DP-2"})); hl.dispatch(hl.dsp.workspace.move({workspace=3, monitor="DP-1"})); hl.dispatch(hl.dsp.workspace.move({workspace=6, monitor="DP-1"})); hl.dispatch(hl.dsp.workspace.move({workspace=9, monitor="DP-1"})); hl.dispatch(hl.dsp.workspace.move({workspace=10, monitor="DP-1"})); hl.dispatch(hl.dsp.focus({workspace=2}))']])
    else
        hl.exec_cmd([[sleep 1 && hyprctl eval 'hl.dispatch(hl.dsp.workspace.move({workspace=1, monitor="DVI-D-1"})); hl.dispatch(hl.dsp.workspace.move({workspace=4, monitor="DVI-D-1"})); hl.dispatch(hl.dsp.workspace.move({workspace=7, monitor="DVI-D-1"})); hl.dispatch(hl.dsp.workspace.move({workspace=2, monitor="HDMI-A-1"})); hl.dispatch(hl.dsp.workspace.move({workspace=5, monitor="HDMI-A-1"})); hl.dispatch(hl.dsp.workspace.move({workspace=8, monitor="HDMI-A-1"})); hl.dispatch(hl.dsp.workspace.move({workspace=3, monitor="DP-2"})); hl.dispatch(hl.dsp.workspace.move({workspace=6, monitor="DP-2"})); hl.dispatch(hl.dsp.workspace.move({workspace=9, monitor="DP-2"})); hl.dispatch(hl.dsp.workspace.move({workspace=10, monitor="DP-2"})); hl.dispatch(hl.dsp.focus({workspace=2}))']])
    end

    -- Hyprland 0.55 regression: cursor can't enter DP-2's region until the monitor is re-applied. Drop once upstream fixes it.
    -- `hyprctl keyword` is disabled under the Lua parser ("keyword can't work with non-legacy parsers"), so route the nudge through `hyprctl eval` instead.
    if hostname == "antoinews-linux" then
        hl.exec_cmd([[sleep 2 && hyprctl eval 'hl.monitor({ output = "DP-2", mode = "1920x1080@60", position = "1x0", scale = 1 })' && hyprctl eval 'hl.monitor({ output = "DP-2", mode = "1920x1080@60", position = "0x0", scale = 1 })']])
    else
        hl.exec_cmd([[sleep 2 && hyprctl eval 'hl.monitor({ output = "DP-2", mode = "1920x1080@60", position = "3601x0", scale = 1 })' && hyprctl eval 'hl.monitor({ output = "DP-2", mode = "1920x1080@60", position = "3600x0", scale = 1 })']])
    end
end)
