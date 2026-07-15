# tidydots v3 config schema

Reference for `tidydots.yaml`. Examples are drawn from the real repo.

## Top level

```yaml
version: 3
manager_priority:        # order tidydots tries package managers
  - pacman
  - yay
  - paru
  - apt
  - brew
  - winget
applications:            # list of managed apps
  - ...
```

## Application

```yaml
- name: neovim                       # required
  description: Vim-fork ...          # optional
  when: '{{ eq .OS "linux" }}'       # optional gate (see Templating)
  entries:                           # optional list of entries
    - ...
  package:                           # optional, SINGULAR
    managers:
      ...
```

## Entry kinds

An entry lives under `entries:`. There are three kinds.

### 1. Config entry (symlink — default)

```yaml
- name: config
  backup: ./Both/Neovim/nvim        # source in the repo
  targets:                          # per-OS live locations
    linux: ~/.config/nvim
    windows: ~/AppData/Local/nvim
  files:                            # optional; omit/empty = whole folder
    - init.lua
  sudo: true                        # optional; elevate for this entry
```

### 2. Copy entry (`method: copy`)

Deploys a real file copy instead of a symlink. Content-based drift detection
re-copies only when the repo file differs; replaces a pre-existing symlink at
the target (safe migration). Requires a non-empty `files:` list. Does NOT
render `.tmpl` files.

```yaml
- name: config
  method: copy
  backup: ./Both/Foo
  targets:
    linux: ~/.config/foo
  files:
    - config.toml
```

### 3. Setup entry (`check` + `run`)

Runs a command instead of deploying files. On restore, `check` runs; if it
exits non-zero, `run` executes, then `check` runs again to confirm. Stateless
and self-healing (no DB). `check` must be read-only and fast — it runs on
every restore, dry-run, and TUI refresh.

```yaml
- name: claude-plugin
  check:
    linux: npm ls -g opencode-with-claude >/dev/null 2>&1
  run:
    linux: npm install -g opencode-with-claude
```

## package.managers

Map each manager to a package name. Supported managers: pacman, yay, paru,
apt, dnf, brew, winget, scoop, choco.

```yaml
package:
  managers:
    pacman: neovim
    apt: neovim
    brew: neovim
    winget: Neovim.Neovim
```

### winget with deps / explicit name

```yaml
winget:
  name: sxyazi.yazi
  deps:
    - 7zip.7zip
    - sharkdp.fd
```

### installer (custom command)

```yaml
installer:
  command:
    linux: curl -fsSL https://claude.ai/install.sh | bash
    windows: irm https://claude.ai/install.ps1 | iex
  binary: claude        # binary that proves it's already installed
```

### git as a package

```yaml
git:
  url: https://github.com/user/plugins.git
  branch: main          # optional
  targets:
    linux: ~/.local/share/nvim/site/pack/plugins/start/myplugins
  sudo: false           # optional
```

If the target has a `.git/`, tidydots runs `git pull`; otherwise it clones.

## Templating

`.tmpl` files (e.g. `.zshrc.tmpl`) render on restore to a sibling
`.tmpl.rendered`; the target symlinks to that (with `.tmpl` stripped). Paths in
`targets:`/`backup:` also support `{{ }}` expressions.

Context variables:

- `.OS` — `"linux"` or `"windows"`
- `.Distro` — e.g. `"arch"`, `"ubuntu"`
- `.Hostname`, `.User`
- `.HasDisplay` — display server present
- `.IsWSL` — running under WSL
- `.Env` — env map, e.g. `{{ index .Env "HOME" }}`

All [sprout](https://github.com/go-sprout/sprout) template functions are
available.

Re-renders use a 3-way merge (base = last pure render in `.tidydots.db`,
theirs = current `.tmpl.rendered`, ours = new render), preserving user edits;
conflicts get `<<<<<<< user-edits` / `=======` / `>>>>>>> template` markers.
`--force-render` bypasses the merge.

### Recommended .gitignore

```
*.tmpl.rendered
*.tmpl.conflict
.tidydots.db
.tidydots.db-*
```
