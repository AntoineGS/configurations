# tidydots v3 config schema

Reference for `tidydots.yaml`. Examples are drawn from the real repo.

Safety and installation behavior below follows the current patched repository
code and docs; do not assume an older installed binary supports it or upgrade
that binary without approval.

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

In the TUI, `-n` / `--dry-run` makes all application/entry add, edit, and
delete operations preview-only: neither `tidydots.yaml` nor the loaded
configuration is mutated. Deleting the last entry removes its application only
if it has no package definition; a package-only application is retained.

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

Deploys real files instead of symlinks. Ordinary non-template files use
content-based drift detection and are copied again only when the repo file
differs; a pre-existing symlink is replaced. Requires a non-empty `files:` list.
A selected `.tmpl` file is rendered to the suffix-free target and merged using
template render history; it does not create the symlink-mode repository alias or
`.tmpl.rendered` cache. Copy mode does not adopt an existing target.

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

Runs a command instead of deploying files. In the default `exit-code` mode, on
restore `check` runs; if it exits non-zero, `run` executes, then `check` runs
again to confirm. Stateless and self-healing (no DB). `check` must be
read-only and fast — it runs on every restore, dry-run, and TUI refresh. In
`status` mode, only exit codes `1` and `2` authorize `run`; a `3` or higher
status is a failed check and blocks it.

```yaml
- name: claude-plugin
  when: '{{ eq .Hostname "omarchbook" }}' # optional entry gate
  check:
    linux: npm ls -g opencode-with-claude >/dev/null 2>&1
  run:
    linux: npm install -g opencode-with-claude
```

#### `check_mode`

`check_mode` is setup-entry-only. Omit it, or set it to `exit-code`, to retain
legacy behavior: exit `0` means **Set up** and every nonzero exit means
**Needs setup**. Set it to `status` when the check can distinguish these
states:

| Exit code | Meaning |
| --- | --- |
| `0` | Set up |
| `1` | Needs setup |
| `2` | Outdated |
| `3` or higher | Check failed (indeterminate or error) |

Negative process exits, launch failures, and cancellation are **Check failed**.
A failed status check is actionable attention, but it blocks `run`, including
in a dry-run, until a safe check reports **Needs setup** or **Outdated**. Status
reporting and TUI refreshes never execute `run`; `run` itself always uses
ordinary success/failure semantics.

Use `status` only with a check command that deliberately implements this
protocol. For example, a status-aware updater can expose `--check` and return
these states (after its coordinated migration has been activated):

```yaml
- name: tidydots-binary
  check:
    linux: ~/.config/tidydots/setup-tidydots.sh --check
  run:
    linux: ~/.config/tidydots/setup-tidydots.sh --apply
  check_mode: status
```

The generic `npm ls` example above remains in legacy `exit-code` mode; do not
add `check_mode: status` unless the command returns the distinct status codes.

### Entry conditions

`when:` is optional on every item in `entries:`, whether it is a symlink, copy,
or setup entry. It uses the templating context below. An entry is included only
when both its application's `when:` and its own `when:` evaluate to `true`.
False results and template errors exclude it before target/backup resolution,
setup checks (including dry-run), setup commands, or listing. Explicit CLI
targeting of an excluded entry returns a conditions mismatch error. `package:`
is singular and application-level, so packages use only the application's `when:`.

```yaml
entries:
  - name: omarchbook .desktop files
    when: '{{ eq .Hostname "omarchbook" }}'
    backup: ./Linux/os/applications/omarchbook
    targets:
      linux: ~/.local/share/applications/omarchbook
```

## package.managers

Map each manager to a package name. Supported managers: pacman, yay, paru, apt,
dnf, brew, winget, scoop, choco.

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
Git URL, current-OS target, and branch are validated before dependencies run,
including when updating an existing checkout. Empty or whitespace-only targets,
including paths that become empty after expansion, are rejected rather than
being interpreted as the current directory.

## custom / url install (siblings of managers)

`custom:` and `url:` sit directly under `package:` — NOT inside `managers:`
(unlike `installer`, which is a manager). tidydots selects an install method
in this order: git, installer, a configured available standard manager, then
current-OS `custom`, then current-OS `url`. Standard managers must have a package
name for the application: choose the first eligible `manager_priority` entry,
then eligible `default_manager`, then platform availability order. A deps-only
manager is not a main-method candidate.

CLI and TUI share an installation plan. The selected main method is validated
before any dependency commands run; no main method or an invalid main method
means no dependency changes. Dependencies from eligible standard managers run
before the main install, and any dependency failure stops the main install.
A selected main-method failure is reported, not retried through later methods.
Dry-run performs the same validation and previews dependencies before the main
command without executing install commands.

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

