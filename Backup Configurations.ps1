# Define source and destination paths
$paths = @{
    Profile = @{ Source = $PROFILE; Destination = ".\Windows\PowerShell" }
    Neovim = @{ Source = "~\AppData\Local\nvim\"; Destination = ".\Both\Neovim\" }
    IdeaVim = @{ Source = "~\.ideavimrc"; Destination = ".\Both\IntelliJ\" }
    VSCode_settings = @{ Source = "~\AppData\Roaming\Code\User\settings.json"; Destination = ".\Both\VSCode\User\" }
    VSCode_keybindings = @{ Source = "~\AppData\Roaming\Code\User\keybindings.json"; Destination = ".\Both\VSCode\User\" }
}

foreach ($path in $paths.Values) {
    New-Item -ItemType Directory -Force -Path $path.Destination
    Get-ChildItem -Path $path.Destination -Recurse | Remove-Item -Force -Recurse
    Copy-Item -Path $path.Source -Destination $path.Destination -Recurse -Force
}
