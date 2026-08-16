# Reproducible Arch Main Integration Handoff

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Preserve the exact state of the reproducible Arch effort and integrate its reviewed parts into current `main` without losing newer main-side configuration.

**Architecture:** Merge the existing feature history into an isolated branch based on current `main`, resolve the seven overlapping paths semantically, and then apply pending fixes individually according to review status. Keep the already-installed `antoinews-linux` machine operationally separate: repository integration does not imply that any resulting bootstrap, package, or Snapper change has been applied to that host.

**Tech Stack:** Git worktrees, Bash, Lua, Python, tidydots v3, Archinstall, Btrfs, Snapper, Limine, Hyprland.

## Global Constraints

- Do not modify or clean the dirty checkout at `/home/antoinegs/gits/configurations`.
- Perform integration only in `/home/antoinegs/gits/configurations/.worktrees/reproducible-arch-main-integration`.
- Never stage or commit this handoff document or any file under `docs/superpowers/plans/` or `docs/superpowers/specs/`.
- Preserve current-main Quickshell, RustDesk, no-hibernation, and `antoinews-linux` workstation policies unless explicitly superseded.
- Preserve feature-side hostname isolation, Omarchy independence, package profiles, bootstrap confirmation boundaries, and one-writer Snapper ownership.
- Do not run a real tidydots install/restore or bootstrap apply as part of repository integration.
- The physical `antoinews-linux` installation already exists. Any post-merge convergence on that host requires a new reviewed dry-run.

---

## 1. Current Repository State

### Main

- Branch: `main`
- Recorded tip at integration start: `4d42e791580f92f8a6ebd31a7caac0ad65ad438b`
- Upstream status: `main...origin/main`
- Original checkout contains unrelated modified and untracked files. It must remain untouched.

### Integration worktree

- Path: `/home/antoinegs/gits/configurations/.worktrees/reproducible-arch-main-integration`
- Branch: `merge/reproducible-arch-environment`
- Created from current `main` at `4d42e79`.

### Feature branch

- Branch: `feat/reproducible-arch-environment`
- Tip: `717ff017d81eb7f7fa0ab44c2be611883d2f2ef1`
- Merge base with current main: `026799e57f89b0753740b9c176f7c22829999cac`
- Divergence at integration start: 51 main-only commits and 80 feature-only commits.
- Aggregate status at the feature tip: fails only on a stale desktop monitor-rule count, fixed by pending commit `0dffc01`.

### Physical machine status

- The user installed Arch on `antoinews-linux` before this integration began.
- No repository action in this integration should assume the installed machine exactly matches the feature branch.
- The previous root-only disposable Btrfs fixture was skipped because mount privileges were unavailable.
- A real post-install inventory and dry-run on `antoinews-linux` remain future operational tasks, not merge prerequisites.

## 2. Implemented Feature Scope at `717ff01`

### Installation and bootstrap

- `Linux/install/archinstall/user_configuration.json`: reusable Archinstall profile with hostname, Limine, networking packages, locale/timezone, and base development packages.
- `Linux/install/archinstall/README.md`: operator workflow and explicit interactive disk/Btrfs boundary.
- `Linux/install/bootstrap`: post-reboot entry point with Arch/user/host/repository/network preflight, prerequisite installation, tidydots preview/apply phases, explicit confirmations, interactive `sudo -v`, and post-install data boundaries.
- `Linux/install/tests/all-tests.sh`: aggregate feature validation.

### Packages and host profiles

- `tidydots.yaml`: shared packages plus exact-host and graphical/headless/WSL policy.
- `Linux/pacman/tests/all-profiles-test.sh`: package/profile/runtime aggregate.
- Intel, SDDM, Hyprland, PipeWire, service, Limine, and Snapper ownership rules are declared and tested.
- Canonical package preview at `717ff01`: 117 successful operations and 0 failures.

### Networking

- `Linux/network/setup-networkd-iwd`: idempotent `systemd-networkd`, `systemd-resolved`, and `iwd` setup/check helper.
- `Linux/network/tests/setup-networkd-iwd-test.sh`: focused fixture tests.

### Snapper

