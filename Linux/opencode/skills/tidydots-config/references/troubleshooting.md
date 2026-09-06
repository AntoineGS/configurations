# tidydots troubleshooting

Safety and package behavior below describes the current patched repository,
not a guarantee about an older installed binary. Verify the installed version;
do not upgrade or apply real restore/install operations without approval.

## Read a dry-run first

Always run the `-n` variant and read the plan before applying:
`tidydots restore -n`. Lines describe what WOULD change. If a change looks
wrong, fix the config before running the real command.

## Symlink conflict / existing file at target

For ordinary symlink entries, default restore (merge mode) adopts a pre-existing real file at
the target in one pass: it moves the file's contents into the backup source in
the repo, auto-resolves any collision by renaming the conflicting file (never
overwriting), removes the target, and creates the symlink. Data is moved into
the repo, not destroyed — if a rename happened, inspect the backup dir in the
repo afterward (and `ls -l <target>`) to reconcile. Non-default NoMerge mode
refuses on a pre-existing file unless `--force` is used; preservation failures
and template-alias safety checks can also block restore as described below.

Folder merge is not transactional: if any file transfer fails, restore returns
an error, leaves failed originals in place, and does not remove the target
folder or replace it with a symlink. Successful partial transfers may already
be in the repo. Inspect both locations before retrying. Date-based conflict
backups are created exclusively; an occupied name gets `.1`, `.2`, and so on
instead of overwriting an earlier backup.

Template aliases have stricter rules than ordinary file adoption. A regular
file at the suffix-free repository alias is preserved by copying it to exclusive
mode-`0600` `<alias>.tidydots.bak`; the original stays until final link
replacement and remains on failure. If that backup is occupied, inspect and
preserve or relocate it before retrying. For a real target folder, an occupied
suffix-free template alias blocks merge and must be manually preserved or
relocated first. `--force-render` does not bypass alias safety.

## Template conflict markers

A `.tmpl.conflict` file means the 3-way merge couldn't reconcile your local
edits with a new render. After successful conflict recovery, in symlink mode,
`.tmpl.rendered` contains the valid pure render; in copy mode there is no
`.tmpl.rendered` cache and the suffix-free
target receives the pure render. Do not edit a generated rendered file or place
conflict markers there. Inspect the separate `.tmpl.conflict` file, port the
desired result into the `.tmpl` source, then re-run restore. Use `--force-render`
only to deliberately discard local edits and overwrite from the template.

Independent insertions/deletions normally merge, but overlapping edits,
final-newline removal versus an EOF append, and broadly divergent edits can
produce conservative conflicts. The bounded fallback favors recovery over an
unsafe automatic merge; a conflict is not evidence that all local edits overlap.

Symlink-mode `.tmpl.conflict`, alias `.tidydots.bak`, and orphan
`.tmpl.rendered.bak` files are exclusive mode-`0600` recovery artifacts. If one
is occupied when needed, restore aborts replacement; `--force-render` does not
bypass their overwrite protection. Resolve or move existing recovery files after
inspection rather than blindly deleting them. Copy-mode `.tmpl.conflict` also
uses `0600`, but a fresh conflict atomically overwrites the previous artifact;
preserve any older recovery content you still need before retrying. In either
mode, failure to read current output or write required recovery data aborts
replacement. The pure-render deployment policy applies only after required
recovery succeeds.

## Selected template does not render or restore rejects it

For an entry with `files:`, list the template source as `name.tmpl`, not the
suffix-free deployed name. Only listed `.tmpl` sources render; `name` remains a
literal selection. In symlink mode the rendered output is linked through the
repository alias. In copy mode the selected template renders into a real
suffix-free target and merges with the previous pure render; ordinary files
still use literal copy behavior.

Restore rejects selected templates that escape the entry, are not regular and
renderable source files, collide with selected/generated names, or use unsafe
source/target aliases or symlink parents. Fix the selection or paths, then run
the narrow dry-run form first: `tidydots restore <app> <entry> -n`.

For copy-mode template conflicts, inspect `<source>.conflict` (for example,
`root.tmpl.conflict`) and either resolve the desired content in the
template/target workflow or use `--force-render` when discarding target edits is
intentional. The target receives the pure render, not conflict markers. A first
deployment with an existing target may leave `<target>.tidydots.bak` unless
`--force-render` explicitly bypasses the no-history backup; this backup is
exclusive, mode `0600`, and restore refuses to overwrite an occupied path.
A legacy target that still has the `.tmpl` suffix is not removed automatically.

