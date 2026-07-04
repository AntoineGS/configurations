-- Menus
hl.bind("SUPER + SPACE",           hl.dsp.exec_cmd("vicinae toggle"),                                  { description = "Dashboard" })
hl.bind("SUPER + CTRL + C",        hl.dsp.exec_cmd("menu capture"),                                    { description = "Capture menu" })
hl.bind("SUPER + CTRL + O",        hl.dsp.exec_cmd("menu toggle"),                                     { description = "Toggle menu" })
hl.bind("SUPER + ALT + SPACE",     hl.dsp.exec_cmd("menu"),                                            { description = "Omarchy menu" })
hl.bind("SUPER + ESCAPE",          hl.dsp.exec_cmd("menu system"),                                     { description = "System menu" })
-- vicinae 0.20.12: `vicinae vicinae://launch/power` registers the deeplink but
-- doesn't raise the window (works fine for clipboard/emojis/calculator). Chain
-- an explicit `open` so the window actually appears.
hl.bind("XF86PowerOff",            hl.dsp.exec_cmd("vicinae open && vicinae deeplink vicinae://launch/power"), { description = "Power menu" })
hl.bind("SUPER + CTRL + K",        hl.dsp.exec_cmd("menu-keybindings"),                                { description = "Show key bindings" })
hl.bind("XF86Calculator",          hl.dsp.exec_cmd("vicinae vicinae://extensions/vicinae/calculator/history"), { description = "Calculator" })
hl.bind("SUPER + CTRL + W",        hl.dsp.exec_cmd("pkill waybar && waybar &"),                        { description = "Reload Waybar" })
hl.bind("SUPER + CTRL + H",        hl.dsp.exec_cmd("restart-hyprctl"),                                 { description = "Reload Hyprland" })

-- Aesthetics
hl.bind("SUPER + SHIFT + SPACE",         hl.dsp.exec_cmd("toggle-waybar"),                                 { description = "Toggle top bar" })
hl.bind("SUPER + CTRL + SPACE",          hl.dsp.exec_cmd("menu background"),                               { description = "Theme background menu" })
hl.bind("SUPER + SHIFT + CTRL + SPACE",  hl.dsp.exec_cmd("menu theme"),                                    { description = "Theme menu" })
hl.bind("SUPER + BACKSPACE",             hl.dsp.window.set_prop({ prop = "opaque", value = "toggle" }),    { description = "Toggle window transparency" })
hl.bind("SUPER + SHIFT + BACKSPACE",     hl.dsp.exec_cmd("hyprland-window-gaps-toggle"),                   { description = "Toggle window gaps" })
hl.bind("SUPER + CTRL + BACKSPACE",      hl.dsp.exec_cmd("hyprland-window-single-square-aspect-toggle"),   { description = "Toggle single-window square aspect" })

-- Notifications
hl.bind("SUPER + COMMA",                 hl.dsp.exec_cmd("makoctl dismiss"),                               { description = "Dismiss last notification" })
hl.bind("SUPER + SHIFT + COMMA",         hl.dsp.exec_cmd("makoctl dismiss --all"),                         { description = "Dismiss all notifications" })
hl.bind("SUPER + CTRL + COMMA",          hl.dsp.exec_cmd("toggle-notification-silencing"),                 { description = "Toggle silencing notifications" })
hl.bind("SUPER + ALT + COMMA",           hl.dsp.exec_cmd("makoctl invoke"),                                { description = "Invoke last notification" })
hl.bind("SUPER + SHIFT + ALT + COMMA",   hl.dsp.exec_cmd("makoctl restore"),                               { description = "Restore last notification" })

-- Pacman
hl.bind("SUPER + CTRL + I",              hl.dsp.exec_cmd("launch-tui-large pkg-install"),                  { description = "Install packages" })
hl.bind("SUPER + CTRL + U",              hl.dsp.exec_cmd("launch-tui-large update"),                       { description = "Update system" })
hl.bind("SUPER + CTRL + R",              hl.dsp.exec_cmd("launch-tui-large pkg-remove"),                   { description = "Remove packages" })
hl.bind("SUPER + CTRL + A",              hl.dsp.exec_cmd("launch-tui-large pkg-aur-install"),              { description = "Install AUR packages" })

-- Captures
hl.bind("PRINT",                         hl.dsp.exec_cmd("cmd-screenshot"),                                { description = "Screenshot" })
hl.bind("ALT + PRINT",                   hl.dsp.exec_cmd("menu screenrecord"),                             { description = "Screenrecording" })
hl.bind("SUPER + PRINT",                 hl.dsp.exec_cmd("pkill hyprpicker || hyprpicker -a"),             { description = "Color picker" })

-- Control panels
hl.bind("SUPER + CTRL + T",              hl.dsp.exec_cmd("launch-tui-large btop"),                         { description = "Top" })

-- Dictation
hl.bind("SUPER + CTRL + X",              hl.dsp.exec_cmd("voxtype record toggle"),                         { description = "Toggle dictation" })

-- Zoom (legacy `hyprctl keyword` rejected by Lua parser; round-trip through `hyprctl eval` + hl.config / hl.get_config)
hl.bind("SUPER + CTRL + Z",              hl.dsp.exec_cmd([[hyprctl eval 'hl.config({cursor = {zoom_factor = hl.get_config("cursor:zoom_factor") + 1}})']]), { description = "Zoom in" })
hl.bind("SUPER + CTRL + ALT + Z",        hl.dsp.exec_cmd([[hyprctl eval 'hl.config({cursor = {zoom_factor = 1}})']]), { description = "Reset zoom" })

-- Lock system
hl.bind("SUPER + CTRL + L",              hl.dsp.exec_cmd("lock-screen"),                                   { description = "Lock system" })

-- Display
-- Laptop-only: the takeover script assumes eDP-1 and disables monitors on the desktop.
local hostname_pipe = io.popen("hostname")
local hostname      = hostname_pipe and hostname_pipe:read("*l") or ""
if hostname_pipe then hostname_pipe:close() end

if hostname == "omarchbook" then
    hl.bind("SUPER + E",                 hl.dsp.exec_cmd("~/.config/hypr/scripts/toggle-external-takeover.sh"), { description = "Toggle external display takeover" })
end

hl.bind("SUPER + V",                     hl.dsp.exec_cmd("vicinae vicinae://launch/clipboard/history"),    { description = "Clipboard history" })
hl.bind("SUPER + PERIOD",                hl.dsp.exec_cmd("vicinae vicinae://launch/core/search-emojis"),   { description = "Emoji picker" })
