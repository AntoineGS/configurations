# De-Omarchy Guide

Remove omarchy's control over your Arch install while keeping all configs and functionality.
After this, omarchy can no longer overwrite your customizations via updates.

## Prerequisites

- An Arch Linux install with omarchy
- Your hyprland config lives in this repo at `Linux/hypr/` and is symlinked via tidydots

## Phase 1: Adopt Hyprland Configs Locally

Omarchy's hyprland defaults live in `~/.local/share/omarchy/default/hypr/` and are sourced
by your `hyprland.conf`. Copy them to a local `adopted/` directory you own.

```bash
# Create directory structure
mkdir -p ~/.config/hypr/adopted/bindings ~/.config/hypr/adopted/apps ~/.config/hypr/adopted/theme

# Copy all omarchy default hypr configs
cp ~/.local/share/omarchy/default/hypr/autostart.conf ~/.config/hypr/adopted/
cp ~/.local/share/omarchy/default/hypr/envs.conf ~/.config/hypr/adopted/
cp ~/.local/share/omarchy/default/hypr/looknfeel.conf ~/.config/hypr/adopted/
cp ~/.local/share/omarchy/default/hypr/input.conf ~/.config/hypr/adopted/
cp ~/.local/share/omarchy/default/hypr/windows.conf ~/.config/hypr/adopted/
cp ~/.local/share/omarchy/default/hypr/apps.conf ~/.config/hypr/adopted/
cp ~/.local/share/omarchy/default/hypr/bindings/*.conf ~/.config/hypr/adopted/bindings/
cp ~/.local/share/omarchy/default/hypr/apps/*.conf ~/.config/hypr/adopted/apps/

# Copy current theme configs
cp ~/.config/omarchy/current/theme/hyprland.conf ~/.config/hypr/adopted/theme/
cp ~/.config/omarchy/current/theme/hyprlock.conf ~/.config/hypr/adopted/theme/
```

### Update internal references in adopted configs

In `~/.config/hypr/adopted/windows.conf`, change:
```
source = ~/.local/share/omarchy/default/hypr/apps.conf
```
to:
```
source = ~/.config/hypr/adopted/apps.conf
```

In `~/.config/hypr/adopted/apps.conf`, replace all occurrences of:
```
~/.local/share/omarchy/default/hypr/apps/
```
with:
```
~/.config/hypr/adopted/apps/
```

Quick sed for that:
```bash
sed -i 's|~/.local/share/omarchy/default/hypr/apps.conf|~/.config/hypr/adopted/apps.conf|' ~/.config/hypr/adopted/windows.conf
sed -i 's|~/.local/share/omarchy/default/hypr/apps/|~/.config/hypr/adopted/apps/|g' ~/.config/hypr/adopted/apps.conf
```

### Update hyprland.conf source lines

In `Linux/hypr/hyprland.conf` (the git repo copy), replace the omarchy source block:

```
# Old
source = ~/.local/share/omarchy/default/hypr/autostart.conf
source = ~/.local/share/omarchy/default/hypr/bindings/media.conf
source = ~/.local/share/omarchy/default/hypr/bindings/tiling.conf
source = ~/.local/share/omarchy/default/hypr/bindings/utilities.conf
source = ~/.local/share/omarchy/default/hypr/envs.conf
source = ~/.local/share/omarchy/default/hypr/looknfeel.conf
source = ~/.local/share/omarchy/default/hypr/input.conf
source = ~/.local/share/omarchy/default/hypr/windows.conf
source = ~/.config/omarchy/current/theme/hyprland.conf

# New
source = ~/.config/hypr/adopted/autostart.conf
source = ~/.config/hypr/adopted/bindings/media.conf
source = ~/.config/hypr/adopted/bindings/tiling.conf
source = ~/.config/hypr/adopted/bindings/utilities.conf
source = ~/.config/hypr/adopted/envs.conf
source = ~/.config/hypr/adopted/looknfeel.conf
source = ~/.config/hypr/adopted/input.conf
source = ~/.config/hypr/adopted/windows.conf
source = ~/.config/hypr/adopted/theme/hyprland.conf
```

### Update hyprlock.conf

In `Linux/hypr/hyprlock.conf`, change:
```
source = ~/.config/omarchy/current/theme/hyprlock.conf
```
to:
```
source = ~/.config/hypr/adopted/theme/hyprlock.conf
```

The `~/.config/omarchy/current/background` reference in hyprlock.conf is fine to keep
(the omarchy config folder stays).

### Update hypridle.conf.tmpl

Replace `omarchy-lock-screen` with a direct hyprlock call:
```
lock_cmd = pidof hyprlock || hyprlock
```

Replace `omarchy-launch-screensaver` with a lock:
```
on-timeout = pidof hyprlock || loginctl lock-session
```

## Phase 2: Resolve Symlinks

Replace symlinks that point to omarchy theme files with actual file copies:

```bash
# btop theme
cp --remove-destination "$(readlink -f ~/.config/btop/themes/current.theme)" ~/.config/btop/themes/current.theme

# mako notification config
cp --remove-destination "$(readlink -f ~/.config/mako/config)" ~/.config/mako/config
```

## Phase 3: Copy All Omarchy Scripts

Copy all ~200 omarchy scripts to `~/.local/bin/` so they're yours:

```bash
mkdir -p ~/.local/bin
cp ~/.local/share/omarchy/bin/* ~/.local/bin/
```

