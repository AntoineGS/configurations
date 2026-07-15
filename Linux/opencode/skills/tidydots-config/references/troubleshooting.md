# tidydots troubleshooting

## Read a dry-run first

Always run the `-n` variant and read the plan before applying:
`tidydots restore -n`. Lines describe what WOULD change. If a change looks
wrong, fix the config before running the real command.

## Symlink conflict / existing file at target

Default restore (merge mode) automatically adopts a pre-existing real file at
the target in one pass: it moves the file's contents into the backup source in
the repo, auto-resolves any collision by renaming the conflicting file (never
overwriting), removes the target, and creates the symlink. Data is moved into
the repo, not destroyed — if a rename happened, inspect the backup dir in the
repo afterward (and `ls -l <target>`) to reconcile. Only the non-default
NoMerge mode refuses on a pre-existing file, which then requires `--force`.

## Template conflict markers

A `.tmpl.conflict` file (or `<<<<<<< user-edits` markers in `.tmpl.rendered`)
means the 3-way merge couldn't reconcile your local edits with a new render.
Resolve by editing the rendered file to the desired content, removing the
markers, then re-running restore. Use `--force-render` only to deliberately
discard local edits and overwrite from the template.

## An app is unexpectedly skipped

Its `when:` expression evaluated false for this machine. Check the real context
values (`tidydots list` shows what's active) — common causes: `.OS`,
`.Distro`, or `.Hostname` differ from what the expression assumes. Example:
`when: '{{ eq .OS "windows" }}'` excludes the app on Linux.

## Wrong package manager used

tidydots picks the first manager present in `manager_priority` that the app
defines. If it chose an unexpected one, either reorder `manager_priority` or
remove the manager entry you don't want on this machine. A top-level
`default_manager:`, when set, acts as a lower-priority fallback in addition to
the `manager_priority` ordering.

## sudo entries

An entry (or git package) with `sudo: true` runs its operations elevated.
Expect a password prompt during restore/install. If a system path like
`/etc/hosts` fails to link, confirm the entry has `sudo: true`.

## Setup entry keeps re-running

A `check`/`run` entry runs `run` whenever `check` exits non-zero. If it runs
every time, the `check` command isn't actually detecting the applied state —
fix `check` to return 0 once `run` has succeeded. Keep `check` read-only and
fast; it runs on every restore, dry-run, and TUI refresh.
