-- This file replaces the deprecated tiling.conf with the tiling-v2 bindings.
-- All bindings below preserve the behavior of the previous .conf.

-- Fullscreen management
hl.bind("SUPER + SHIFT + F", hl.dsp.window.fullscreen({ mode = "fullscreen", action = "toggle" }), { description = "Force full screen" })
hl.bind("SUPER + F",         hl.dsp.window.fullscreen({ mode = "maximized",  action = "toggle" }), { description = "Full width" })

-- Close windows
hl.bind("SUPER + W",          hl.dsp.window.close(),                                       { description = "Close window" })
hl.bind("CTRL + ALT + DELETE", hl.dsp.exec_cmd("hyprland-window-close-all"),               { description = "Close all windows" })

-- Control tiling
hl.bind("SUPER + SHIFT + V", hl.dsp.window.float({ action = "toggle" }),                  { description = "Toggle window floating/tiling" })

-- Switch workspaces with SUPER + [0-9] (via scancode)
hl.bind("SUPER + code:10", hl.dsp.focus({ workspace = 1  }), { description = "Switch to workspace 1" })
hl.bind("SUPER + code:11", hl.dsp.focus({ workspace = 2  }), { description = "Switch to workspace 2" })
hl.bind("SUPER + code:12", hl.dsp.focus({ workspace = 3  }), { description = "Switch to workspace 3" })
hl.bind("SUPER + code:13", hl.dsp.focus({ workspace = 4  }), { description = "Switch to workspace 4" })
hl.bind("SUPER + code:14", hl.dsp.focus({ workspace = 5  }), { description = "Switch to workspace 5" })
hl.bind("SUPER + code:15", hl.dsp.focus({ workspace = 6  }), { description = "Switch to workspace 6" })
hl.bind("SUPER + code:16", hl.dsp.focus({ workspace = 7  }), { description = "Switch to workspace 7" })
hl.bind("SUPER + code:17", hl.dsp.focus({ workspace = 8  }), { description = "Switch to workspace 8" })
hl.bind("SUPER + code:18", hl.dsp.focus({ workspace = 9  }), { description = "Switch to workspace 9" })
hl.bind("SUPER + code:19", hl.dsp.focus({ workspace = 10 }), { description = "Switch to workspace 10" })

-- Move active window to a workspace with SUPER + SHIFT + [0-9]
hl.bind("SUPER + SHIFT + code:10", hl.dsp.window.move({ workspace = 1  }), { description = "Move window to workspace 1" })
hl.bind("SUPER + SHIFT + code:11", hl.dsp.window.move({ workspace = 2  }), { description = "Move window to workspace 2" })
hl.bind("SUPER + SHIFT + code:12", hl.dsp.window.move({ workspace = 3  }), { description = "Move window to workspace 3" })
hl.bind("SUPER + SHIFT + code:13", hl.dsp.window.move({ workspace = 4  }), { description = "Move window to workspace 4" })
hl.bind("SUPER + SHIFT + code:14", hl.dsp.window.move({ workspace = 5  }), { description = "Move window to workspace 5" })
hl.bind("SUPER + SHIFT + code:15", hl.dsp.window.move({ workspace = 6  }), { description = "Move window to workspace 6" })
hl.bind("SUPER + SHIFT + code:16", hl.dsp.window.move({ workspace = 7  }), { description = "Move window to workspace 7" })
hl.bind("SUPER + SHIFT + code:17", hl.dsp.window.move({ workspace = 8  }), { description = "Move window to workspace 8" })
hl.bind("SUPER + SHIFT + code:18", hl.dsp.window.move({ workspace = 9  }), { description = "Move window to workspace 9" })
hl.bind("SUPER + SHIFT + code:19", hl.dsp.window.move({ workspace = 10 }), { description = "Move window to workspace 10" })

hl.bind("SUPER + U", hl.dsp.focus({ workspace = "previous" }), { description = "Former workspace" })

-- Swap active window with the one next to it with SUPER + SHIFT + arrow keys
hl.bind("SUPER + SHIFT + LEFT",  hl.dsp.window.swap({ direction = "left"  }), { description = "Swap window to the left" })
hl.bind("SUPER + SHIFT + RIGHT", hl.dsp.window.swap({ direction = "right" }), { description = "Swap window to the right" })
hl.bind("SUPER + SHIFT + UP",    hl.dsp.window.swap({ direction = "up"    }), { description = "Swap window up" })
hl.bind("SUPER + SHIFT + DOWN",  hl.dsp.window.swap({ direction = "down"  }), { description = "Swap window down" })

