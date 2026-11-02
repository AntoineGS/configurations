hl.window_rule({
  name = "mdexplorer-workspace",
  match = { class = "^mdexplorer\\.exe$", title = ".+" },
  workspace = "9",
})

hl.window_rule({
  name = "mdexplorer-go-workspace",
  match = { class = "^org\\.wails\\.mdexplorergo$" },
  workspace = "9",
})
