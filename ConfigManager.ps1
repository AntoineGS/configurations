if ($args.Length -eq 0) {
    Write-Host "An argument is required. Use 'backup' to backup configurations or 'restore' to restore them."
    exit
}

$action = $args[0]

if ($action -ne "backup" -and $action -ne "restore") {
    Write-Host "Invalid argument. Use 'backup' to backup configurations or 'restore' to restore them."
    exit
}

$profileFile = Split-Path -Path $PROFILE -Leaf

# Define source and destination paths
$paths = @{
    Profile = @{ Data = $PROFILE; Backup = ".\Windows\PowerShell\$profileFile" }
    Neovim = @{ Data = "~\AppData\Local\nvim\"; Backup = ".\Both\Neovim\" }
    IdeaVim = @{ Data = "~\.ideavimrc"; Backup = ".\Both\IntelliJ\.ideavimrc" }
    VSCodeSettings = @{ Data = "~\AppData\Roaming\Code\User\settings.json"; Backup = ".\Both\VSCode\User\settings.json" }
    VSCodeKeybindings = @{ Data = "~\AppData\Roaming\Code\User\keybindings.json"; Backup = ".\Both\VSCode\User\keybindings.json" }
}

if ($action -eq "backup") {
    # Some paths may share the same destination so to prevent deleting a previously copied file we do this in two passes
    foreach ($path in $paths.Values) {
        $actualPath = Split-Path -Path $path.Backup
        New-Item -ItemType Directory -Force -Path $actualPath
        Get-ChildItem -Path $path.Backup | Remove-Item -Force -Recurse
    }

    foreach ($path in $paths.Values) {
        Copy-Item -Path $path.Data -Destination $path.Backup -Recurse -Force
    }
}
elseif ($action -eq "restore") {
    foreach ($path in $paths.Values) {
        if (Test-Path -Path $path.Data) {
            $actualPath = $path.Data
            Remove-Item -Path $path.Data -Force -Recurse 
            $actualPath = Split-Path -Path $path.Data
        }
        else {
            $actualPath = Split-Path -Path $path.Data
        }

        Get-ChildItem -Path $path.Backup | Copy-Item -Destination $actualPath -Recurse -Force -Verbose
    }
}