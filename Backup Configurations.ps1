# Define source and destination paths
$paths = @{
    Profile = @{ Source = $PROFILE; Destination = ".\Windows\PowerShell" }
    Neovim = @{ Source = "~\AppData\Local\nvim\"; Destination = ".\Both\Neovim\" }
    IdeaVim = @{ Source = "~\.ideavimrc"; Destination = ".\Both\IntelliJ\" }
    VSCode_settings = @{ Source = "~\AppData\Roaming\Code\User\settings.json"; Destination = ".\Both\VSCode\User\" }
    VSCode_keybindings = @{ Source = "~\AppData\Roaming\Code\User\keybindings.json"; Destination = ".\Both\VSCode\User\" }
}

# Some paths may share the same destination so to prevent deleting a previously copied file we do this in two passes
foreach ($path in $paths.Values) {
    New-Item -ItemType Directory -Force -Path $path.Destination
    Get-ChildItem -Path $path.Destination -Recurse | Remove-Item -Force -Recurse
}

foreach ($path in $paths.Values) {
    Copy-Item -Path $path.Source -Destination $path.Destination -Recurse -Force
}
