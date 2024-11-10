# Todo: add linux-only support

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

def copy_data [filenames, _source, _destination] {
  # script does not like the ~, it sees it as a folder when used in a command
  let source = $_source | path expand
  let destination = $_destination | path expand

  if (is_a_folder $filenames) {
    if ($source | path exists) {
      print $"copying folder ($source) to ($destination)"
      cp -r $source ($destination | path dirname)
    }
  } else {
    for $src_filename in $filenames {
      let src_filepath = $source | path join $src_filename

      if ($src_filepath | path exists) {
        print $"copying file ($src_filepath) to ($destination)"
        cp $src_filepath ($destination | path join $src_filename)
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
    if not ($path.backup_path | path exists) {
      mkdir $path.backup_path
    }

    if ($path.backup_path | path exists) {
      remove_files $path.filenames $path.backup_path
    }

    # we prioritize the windows path
    mut source = if ($path.windows_path == "") { $path.wsl_path } else { $path.windows_path }
    copy_data $path.filenames $source $path.backup_path
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

  # need to restore both windows and wsl files
  for $path in $paths {
    restore_files $path.filenames $path.backup_path $path.windows_path
    restore_files $path.filenames $path.backup_path $path.wsl_path
  }
}

def init_paths [wsl_instance_name = "Ubuntu", wsl_user = "antoinegs"] {
  let pwsh_profile = pwsh -c "echo $PROFILE"
  let pwsh_file = $pwsh_profile | path basename 
  let pwsh_path = $pwsh_profile | path dirname
  let wsl_user_path = $"//wsl.localhost/($wsl_instance_name)/home/($wsl_user)"
   
  [
    [filenames, windows_path, wsl_path, backup_path]; 
    [[$pwsh_file], $pwsh_path, "", $"./Windows/PowerShell"]
    [[], "~/AppData/Local/nvim", $"($wsl_user_path).config", "./Both/Neovim/nvim"] 
    [[".ideavimrc"], "~", "", "./Both/IntelliJ"]
    [["settings.json", "keybindings.json"], "~/AppData/Roaming/Code/User", "", "./Both/VSCode/User"]
    [["settings.json"], "~/AppData/Local/Packages/Microsoft.WindowsTerminal_8wekyb3d8bbwe/LocalState", "", "./Windows/WindowsTerminal"]
    [[".bashrc"], "", $"($wsl_user_path)", "./Linux/Bash"]
    [["starship.toml"], "~/.config", $"($wsl_user_path)/.config", "./Both/Starship"]
    [["init.nu"], "~/.cache/starship", $"($wsl_user_path)/.cache/starship", "./Both/Starship"]
    [["user_preferences.json"], "", $"($wsl_user_path)/.config/warp-terminal", "./Linux/Warp"]
    [["env.nu", "config.nu"], "~/AppData/Roaming/nushell", $"($wsl_user_path)/.config/nushell", "./Both/Nushell"]
    [[], "~/AppData/Roaming/nushell/themes", $"($wsl_user_path)/.config/nushell/themes", "./Both/Nushell/themes"]
    [[".wezterm.lua"], "~", "", "./Both/Wezterm"]
    [[".zoxide.nu"], "~", $"($wsl_user_path)", "./Both/Zoxide"]
    [["init.nu"], "~/.cache/carapace", $"($wsl_user_path)/.cache/carapace" "./Both/Carapace"]
  ]
}

def "main list" [wsl_instance_name = "Ubuntu", wsl_user = "antoinegs"] {
  let paths = init_paths $wsl_instance_name $wsl_user

  for $path in $paths {
    print $"path: ($path.filenames) -> ($path.windows_path) -> ($path.wsl_path) -> ($path.backup_path)"
  }
}