- `Linux/Snapper/snapper-initialize`: validates Btrfs topology, initializes root/home Snapper configuration, creates initial snapshots, and checks convergence.
- `Linux/install/bootstrap`: owns deployment of root-only Snapper artifacts for `antoinews-linux`.
- Host ownership policy:
  - `antoinews-linux`: custom Archinstall layout and bootstrap writer.
  - `DESKTOP-E07VTRN`: existing tidydots-managed configuration.
  - `omarchbook`: snapshots disabled.
  - `server`: unmanaged layout.
- Tests cover host selection, staging, locks, rollback fixtures, initializer behavior, and package ownership.

### Desktop and Omarchy independence

- Host-specific monitor policies in `Linux/hypr/monitors.lua` and `Linux/hypr/autostart.lua`.
- Omarchy runtime helpers and references were removed or replaced.
- Screenrecord, notification, menu, system helper, and desktop status independence tests were added.
- Graphical launcher/package ownership audit exists under `Linux/pacman/tests/`.

## 3. Pending Direct Child Branches

### Approved monitor and hostname fix

- Branch: `fix/repro-final-monitor-hostname`
- Commit: `0dffc0131452613550d93c0fa8ca3e86786e629d`
- Review verdict: approved.
- Changes:
  - Correct desktop window-rule expectation from eight to seven after intentional GitKraken removal.
  - Assert GitKraken policy is absent.
  - Replace the non-stock `hostname` command dependency with `/proc/sys/kernel/hostname`.
  - Preserve fail-closed equality with `hostnamectl --static`.
- Full aggregate suite passed on this branch.

### Runtime coverage branch

- Branch: `fix/repro-final-runtime-coverage`
- Commit: `06e739bf771f4fa4c92add8b8f9d45ebfef0f266`
- Test status: aggregate passes; runtime audit reports 79 commands; package preview reports 118 successes.
- Review verdict: changes requested.
- Accepted value:
  - Adds missing active Hyprland binding modules and `voxtype-bin` ownership.
  - Converts media launcher expressions to deterministic commands.
- Rejected architecture:
  - Lexical Python analysis cannot prove arbitrary Lua indirection is safe.
  - Entrypoint commands, alternate loaders, aliases, `rawget`, computed APIs, and equivalent syntax can bypass a parser based on patterns.
- Integration rule: do not cherry-pick this commit wholesale without deciding whether to keep only concrete package/command changes or replace the lexical audit with a restricted behavior harness.

### Snapper boundary branch

- Branch: `fix/repro-final-snapper-boundary`
- Commit: `e642ece2075f6cb6d392813e926bce37de00758d`
- Focused Snapper tests pass; aggregate inherits the stale monitor assertion.
- Review verdict: changes requested.
- Accepted value:
  - Removes environment-controlled production path overrides.
  - Removes the trusted internal lock-bypass flag.
  - Adds recovery file/schema/path validation and adversarial tests.
- Remaining integrity gaps:
  - Distinct bootstrap and initializer locks do not provide one global writer across both entry points.
  - Recovery permits incomplete manifests instead of the exact four managed file targets.
  - Journal target/staged state is not fully cross-checked against the manifest.
  - Backup artifacts are not completely validated before live targets may be removed.
- Integration rule: do not cherry-pick wholesale until the lock hierarchy and complete artifact preflight are fixed, or simplify the custom recovery design.

## 4. Main Drift That Must Be Preserved

- `tidydots.yaml`:
  - Quickshell desktop shell package/configuration.
  - RustDesk Wayland service override.
  - No-hibernate and lid handling.
  - Newer OpenCode/OMP integration where applicable.
- `Linux/hypr/autostart.lua` and `Linux/hypr/monitors.lua`:
  - Main-side `antoinews-linux` workstation policy.
  - Feature-side `DESKTOP-E07VTRN`, laptop, and unknown-host isolation.
  - Omarchy-independent launch commands.
- `Linux/limine/limine`:
  - Preserve main's removal of resume/hibernation parameters.
  - Preserve feature's Arch identity/boot naming where still applicable.
  - Reconcile any `omarchy_linux.efi` checks with the actual installed system and current Limine ownership.
- `Linux/waybar/config.jsonc.tmpl` and `Linux/waybar/style.css`:
  - Preserve current-main desktop shell decisions; avoid restoring obsolete Waybar ownership if Quickshell supersedes it.
- Shell-picker:
  - Main and feature contain alternate setup implementations. Keep one coherent implementation and matching tidydots commands.
- OpenCode setup:
  - Prefer external scripts over multiline YAML only when the referenced scripts exist after merge.

