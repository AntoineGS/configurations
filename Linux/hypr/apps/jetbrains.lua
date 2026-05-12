-- Fix splash screen showing in weird places and prevent annoying focus takeovers
hl.window_rule({
    name = "jetbrains-splash",
    match = { class = "^(jetbrains-.*)$", title = "^(splash)$", float = true },
    tag = "+jetbrains-splash",
    center = true,
    no_focus = true,
    border_size = 0,
})

-- Center popups/find windows
hl.window_rule({
    name = "jetbrains-popup",
    match = { class = "^(jetbrains-.*)", title = "^(| )$", float = true },
    tag = "+jetbrains",
    center = true,
    -- Enabling this makes it possible to provide input in popup dialogs (search window, new file, etc.)
    stay_focused = true,
    border_size = 0,
    min_size = "(monitor_w*0.5) (monitor_h*0.5)",
})

-- Disable window flicker when autocomplete or tooltips appear
hl.window_rule({
    name = "jetbrains-tooltip",
    match = { class = "^(jetbrains-.*)$", title = "^(win.*)$", float = true },
    no_initial_focus = true,
})

-- Disable mouse focus
hl.window_rule({
    name = "jetbrains-focus",
    match = { class = "^(jetbrains-.*)$" },
    no_follow_mouse = true,
})
