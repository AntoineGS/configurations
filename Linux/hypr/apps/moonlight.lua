hl.window_rule({
    name = "moonlight",
    match = { class = "com.moonlight_stream.Moonlight" },
    fullscreen = true,
    idle_inhibit = "fullscreen",
    -- Keep the clean-submap escape binding available during keyboard capture.
    no_shortcuts_inhibit = true,
})
