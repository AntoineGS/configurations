# Nushell fzf Pickers Design

## Goal

Reproduce the zsh `cd` and `cp` fzf pickers in Nushell on Windows. Typing `cd ` opens a
directory picker that walks the filesystem and accepts a destination; typing `cp ` opens a
multi-select file picker that inserts the chosen paths at the cursor. Both keep the modal
`[I]`/`[N]` keymap of the Linux originals. Windows only.

## Current State

The Linux implementation lives in three files:

- `Linux/zsh/.zshrc:28-331`: the `_fzf_cd_navigate`, `_fzf_cp_complete`, `_fzf_tab_complete`,
  and `_cd_space_autopicker` widgets, plus the `zvm_after_init` bindings
- `Linux/fzf/fzf-picker-candidates.zsh`: a 429-line helper with fourteen subcommands
- `Linux/fzf/fzf-preview.sh`, `Linux/fzf/fzf-batch-encode.pl`: preview rendering and batch
  path encoding

`_cd_space_autopicker` binds space, runs `magic-space`, and fires the cd picker when the
buffer is exactly `cd `. `_fzf_tab_complete` binds Tab, parses the buffer, and dispatches to
the cp picker when the command word is `cp`, otherwise falling through to `fzf_completion`.

Windows has Nushell 0.113.1, fzf 0.74.1, `fd`, `zoxide`, `eza`, and Strawberry Perl. `bat` is
not installed. The `nushell` entry in `tidydots.yaml:110-131` is already gated
`when: '{{ eq .OS "windows" }}'`, so files under `Both/Nushell` deploy to Windows only.

### Measured costs

These numbers drive the architecture. Each is a warm mean over 10-20 repetitions on the
target machine.

| Operation | Cost |
| --- | --- |
| `nu -c` interpreter startup | 93 ms |
| `cmd /c` startup | 39 ms |
| `pwsh -NoProfile` startup | 402 ms |
| fzf launch | 38 ms |
| `fd --max-depth 1` | 45 ms |
| `eza -la` | 47 ms |
| Nushell builtin `ls` | 73 ms |
| `zoxide query --list` | 61 ms |

An initial `eza` measurement of 324 ms was a cold-filesystem-cache artifact and should be
disregarded.

### Verified fzf capabilities

Every action this design depends on was confirmed present on fzf 0.74.1 on Windows by
running it and checking the exit status against a control. Bogus actions and bogus flags
exit 2 with a diagnostic; all of the following exit 0:

`transform`, `reload-sync`, `change-prompt`, `transform-prompt`, `change-header`,
`transform-header`, `change-border-label`, `become`, `print()+accept`, `rebind`, `unbind`,
`enable-search`, `disable-search`, `trigger`, `clear-multi`, `--with-shell`, `--multi=1`,
`--delimiter`/`--with-nth`, `--print-query`.

fzf has no action that redefines what a key does. `rebind` and `unbind` only enable and
disable bindings declared at launch. This constraint shapes the mode-indicator design below.

## Chosen Approach

Port the Linux architecture directly: a long-lived fzf process whose keys are bound to
`transform:` actions that invoke a helper, which rewrites state files and prints fzf actions
back on standard output. Directory changes redraw in place via `reload-sync`.

The helper is `Both/Nushell/fzf-picker.nu`, invoked as `nu <path> <subcommand> [args...]`.

The alternative considered was a loop driven from Nushell, where fzf exits on each navigation
keypress and Nushell relaunches it with fresh candidates. That is cheaper per keystroke
(about 83 ms against 138 ms) and simpler to test, because all state lives in Nushell
variables rather than temp files. It was rejected because each navigation step redraws the
whole picker instead of updating in place.

A faithful transform-based port costs 93 ms of Nushell startup plus 45 ms of `fd` on every
navigation keypress. This is accepted.

## Simplifications Over the Linux Version

### Base64 encoding is removed

`fzf-picker-candidates.zsh` encodes every path because POSIX filenames may contain newlines,
tabs, and quotes. NTFS forbids characters 0-31 and the set `< > : " / \ | ? *` in filenames,
so a Windows path can contain neither a tab nor a newline.

The candidate record therefore carries raw paths:

```text
kind <TAB> display <TAB> absolute_path
```

This removes the `encode` and `decode0` subcommands outright, removes the payload
encoding and decoding from `parent` and `relative0`, removes the `escape_display`
octal-normalizing loop, and removes the `fzf-batch-encode.pl` dependency.

### Mode switching costs no subprocesses

The Linux version spends a `modal` helper round-trip on `i`, `a`, and `esc` because zsh also
sets the terminal cursor shape. Cursor shape does not work on Windows and `[A]` mode is out
of scope, so mode switching reduces to pure fzf actions.

Because fzf cannot redefine a binding at runtime, the mode indicator and the current
directory must live on separate fzf surfaces. Baking `change-prompt([I] C:\path\ )` into the
`i` binding at launch would go stale on the first navigation.

