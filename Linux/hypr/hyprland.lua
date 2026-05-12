-- Hyprland 0.55+ Lua entrypoint. Mirrors the source-chain that hyprland.conf used.
-- Wiki: https://wiki.hypr.land/Configuring/Start/

require("autostart")
require("monitors")
require("input")
require("envs")
require("theme.hyprland")
require("looknfeel")
require("windows")
require("bindings.media")
require("bindings.tiling")
require("bindings.utilities")
require("bindings.apps")

-- Bypass GTK portal for URI opening (enables custom URI scheme handlers)
hl.env("GTK_USE_PORTAL", "0")

-- NVIDIA environment variables
hl.env("NVD_BACKEND", "direct")
hl.env("LIBVA_DRIVER_NAME", "nvidia")
hl.env("__GLX_VENDOR_LIBRARY_NAME", "nvidia")
