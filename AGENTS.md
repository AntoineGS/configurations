# Agent Guidelines for Configurations Repository

## Repository Overview
Personal dotfiles repository managing configurations for Windows and Linux environments (Neovim, Nushell, Hyprland, QMK, WezTerm, etc).

## Build/Test Commands
- **Backup configs**: `nu backup-manager.nu backup`
- **Restore configs**: `nu backup-manager.nu restore`
- **List mappings**: `nu backup-manager.nu list`
- **Lua formatting**: `stylua .` (uses .stylua.toml: 120 columns, 2 spaces, Unix line endings)
- **No dedicated test suite** - configs are validated by direct application usage

## Code Style
- **Line endings**: LF only (enforced via .gitattributes)
- **Lua**: 2 spaces, no call parentheses, double quotes preferred, 120 column width
- **Nushell**: snake_case, explicit types where helpful, immutable by default (use `mut` when needed)
- **C (QMK)**: Follow QMK conventions, use clang-format, descriptive layer names
- **Config files**: Preserve existing indentation and style (YAML: 2 spaces, TOML: varies)

## Commit Messages
Use conventional commits format: `type(scope): description` (e.g., `feat(tmux): improve UI`, `fix(backup): zsh-transient-prompt repo`, `chore(pacman): sync packages`)
