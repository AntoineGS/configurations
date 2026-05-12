-- Autostart processes. Order matches the original autostart.conf exec-once chain.

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
    hl.exec_cmd("vicinae server")

    -- Ensure all persistent workspaces are on correct monitors
    hl.exec_cmd([[sleep 1 && hyprctl --batch "dispatch moveworkspacetomonitor 1 DVI-D-1 ; dispatch moveworkspacetomonitor 4 DVI-D-1 ; dispatch moveworkspacetomonitor 7 DVI-D-1 ; dispatch moveworkspacetomonitor 2 HDMI-A-1 ; dispatch moveworkspacetomonitor 5 HDMI-A-1 ; dispatch moveworkspacetomonitor 8 HDMI-A-1 ; dispatch moveworkspacetomonitor 3 DP-2 ; dispatch moveworkspacetomonitor 6 DP-2 ; dispatch moveworkspacetomonitor 9 DP-2 ; dispatch moveworkspacetomonitor 10 DP-2 ; dispatch workspace 2"]])

    -- Hyprland 0.55 regression: cursor can't enter DP-2's region until the monitor is re-applied. Drop once upstream fixes it.
    hl.exec_cmd([[sleep 2 && hyprctl keyword monitor "DP-2, 1920x1080@60, 3601x0, 1" && hyprctl keyword monitor "DP-2, 1920x1080@60, 3600x0, 1"]])
end)
