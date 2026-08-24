`sudo pacman -S texlive-basic texlive-xetex texlive-latexextra texlive-fontsextra`
`texlive-fontsrecommended texlive-bin texlive-doc sudo pacman -S`
`texlive-fontsrecommended texlive-latexextra texlive-fontsextra sudo pacman -S`
`texlive-fontsextra sudo ln -s /usr/share/texmf-dist/fonts/opentype`
`/usr/share/fonts/texmf-opentype; fc-cache -f`

!! Add Everything config and MultiCommander config !! Add
`/etc/pam.d/system-local-login`

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

## Arch Installation

- Follow the [reproducible Arch installation guide](Linux/install/archinstall/README.md) for the ISO workflow.
- After reboot, run `Linux/install/bootstrap` as the sole post-reboot setup entry point.
- Run `Linux/install/bootstrap --dry-run` before applying changes. If `tidydots` is
  unavailable, the command reports an incomplete preview with exit status `4`,
  explicitly skips its package and configuration phases, and must be rerun after
  installing the prerequisite.

## Package Profiles

`tidydots.yaml` is desired package state.
`pkglist-pacman-<hostname>.txt` and `pkglist-aur-<hostname>.txt` are generated audit snapshots.
- Graphical shared packages/configs require real Linux, a display, and non-WSL execution, except `antoinews-linux` is explicitly allowed headless.
- Machine-wide shared services use real Linux/non-WSL conditions.
Hardware and machine policy use exact hostname conditions.
`antoinews-linux` is the Intel desktop profile.

Focused previews such as `tidydots --dir "$REPO_DIR" install hyprland -n` are
intentionally limited to that application and may install only its package.
The canonical complete bootstrap package preview is the unscoped command:
`tidydots --dir "$REPO_DIR" install -n`.

Review only the relevant profile with a worktree-scoped dry-run. Set `REPO_DIR`
to the checkout being reviewed; every command below is non-mutating:

```bash
REPO_DIR=/path/to/configurations

# Shared desktop baseline
tidydots --dir "$REPO_DIR" install hyprland -n
tidydots --dir "$REPO_DIR" install pipewire-audio -n
tidydots --dir "$REPO_DIR" install linux-services-packages -n

# Intel desktop profile
tidydots --dir "$REPO_DIR" install antoinews-linux-intel -n

# Network stack
tidydots --dir "$REPO_DIR" install antoinews-linux-network -n
tidydots --dir "$REPO_DIR" restore antoinews-linux-network -n

# Limine and Snapper
tidydots --dir "$REPO_DIR" install limine -n
tidydots --dir "$REPO_DIR" install limine-snapper-sync -n
tidydots --dir "$REPO_DIR" restore limine-current-desktop-config -n
tidydots --dir "$REPO_DIR" install snapper -n
tidydots --dir "$REPO_DIR" restore snapper -n
```

Hostname-gated previews can report a condition mismatch when intentionally run
on another host; that is the expected exclusion behavior.

## Systemd Units Backup

Daily timer to backup enabled services and timers to
`Linux/systemd/units-enabled.txt`:

```bash
sudo systemctl daemon-reload
sudo systemctl enable --now units-backup.timer
```

## Hyprland

- `systemctl --user daemon-reload; systemctl --user enable --now watch-rustdesk-submap.service`
- `sudo chmod +x ~/.config/hypr/rustdesk-submap-watch.sh`

## SSH Agent

Systemd socket-activated ssh-agent with 4-hour key lifetime. Keys are
automatically added on first use via `AddKeysToAgent yes` in `~/.ssh/config`.

```bash
systemctl --user daemon-reload
systemctl --user enable --now ssh-agent.socket
```

Log out and back in (or
`export SSH_AUTH_SOCK="$XDG_RUNTIME_DIR/ssh-agent.socket"` in the current
session) for the environment variable to take effect.

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

- Install Nerd Fonts (JetBrains Mono Nerd Font)
- `brew install starship`

## Nushell

- `which nu | sudo tee -a /etc/shells`
- `chsh -s "$(which nu)"` From Nushell, most likely not needed:

## Yazi

- `brew install yazi ffmpegthumbnailer sevenzip jq poppler fd ripgrep fzf zoxide imagemagick`

# TODO

- Add nushell LSP/Formatter
- Add pwsh Formatter
