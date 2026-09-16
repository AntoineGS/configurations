hl.window_rule({
  name = "mdexplorer-workspace",
  match = { class = "^mdexplorer\\.exe$", title = ".+" },
  workspace = "9",
})

hl.window_rule({
  name = "mdexplorer-no-animations",
  match = { class = "^mdexplorer\\.exe$" },
  no_anim = true,
})

-- VCL's TApplication helper: class mdexplorer.exe, empty title from birth,
-- never owned by another window. Real MDExplorer dialogs/popups are owned,
-- so Hyprland floats them; the helper is the only one that gets tiled.
-- Under XWayland it instead arrives floating at 800x800.
local function is_application_window(window)
  if
    window.class ~= "mdexplorer.exe"
    or window.title ~= ""
    or window.initial_title ~= ""
  then
    return false
  end
  if window.xwayland then
    return window.floating and window.size.x == 800 and window.size.y == 800
  end
  return not window.floating
end

-- Park it in a named special workspace that is never toggled on: it leaves
-- the tiling layout entirely and cannot take focus.
local function hide_application_window(window)
  if not is_application_window(window) then
    return
  end

  hl.dispatch(hl.dsp.window.set_prop({ prop = "no_anim", value = "1", window = window }))
  hl.dispatch(hl.dsp.window.set_prop({ prop = "no_focus", value = "1", window = window }))
  hl.dispatch(hl.dsp.window.set_prop({ prop = "focus_on_activate", value = "0", window = window }))
  hl.dispatch(hl.dsp.window.move({ workspace = "special:mdexplorer-app", follow = false, window = window }))
end

hl.on("window.open", hide_application_window)

for _, window in ipairs(hl.get_windows()) do
  hide_application_window(window)
end