`.tmpl` files (e.g. `.zshrc.tmpl`) render on restore. Symlink entries write a
sibling `.tmpl.rendered` file and point the suffix-free repository alias at it;
copy entries with an explicit `.tmpl` selection render directly to the
suffix-free real target. Paths in `targets:`/`backup:` also support `{{ }}`
expressions. CLI and TUI use the same strict path-template resolution: parse or
render errors fail the operation instead of falling back to a literal path.
Successful template rendering or environment expansion that yields an empty
path is also rejected. Use explicit `.` when intentionally selecting the current
directory (or the repository root for a relative backup path).

For a symlink entry with `files:`, list the template **source** including
`.tmpl`. Only listed templates render or affect template status/diffs; a
suffix-free selection is literal and does not discover a template. The layout
for `files: [".gitconfig.tmpl"]` is:

```text
git/.gitconfig.tmpl                  template source
git/.gitconfig.tmpl.rendered         generated content
git/.gitconfig -> .gitconfig.tmpl.rendered
~/.gitconfig -> <repo>/git/.gitconfig
```

Only one trailing `.tmpl` is removed (`config.tmpl.tmpl` deploys as
`config.tmpl`); nested names preserve their parent (`nested/config.tmpl.tmpl`
deploys as `nested/config.tmpl`). In copy mode, selected `.tmpl` files render
directly to those suffix-free target names without creating the symlink-mode
repository alias or `.tmpl.rendered` cache. Unselected template files are
untouched. Backup skips `.tmpl` paths for both methods so an installed target
cannot overwrite the source.

Before a selected-template restore makes changes, tidydots validates all
selected template sources and template-derived paths: sources must be regular
and renderable within the entry, generated names cannot collide, and unsafe
source/target aliases or symlink parents are rejected. Literal selections
still use their normal restore checks and can fail later if a source is missing
or a target policy disallows the change. Use `tidydots restore <app> <entry> -n`
before the real restore.

For symlink templates, a regular file occupying the suffix-free repository
alias is copied to exclusive mode-`0600` `<alias>.tidydots.bak` before replacement.
The original alias remains until final link replacement; a failed render or
replacement leaves it in place. An occupied recovery path blocks restore.
For a real target folder, an occupied template-derived suffix-free alias blocks
the folder merge: preserve or relocate it manually before retrying.
`--force-render` does not bypass either alias-safety rule.

Context variables:

- `.OS` — `"linux"` or `"windows"`
- `.Distro` — e.g. `"arch"`, `"ubuntu"`
- `.Hostname`, `.User`
- `.HasDisplay` — display server present
- `.IsWSL` — running under WSL
- `.Env` — env map, e.g. `{{ index .Env "HOME" }}`

All [sprout](https://github.com/go-sprout/sprout) template functions are
available.

Symlink-mode re-renders use a 3-way merge (base = last pure render in
`.tidydots.db`, theirs = current `.tmpl.rendered`, ours = new render),
normally preserving independent user edits. Copy-mode re-renders use the
suffix-free target as `theirs`; the source template remains the source of truth for generated
content. Hunk-based 3-way merging normally retains independent insertions,
deletions, and changes. Overlapping changes conflict; removing the final newline
on one side while the other appends at EOF also conservatively conflicts.
Broadly divergent edits use a bounded fallback that may conservatively conflict
rather than attempt an unsafe merge.

Conflicts save full recovery content beside the source as mode-`0600`
`.tmpl.conflict` before deploying the pure render. In symlink mode this file is
exclusive: an occupied conflict path aborts replacement. In copy mode a fresh
conflict atomically overwrites the previous conflict artifact. In both modes,
a recovery-write failure aborts deployment, and a later conflict-free render
removes the stale artifact. In symlink mode,
unreadable current output or failed orphan preservation also aborts output/alias
replacement; orphan backups use exclusive mode-`0600` `.tmpl.rendered.bak`.
`--force-render` bypasses the merge and overwrites from the template, but never
bypasses alias preservation or overwrite protection for symlink conflict files,
alias backups, or orphan backups.
The source hash covers source bytes only, not hostname, OS, user, or environment
context, so use `--force-render` when context changes. A first copy-template
deployment that replaces an existing target saves an exclusive
`<target>.tidydots.bak` unless `--force-render` explicitly bypasses that
no-history backup; an occupied path is never overwritten. Matching content alone
is not a no-op when required type or sudo ownership needs repair.
Existing regular modes are retained, native-created files use source
permissions, sudo-enabled Linux new or symlink-replacement files use `0600`,
and recovery/conflict artifacts use `0600`. Legacy targets with a `.tmpl` suffix
are not removed implicitly. Status and diff inspection use native reads and
never request sudo; unreadable sources or targets are reported as actionable
`Unavailable` status.
### Recommended .gitignore

```
*.tmpl.rendered
*.tmpl.conflict
.tidydots.db
.tidydots.db-*
```