- The **prompt** holds the current directory. `navigate` updates it with
  `change-prompt(<newdir>\ )`, which is free because `navigate` already knows the new path.
- The **header** holds the mode. `i` emits `change-header([I])` and `esc` emits
  `change-header([N])`. These are permanent literals and never go stale.

This is a visual departure from the Linux combined `[I] /path/ ` prompt.

### State reduces to two files

Because the helper no longer needs to know the keymap mode, `keymap_mode_file` disappears.
`prompt_file` disappears because prompts are emitted as literals. The remaining state is:

- `candidates`: the record list, re-read by `reload-sync`
- `dir`: the current directory, so parent navigation knows where it is

Linux carries five state files. Candidate writes use the write-to-`.next`-then-atomic-rename
pattern of `fzf-picker-candidates.zsh:279-327`, because a torn candidates file would be read
directly by fzf.

### Helper subcommands reduce from fourteen to six

`candidates cd|cp <dir>`, `navigate cd|cp <target> <state-files>`, `parent <path>`,
`drives`, `key cd|cp slash|tilde <query> <state-files>`, `preview cd|cp <path>`.

`key` exists because `/` and `~` are query-dependent and fzf cannot bind one key to
different actions per mode. A single binding must serve both modes, so the helper decides
from the query. In `[N]` search is disabled and the query is always empty, which resolves
naturally to the drive list for `/` and to the home directory for `~`. It replaces the
`slash` subcommand at `fzf-picker-candidates.zsh:167-207` and the inline `~` transform at
`Linux/zsh/.zshrc:91-100`.

## Trigger

A single `Space` keybinding in `config.nu` covers both pickers, using the `ExecuteHostCommand`
event. It intercepts the keypress before insertion, so where zsh tests `$BUFFER == "cd "` and
`$CURSOR -eq 3` after `magic-space` has already run, the Nushell version tests the
pre-insertion state and inserts the space itself on the fall-through path:

```nu
if (commandline) == "cd" and (commandline get-cursor) == 2      # cd picker
else if (commandline) == "cp" and (commandline get-cursor) == 2 # cp picker
else { commandline edit --insert " " }                          # ordinary space
```

Aborting either picker inserts the space, leaving the buffer as `cd ` or `cp `, matching
`_cd_space_autopicker` at `Linux/zsh/.zshrc:294`.

Tab is not used. On Linux the cp picker is bound to Tab with a fall-through to
`fzf_completion`, but Nushell cannot trigger a reedline menu from inside `ExecuteHostCommand`,
and the `until:` construct falls through only on event failure, not on a condition evaluated
in Nushell. Rebinding Tab would forfeit `completion_menu` for every other command.

## Keymap

Both pickers launch in `[I]`, matching `modal insert` at `Linux/zsh/.zshrc:66`.

| Key | `[I]` insert | `[N]` normal |
| --- | --- | --- |
| printable | filters | unbound, search disabled |
| `i` | unbound | enter `[I]` |
| `Esc` | enter `[N]` | `clear-multi` |
| `j` / `k` | unbound | move down / up |
| `l` / `h` | unbound | descend / ascend |
| `Tab` / `Right` / `Left` | descend / descend / ascend | unbound |
| `q` | unbound | abort |
| `Space` | unbound | toggle selection |
| `/` | drives when query empty, parent when query is `..`, else `put(/)` | drives when query empty, parent when query is `..`, else `ignore` |
| `~` | home when query empty, else `put(~)` | home when query empty, else `ignore` |
| `Enter` | accept | accept |

Navigation keys are bound per mode rather than through `trigger`, because each mode's keys
must remain distinct for `rebind`/`unbind` to switch between them. This differs from
`Linux/zsh/.zshrc:81`, where `h` and `l` delegate via `trigger(ctrl-h)` and `trigger(tab)`
and where Tab stays live in normal mode.

The cd picker uses `--multi=1` with `space:clear-multi+toggle`, matching
`Linux/zsh/.zshrc:75,81`, even though it only ever accepts one item. The cp picker uses
unlimited `--multi`.

## Candidates

### cd picker

`.`, then `..`, then local subdirectories, then zoxide entries. Local subdirectories come
from `fd --type d --max-depth 1 --hidden`, with hidden entries sorted first and non-hidden
second, mirroring `fzf-picker-candidates.zsh:71-89`. Zoxide entries whose absolute path
already appeared as a local candidate are skipped, mirroring
`fzf-picker-candidates.zsh:386-395`. Kinds are `local` and `zoxide`.

### cp picker

`.`, then `..`, then directories with a trailing `/`, then files. Hidden entries sort first
within each group, mirroring `fzf-picker-candidates.zsh:397-423`. Kinds are `directory` and
`file`.

### Drive list

When `/` fires with an empty query, it replaces the candidate list with kind `drive` entries,
one per mounted drive, obtained from `sys disks`. If `sys disks` proves unreliable, fall back
to probing `C:` through `Z:`.
The `dir` state file is set to a sentinel meaning "no parent", so `h` and `Left` at the drive
list are a no-op rather than an error.

