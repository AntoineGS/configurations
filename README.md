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
  - Download and install with right click..

## Neovim

- `winget install Neovim.Neovim`

## Starship

- `winget install Starship.Starship`

## PowerShell

- Use latest version of PowerShell
- To get the path to the PowerShell configuration file, type `$PROFILE` in pwsh
- Set JetBrains Mono Nerd Font Bold as default font

# Linux

Use Hombrew whenever possible

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

## Homebrew

- `/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"`
- `echo >> /home/a_simard/.bashrc`
- `echo 'eval "$(/home/linuxbrew/.linuxbrew/bin/brew shellenv)"' >> /home/a_simard/.bashrc`

## Neovim

- `brew install neovim`
- `sudo update-alternatives --install /usr/bin/editor editor /home/linuxbrew/.linuxbrew/bin/nvim 1 && \
sudo update-alternatives --set editor /home/linuxbrew/.linuxbrew/bin/nvim`
- `~/.config/nvim`
- If error when copying to "+ then:
  - `sudo apt install xclip`
  - Through ssh it is said to install lemonade

## Starship

- Install NerdFont (JetBrains Mono Nerd Font)
- `brew install starship`
- restore to `\\wsl.localhost\Ubuntu\home\antoinegs\.config\starship.toml` or
  `\\wsl.localhost\Ubuntu\home\antoi\.config\starship.toml`

## Warp Terminal

- `https://www.warp.dev/download`
- Font to JetBrainsMono and 16pt on WSL

# TODO

- .bashrc, but need restore option for wgpu
