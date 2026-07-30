# RustDesk-Safe Notification Routing

**Date:** 2026-07-30
**Status:** Design / pre-implementation
**Scope:** `Linux/hypr/watch-rustdesk-submap.sh`, `Linux/mako/config`, and a
focused Mako cue helper

## Goal

Route Mako notification content away from monitors showing a RustDesk Remote
Desktop window, while accepting the short transition race inherent in
event-driven routing. Route the real toast to a safe monitor and show a
content-free directional cue on the focused RustDesk monitor so the user knows
where to look.

## Current Environment

- Arch Linux with Hyprland and Mako on Wayland.
- Three fixed outputs: `DVI-D-1`, `HDMI-A-1`, and `DP-2`.
- `watch-rustdesk-submap.sh` already consumes Hyprland events and identifies
  RustDesk Remote Desktop windows.
- Mako currently shows notifications on the focused output because no explicit
  output is configured.
- The existing `do-not-disturb` mode and Spotify suppression must continue to
  take precedence.

## Requirements

- Exclude an output only while a mapped RustDesk Remote Desktop window is
  currently visible on it. A RustDesk window on a hidden workspace does not
  exclude the output.
- If the focused output is safe, place the real toast there and show no cue.
- If the focused output shows RustDesk, route the real toast to a safe output.
  Prefer the leftmost safe output when the focused output is excluded.
- Show a normal-sized, five-second cue toast on the focused RustDesk output.
  The cue contains only one centered arrow and no application icon, title,
  body, action, or identifying metadata from the real notification.
- Compute `left`, `right`, `up`, or `down` from the centers of the cue and real
  toast outputs. Use the dominant axis rather than diagonal arrows.
- Render the cue in Mako's overlay layer so it remains visible over fullscreen
  RustDesk.
- If all active outputs show RustDesk, hide the real toast through its normal
  Mako lifecycle/history and show a centered neutral bullet on the focused
  output because no destination direction exists.
- Existing intentionally suppressed notifications must not produce cues.
- Preserve the existing do-not-disturb exception for `app-name=notify-send`.
  Its mode-change confirmation remains eligible for safe routing and a cue.
- A watcher or notification-daemon failure must not allow notification content
  to appear on an unverified output.

## Non-Goals

- Do not modify Herdr or individual notification-producing applications.
- Do not replace Mako or add a D-Bus notification proxy.
- Do not support arbitrary output names beyond the three configured outputs in
  this iteration.
- Do not expose notification content, source application, urgency, or count in
  the RustDesk cue.

## Architecture

Extend the existing RustDesk watcher rather than introducing another service.
The watcher remains the sole consumer of Hyprland events and gains one routing
reconciliation step. Mako owns rendering and notification duplication through
static criteria and watcher-selected modes.

The watcher owns modes under a dedicated prefix and never replaces unrelated
Mako modes. It activates exactly one real-notification routing mode and, only
when needed, one generic cue mode. The routing mode selects a safe output or
the hidden state. An atomic runtime state file records the focused RustDesk
output and the direction token used by the cue helper.

### Practical Privacy Guarantee

The watcher reconciles immediately for relevant compositor events and each
event-stream connection, and periodically while connected. This minimizes the
transition exposure window and ensures a dropped event, a DPMS change without
an event, or a Mako restart cannot leave routing stale indefinitely.

Hyprland window visibility and Mako notification delivery cannot be updated as
one atomic operation. A notification delivered after a visibility transition
but before watcher reconciliation can therefore use the previous verified
route. This design deliberately accepts that short race rather than reserving
an output, proxying notifications, or suppressing all real notifications while
any RustDesk window is visible. It does not claim a literal zero-race or
absolute `never` guarantee.

## Routing State

On each event-stream connection, every 30 seconds while connected, and relevant
Hyprland events, the watcher reads monitor and client state and derives:

1. Active outputs, their IDs, positions, sizes, and focused state.
2. Excluded output IDs containing a mapped, visible client whose class matches
   `rustdesk` and whose title matches `Remote Desktop`, case-insensitively.
3. Safe outputs: active outputs not in the excluded set.
4. Real-toast output:
   - focused output when it is safe;
   - otherwise the safe output with the smallest X coordinate, using Y and
     output name as deterministic tie breakers;
   - otherwise no output, which selects the hidden route.
5. Cue state:
   - disabled when the focused output is safe;
   - focused output plus a four-direction arrow when a safe output exists;
   - focused output plus a neutral bullet when no safe output exists.

The arrow is based on the vector between output centers. Horizontal wins when
the absolute X distance is greater than or equal to the absolute Y distance;
otherwise vertical wins.

The watcher updates Mako only when the derived routing state or live Mako mode
state changes. Mode changes remove only watcher-owned routing and cue modes,
preserving `default`, `do-not-disturb`, and any future unrelated modes. It
writes cue state atomically before enabling the cue mode and removes the state
after disabling that mode.

## Mako Criteria

Mako receives static criteria for each configured output:

- A catch-all fail-closed criterion makes ordinary notifications invisible
  until a watcher-owned safe routing mode explicitly makes them visible.
- One routing mode per configured output sets `output` and restores visibility.
- One hidden routing mode leaves ordinary notifications invisible.
- One generic cue mode adds an `on-notify` action that invokes the cue helper
  with the original notification ID.