This replaces the Linux behaviour of jumping to filesystem root at `Linux/zsh/.zshrc:90`.
Windows has no single root, and a drive list is the only way to reach another drive without
aborting the picker.

`~` jumps to `$env.USERPROFILE` under both pickers.

## Navigation and Reload

`navigate` writes the new candidate list, updates the `dir` state file, and prints:

```text
clear-multi+reload-sync(type <candidates-file>)+change-prompt(<newdir>\ )+clear-query+wait+first
```

`type` is a `cmd` builtin costing 39 ms, rather than a second 93 ms Nushell spawn to re-read
a file it just wrote.

The cp picker descends only into directories, guarding on field 1 being `directory` as
`Linux/zsh/.zshrc:193` does. The cd picker descends into any candidate.

## Preview

`preview cd` uses Nushell's builtin `ls`, sorted directories-first, rendering name, size, and
modified time. The 93 ms interpreter startup is already paid by the helper process, so the
listing costs a few additional milliseconds; shelling out to `eza` would add a further 47 ms
spawn and a dependency.

`preview cp` renders a directory listing for directories, the first 80 lines for text files,
and name, size, and modified time for binaries.

`Linux/fzf/fzf-preview.sh` does not port. Its `bat`, `ffmpegthumbnailer`, ImageMagick, and
kitty-graphics paths have no Windows equivalent in this configuration, and `bat` is not
installed.

## Accept and Buffer Handling

The cd picker requires exactly one selection, matching the `target_count != 1` guard at
`Linux/zsh/.zshrc:124`. On accept, the host command runs `cd <path>`. `cd` is aliased to `z`
at `Both/Nushell/config.nu:780`; passing zoxide an existing absolute path performs a plain
directory change.

The cp picker makes each selected path relative to the invocation directory using Nushell's
`path relative-to`, quotes each, joins with spaces, and inserts at the cursor with a trailing
space, leaving the cursor positioned to type the destination. This replaces
`realpath --zero --no-symlinks --relative-to` and the `relative0` decode loop at
`fzf-picker-candidates.zsh:354-370`. When a selection is on a different drive than the
invocation directory, no relative path exists and the absolute path is used.

## Error Handling

Any helper failure prints `ignore` and exits 0. fzf treats `ignore` as a no-op, so a
transient failure leaves the picker alive on its last good state rather than half-navigated.
Only the picker's own abort paths unwind to the shell.

## Behaviours to Verify During Implementation

These are assumptions the design rests on that have not been confirmed on the target machine.
Each is cheap to check and should be checked before code depends on it.

1. Whether `ExecuteHostCommand` writes its command string into Nushell history. The Space
   binding fires on every space typed, so history pollution would be severe. If it does
   pollute, the fall-through path needs a different mechanism.
2. Whether `cd` inside the host command's `if` block propagates to the REPL. Nushell blocks
   share the parent's environment scope, unlike closures, so it should, but the cd picker is
   useless if it does not.
3. Whether fzf quotes placeholder expansions safely for `cmd /c` when a Windows path contains
   `&` or `%`. If not, set `--with-shell 'nu --no-config-file -c'`, which costs 93 ms on
   reload and preview instead of 39 ms.

## Testing

`Both/Nushell/tests/fzf-picker.test.nu`, following the precedent of
`Linux/fzf/tests/fzf-picker.test.zsh` but substantially smaller. The interactive fzf session
is not tested. The helper's subcommands are tested as pure functions against a temporary
directory tree:

- candidate ordering for both pickers: `.` and `..` present, hidden entries first,
  directories before files
- zoxide entries deduplicated against local entries
- `parent` at a drive root returns the no-parent sentinel
- `path relative-to` across drives falls back to the absolute path
- the exact action string `navigate` emits
- `drives` returns at least the drive holding `$env.USERPROFILE`

## Deployment

- New file `Both/Nushell/fzf-picker.nu`
- New file `Both/Nushell/tests/fzf-picker.test.nu`
- Add `fzf-picker.nu` to the `files:` list at `tidydots.yaml:124`. The
  `when: '{{ eq .OS "windows" }}'` guard at `tidydots.yaml:117` keeps it off Linux.
- `Both/Nushell/config.nu` gains the `Space` keybinding in the `keybindings` list ending at
  `config.nu:754`, and a `source` line beside `source ~/.zoxide.nu` at `config.nu:775`.

## Out of Scope

- `[A]` add-directory mode from `fzf-picker-candidates.zsh:208-259`
- Terminal cursor-shape feedback from `fzf-picker-candidates.zsh:5-15`
- `bat`, image, and video previews from `Linux/fzf/fzf-preview.sh`
- Tab-key completion dispatch
- Nushell picker support on Linux, which uses zsh
- Any change to the existing Linux implementation
