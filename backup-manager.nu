#!/usr/bin/env nu
const env_types = {windows: "windows", linux: "linux"}
mut curr_env = $env_types.linux

if (($env | get -o OS) | default "" | str contains --ignore-case "windows") {
  $curr_env = $env_types.windows
}

let curr_env = $curr_env

print $"Detected OS: $($curr_env)"

def main [] {
  error make {msg: "You must either use `backup` or `restore` sub commands", }
}

def remove_files [filenames, _path] {
  let $path = $_path | path expand --no-symlink

  if (is_a_folder $filenames) {
    if (($path | path exists) and ($path | path type) != "symlink") {
      print $"removing folder ($path)"
      rm -r $path
    }
  } else {
    for $filename in $filenames {
      let filepath = $path | path join $filename

      if (($filepath | path exists) and ($filepath | path type) != "symlink") {
        print $"removing file ($filepath), type: ($filepath | path type)"
        rm $filepath
      }
    }
  }
}

def copy_data [filenames, _source, _destination] {
  # script does not like the ~, it sees it as a folder when used in a command
  let source = $_source | path expand
  let destination = $_destination | path expand

  if (is_a_folder $filenames) {
    if ($source | path exists) {
      print $"copying folder ($source) to ($destination)"

      if not ($destination | path exists) {
        mkdir $destination
      }

      cp -r $source $destination
    }
  } else {
    for $src_filename in $filenames {
      let src_filepath = $source | path join $src_filename

      if ($src_filepath | path exists) {
        print $"copying file ($src_filepath) to ($destination)"
        cp $src_filepath $destination
      }
    }
  }
}

def is_a_folder [filenames] {
  $filenames == []
}

def restore_files [filenames, _source, _destination] {
  if ($_destination == "") {
    return
  }
  
  remove_files $filenames $_destination

  if (is_a_folder $filenames) {
    let source = $_source | path expand
    let destination = $_destination | path expand --no-symlink

    if (($destination | path type) == "symlink") {
      return 
    }
         
    print $"creating symlink from ($source) to ($destination)"

    if ($curr_env == $env_types.windows) {
      mklink /J $destination $source
    } else { 
      ln -s $source $destination
    } 
    
    return
  } else {
    for $src_filename in $filenames {
      let src_filepath = $_source | path join $src_filename

      if ($src_filepath | path exists) {
        let source = $src_filepath | path expand
        let destination = ($_destination | path join $src_filename) | path expand --no-symlink
        
        if (($destination | path type) == "symlink") {
          return 
        }

        print $"creating symlink from ($source) to ($destination)"    
        if ($curr_env == $env_types.windows) {
          mklink $destination $source
        } else { 
          ln -s $source $destination
        } 
      }
    }
  }
}

def "main restore" [] {
  let paths = init_paths

  for $path in $paths {
    if ($curr_env == $env_types.windows) {
      restore_files $path.filenames $path.backup_path $path.windows_path
    } else {
      mut $linux_path = $path.linux_path
      restore_files $path.filenames $path.backup_path $linux_path
    }
  }
}

def init_paths [] {
  let pwsh_profile = if ($curr_env == $env_types.windows) {pwsh -c "echo $PROFILE"} else {""}
  let pwsh_file = $pwsh_profile | path basename 
  let pwsh_path = $pwsh_profile | path dirname
  mut is_root = false

  if ($curr_env != $env_types.windows) {
    $is_root = (id -u | str trim) == "0"
  } 

  if $is_root {
    [
      [filenames, windows_path, linux_path, backup_path]; 
      [[pkg-backup-aur.hook,pkg-backup-pacman.hook], "", "/usr/share/libalpm/hooks", "./Linux/pacman"]
    ]
  } else { 
    [
      [filenames, windows_path, linux_path, backup_path]; 
      [[$pwsh_file], $pwsh_path, "", "./Windows/PowerShell"]
      [[komorebi.json], "~", "", "./Windows/Komorebi"]
      [[whkdrc], "~/.config", "", "./Windows/Komorebi"]
      [["config.yaml", "styles.css"], "~/.config/yasb", "", "./Windows/Yasb"]
      [[], "~/AppData/Local/nvim", "~/.config/nvim", "./Both/Neovim/nvim"] 
      [[".ideavimrc"], "~", "", "./Both/IntelliJ"]
      [["settings.json", "keybindings.json"], "~/AppData/Roaming/Code/User", "", "./Both/VSCode/User"]
      [["settings.json"], "~/AppData/Local/Packages/Microsoft.WindowsTerminal_8wekyb3d8bbwe/LocalState", "", "./Windows/WindowsTerminal"]
      [[".bashrc"], "", "~", "./Linux/Bash"]
      [["starship.toml"], "~/.config", "~/.config", "./Both/Starship"]
      [["init.nu"], "~/.cache/starship", "~/.cache/starship", "./Both/Starship"]
      [["user_preferences.json"], "", "~/.config/warp-terminal", "./Linux/Warp"]
      [["env.nu", "config.nu"], "~/AppData/Roaming/nushell", "~/.config/nushell", "./Both/Nushell"]
      [[], "~/AppData/Roaming/nushell/themes", "~/.config/nushell/themes", "./Both/Nushell/themes"]
      [[".wezterm.lua"], "~", "~", "./Both/Wezterm"]
      [[".zoxide.nu"], "~", "~", "./Both/Zoxide"]
      [["init.nu"], "~/.cache/carapace", "~/.cache/carapace" "./Both/Carapace"]
      [[], "", "~/qmk_firmware/keyboards/beekeeb/piantor_pro/keymaps/AntoineGS", "./Linux/QMK/piantor_pro/AntoineGS"]
      [[], "", "~/qmk_firmware/keyboards/ploopyco/trackball_nano/keymaps/AntoineGS", "./Linux/QMK/trackball_nano/AntoineGS"]
      [[], "", "~/qmk_firmware/keyboards/sofle_choc/keymaps/AntoineGS", "./Linux/QMK/sofle_choc/AntoineGS"]
      [["config.yaml"], "~/.glzr/glazewm", "", "./Both/GlazeWM"]
      [[wincmd.ini], "~/AppData/Roaming/GHISLER", "", "./Windows/TotalCommander"]
      [[Everything-1.5a.ini], "~/AppData/Roaming/Everything", "", "./Windows/TotalCommander"]
      [[], "", "~/.config/hypr", "./Linux/hypr"]
      [[watch-rustdesk-submap.service], "", "~/.config/systemd/user", "./Linux/hypr"]
      [[], "", "~/.config/walker", "./Linux/walker"]
      [[], "", "~/.config/waybar", "./Linux/waybar"]
      [[], "", "~/.config/fsearch", "./Linux/fsearch"]
      [[], "", "~/.config/uwsm/default", "./Linux/uwsm/default"]
      [[], "~/AppData/Roaming/yazi/config", "~/.config/yazi", "./Both/Yazi"]
      [[".Xcompose"], "~", "~", "./Linux/Xcompose"]
    ]
  }
}

def "main list" [] {
  let paths = init_paths

  for $path in $paths {
    print $"path: ($path.filenames) -> ($path.windows_path) -> ($path.linux_path) -> ($path.backup_path)"
  }
}