## Versions with repository-scoped template history

Older entry-relative history keys can collide when different templates have
the same selected filename. Patched versions use `./`-prefixed repository-relative
source keys (for example, `./git/config.tmpl`) for symlink history, scoped by OS
and hostname. Copy keys additionally include the expanded, cleaned absolute
suffix-free target, for example `copy:"./git/config.tmpl":"/home/user/.gitconfig"`.
Different copy targets and the symlink output do not share baselines. This
behavior requires the patched binary; do not assume the installed older binary
supports it or upgrade it without approval.

Legacy records are reused only for the current source's SHA-256 hash, OS, and
hostname, and only when all matching records agree on the pure rendered
baseline. The first normal restore with unchanged sources copies verified
history into the new keys while preserving output and local edits. Old records
remain; unrelated history is not merged or moved. Status, diff, and dry runs do
not migrate state. After an approved upgrade, preview the narrow normal restore
and confirm before applying, preferably before editing template sources.

If the source changed before its first restore with the patched version, or
matching legacy baselines disagree, status reports `Outdated` and normal restore
blocks overwriting existing output rather than guessing a merge base. Preserve
local edits in the template source or a separate recovery file, then preview
`tidydots restore <app> <entry> --force-render -n`. Review the plan and obtain
confirmation before running the same command without `-n`: `--force-render`
discards output edits and bypasses the no-history target backup. Missing outputs
can render normally; templates without legacy history retain first-render behavior.

Copy migration never borrows another deployment's copy history or a source-only
scoped baseline. With only source-only scoped history, an existing target can
initialize copy history if it exactly matches a fresh render; differing output
remains blocked and requires the same preserve-edits recovery workflow.

## An app or entry is unexpectedly skipped

Its `when:` expression evaluated false for this machine, or (for an entry) its
parent application's condition did. Check the real context values (`tidydots
list` shows what's active) — common causes: `.OS`, `.Distro`, or `.Hostname`
differ from what the expression assumes. Example: `when: '{{ eq .OS "windows" }}'`
excludes the app or entry on Linux. A malformed `when:` template also excludes
it. If you explicitly name the excluded app or entry in a CLI command, tidydots
returns a conditions mismatch error rather than proceeding.

## Wrong package manager used

Git and installer take precedence over standard managers. For standard managers,
tidydots selects an available manager with a package name for this application:
first `manager_priority`, then `default_manager`, then platform availability
order. Deps-only entries cannot be the main method. Custom and URL methods are
fallbacks, not retries after a selected method fails. Reorder priority or adjust
the application's manager definitions if the selected method is unintended.

The shared CLI/TUI plan validates the selected main method before dependencies
run. No main method or invalid main configuration means no dependency changes;
dependency failure stops the main install. Check git URL/branch and the current-OS
target (including empty or whitespace-only values after expansion), or the
installer's current-OS command. Git branch validation applies to updates too.
Preview with `tidydots install <app> -n` to validate and inspect dependency
commands followed by the main command without executing installs.

## TUI paths, dry-run edits, or stale package status

CLI and TUI share strict `targets`/`backup` path-template resolution. A parse or
render error is an error, never a literal deployment path; correct the expression
before retrying. This differs from `when:` errors, which exclude the entry.
An empty result is also rejected, even after successful template rendering or
environment expansion. Use explicit `.` for an intentional current-directory
target or repository-root backup path, not an empty expression.

With `-n` / `--dry-run`, all application/entry additions, edits, and deletions
are previews: neither the YAML file nor the loaded configuration changes.
Outside dry-run, deleting the last entry retains the application if it has a
package definition.

Manual/status refresh invalidates cached installed-package results before
rechecking, so external package changes can be detected. Refresh before treating
a stale row as a reason to reinstall; on older binaries verify that this patched
refresh behavior is available.

## sudo entries

An entry (or git package) with `sudo: true` runs its operations elevated.
Expect a password prompt during restore/install. If a system path like
`/etc/hosts` fails to link, confirm the entry has `sudo: true`.

For copy-template entries, sudo writes are supported only on a Linux runtime;
Windows uses native operations, and sudo-enabled copy-template operations on
another runtime host fail explicitly. Status and diff inspection never request
sudo, so an unreadable protected source or target is reported as actionable
`Unavailable` rather than prompting.

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
