# Define source and destination paths
$paths = @{
    Profile = @{ Source = $PROFILE; Destination = ".\Windows\PowerShell" }
    Neovim = @{ Source = "~\AppData\Local\nvim\"; Destination = ".\Both\Neovim\" }
    IdeaVim = @{ Source = "~\.ideavimrc"; Destination = ".\Both\IntelliJ\" }
}

foreach ($path in $paths.Values) {
    New-Item -ItemType Directory -Force -Path $path.Destination
    Get-ChildItem -Path $path.Destination -Recurse | Remove-Item -Force -Recurse
    Copy-Item -Path $path.Source -Destination $path.Destination -Recurse -Force
}
