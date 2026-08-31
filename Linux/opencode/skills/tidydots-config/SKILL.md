---
name: tidydots-config
description: Use when authoring, editing, running, or troubleshooting tidydots dotfile configs — tidydots.yaml (v3), restore/backup/install, symlinks, templates, packages, or when/setup entries. Covers the config format and the safe dry-run-first workflow.
---

# tidydots-config

Help author, run, and troubleshoot [tidydots](https://tidydots.io) dotfile
configurations. tidydots manages configs via symlinks, clones git repos, and
installs packages across many package managers from a single `tidydots.yaml`.

## Where the config lives

- Default config repo on this machine: `~/gits/configurations`
  (`tidydots.yaml` at its root).
- If that path is absent, discover the repo from the tidydots app config at
  `~/.config/tidydots/config.yaml`, or ask the user for the path. Do not assume.
- `~/.config/tidydots/config.yaml` is local app metadata: it contains `config_dir`
  and may contain a `hostnames` list for TUI When-field presets. `hostnames` is
  not a `tidydots.yaml` v3 field.
- The repository's `tidydots.yaml` is the versioned v3 configuration containing
  applications, entries, packages, and `when` expressions.
- Backup dirs follow a platform convention: `Both/` (shared), `Linux/`,
  `Windows/`. An entry's `backup:` is a path into one of these.
- Targets are **symlinked** into place by default (a config file in the repo is
  linked to its live location like `~/.config/nvim`). `method: copy` deploys a
  real copy instead.

## Safety workflow (dry-run first, then confirm)

Any command that changes the system — `restore`, `backup`, `install`, delete —
MUST be previewed first:

1. Run with `-n` (dry-run): e.g. `tidydots restore -n`.
2. Show the user the planned changes.
3. Ask for confirmation before running the real (non-`-n`) command.

Never run a real `restore`/`install`/delete without showing the dry-run plan
first.

Prefer the narrowest restore scope. `tidydots restore <app>` restores one
application, while `tidydots restore <app> <entry>` restores one entry. Apply
the same positional arguments to the dry run first, for example:

```sh
tidydots restore herdr -n
tidydots restore herdr
```

## Common tasks

Read `references/schema.md` for full field details before authoring anything
non-trivial. Quick recipes:

- **Add an application:** append an item under `applications:` with `name`,
  optional `description`, optional `when`, and `entries:` and/or `package:`.
- **Add a config entry (symlink):** under an app's `entries:`, add `name`,
  optional `when:`, `backup:` (repo path), `targets:` (per-OS live paths),
  optional `files:` (omit/empty = whole folder).
- **Deploy a copy instead of a symlink:** add `method: copy` to the entry;
  copy mode requires a non-empty `files:` list.
- **Add a package:** under the app's `package.managers`, map each manager to a
  package name (`pacman: neovim`, `brew: neovim`, ...). Git repos and custom
  installers are also packages — see schema.
- **Add a template:** name the repo file `*.tmpl` (e.g. `.zshrc.tmpl`); it
  renders on restore using platform context (`.OS`, `.Distro`, ...).
- **Add a setup entry:** an entry with optional `when:`, `check:` and `run:`
  (both OS→command maps) runs a command instead of deploying files. `check`
  must be read-only and fast — it runs on every restore and dry-run when the
  entry's condition matches.
- **Gate by platform/host:** add a `when:` Go-template expression, e.g.
  `when: '{{ eq .OS "linux" }}'`.

In the TUI, hostnames configured in the local app config can be selected from the
When chooser. One selected host generates `{{ eq .Hostname "desktop" }}`; multiple
hosts generate `{{ or (eq .Hostname "desktop") (eq .Hostname "laptop") }}`. The
chooser only writes the generated expression into the repository application's
or entry's `when` field; it does not add `hostnames` to `tidydots.yaml`.

The global `--dir` flag overrides which repository is selected for an operation;
it does not discard local app metadata. In particular, the TUI can still load
saved hostnames from `~/.config/tidydots/config.yaml`.

An entry must match both its own condition and its application's condition.
Packages are application-level only and use the application's condition.

## Field-name gotchas

- `entries` — NOT `configs` or `packages`.
- `package` is singular at the application level.
- `when` — NOT `filters`.

## Verify after editing

1. `tidydots list` — confirms the config parses and shows apps/entries.
2. `tidydots restore [app [entry]] -n` — dry-run the narrowest applicable
   scope to confirm the intended changes.
3. Commit the config repo when the change is confirmed.

See `references/troubleshooting.md` when something misbehaves.
