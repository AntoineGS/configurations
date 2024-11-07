# Both

## Requirements

## VSCode

- Install NeoVim plugin

## IntelliJ

- Install IdeaVim
- .ideavimrc is located in user directory root

# Windows

Use Winget whenever possible

## Requirements

- Python
  - `choco install python mingw`
- NodeJS
- Go
  - `winget install GoLang.Go`
- Nerdfonts
  - `wget https://github.com/ryanoasis/nerd-fonts/releases/download/v3.2.1/JetBrainsMono.zip`
  - Download and install with right click.
- Java
  - `winget install Microsoft.OpenJDF.21`
- Rust / Cargo

## WezTerm

- `winget install wez.wezterm`

## Neovim

- `winget install Neovim.Neovim`

## Starship

- `winget install Starship.Starship`

## PowerShell

- Use latest version of PowerShell
- To get the path to the PowerShell configuration file, type `$PROFILE` in pwsh
- Set JetBrains Mono Nerd Font Bold as default font

## Nushell

- `winget install nushell`
- `cargo install nu_plugin_semver nu_plugin_regex`
  From Nushell:
- `plugin add ~\.cargo\bin\nu_plugin_regex.exe`
- `plugin add ~\.cargo\bin\nu_plugin_semver.exe`

## Zoxide

- `winget install ajeetdsouza.zoxide`

## eza

`cargo install eza`

## carapace

`winget install -e --id rsteube.Carapace`

## Yazi

`winget install sxyazi.yazi`
`winget install 7zip.7zip jqlang.jq sharkdp.fd BurntSushi.ripgrep.MSVC junegunn.fzf ajeetdsouza.zoxide ImageMagick.ImageMagick`

# Linux

Use Homebrew whenever possible

## Requirements

- Go, Python
  - `sudo apt install golang python3 python3-venv build-essential`
- NodeJS
  - `curl -o- https://raw.githubusercontent.com/nvm-sh/nvm/v0.40.0/install.sh | bash`
  - `nvm install 22`
  - `npm install -g shelljs typescript`
- Nerdfonts
  - Go in a temp directory
  - `wget https://github.com/ryanoasis/nerd-fonts/releases/download/v3.2.1/JetBrainsMono.zip`
  - `unzip JetBrainsMono.zip`
  - `rm JetBrainsMono.zip`
  - `sudo mv JetBrainsMono* /usr/share/fonts/`
  - `fc-cache -f -v`
- Rust / Cargo

## Homebrew

- Bash
  - `/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"`
  - `echo >> /home/a_simard/.bashrc`
  - `echo 'eval "$(/home/linuxbrew/.linuxbrew/bin/brew shellenv)"' >> /home/a_simard/.bashrc`

## WezTerm

- `brew tap wez/wezterm-linuxbrew`
- `brew install wezterm`

## Neovim

- `brew install neovim`
- `sudo update-alternatives --install /usr/bin/editor editor /home/linuxbrew/.linuxbrew/bin/nvim 1 && \
sudo update-alternatives --set editor /home/linuxbrew/.linuxbrew/bin/nvim`
- If error when copying to "+ then:
  - `sudo apt install xclip`
  - Through ssh it is said to install lemonade

## Starship

- Install NerdFont (JetBrains Mono Nerd Font)
- `brew install starship`

## Warp Terminal

- `https://www.warp.dev/download`
- Font to JetBrainsMono and 16pt on WSL

## Nushell

- `apt install pkg-config libssl-dev build-essential`
- `brew install nushell`
- `cargo install nu_plugin_semver nu_plugin_regex`
  From Nushell, most likely not needed:
- `plugin add ~\.cargo\bin\nu_plugin_regex`
- `plugin add ~\.cargo\bin\nu_plugin_semver`

## Zoxide

- `brew install zoxide`

## eza

- `cargo install eza`

## carapace

- `brew install carapace`

## Yazi

- `brew install yazi ffmpegthumbnailer sevenzip jq poppler fd ripgrep fzf zoxide imagemagick font-symbols-only-nerd-font`

# TODO

- .bashrc, but need restore option for wgpu

# Notes

- On Work computer:

  - `./ConfigManager.ps1 -restore -wslUser a_simard`
