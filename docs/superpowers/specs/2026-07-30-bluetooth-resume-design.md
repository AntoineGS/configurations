# Bluetooth Resume Restart Design

## Goal

Restart `bluetooth.service` whenever the laptop resumes from any supported sleep path. Do not install or run this behavior on other hosts.

## Current State

The `system-sleep-hooks` tidydots component is restricted to hostname `omarchbook` and installs executable hooks from `Linux/system-sleep` into `/usr/lib/systemd/system-sleep`. Existing hooks use systemd's `pre`/`post` arguments and recognize suspend, hibernate, hybrid sleep, and suspend-then-hibernate.

`bluetooth.service` is already enabled on non-WSL Linux machines by the `enable-linux-services` component.

## Implementation

Add a standalone executable hook at `Linux/system-sleep/bluetooth-restart`. Add that filename to the existing laptop-only `system-sleep-hooks` file list in `tidydots.yaml`.

The hook will:

1. Exit successfully unless the phase is `post`.
2. Exit successfully unless the sleep state is `suspend`, `hibernate`, `hybrid-sleep`, or `suspend-then-hibernate`.
3. Queue `systemctl restart --no-block bluetooth.service`.
4. Ignore a restart error and exit successfully so Bluetooth cannot delay or fail the resume path.

The hook itself does not need a hostname check. Tidydots only installs it on `omarchbook`, following the existing host-isolation boundary for all resume hooks.

## Alternatives

- Adding the command to an existing hook would reduce the file count but couple unrelated hardware recovery behavior.
- A dedicated systemd unit could provide richer journal metadata, but ordering it across every sleep mode is more complex than the repository's established system-sleep hook pattern.

## Validation

- Run `bash -n` against the hook.
- Use a stub `systemctl` to confirm `pre` phases and unsupported states perform no action.
- Use the stub to confirm every supported `post` state invokes exactly `restart --no-block bluetooth.service`.
- Confirm restart failures still produce a successful hook exit.
- Confirm the hook is executable.
- Run a tidydots dry run and confirm the hook is selected on `omarchbook` through the existing hostname-gated component.
- Run `git diff --check` on the changed files.

## Out of Scope

- Changing how `bluetooth.service` is enabled on Linux hosts
- Adding Bluetooth recovery to non-laptop hosts
- Restarting Bluetooth before sleep
- Diagnosing or changing the underlying Bluetooth driver
