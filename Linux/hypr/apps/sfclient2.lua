-- SFClient2 (Delphi 2010) leaves Application.MainFormOnTaskbar off, so Wine
-- makes every form transient for VCL's hidden application window and Hyprland
-- floats them all, main form included. Its startup maximize is suppressed too
-- (windows.lua), so it opened as a small float that SUPER + J/K could not leave.
-- Tile the main form only: DataNavigator titles it with Application.Title and
-- the database suffix, while dialogs use the bare Application.Title.
hl.window_rule({
  name = "sfclient2-main-form-tile",
  match = { class = "^sfclient2\\.exe$", title = "^ChainDrive SF - .+" },
  tile = true,
})

-- SFClient2 keeps creating and retitling hidden forms, and Wine turns their
-- activation into activate requests that pulled focus back to its workspace
-- right after leaving it.
hl.window_rule({
  name = "sfclient2-no-focus-on-activate",
  match = { class = "^sfclient2\\.exe$" },
  focus_on_activate = false,
})
