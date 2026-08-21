hl.window_rule({
  name = "mdexplorer-workspace",
  match = { class = "^mdexplorer\\.exe$", title = ".+" },
  workspace = "9",
})

local function hide_application_window(window)
  if
    window.class ~= "mdexplorer.exe"
    or window.title ~= ""
    or not window.xwayland
    or not window.floating
    or window.size.x ~= 800
    or window.size.y ~= 800
  then
    return
  end

  hl.dispatch(hl.dsp.window.set_prop({ prop = "no_anim", value = "1", window = window }))
  hl.dispatch(hl.dsp.window.set_prop({ prop = "no_focus", value = "1", window = window }))
  hl.dispatch(hl.dsp.window.set_prop({ prop = "border_size", value = "0", window = window }))
  hl.dispatch(hl.dsp.window.set_prop({ prop = "opacity", value = "0", window = window }))
  hl.dispatch(hl.dsp.window.set_prop({ prop = "opacity_inactive", value = "0", window = window }))
  hl.dispatch(hl.dsp.window.set_prop({ prop = "opacity_fullscreen", value = "0", window = window }))
  hl.dispatch(hl.dsp.window.resize({ x = 1, y = 1, window = window }))
  hl.dispatch(hl.dsp.window.move({ x = 0, y = 0, window = window }))
end

hl.on("window.open", hide_application_window)

for _, window in ipairs(hl.get_windows()) do
  hide_application_window(window)
end
