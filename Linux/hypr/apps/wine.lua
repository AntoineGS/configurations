-- Wine names every window's class after its executable (mdexplorer.exe,
-- bds.exe, sfclient2.exe...), so this covers all Wine apps.
hl.window_rule({
  name = "wine-no-animations",
  match = { class = "^.*\\.exe$" },
  no_anim = true,
})