-- Cycle through applications on active workspace
hl.bind("ALT + TAB",         hl.dsp.window.cycle_next(),                  { description = "Cycle to next window" })
hl.bind("ALT + SHIFT + TAB", hl.dsp.window.cycle_next({ next = false }),  { description = "Cycle to prev window" })
hl.bind("ALT + TAB",         hl.dsp.window.bring_to_top(),                { description = "Reveal active window on top" })
hl.bind("ALT + SHIFT + TAB", hl.dsp.window.bring_to_top(),                { description = "Reveal active window on top" })

-- Resize active window
hl.bind("SUPER + code:20",         hl.dsp.window.resize({ x = -100, y = 0,   relative = true }), { description = "Expand window left" })  -- - key
hl.bind("SUPER + code:21",         hl.dsp.window.resize({ x = 100,  y = 0,   relative = true }), { description = "Shrink window left" })  -- = key
hl.bind("SUPER + SHIFT + code:20", hl.dsp.window.resize({ x = 0,    y = -100, relative = true }), { description = "Shrink window up" })
hl.bind("SUPER + SHIFT + code:21", hl.dsp.window.resize({ x = 0,    y = 100,  relative = true }), { description = "Expand window down" })

-- Move/resize windows with mainMod + LMB/RMB and dragging
hl.bind("SUPER + mouse:272", hl.dsp.window.drag(),   { mouse = true, description = "Move window" })
hl.bind("SUPER + mouse:273", hl.dsp.window.resize(), { mouse = true, description = "Resize window" })

-- Resize submap (arrow-key resizing)
hl.bind("SUPER + R", hl.dsp.submap("resize"), { description = "Resize mode" })
hl.define_submap("resize", function()
    hl.bind("l",      hl.dsp.window.resize({ x =  10, y =   0, relative = true }), { repeating = true, description = "Resize: grow width" })
    hl.bind("h",      hl.dsp.window.resize({ x = -10, y =   0, relative = true }), { repeating = true, description = "Resize: shrink width" })
    hl.bind("k",      hl.dsp.window.resize({ x =   0, y = -10, relative = true }), { repeating = true, description = "Resize: shrink height" })
    hl.bind("j",      hl.dsp.window.resize({ x =   0, y =  10, relative = true }), { repeating = true, description = "Resize: grow height" })
    hl.bind("escape", hl.dsp.submap("reset"), { description = "Resize: exit" })
end)

-- Tiling
hl.bind("SUPER + SHIFT + H", hl.dsp.window.move({ direction = "left"  }), { description = "Move window to left workspace" })
hl.bind("SUPER + SHIFT + L", hl.dsp.window.move({ direction = "right" }), { description = "Move window to right workspace" })
hl.bind("SUPER + SHIFT + K", hl.dsp.window.move({ direction = "up"    }), { description = "Move window to upper workspace" })
hl.bind("SUPER + SHIFT + J", hl.dsp.window.move({ direction = "down"  }), { description = "Move window to lower workspace" })
hl.bind("SUPER + M",         hl.dsp.layout("swapwithmaster"),             { description = "Swap with master" })

hl.bind("SUPER + H", hl.dsp.focus({ direction = "left"  }), { description = "Move focus left" })
hl.bind("SUPER + L", hl.dsp.focus({ direction = "right" }), { description = "Move focus right" })
hl.bind("SUPER + K", hl.dsp.focus({ direction = "up"    }), { description = "Move focus up" })
hl.bind("SUPER + J", hl.dsp.focus({ direction = "down"  }), { description = "Move focus down" })
hl.bind("SUPER + N", hl.dsp.focus({ workspace  = "m+1"  }), { description = "Next workspace on monitor" })
hl.bind("SUPER + P", hl.dsp.focus({ workspace  = "m-1"  }), { description = "Previous workspace on monitor" })
hl.bind("SUPER + SHIFT + ALT + H", hl.dsp.workspace.move({ monitor = "l" }), { description = "Move current workspace left" })
hl.bind("SUPER + SHIFT + ALT + L", hl.dsp.workspace.move({ monitor = "r" }), { description = "Move current workspace right" })

hl.bind("SUPER + S", hl.dsp.layout("swapsplit"),                      { description = "Swap split orientation" })
hl.bind("SUPER + T", hl.dsp.layout("orientationcycle left top left"), { description = "Cycle window orientation" })

-- Clean submap (disables most keybinds, used by RustDesk integration)
hl.bind("SUPER + SHIFT + Q", hl.dsp.submap("clean"), { description = "Clean mode (disable keybinds)" })
hl.define_submap("clean", function()
    hl.bind("SUPER + mouse:272", hl.dsp.window.drag(), { mouse = true, description = "Clean mode: move window" })
    hl.bind("SUPER + SHIFT + Q", hl.dsp.submap("reset"), { description = "Clean mode: exit" })
end)
