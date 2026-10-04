-- VCL's TApplication helper window, for any Delphi app running under Wine.
-- Wine names every window's class after its executable (bds.exe,
-- mdexplorer.exe...), and the helper is created 0x0, so under XWayland it
-- floats at a size Hyprland picked rather than one the app asked for.

-- Unless the app sets Application.Title, VCL titles the helper with the
-- executable name, first letter upper and the rest lower ("Bobasegenerator").
local function default_application_title(class)
  local stem = class:match("^(.+)%.exe$")
  return stem and stem:sub(1, 1):upper() .. stem:sub(2):lower()
end

-- Apps whose Application.Title matches their main form's title, so only the
-- helper's size identifies it.
local custom_title_apps = {
  ["sfclient2.exe"] = true,
}

local function is_application_window(window)
  local default_title = default_application_title(window.class)
  if not default_title then
    return false
  end
  local untitled = window.title == "" and window.initial_title == ""

  -- Native Wayland driver: dialogs and popups are owned, so Hyprland floats
  -- them; the untitled helper is the only window that gets tiled.
  if not window.xwayland then
    return untitled and not window.floating
  end
  if not window.floating then
    return false
  end

  -- An untitled helper floats at Hyprland's default 800x800. A titled one has
  -- a caption, so Wine pins its client area to 794x768 inside that frame.
  if untitled then
    return window.size.x == 800 and window.size.y == 800
  end
  if window.size.x ~= 794 or window.size.y ~= 768 then
    return false
  end
  return window.initial_title == default_title or custom_title_apps[window.class] == true
end

-- Park it in a named special workspace that is never toggled on: it leaves
-- the layout entirely and cannot take focus.
local function hide_application_window(window)
  if not is_application_window(window) then
    return
  end

  hl.dispatch(hl.dsp.window.set_prop({ prop = "no_anim", value = "1", window = window }))
  hl.dispatch(hl.dsp.window.set_prop({ prop = "no_focus", value = "1", window = window }))
  hl.dispatch(hl.dsp.window.set_prop({ prop = "focus_on_activate", value = "0", window = window }))
  hl.dispatch(hl.dsp.window.move({ workspace = "special:vcl-app", follow = false, window = window }))
end

hl.on("window.open", hide_application_window)

for _, window in ipairs(hl.get_windows()) do
  hide_application_window(window)
end
