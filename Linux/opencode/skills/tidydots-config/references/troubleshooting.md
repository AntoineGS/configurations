# tidydots troubleshooting

## Read a dry-run first

Always run the `-n` variant and read the plan before applying:
`tidydots restore -n`. Lines describe what WOULD change. If a change looks
wrong, fix the config before running the real command.

## Symlink conflict / existing file at target

If a target path already exists as a real file (not the expected symlink),
restore backs it up rather than clobbering it. Inspect the target:
`ls -l <target>`. If it should be managed, confirm the backed-up copy matches
the repo, then let restore create the symlink.

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
remove the manager entry you don't want on this machine.

## sudo entries

An entry (or git package) with `sudo: true` runs its operations elevated.
Expect a password prompt during restore/install. If a system path like
`/etc/hosts` fails to link, confirm the entry has `sudo: true`.

## Setup entry keeps re-running

A `check`/`run` entry runs `run` whenever `check` exits non-zero. If it runs
every time, the `check` command isn't actually detecting the applied state —
fix `check` to return 0 once `run` has succeeded. Keep `check` read-only and
fast; it runs on every restore, dry-run, and TUI refresh.
