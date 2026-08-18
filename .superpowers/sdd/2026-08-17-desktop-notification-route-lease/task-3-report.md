## Task 3 Implementation Report

- Task: Require the lease in the Mako adapter.
- Scope changed:
  - `Linux/os/helpers/desktop-shell-mako-route`
  - `Linux/quickshell/desktop-shell/tests/mako-route-adapter-test.sh`

### What changed

- Refactored the adapter entry point into `run_adapter` and guarded execution with `[[ ${BASH_SOURCE[0]} == "$0" ]]` so sourcing the helper exposes functions without starting the polling loop.
- Added secure metadata checks in the adapter for the private route directory and both route/lease files.
- Added paired route+lease validation in one `jq` path.
- Required exact supported outputs `DVI-D-1`, `HDMI-A-1`, and `DP-2`.
- Preserved the existing 45 second route staleness gate.
- Failed closed to `rustdesk-route-hidden` with an empty cue for invalid, missing, stale, mismatched, insecure, or unsupported route/lease states.
- Preserved valid cue behavior for visible routed states and preserved adapter cleanup behavior.
- Hardened the test harness owned-child cleanup checks to require parent PID, process start time, and executable path before sending `TERM`.

### TDD notes

- Verified the pre-refactor executable behavior first with the existing adapter test.
- Added deterministic direct-call coverage that initially failed on the missing-lease route case.
- Implemented the minimal adapter changes required to make the new lease and metadata cases pass.

### Deterministic coverage added

- Missing lease.
- Valid route+lease pair.
- Valid cue-bearing visible route.
- Hidden route carrying cue data.
- Route age at exactly 45 seconds.
- Malformed route JSON.
- Malformed lease JSON.
- Stale lease.
- Future lease.
- Overlong lease lifetime.
- Mismatched `routeUpdatedAt`.
- Unsupported route outputs.
- Unsupported cue outputs.
- Insecure route directory mode.
- Wrong-owner route directory metadata.
- Insecure route file mode.
- Wrong-owner route file metadata.
- Insecure lease file mode.
- Wrong-owner lease file metadata.
- Symlink lease file.
- Symlink route file.
- Symlink route directory.
- Mismatched child identity cleanup fixture.

### Verification run

- `bash Linux/quickshell/desktop-shell/tests/mako-route-adapter-test.sh`
- `bash -n Linux/os/helpers/desktop-shell-mako-route Linux/quickshell/desktop-shell/tests/mako-route-adapter-test.sh`
- `shellcheck Linux/os/helpers/desktop-shell-mako-route Linux/quickshell/desktop-shell/tests/mako-route-adapter-test.sh`

### Result

- All required verification commands passed.

### Concerns

- The adapter now intentionally treats hidden routes with cue payloads as invalid and suppresses the cue entirely; this matches the Task 3 brief but changes the previous executable-path test expectation.

## Task 3 Fix Round

- Changed files:
  - `Linux/os/helpers/desktop-shell-mako-route`
  - `Linux/quickshell/desktop-shell/tests/mako-route-adapter-test.sh`
- Tests:
  - `bash Linux/quickshell/desktop-shell/tests/mako-route-adapter-test.sh`
  - `bash -n Linux/os/helpers/desktop-shell-mako-route Linux/quickshell/desktop-shell/tests/mako-route-adapter-test.sh`
  - `shellcheck Linux/os/helpers/desktop-shell-mako-route Linux/quickshell/desktop-shell/tests/mako-route-adapter-test.sh`
- Commit ID:
  - `aa1b64e` `fix(mako): restore route lease regressions`
- Concerns:
  - The original report section above is now stale about hidden cue-only routes; this fix round restores the prior behavior and keeps valid hidden cues active under the hidden route mode.

## Task 3 Second Fix Round

- Changed files:
  - `Linux/quickshell/desktop-shell/tests/mako-route-adapter-test.sh`
- What changed:
  - Replaced the adapter cleanup descendant walk with identity-aware child cleanup in the test harness, so every `TERM` path revalidates parent PID, process start time, and executable before signaling.
  - Removed the fake-Mako empty-identity registration window by tracking pending children immediately, waiting for the final `/usr/bin/sleep` executable before registration, and cleaning pending children on abnormal exit.
  - Added valid-lease regression coverage for metacharacter route output `DVI-D-1;touch`.
  - Added hidden cue-only coverage for the legacy null-direction cue text `DP-2|none` in both direct reconciliation and executable polling paths.
- Tests:
  - `bash Linux/quickshell/desktop-shell/tests/mako-route-adapter-test.sh`
  - `bash -n Linux/os/helpers/desktop-shell-mako-route Linux/quickshell/desktop-shell/tests/mako-route-adapter-test.sh`
  - `shellcheck Linux/os/helpers/desktop-shell-mako-route Linux/quickshell/desktop-shell/tests/mako-route-adapter-test.sh`
- Concerns:
  - None.
