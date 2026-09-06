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

## An app or entry is unexpectedly skipped

Its `when:` expression evaluated false for this machine, or (for an entry) its
parent application's condition did. Check the real context values (`tidydots
list` shows what's active) — common causes: `.OS`, `.Distro`, or `.Hostname`
differ from what the expression assumes. Example: `when: '{{ eq .OS "windows" }}'`
excludes the app or entry on Linux. A malformed `when:` template also excludes it.
If you explicitly name the excluded app or entry in a CLI command, tidydots returns
a conditions mismatch error rather than proceeding.

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

In the default `exit-code` mode, a `check`/`run` entry runs `run` whenever
`check` exits non-zero. If it runs every time, the `check` command isn't
actually detecting the applied state — fix `check` to return 0 once `run` has
succeeded. Keep `check` read-only and fast; it runs on every restore, dry-run,
and TUI refresh. In `check_mode: status`, only exits `1` and `2` authorize
`run`; `0` means Set up and `3` or higher means Check failed, which blocks
`run`.

## Status-mode setup check failed

For `check_mode: status`, the meanings are **0 = Set up**, **1 = Needs setup**,
**2 = Outdated**, and **3 or higher = Check failed**. Negative process exits,
launch failures, cancellation, and unavailable remote checks are errors rather
than evidence that setup is missing. A Check failed result is actionable for
diagnosis but never authorizes `run`, even during `tidydots restore -n`.

Inspect the bounded diagnostic shown by the TUI or `tidydots status`; keep the
check read-only, noninteractive, and fast. Put status explanations on stderr:
nonblank stderr from status 1 or 2 is retained for display and is appended when
a post-check remains unapplied; stdout is not used for this diagnostic. For a
Check failed result, stderr remains preferred over the execution-error or
fixed-exit fallback. Fix the check or its dependency, then run the narrow
dry-run again before applying setup.

## Remote revision is outdated or indeterminate

Remote-default-branch tracking is an optional personal setup workflow, not a
default feature of every Git package. It compares the installed binary's
`vcs.revision` metadata with the remote's advertised default branch. A local
checkout may be behind, ahead, or contain an unpushed commit; that is expected
for local development and can make the installed binary differ from the
remote.

The updater deliberately compares the checkout's `origin` and
`TIDYDOTS_REPOSITORY` as exact strings. Match the transport spelling already in
the checkout (HTTPS versus SSH or scp-style); there is no URL canonicalizer.
When embedding the value in both `check` and `run`, use a defaulting override
such as `${TIDYDOTS_REPOSITORY:-git@github.com:AntoineGS/tidydots.git}` so an
existing non-empty environment override is preserved.

Missing or malformed Go VCS metadata is **Check failed** (status `3` or
higher), not **Outdated**. Remote lookup failures and timeouts are also
indeterminate, never a known available update. Remote metadata lookup must be
read-only, noninteractive, and limited to five seconds.

## Coordinated updater migration

Keep a replacement updater and its matching YAML `check_mode: status` change
staged and inactive until a tidydots binary that understands status-mode setup
entries has been installed. Activate the script and YAML change together, and
preview with `tidydots restore -n` first. A symlinked script source is active
configuration, not a safe inactive copy; do not activate the migration merely
because the patch has been prepared.
