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
    StarshipNushell          = @{ 
        Data   = "~\.cache\starship\init.nu"; 
        Backup = ".\Both\Starship\init.nu" 
    }
    Warp              = @{ 
        Data   = "\\wsl.localhost\$wslInstanceName\home\$wslUser\.config\warp-terminal\user_preferences.json"; 
        Backup = ".\Linux\Warp\user_preferences.json" 
    }
    NushellEnv = @{
        Data = "~\AppData\Roaming\nushell\env.nu";
        Backup = ".\Both\Nushell\env.nu"
    }
    NushellConfig = @{
        Data = "~\AppData\Roaming\nushell\config.nu";
        Backup = ".\Both\Nushell\config.nu"
    }
    NushellThemes = @{
        Data = "~\AppData\Roaming\nushell\themes\";
        Backup = ".\Both\Nushell\themes"
    }
    Wezterm = @{
        Data = "~/.wezterm.lua";
        Backup = "./Both/Wezterm/.wezterm.lua"
    }
    Zoxide = @{
        Data = "~/.zoxide.nu";
        Backup = "./Both/Zoxide/.zoxide.nu"
    }
    Carapace = @{
        Data = "~/.cache/carapace/init.nu"
        Backup = "./Both/Carapace/init.nu"
    }
}

if ($restore) {
    $paths += @{
        StarshipLinux = @{ 
            Data   = "\\wsl.localhost\$wslInstanceName\home\$wslUser\.config\starship.toml"; 
            Backup = ".\Both\Starship\starship.toml" 
        }    
        StarshipNushellLinux          = @{ 
            Data   = "\\wsl.localhost\$wslInstanceName\home\$wslUser\.cache\starship\init.nu"; 
            Backup = ".\Both\Starship\init.nu" 
        }
        NeovimLinux   = @{ 
            Data   = "\\wsl.localhost\$wslInstanceName\home\$wslUser\.config\nvim\"; 
            Backup = ".\Both\Neovim\nvim" 
        }
        NushellEnvLinux = @{
            Data   = "\\wsl.localhost\$wslInstanceName\home\$wslUser\.config\nushell\env.nu"; 
            Backup = ".\Both\Nushell\env.nu"
        }
        NushellConfigLinux = @{
            Data   = "\\wsl.localhost\$wslInstanceName\home\$wslUser\.config\nushell\config.nu"; 
            Backup = ".\Both\Nushell\config.nu"
        }
        NushellThemesLinux = @{
            Data   = "\\wsl.localhost\$wslInstanceName\home\$wslUser\.config\nushell\themes\"; 
            Backup = ".\Both\Nushell\themes"
        }
        # Wezterm
        ZoxideLinux = @{
            Data   = "\\wsl.localhost\$wslInstanceName\home\$wslUser\.zoxide.nu"; 
            Backup = ".\Both\Zoxide\.zoxide.nu"
        }
        CarapaceLinux = @{
            Data   = "\\wsl.localhost\$wslInstanceName\home\$wslUser\.cache\carapace\init.nu"; 
            Backup = ".\Both\Carapace\init.nu"
        }
    }

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
