# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Repository Overview

This is a cross-platform dotfiles/configuration repository for Linux (Arch Linux with Hyprland) and Windows systems. Configurations are organized by platform with shared configs in `Both/`.

**Directory Structure:**

- `Both/` - Cross-platform configurations (Neovim, WezTerm, Nushell, Starship, VSCode, IntelliJ, Yazi)
- `Linux/` - Linux-specific configs (Hyprland, Bash, Zsh, Pacman hooks, QMK keyboard firmware)
- `Windows/` - Windows-specific configs (Komorebi, GlazeWM, Yasb, PowerShell, Total Commander)

## Package Management

### Linux (Arch Linux)

**Automatic package list tracking:**
The repository uses Pacman hooks to automatically update package lists on install/remove operations.

Hooks located in `Linux/pacman/`:

- `pkg-backup-pacman.hook` - Tracks explicitly installed pacman packages to `pkglist-pacman.txt`
- `pkg-backup-aur.hook` - Tracks AUR packages to `pkglist-aur.txt`

These hooks execute Nushell commands post-transaction:

```bash
# Pacman packages (explicitly installed)
pacman -Qqent | save -f /home/antoinegs/gits/configurations/Linux/pacman/pkglist-pacman.txt

# AUR packages (explicitly installed from AUR)
pacman -Qqemt | save -f /home/antoinegs/gits/configurations/Linux/pacman/pkglist-aur.txt
```

**Install hooks:**

```bash
sudo cp Linux/pacman/*.hook /etc/pacman.d/hooks/
```

## Neovim Configuration

**Location:** `Both/Neovim/nvim/`

**Architecture:**

- Uses lazy.nvim plugin manager
- NvChad-based configuration with base46 theming
- Plugin files in `lua/plugins/` (each plugin gets its own file)
- Modular structure: `init.lua` → `configs/lazy.lua` → individual plugin imports
- Custom options in `lua/options.lua`, autocmds in `lua/autocmds.lua`, keymaps in `lua/mappings.lua`

**Key features:**

- Home row mods pattern awareness (for consistency with QMK keyboards)
- Transparency settings applied to base46 theme
- AI assistants: Avante, CodeCompanion, Copilot
- Blink.cmp for completion
- LSP via lspconfig with Mason

**Lock file:** `lazy-lock.json` tracks exact plugin versions (commit when intentionally updating plugins)

## QMK Keyboard Firmware

**Location:** `Linux/QMK/` contains keymaps for multiple keyboards:

- `piantor_pro/AntoineGS/` - Beekeeb Piantor Pro (36-key split)
- `sofle_choc/AntoineGS/` - Sofle Choc variant
- `trackball_nano/AntoineGS/` - Trackball Nano

**Build commands (from QMK firmware repo):**

```bash
# Compile firmware
qmk compile -kb beekeeb/piantor_pro -km AntoineGS
qmk compile -kb sofle_choc -km AntoineGS

# Flash to keyboard
qmk flash -kb beekeeb/piantor_pro -km AntoineGS
```

**Architecture details:**
See `Linux/QMK/piantor_pro/AntoineGS/CLAUDE.md` for detailed documentation on:

- Layer system (DEF/NAV/SYM/NUM with tri-layer activation)
- Home row mods pattern
- Custom keycode handling requirements for mod-tap functions
- French accented character implementation using US International dead keys

## ZMK Keyboard Firmware

**Location:** `Linux/zmk-config/keyball44/`

**Keyboards using ZMK:**

- `keyball44/` - Keyball 44 (44-key split with PMW3610 trackball)

**Build Environment:**

- ZMK firmware repository: `~/gits/zmk`
- Python virtual environment: `~/gits/zmk/.venv`
- Build system: West (Zephyr meta-tool)
- Module structure: Uses ZMK module pattern with `zephyr/module.yml`

**Build and Flash (Automated):**

```bash
# From the keyball44 config directory
cd ~/gits/configurations/Linux/zmk-config/keyball44

# Build and flash left side
./build_flash.sh left

# Build and flash right side
./build_flash.sh right
```

The script will:
- Build the firmware with pristine build (`-p` flag)
- Wait for you to double-tap the reset button
- Automatically detect and mount the Nice Nano
- Flash the firmware
- Sync and unmount

**Manual Build Commands (if needed):**

```bash
cd ~/gits/zmk
source .venv/bin/activate
cd app

# Build left side
west build -d build/left -b nice_nano_v2 -- -DSHIELD="keyball44_left nice_view_adapter nice_view_custom" -DZMK_CONFIG=/home/antoinegs/gits/configurations/Linux/zmk-config/keyball44

# Build right side (with PMW3610 trackball driver)
west build -d build/right -b nice_nano_v2 -- -DSHIELD="keyball44_right nice_view_adapter nice_view" -DZMK_CONFIG=/home/antoinegs/gits/configurations/Linux/zmk-config/keyball44
```

**Firmware Output:**

