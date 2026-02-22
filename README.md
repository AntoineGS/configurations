sudo pacman -S texlive-basic texlive-xetex texlive-latexextra texlive-fontsextra
texlive-fontsrecommended texlive-bin texlive-doc sudo pacman -S
texlive-fontsrecommended texlive-latexextra texlive-fontsextra sudo pacman -S
texlive-fontsextra sudo ln -s /usr/share/texmf-dist/fonts/opentype
/usr/share/fonts/texmf-opentype; fc-cache -f

!! Add Everything config and MultiCommander config !! Add
/etc/pam.d/system-local-login

# Windows

## Requirements

- Nerdfonts
  - `wget https://github.com/ryanoasis/nerd-fonts/releases/download/v3.2.1/JetBrainsMono.zip`
  - Download and install with right click.

## Nushell

- `winget install nushell`
- `cargo install nu_plugin_semver nu_plugin_regex` From Nushell:
- `plugin add ~\.cargo\bin\nu_plugin_regex.exe`
- `plugin add ~\.cargo\bin\nu_plugin_semver.exe`

## File Indexing

- Install Everything as a service:
  - `https://www.voidtools.com/`

## Total Commander

`https://www.ghisler.com/download.htm`

- Plugins: `https://www.ghisler.ch/board/viewtopic.php?t=33740`

## Winaero Tweaker

## ContextMenuManager

`https://github.com/BluePointLilac/ContextMenuManager/releases`

# Linux

## Systemd Units Backup

Daily timer to backup enabled services and timers to
`Linux/systemd/units-enabled.txt`:

```bash
sudo systemctl daemon-reload
sudo systemctl enable --now units-backup.timer
```

## Hyperland

- `systemctl --user daemon-reload; systemctl --user enable --now watch-rustdesk-submap.service`
- `sudo chmod +x ~/.config/hypr/rustdesk-submap-watch.sh`

## SSH Agent

Systemd socket-activated ssh-agent with 4-hour key lifetime. Keys are automatically added on first use via `AddKeysToAgent yes` in `~/.ssh/config`.

```bash
systemctl --user daemon-reload
systemctl --user enable --now ssh-agent.socket
```

Log out and back in (or `export SSH_AUTH_SOCK="$XDG_RUNTIME_DIR/ssh-agent.socket"` in the current session) for the environment variable to take effect.

## Requirements

- NodeJS
  - `sudo npm install -g shelljs typescript`
- Nerdfonts
  - Go in a temp directory
  - `wget https://github.com/ryanoasis/nerd-fonts/releases/download/v3.2.1/JetBrainsMono.zip`
  - `unzip JetBrainsMono.zip`
  - `rm JetBrainsMono.zip`
  - `sudo mv JetBrainsMono* /usr/share/fonts/`
  - `fc-cache -f -v`

## Homebrew

- Bash
  - `/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"`
  - `echo >> ~/.bashrc`
  - `echo 'eval "$(/home/linuxbrew/.linuxbrew/bin/brew shellenv)"' >> ~/.bashrc`

## Ghostty

- `xdg-mime default com.mitchellh.ghostty.desktop x-scheme-handler/terminal`

## Neovim

- `sudo update-alternatives --install /usr/bin/editor editor /home/linuxbrew/.linuxbrew/bin/nvim 1 && \ sudo update-alternatives --set editor /home/linuxbrew/.linuxbrew/bin/nvim`
- If error when copying to "+ then:
  - `sudo apt install xclip`
  - Through ssh it is said to install lemonade

## Starship

- Install NerdFont (JetBrains Mono Nerd Font)
- `brew install starship`

## Nushell

- `which nu | sudo tee -a /etc/shells`
- `chsh -s "$(which nu)"` From Nushell, most likely not needed:

## Yazi

- `brew install yazi ffmpegthumbnailer sevenzip jq poppler fd ripgrep fzf zoxide imagemagick`

# TODO

- Add nushell LSP/Formatter
- Add pwsh Formatter
