-- Control your input devices
-- See https://wiki.hypr.land/Configuring/Variables/#input
hl.config({
    input = {
        kb_layout  = "us",
        kb_variant = "intl",
        kb_options = "compose:caps",
        kb_model   = "",
        kb_rules   = "",

        repeat_rate  = 40,
        repeat_delay = 600,

        numlock_by_default = false,

        follow_mouse = 1,
        sensitivity  = 0,

        touchpad = {
            scroll_factor  = 0.4,
            natural_scroll = false,
        },
    },
})

-- Scroll nicely in the terminal
hl.window_rule({
    match = { class = "(Alacritty|kitty)" },
    scroll_touchpad = 1.5,
})
hl.window_rule({
    match = { class = "com.mitchellh.ghostty" },
    scroll_touchpad = 0.2,
})

hl.config({
    misc = {
        key_press_enables_dpms  = true, -- key press will trigger wake
        mouse_move_enables_dpms = true, -- mouse move will trigger wake
    },
})

-- Keep the laptop running while the closed lid turns off only its panel.
hl.bind("switch:on:Lid Switch", function()
    hl.config({ misc = { key_press_enables_dpms = false, mouse_move_enables_dpms = false } })
    hl.dispatch(hl.dsp.dpms({ action = "off", monitor = "eDP-1" }))
end, { locked = true })
hl.bind("switch:off:Lid Switch", function()
    hl.config({ misc = { key_press_enables_dpms = true, mouse_move_enables_dpms = true } })
    hl.dispatch(hl.dsp.dpms({ action = "on", monitor = "eDP-1" }))
end, { locked = true })