- Left: `~/gits/zmk/app/build/left/zephyr/zmk.uf2` (~544 KB)
- Right: `~/gits/zmk/app/build/right/zephyr/zmk.uf2` (~698 KB)

**Flashing:**

1. Double-tap reset button on Nice Nano to enter bootloader mode
1. Copy the `.uf2` file to the mounted USB drive
1. Board will automatically reboot with new firmware

**Important Notes:**

- The `-p` flag does a pristine build (clean rebuild)
- Remove `-p` for incremental builds after making small changes
- The right side is larger due to the PMW3610 trackball driver
- PMW3610 driver is fetched via West from kumamuk-git/zmk-pmw3610-driver

**Dependencies:**

- Zephyr SDK 0.16.3 installed at `~/zephyr-sdk-0.16.3`
- Python packages in venv: setuptools, protobuf, west
- CMake, dtc (device tree compiler), ninja-build

**Configuration Files:**

- `boards/shields/keyball44/keyball44.keymap` - Main keymap with layers, behaviors, and macros
- `boards/shields/keyball44/keyball44.conf` - Keyboard-level configuration (BLE, display, behaviors)
- `boards/shields/keyball44/keyball44_left.overlay` - Left side hardware definition
- `boards/shields/keyball44/keyball44_right.overlay` - Right side hardware definition
- `boards/shields/keyball44/keyball44_right.conf` - PMW3610 trackball configuration
- `config/west.yml` - West manifest for dependencies
- `zephyr/module.yml` - ZMK module definition

**Architecture details:**
See `Linux/zmk-config/keyball44/CONFIG.md` for detailed documentation on:

- Timeless homerow mods implementation (urob's pattern)
- 4-layer system (DEF/NAV/SYM/NUM with tri-layer)
- French character macros using US International dead keys
- PMW3610 trackball driver configuration
- Key position definitions for positional hold-tap
- Testing checklist and migration notes from QMK

**Troubleshooting:**

- If build fails with "unknown symbol PMW3610": Run `west update` to fetch driver modules
- If Python errors occur: Ensure `setuptools` and `protobuf` are installed in venv
- Devicetree errors: Check syntax in `.overlay` and `.keymap` files (use `,` between binding items)

## Hyprland Window Manager

**Location:** `Linux/hypr/`

**Architecture:**

- Uses Omarchy defaults as base (sourced from `~/.local/share/omarchy/`)
- Custom overrides in individual conf files: `monitors.conf`, `bindings.conf`, `input.conf`, `looknfeel.conf`, `autostart.conf`
- NVIDIA-specific environment variables configured
- Modular configuration split across multiple files

**RustDesk integration:**

- `watch-rustdesk-submap.sh` - Event-driven script that watches Hyprland socket for RustDesk windows
- Automatically switches to `clean` submap (disables most keybindings) when RustDesk Remote Desktop window is active
- Runs as systemd user service: `watch-rustdesk-submap.service`

**Enable RustDesk watcher:**

```bash
systemctl --user daemon-reload
systemctl --user enable --now watch-rustdesk-submap.service
```

## Shell Configurations

**Nushell:** Primary shell (`Both/Nushell/config.nu`, `env.nu`)

- Used in Pacman hooks for package list management
- Plugins: nu_plugin_semver, nu_plugin_regex

**PowerShell:** Windows (`Windows/PowerShell/`)
**Bash/Zsh:** Linux alternatives (`Linux/Bash/`, `Linux/Zsh/`)

**Starship:** Cross-platform prompt (`Both/Starship/`)

## Terminal Emulators

**WezTerm:** Primary terminal (`Both/Wezterm/.wezterm.lua`)
**Ghostty:** Alternative Linux terminal (`Linux/ghostty/`)

Both use JetBrains Mono Nerd Font.

## Window Managers (Windows)

**GlazeWM:** Tiling window manager for Windows (`Both/GlazeWM/config.yaml`)
**Komorebi:** Alternative tiling WM (`Windows/Komorebi/komorebi.json`, `whkdrc`)
**Yasb:** Status bar (`Windows/Yasb/config.yaml`, `styles.css`)

## File Managers

**Yazi:** Terminal file manager (`Both/Yazi/`)
**Total Commander:** Windows GUI file manager (`Windows/TotalCommander/`)

## Common Workflows

**After installing a package on Arch Linux:**
The package lists are automatically updated via hooks - just commit the changed `pkglist-*.txt` files.

**Updating Neovim plugins:**
Changes to `lazy-lock.json` should be committed when intentionally updating plugins (not on every sync).

**Working on QMK keymaps:**
The actual keymaps live in the QMK firmware repository (`~/qmk_firmware/keyboards/*/keymaps/AntoineGS`). This repo contains symlinks or copies for backup/versioning. Always compile from the QMK firmware repo.

**Hyprland configuration changes:**
Edit the individual conf files in `Linux/hypr/`, not the main `hyprland.conf` (which just sources other files). This preserves the Omarchy base and makes custom changes clear.
