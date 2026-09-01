# tidydots v3 config schema

Reference for `tidydots.yaml`. Examples are drawn from the real repo.

The local app configuration lives at `~/.config/tidydots/config.yaml` and selects the
repository:

```yaml
config_dir: ~/.dotfiles
```

Hostname choices belong in the tracked `tidydots.yaml` v3 config:

```yaml
version: 3
hostnames:
  - desktop
  - laptop
```

`hostnames` is optional TUI metadata for the When chooser. The chooser generates
`{{ eq .Hostname "desktop" }}` for one selected host or
`{{ or (eq .Hostname "desktop") (eq .Hostname "laptop") }}` for multiple hosts,
which is stored as an application's or entry's v3 `when` expression.
For compatibility, a local `hostnames` list is used only when `tidydots.yaml` omits it.

## Top level

```yaml
version: 3
hostnames:               # optional choices for the TUI When chooser
  - desktop
  - laptop
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
  when: '{{ eq .Hostname "omarchbook" }}' # optional entry gate
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
  when: '{{ eq .Hostname "omarchbook" }}' # optional entry gate
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
  when: '{{ eq .Hostname "omarchbook" }}' # optional entry gate
  check:
    linux: npm ls -g opencode-with-claude >/dev/null 2>&1
  run:
    linux: npm install -g opencode-with-claude
```

### Entry conditions

`when:` is optional on every item in `entries:`, whether it is a symlink, copy,
or setup entry. It uses the templating context below. An entry is included only
when both its application's `when:` and its own `when:` evaluate to `true`.
False results and template errors exclude it before target/backup resolution,
setup checks (including dry-run), setup commands, or listing. Explicit CLI
targeting of an excluded entry returns a conditions mismatch error. `package:` is
singular and application-level, so packages use only the application's `when:`.

```yaml
entries:
  - name: omarchbook .desktop files
    when: '{{ eq .Hostname "omarchbook" }}'
    backup: ./Linux/os/applications/omarchbook
    targets:
      linux: ~/.local/share/applications/omarchbook
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

## custom / url install (siblings of managers)

`custom:` and `url:` sit directly under `package:` — NOT inside `managers:`
(unlike `installer`, which is a manager). tidydots selects an install method
by availability: package `managers` first, then `custom`, then `url`.

`custom:` maps OS → shell command:

```yaml
package:
  name: mytool
  custom:
    linux: cargo install mytool
    windows: scoop install mytool
```

`url:` maps OS → a download-and-run spec. `command` runs after download; use
`{file}` as the placeholder for the downloaded file path:

```yaml
package:
  name: mytool
  url:
    linux:
      url: https://example.com/mytool-linux
      command: install -m755 {file} ~/.local/bin/mytool
```

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
