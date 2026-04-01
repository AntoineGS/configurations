# Omarchy Menu - Manual Commands Reference

Commands behind the Omarchy menu (`SUPER ALT + SPACE` -> `omarchy-menu`), for running without Walker.

## Trigger

### Capture

| Action | Command |
|---|---|
| Screenshot | `omarchy-cmd-screenshot` |
| Screenrecord (no audio) | `omarchy-cmd-screenrecord` |
| Screenrecord (desktop audio) | `omarchy-cmd-screenrecord --with-desktop-audio` |
| Screenrecord (desktop + mic) | `omarchy-cmd-screenrecord --with-desktop-audio --with-microphone-audio` |
| Screenrecord (desktop + mic + webcam) | `omarchy-cmd-screenrecord --with-desktop-audio --with-microphone-audio --with-webcam --webcam-device=<device>` |
| Stop recording | `omarchy-cmd-screenrecord --stop-recording` |
| Color picker | `hyprpicker -a` (or `pkill hyprpicker` to stop) |

List webcam devices: `v4l2-ctl --list-devices`

### Share

| Action | Command |
|---|---|
| Clipboard | `omarchy-cmd-share clipboard` |
| File | `omarchy-cmd-share file` |
| Folder | `omarchy-cmd-share folder` |

### Toggle

| Action | Command |
|---|---|
| Screensaver | `omarchy-toggle-screensaver` |
| Nightlight | `omarchy-toggle-nightlight` |
| Idle lock | `omarchy-toggle-idle` |
| Top bar (Waybar) | `omarchy-toggle-waybar` |
| Workspace layout | `omarchy-hyprland-workspace-layout-toggle` |
| Window gaps | `omarchy-hyprland-window-gaps-toggle` |
| 1-window ratio | `omarchy-hyprland-window-single-square-aspect-toggle` |
| Display scaling cycle | `omarchy-hyprland-monitor-scaling-cycle` |

### Hardware

| Action | Command |
|---|---|
| Hybrid GPU toggle | `omarchy-toggle-hybrid-gpu` |

## Style

| Action | Command |
|---|---|
| Theme picker | `omarchy-launch-walker -m menus:omarchythemes --width 800 --minheight 400` (uses Walker/elephant) |
| Font list | `omarchy-font-list` |
| Font current | `omarchy-font-current` |
| Font set | `omarchy-font-set "<font name>"` |
| Background picker | `omarchy-launch-walker -m menus:omarchyBackgroundSelector --width 800 --minheight 400` (uses Walker/elephant) |
| Edit Hyprland look | `$EDITOR ~/.config/hypr/looknfeel.conf` |
| Edit screensaver text | `$EDITOR ~/.config/omarchy/branding/screensaver.txt` |
| Edit about text | `$EDITOR ~/.config/omarchy/branding/about.txt` |

**Note:** Theme and Background pickers depend on Walker's elephant menus. The underlying Lua scripts are at `~/.local/share/omarchy/default/elephant/omarchy_themes.lua` and `omarchy_background_selector.lua`. To replace Walker, these would need an alternative launcher or direct script invocations.

## Setup

### Audio / Network / Bluetooth

| Action | Command |
|---|---|
| Audio settings | `omarchy-launch-audio` |
| Wi-Fi settings | `omarchy-launch-wifi` |
| Bluetooth settings | `omarchy-launch-bluetooth` |

### Power Profile

| Action | Command |
|---|---|
| List profiles | `omarchy-powerprofiles-list` |
| Get current | `powerprofilesctl get` |
| Set profile | `powerprofilesctl set <profile>` |

### System Sleep

| Action | Command |
|---|---|
| Toggle suspend | `omarchy-toggle-suspend` |
| Enable hibernate | `omarchy-hibernation-setup` |
| Disable hibernate | `omarchy-hibernation-remove` |
| Check hibernate available | `omarchy-hibernation-available` |

### Config Editors

These open the config file in your editor; some restart the service after saving:

| Config | File | Restart command |
|---|---|---|
| Monitors | `~/.config/hypr/monitors.conf` | - |
| Keybindings | `~/.config/hypr/bindings.conf` | - |
| Input | `~/.config/hypr/input.conf` | - |
| Key remapping | `~/.config/makima/AT Translated Set 2 keyboard.toml` | `omarchy-setup-makima` then `omarchy-restart-makima` |
| Defaults (UWSM) | `~/.config/uwsm/default` | - |
| Hyprland | `~/.config/hypr/hyprland.conf` | - |
| Hypridle | `~/.config/hypr/hypridle.conf` | `omarchy-restart-hypridle` |
| Hyprlock | `~/.config/hypr/hyprlock.conf` | - |
| Hyprsunset | `~/.config/hypr/hyprsunset.conf` | `omarchy-restart-hyprsunset` |
| Swayosd | `~/.config/swayosd/config.toml` | `omarchy-restart-swayosd` |
| Walker | `~/.config/walker/config.toml` | `omarchy-restart-walker` |
| Waybar | `~/.config/waybar/config.jsonc` | `omarchy-restart-waybar` |
| XCompose | `~/.XCompose` | `omarchy-restart-xcompose` |

### DNS / Security

| Action | Command |
|---|---|
| DNS setup | `omarchy-setup-dns` |
| Fingerprint setup | `omarchy-setup-fingerprint` |
| Fingerprint remove | `omarchy-setup-fingerprint --remove` |
| FIDO2 setup | `omarchy-setup-fido2` |
| FIDO2 remove | `omarchy-setup-fido2 --remove` |