The seven paths changed on both sides are:

```text
Linux/hypr/autostart.lua
Linux/hypr/monitors.lua
Linux/limine/limine
Linux/user-tmpfiles.d/opencode.conf
Linux/waybar/config.jsonc.tmpl
Linux/waybar/style.css
tidydots.yaml
```

`Linux/user-tmpfiles.d/opencode.conf` was identical on both sides at the integration start.

## 5. Integration Plan

### Task 1: Merge feature history into current main

**Files:** the complete `main..feat/reproducible-arch-environment` merge, with manual resolution limited to actual conflicts.

- [ ] Merge `feat/reproducible-arch-environment` with `--no-commit` in the integration worktree.
- [ ] Record every textual conflict before resolution.
- [ ] Preserve current-main Quickshell, RustDesk, no-hibernation, and workstation behavior.
- [ ] Preserve feature package profiles, bootstrap, Snapper host ownership, and Omarchy independence.
- [ ] Run `git diff --check` and focused tests before creating the merge commit.
- [ ] Create a non-fast-forward merge commit only after conflict resolution tests pass.

### Task 2: Apply the approved monitor/hostname fix

**Commit:** `0dffc0131452613550d93c0fa8ca3e86786e629d`

- [ ] Cherry-pick the approved commit after the feature merge.
- [ ] Resolve any monitor-policy conflict against current-main `antoinews-linux` behavior.
- [ ] Run `bash Linux/hypr/tests/monitor-policy-test.sh`.
- [ ] Run `bash Linux/install/tests/bootstrap-test.sh`.

### Task 3: Triage pending runtime changes

**Commit for inspection only:** `06e739bf771f4fa4c92add8b8f9d45ebfef0f266`

- [ ] Extract concrete package/profile changes that remain useful on current main.
- [ ] Do not preserve the claim that lexical analysis is a security boundary.
- [ ] Choose either a restricted behavior harness or a smaller explicit trusted-command inventory.
- [ ] Keep the solution proportional to a trusted personal configuration repository.

### Task 4: Triage pending Snapper hardening

**Commit for inspection only:** `e642ece2075f6cb6d392813e926bce37de00758d`

- [ ] Preserve removal of environment-controlled root path overrides.
- [ ] Establish one lock hierarchy for every writer, or simplify to one supported entry point.
- [ ] Require exact recovery manifest completeness and artifact validation before mutation.
- [ ] If complexity remains disproportionate, prefer fail-closed manual recovery over a custom transaction engine.

### Task 5: Verify the integrated branch

- [ ] Run `bash Linux/install/tests/all-tests.sh`.
- [ ] Run current-main Quickshell tests under `Linux/quickshell/desktop-shell/tests/`.
- [ ] Run `bash Linux/os/tests/hibernation-disabled-config-test.sh`.
- [ ] Run `tidydots --dir "$PWD" install -n`.
- [ ] Run `tidydots --dir "$PWD" restore -n` only as a dry-run.
- [ ] Run ShellCheck, Lua syntax/format checks, Python audit tests, and `git diff --check` through the aggregate suite.
- [ ] Record the root-only Btrfs fixture as skipped unless run with explicit disposable-mount privileges.

### Task 6: Prepare main-bound review

- [ ] Review `main..merge/reproducible-arch-environment`, not only the final commit.
- [ ] Verify no planning/spec/handoff document is staged.
- [ ] Verify the original main checkout's dirty files are untouched.
- [ ] Report repository merge readiness separately from physical-host convergence readiness.

## 6. Operational Follow-up for Installed `antoinews-linux`

These steps are deliberately outside the Git merge:

1. Inventory the installed host's actual bootloader, Btrfs subvolumes, packages, services, monitor policy, and Snapper state.
2. Compare that state with the final merged tidydots profile.
3. Run the final `Linux/install/bootstrap --dry-run --repo <final-checkout>`.
4. Review package removals, service changes, root file writes, and Snapper actions manually.
5. Apply only after confirming the installed machine's current state is compatible.

## 7. Known Non-Goals

- Reinstalling Arch.
- Replaying Archinstall on the existing machine.
- Automatically converging the installed machine during Git integration.
- Committing local design, plan, or handoff documents.
- Cleaning unrelated main-checkout changes.
- Proving arbitrary hostile Lua safe through lexical pattern matching.
