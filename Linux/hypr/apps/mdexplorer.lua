-- Hide the empty VCL TApplication window while leaving MDExplorer's titled windows managed normally.
hl.window_rule({
  name = "mdexplorer-application-window",
  match = { class = "^mdexplorer\\.exe$", title = "^$", xwayland = true, float = true },
  tag = "-default-opacity",
  size = "1 1",
  move = "0 0",
  opacity = "0 0",
  border_size = 0,
  no_focus = true,
  no_initial_focus = true,
})
