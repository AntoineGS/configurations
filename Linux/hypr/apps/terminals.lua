-- Define terminal tag to style them uniformly
hl.window_rule({ match = { class = "(Alacritty|kitty|com.mitchellh.ghostty)" }, tag = "+terminal" })
hl.window_rule({ match = { tag = "terminal" }, tag = "-default-opacity" })
hl.window_rule({ match = { tag = "terminal" }, opacity = "0.97 0.9" })

local sleeping_bell_rule = hl.window_rule({
  name = "ghostty-sleeping-bell",
  match = { class = "com.mitchellh.ghostty" },
  enabled = false,
  focus_on_activate = false,
})

-- Urgency is emitted before activation; update the rule synchronously to avoid waking displays.
hl.on("window.urgent", function(window)
  if window.class ~= "com.mitchellh.ghostty" then
    return
  end

  local sleeping = false
  for _, monitor in ipairs(hl.get_monitors()) do
    local virtual = monitor.name:match("^HEADLESS%-") or monitor.name:match("^Virtual%-")
    if not virtual and not monitor.dpms_status then
      sleeping = true
      break
    end
  end
  sleeping_bell_rule:set_enabled(sleeping)
end)
