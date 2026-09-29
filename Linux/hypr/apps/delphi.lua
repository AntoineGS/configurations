-- Match the VCL TApplication helper using the same checks as MDExplorer.
-- The XWayland helper is untitled from birth and floats at 800x800;
-- the native Wayland helper is tiled instead of owned by another window.
local function is_application_window(window)
  if window.class ~= "bds.exe" or window.title ~= "" or window.initial_title ~= "" then
    return false
  end
  if window.xwayland then
    return window.floating and window.size.x == 800 and window.size.y == 800
  end
  return not window.floating
end

local function hide_application_window(window)
  if not is_application_window(window) then
    return
  end

  hl.dispatch(hl.dsp.window.set_prop({ prop = "no_anim", value = "1", window = window }))
  hl.dispatch(hl.dsp.window.set_prop({ prop = "no_focus", value = "1", window = window }))
  hl.dispatch(hl.dsp.window.set_prop({ prop = "focus_on_activate", value = "0", window = window }))
  hl.dispatch(hl.dsp.window.move({ workspace = "special:delphi-app", follow = false, window = window }))
end

hl.on("window.open", hide_application_window)

for _, window in ipairs(hl.get_windows()) do
  hide_application_window(window)
end
