#!/usr/bin/env nu
const env_types = {windows: "windows", wsl: "wsl", linux: "linux"}
# we assume linux if its neither windows nor wsl, this means SSH is also assumed linux, which is pretty much true
mut curr_env = $env_types.linux

if (($env | get --ignore-errors OS) | default "" | str contains --ignore-case "windows") {
  $curr_env = $env_types.windows
} else if (($env | get --ignore-errors WSL_DISTRO_NAME) != "") {
  $curr_env = $env_types.wsl
}

let curr_env = $curr_env

print $"Detected OS: $($curr_env)"

def main [] {
  error make {msg: "You must either use `backup` or `restore` sub commands", }
}

def remove_files [filenames, _path] {
  let $path = $_path | path expand

  if (is_a_folder $path) {
    rm -r $path
  } else {
    for $filename in $filenames {
      let filepath = $path | path join $filename

      if ($filepath | path exists) {
        rm $filepath
      }
    }
  }
}

# todo this should test if the folder exists and create if not
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
        let destination = ($destination | path join $src_filename)
        print $"copying file ($src_filepath) to ($destination)"
        cp $src_filepath $destination
      }
    }
  }
}

def is_a_folder [filenames] {
  $filenames == []
}

def "main backup" [wsl_instance_name = "Ubuntu", wsl_user = "antoinegs"] {
  let paths = init_paths $wsl_instance_name $wsl_user
  
  for $path in $paths {
    let backup_path = if (is_a_folder $path.filenames) {$path.backup_path | path dirname} else {$path.backup_path}

    if not ($backup_path | path exists) {
      mkdir $backup_path
    }

    if ($backup_path | path exists) {
      remove_files $path.filenames $backup_path
    }

    # we prioritize the windows path
    mut source = if ($path.windows_path == "") { $path.linux_path } else { $path.windows_path }
    copy_data $path.filenames $source $backup_path
  }
}

def restore_files [filenames, source, destination] {
  if ($destination == "") {
    return
  }

  remove_files $filenames $destination
  copy_data $filenames $source $destination
}

def "main restore" [wsl_instance_name = "Ubuntu", wsl_user = "antoinegs"] {
  let paths = init_paths $wsl_instance_name $wsl_user

  for $path in $paths {
    if ($curr_env == $env_types.windows) {
      restore_files $path.filenames $path.backup_path ($path.windows_path | path dirname) 
    }
    restore_files $path.filenames $path.backup_path $path.linux_path
  }
}

def init_paths [wsl_instance_name = "Ubuntu", wsl_user = "antoinegs"] {
  let pwsh_profile = if ($curr_env == $env_types.windows) {pwsh -c "echo $PROFILE"} else {""}
  let pwsh_file = $pwsh_profile | path basename 
  let pwsh_path = $pwsh_profile | path dirname
  let wsl_user_path = $"//wsl.localhost/($wsl_instance_name)/home/($wsl_user)"
  let linux_user_path = if ($curr_env == $env_types.windows) { $wsl_user_path } else { "~" }
   
  [
    # Note: The Windows path must include the folder for folder backups, but not the Linux path
    [filenames, windows_path, linux_path, backup_path]; 
    [[$pwsh_file], $pwsh_path, "", $"./Windows/PowerShell"]
    [[], "~/AppData/Local/nvim", $"($linux_user_path)/.config", "./Both/Neovim/nvim"] 
    [[".ideavimrc"], "~", "", "./Both/IntelliJ"]
    [["settings.json", "keybindings.json"], "~/AppData/Roaming/Code/User", "", "./Both/VSCode/User"]
    [["settings.json"], "~/AppData/Local/Packages/Microsoft.WindowsTerminal_8wekyb3d8bbwe/LocalState", "", "./Windows/WindowsTerminal"]
    [[".bashrc"], "", $"($linux_user_path)", "./Linux/Bash"]
    [["starship.toml"], "~/.config", $"($linux_user_path)/.config", "./Both/Starship"]
    [["init.nu"], "~/.cache/starship", $"($linux_user_path)/.cache/starship", "./Both/Starship"]
    [["user_preferences.json"], "", $"($linux_user_path)/.config/warp-terminal", "./Linux/Warp"]
    [["env.nu", "config.nu"], "~/AppData/Roaming/nushell", $"($linux_user_path)/.config/nushell", "./Both/Nushell"]
    [[], "~/AppData/Roaming/nushell/themes", $"($linux_user_path)/.config/nushell/themes", "./Both/Nushell/themes"]
    [[".wezterm.lua"], "~", $"($linux_user_path)", "./Both/Wezterm"]
    [[".zoxide.nu"], "~", $"($linux_user_path)", "./Both/Zoxide"]
    [["init.nu"], "~/.cache/carapace", $"($linux_user_path)/.cache/carapace" "./Both/Carapace"]
    [[], "", $"($linux_user_path)/qmk_firmware/keyboards/beekeeb/piantor_pro/keymaps/AntoineGS", "./Linux/QMK/AntoineGS"]
  ]
}

def "main list" [wsl_instance_name = "Ubuntu", wsl_user = "antoinegs"] {
  let paths = init_paths $wsl_instance_name $wsl_user

  for $path in $paths {
    print $"path: ($path.filenames) -> ($path.windows_path) -> ($path.linux_path) -> ($path.backup_path)"
  }
}

