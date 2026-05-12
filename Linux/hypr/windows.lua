-- See https://wiki.hypr.land/Configuring/Basics/Window-Rules/ for more

-- Ignore maximize requests from all apps. You'll probably like this.
hl.window_rule({
    name = "suppress-maximize",
    match = { class = ".*" },
    suppress_event = "maximize",
})

-- Tag all windows for default opacity (apps can override with -default-opacity tag)
hl.window_rule({
    name = "default-opacity-tag",
    match = { class = ".*" },
    tag = "+default-opacity",
})

-- Fix some dragging issues with XWayland
hl.window_rule({
    name = "fix-xwayland-drags",
    match = { class = "^$", title = "^$", xwayland = true, float = true, fullscreen = false, pin = false },
    no_focus = true,
})

-- App-specific tweaks (may remove default-opacity tag)
require("apps")

-- Apply default opacity after apps have had a chance to opt out
hl.window_rule({
    name = "apply-default-opacity",
    match = { tag = "default-opacity" },
    opacity = "0.97 0.9",
})
