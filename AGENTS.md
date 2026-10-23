# Agent Guidelines for Configurations Repository

## CRITICAL: This Is a Public Repository

This repository is published publicly on GitHub. **Never commit private
details**, including:

- Secrets: passwords, API keys, tokens, SSH or GPG private keys, certificates
- Internal hostnames, IP addresses, domains, VPN/Tailscale details, and network
  layouts that are not already public
- Employer or client names, internal project details, customer data
- Personal information: emails, phone numbers, addresses, account identifiers

Keep such values out of tracked files: use templates with values supplied at
install time, environment variables, or untracked local files. Check every diff
for private details before staging. If something private is already tracked,
stop and tell the user instead of committing over it; removing it requires
rewriting history.

## Issue Tracking

Issues are tracked with beads (`bd`) on the shared Dolt server. Issue data is
auto-committed and pushed to `refs/dolt/data` on the **private** repository
`AntoineGS/configurations-beads`, never to this public repository. Issues may
hold private details; code and config in this repository may not.

## Repository Overview

Personal dotfiles repository managing configurations for Windows and Linux
environments (Neovim, Nushell, Hyprland, QMK, WezTerm, etc).

## Build/Test Commands

- **Backup configs**: `nu backup-manager.nu backup`
- **Restore configs**: `nu backup-manager.nu restore`
- **List mappings**: `nu backup-manager.nu list`
- **Lua formatting**: `stylua .` (uses .stylua.toml: 120 columns, 2 spaces, Unix
  line endings)

## Development Policy

- For simple configurations changes, do not create plans or tests unless
  explicitely asked, make the changes and ask the user to test. Reviewing your
  own changes is important though.

## Testing Policy

- This is a personal configuration repository; direct application and use are
  the default validation methods.
- Tests are exceptional. Add or retain them only for complex stateful behavior,
  destructive or security-sensitive operations, or durable regressions for
  non-obvious bugs.
- Routine configuration changes must not require adding or updating tests.
- Do not test declarative configuration, package lists, styling or layout,
  keybindings, manifests, exact source text, simple wrappers, or straightforward
  command wiring.
- Bug-investigation tests may be temporary. Keep them only when they protect
  against a likely-to-recur failure.
- Run retained tests individually when changing their associated complex
  behavior or investigating a relevant bug; there is no repository-wide test
  suite. Use the narrowest worktree-scoped dry-run when reviewing a profile:

```bash
REPO_DIR=/path/to/configurations
tidydots --dir "$REPO_DIR" install hyprland -n
```

## Code Style

- **Line endings**: LF only (enforced via .gitattributes)
- **Lua**: 2 spaces, no call parentheses, double quotes preferred, 120 column
  width
- **Nushell**: snake_case, explicit types where helpful, immutable by default
  (use `mut` when needed)
- **C (QMK)**: Follow QMK conventions, use clang-format, descriptive layer names
- **Config files**: Preserve existing indentation and style (YAML: 2 spaces,
  TOML: varies)

## Commit Messages

Use conventional commits format: `type(scope): description` (e.g.,
`feat(tmux): improve UI`, `fix(backup): zsh-transient-prompt repo`,
`chore(pacman): sync packages`)
