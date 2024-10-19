# Both
## Requirements
- Python
- NodeJS
  - `npm install -g shelljs`
  - `npm install --global typescript`
- Go
  - `winget install GoLang.Go`

## Neovim
- Using Chad config
- Requirements:
  - NodeJS (use nvm)
  - GCC (build-essentials on Linux and mingw using Choco on Windows)
  - Python
- On Windows: `C:\Users\antoi\AppData\Local\nvim\`
- On Linux: `~/.config/nvim` 
## VSCode
- Install NeoVim (tbd, does not feel as native as Vim but uses same config files as NeoVim... so we'll see)
## IntelliJ
- Install IdeaVim
- .ideavimrc is located in user directory root
## VSCode
- Copy the files to the right location

# Windows
- Use Winget whenever possible
## Starship
- Install NerdFont (JetBrains Mono Nerd Font)
- Install Starship from `https://starship.rs/installing/`
## PowerShell
- Use latest version of PowerShell
- To get the path to the PowerShell configuration file, type `$PROFILE` in pwsh
- Set JetBrains Mono Nerd Font Bold as default font

# Linux
## Starship
- Install NerdFont (JetBrains Mono Nerd Font)
- Install Starship from `https://starship.rs/installing/`
## Bash
- `nvim ~/.bashrc`
- Add `set -i vi` to the top 
- Add `eval "$(starship init bash)"` to the bottom