- The helper reads and validates the runtime cue state, inspects the original
  notification through `makoctl list -j`, honors Spotify and do-not-disturb
  suppression, maps the direction token to an arrow or neutral bullet, and
  sends one synthetic notification with a reserved category.
- Reserved cue-category criteria route each synthetic cue to its RustDesk
  output, disable recursive `on-notify` handling, disable icons/actions/history,
  center the symbol, set the five-second timeout, and use the overlay layer.
- Route-specific `app-name=notify-send` criteria replace the broad existing
  do-not-disturb exception. They restore visibility and cue eligibility for the
  mode-change confirmation only when a verified safe route is active. Under
  the hidden route, they permit the cue but keep the real notification hidden.

Criteria order is part of the design:

1. Fail-closed default.
2. Watcher-owned real routing modes.
3. Watcher-owned generic cue trigger mode.
4. Existing application suppression and do-not-disturb rules.
5. Route-specific `notify-send` confirmation exceptions.
6. Reserved cue-category rendering and recursion guards.
7. Existing urgency and notification-specific styling.

This ordering lets a cue override the fail-closed default while allowing
Spotify suppression and ordinary do-not-disturb notifications to suppress both
the real notification and cue trigger. The route-specific `notify-send`
exceptions restore visibility and cue eligibility for the do-not-disturb
mode-change confirmation without bypassing fail-closed routing. Cue
notifications are not retained in history.

## Event Flow

Reconcile routing on each connection, every 30 seconds, and events that can
change monitor focus/activity/geometry, visible workspaces, RustDesk
classification/placement/visibility, or the monitor set. For Hyprland 0.56.0,
these include window open/close/move/title/focus/minimize, workspace and special
workspace changes, focused monitor and monitor add/remove events, fullscreen,
pin/group changes, and configuration reloads, including available v2 forms.
Stream termination returns to a two-second reconnect delay rather than a tight
EOF loop.

For an incoming real notification:

1. The active routing mode assigns it to the selected safe output or keeps it
   invisible when no safe output exists.
2. If the cue mode is active, its `on-notify` action invokes the cue helper with
   the original notification ID.
3. The helper validates the runtime state and original notification, then sends
   a second notification containing only the selected symbol under the
   reserved output category.
4. Reserved cue criteria place the cue on the focused RustDesk output and
   disable the cue's own `on-notify` action, preventing recursion.
5. If a safe output appears while a hidden real notification is still active,
   Mako can reevaluate it under the new routing mode. Expired notifications
   remain available through normal history behavior.

## Failure Handling

- Fail closed when no watcher-owned route is active: hide ordinary popups
  rather than letting Mako choose the focused output.
- Treat malformed or unavailable Hyprland state as no verified safe route.
- Reject missing or malformed runtime cue state without showing a cue.
- Do not terminate the existing RustDesk submap watcher because `makoctl` is
  temporarily unavailable. Log the failure and retry during the next routing
  reconciliation.
- Keep the previous known mode when state is unchanged; avoid redundant Mako
  updates and duplicate cue triggers.
- Preserve unrelated Mako modes during every update.
- Mako configuration reloads retain the current routing modes. After a full
  Mako restart, fail-closed configuration keeps content hidden until the next
  event or periodic reconciliation, no later than the configured interval while
  the event stream remains connected.

## Validation

Add fixture-driven shell tests around routing-state calculation and mode
selection with mocked `hyprctl` and `makoctl` behavior. Cover:

- Focused safe output: real route to focus, no cue.
- Focused RustDesk output with safe destinations left, right, above, and below.
- Multiple safe outputs: deterministic leftmost fallback.
- RustDesk on a hidden workspace: output remains safe.
- Every output excluded: hidden real route and neutral cue.
- Mode updates preserve unrelated modes and avoid redundant changes.
- Temporary `makoctl` failure does not terminate the watcher.
- Cue helper rejects malformed state, missing notification IDs, recursive cue
  categories, Spotify, and ordinary do-not-disturb notifications.

Validate Mako behavior live after the automated checks:

- Reload the managed Mako configuration.
- Restart the watcher service and confirm its active modes.
- With RustDesk visible on `HDMI-A-1` and `DP-2`, focus each RustDesk output and
  send a test notification.
- Confirm only the arrow appears over RustDesk and the complete notification
  appears on `DVI-D-1`.
- Confirm ordinary do-not-disturb and Spotify suppression produce no cue, while
  the existing do-not-disturb `notify-send` confirmation still routes safely
  and produces a cue when the focused output shows RustDesk.
- Confirm cue notifications do not enter history or recursively duplicate.

Directional cue rendering, exactly one cue with no cue history, and the
do-not-disturb confirmation while `rustdesk-cue` is active remain residual live
checks when the current session does not have both a visible RustDesk Remote
Desktop window and a DPMS-active safe output. Do not infer those visual results
from an all-hidden or DPMS-off state.

## Rollout

Edit the repository sources, which are already symlinked into
`~/.config/hypr`, `~/.config/systemd/user`, and `~/.config/mako`. Reload Mako,
restart `watch-rustdesk-submap.service`, and perform the live checks without
restarting the Hyprland session.
