-- VCL's TApplication helper. Unlike MDExplorer's, Delphi 2010 titles it with
-- Application.Title, the same title as the main form, so match its size
-- instead: created 0x0, it floats at Hyprland's default 800x800, which Wine
-- pins as a fixed 794x768 client area (minus its caption and borders). The
-- Superform prefix uses the X11 driver, so it is always an XWayland window.
local function is_application_window(window)
  return window.class == "sfclient2.exe"
    and window.xwayland
    and window.floating
    and window.size.x == 794
    and window.size.y == 768
end

-- Park it in a named special workspace that is never toggled on: it leaves
-- the layout entirely and cannot take focus.
local function hide_application_window(window)
  if not is_application_window(window) then
    return
  end

  hl.dispatch(hl.dsp.window.set_prop({ prop = "no_focus", value = "1", window = window }))
  hl.dispatch(hl.dsp.window.set_prop({ prop = "focus_on_activate", value = "0", window = window }))
  hl.dispatch(hl.dsp.window.move({ workspace = "special:superform-app", follow = false, window = window }))
end

hl.on("window.open", hide_application_window)

for _, window in ipairs(hl.get_windows()) do
  hide_application_window(window)
end