## Phase 4: Update Environment & Systemd

### Update uwsm env

Edit `~/.config/uwsm/env` — change PATH to use `~/.local/bin` instead of the omarchy git repo:

```bash
# Old
export OMARCHY_PATH=$HOME/.local/share/omarchy
export PATH=$OMARCHY_PATH/bin:$PATH

# New — keep OMARCHY_PATH (scripts reference it for themes/resources)
# but use local bin for the scripts themselves
export OMARCHY_PATH=$HOME/.local/share/omarchy
export PATH=$HOME/.local/bin:$PATH
```

Also replace `omarchy-cmd-present mise` with `command -v mise >/dev/null 2>&1`.

### Update battery monitor service

Edit `~/.config/systemd/user/omarchy-battery-monitor.service`, change:
```
ExecStart=%h/.local/share/omarchy/bin/omarchy-battery-monitor
```
to:
```
ExecStart=%h/.local/bin/omarchy-battery-monitor
```

Then reload:
```bash
systemctl --user daemon-reload
```

## Phase 5: Restore Official Arch Mirrors (requires sudo)

Omarchy redirects all pacman traffic through `stable-mirror.omarchy.org` via `/etc/pacman.d/mirrorlist`.
This delays upstream packages (e.g. Qt 6.11 shipped in Arch on March 26 but the omarchy mirror lagged behind),
which causes ABI mismatches with omarchy packages built against newer versions.

```bash
# Back up current mirrorlist
sudo cp /etc/pacman.d/mirrorlist /etc/pacman.d/mirrorlist.omarchy

# Generate a fresh mirrorlist with reflector (adjust --country as needed)
sudo reflector --country Canada --latest 10 --sort rate --save /etc/pacman.d/mirrorlist

# Or manually set a mirror
# echo 'Server = https://mirror.csclub.uwaterloo.ca/archlinux/$repo/os/$arch' | sudo tee /etc/pacman.d/mirrorlist

# Full system update with the real repos
sudo pacman -Syu
```

## Phase 6: Remove Omarchy Repo & Keyring (requires sudo)

```bash
# Remove [omarchy] section from pacman.conf
sudo sed -i '/^\[omarchy\]/,/^Server = https:\/\/pkgs\.omarchy\.org/d' /etc/pacman.conf

# Remove the keyring package
sudo pacman -R omarchy-keyring

# Refresh databases — omarchy packages become "foreign" (like AUR)
sudo pacman -Syyu
```

After this, all ex-omarchy packages stay installed but won't auto-update.
Reinstall from AUR later if you want updates for specific packages (yay, spotify, etc.).

## Phase 7: System Cleanup (requires sudo)

### Plymouth boot splash

```bash
# List available themes
plymouth-set-default-theme -l

# Switch to bgrt (manufacturer logo + spinner) and rebuild initramfs
sudo plymouth-set-default-theme -R bgrt
```

### Rename /etc config files

```bash
# inotify watchers (useful setting, just rename)
sudo mv /etc/sysctl.d/90-omarchy-file-watchers.conf /etc/sysctl.d/90-file-watchers.conf

# initramfs hooks — rename but keep contents (has encrypt + btrfs-overlayfs)
# Review contents first: cat /etc/mkinitcpio.conf.d/omarchy_hooks.conf
sudo mv /etc/mkinitcpio.conf.d/omarchy_hooks.conf /etc/mkinitcpio.conf.d/hooks.conf
```

### SDDM (optional)

The SDDM theme is set to "omarchy" in `/etc/sddm.conf.d/autologin.conf`.
Theme files in `/usr/share/sddm/themes/omarchy/` will persist. Change the theme
if desired or leave it.

## Post-Reboot Verification

After rebooting, verify:

```bash
# Hyprland configs don't reference omarchy git repo
grep -r '.local/share/omarchy' ~/.config/hypr/*.conf ~/.config/hypr/adopted/**/*.conf

# pacman.conf is clean
grep omarchy /etc/pacman.conf

# Plymouth is not omarchy
plymouth-set-default-theme

# Scripts come from ~/.local/bin
which omarchy-lock-screen  # should show ~/.local/bin/omarchy-lock-screen
```

## What You Keep

| Location | Purpose |
|----------|---------|
| `~/.config/hypr/adopted/` | Locally owned hyprland defaults — edit freely |
| `~/.local/bin/omarchy-*` | Your copies of all omarchy scripts |
| `~/.config/omarchy/` | Themes, backgrounds, branding — kept as-is |
| `~/.local/share/omarchy/` | Old git repo — reference only, not on PATH |

## Foreign Packages to Review Later

These ex-omarchy packages are frozen at their current version. Reinstall from
AUR for updates, or remove if unused:

- elephant + elephant-* plugins (app launcher)
- walker (app launcher backend)
- aether (display manager helper)
- omarchy-nvim (pre-built LazyVim — you have your own nvim config)
- omarchy-walker (meta package)
- makima-bin (input device remapper)
- asdcontrol (Apple Studio Display control)
- tobi-try
- 1password-beta, 1password-cli
- spotify, typora, pinta, localsend
- ttf-ia-writer, yaru-icon-theme
- python-terminaltexteffects
- limine-mkinitcpio-hook, limine-snapper-sync
- hyprland-preview-share-picker
- tzupdate, ufw-docker, xdg-terminal-exec, yay
