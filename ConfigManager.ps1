param (
    [switch]$restore,
    [string]$wslInstanceName = "Ubuntu",
    [string]$wslUser = "antoinegs"
)

$profileFile = Split-Path -Path $PROFILE -Leaf

# Define source and destination paths
$paths = @{
    Profile           = @{ 
        Data   = $PROFILE; 
        Backup = ".\Windows\PowerShell\$profileFile" 
    }
    Neovim            = @{ 
        Data   = "~\AppData\Local\nvim\"; 
        Backup = ".\Both\Neovim\nvim" 
    }
    IdeaVim           = @{ 
        Data   = "~\.ideavimrc"; 
        Backup = ".\Both\IntelliJ\.ideavimrc" 
    }
    VSCodeSettings    = @{ 
        Data   = "~\AppData\Roaming\Code\User\settings.json"; 
        Backup = ".\Both\VSCode\User\settings.json" 
    }
    VSCodeKeybindings = @{ 
        Data   = "~\AppData\Roaming\Code\User\keybindings.json"; 
        Backup = ".\Both\VSCode\User\keybindings.json" 
    }
    WindowsTerminal   = @{ 
        Data   = "~\AppData\Local\Packages\Microsoft.WindowsTerminal_8wekyb3d8bbwe\LocalState\settings.json"; 
        Backup = ".\Windows\WindowsTerminal\settings.json" 
    }
    Bashrc            = @{ 
        Data   = "\\wsl.localhost\$wslInstanceName\home\$wslUser\.bashrc"; 
        Backup = ".\Linux\Bash\.bashrc" 
    }
    Starship          = @{ 
        Data   = "~\.config\starship.toml"; 
        Backup = ".\Both\Starship\starship.toml" 
    }
    Warp              = @{ 
        Data   = "\\wsl.localhost\$wslInstanceName\home\$wslUser\.config\warp-terminal\user_preferences.json"; 
        Backup = ".\Linux\Warp\user_preferences.json" 
    }
}

if ($restore) {
    foreach ($path in $paths.Values) {
        if ($path.Data -like "*\") {
            $actualPath = $path.Data
            Remove-Item -Path $path.Data -Force -Recurse 
            $actualPath = Split-Path -Path $path.Data
        }
        else {
            $actualPath = Split-Path -Path $path.Data
        }

        Copy-Item $path.Backup -Destination $actualPath -Recurse -Force -Verbose
    }
}
else {
    # Some paths may share the same destination so to prevent deleting a previously copied file we do this in two passes
    foreach ($path in $paths.Values) {
        $actualPath = Split-Path -Path $path.Backup
        New-Item -ItemType Directory -Force -Path $actualPath

        if ( Test-Path $path.Backup ) {
            Remove-Item $path.Backup -Force -Recurse
        }
    }

    foreach ($path in $paths.Values) {
        Copy-Item -Path $path.Data -Destination $path.Backup -Recurse -Force
    }
}
