# RustDesk-Safe Notification Routing Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Route real Mako notifications away from visible RustDesk outputs and show only a directional, content-free cue on the focused RustDesk output.

**Architecture:** Extend the existing Hyprland RustDesk watcher to derive one fail-closed Mako route plus optional cue state from live monitor/client JSON. A focused Mako helper validates the original notification and atomically written cue state before emitting an arrow notification; static Mako criteria route real notifications and synthetic cues without exposing real content.

**Tech Stack:** Bash, `jq`, Hyprland socket events/`hyprctl`, Mako modes and criteria, `makoctl`, `notify-send`, systemd user service.

## Global Constraints

- Work in a project-local configurations worktree created with the `using-git-worktrees` skill; `.worktrees/` is already ignored by `.gitignore`.
- Do not commit unless the user explicitly requests a commit. Keep changes reviewable in the working tree.
- Support exactly `DVI-D-1`, `HDMI-A-1`, and `DP-2`; unknown outputs are not notification targets.
- Exclude only mapped, visible RustDesk Remote Desktop windows. Hidden-workspace RustDesk windows do not exclude an output.
- Never copy title, body, source application, urgency, actions, or notification count into a RustDesk cue.
- Preserve unrelated Mako modes, the existing do-not-disturb behavior, its `notify-send` mode-change confirmation, and Spotify suppression.
- Fail closed: without one verified watcher-owned route, ordinary notifications remain invisible and retain normal Mako history behavior.
- Add no dependencies; `bash`, `jq`, `hyprctl`, `socat`, `makoctl`, and `notify-send` are already installed.
- Keep the existing RustDesk clean-submap and second-window placement behavior unchanged.
- Use practical event-driven routing: relevant events, reconnect reconciliation,
  and a 30-second periodic deadline minimize exposure and prevent indefinite
  stale routing, but cannot atomically synchronize a Wayland visibility change
  with Mako delivery. Do not claim a literal zero-race or absolute `never`
  guarantee, and do not replace this with a proxy, reserved output, or global
  RustDesk-time suppression architecture.

---

## File Map

- Modify `Linux/hypr/watch-rustdesk-submap.sh`: derive routing state, maintain watcher-owned Mako modes and cue state, and reconcile on relevant Hyprland events.
- Create `Linux/hypr/tests/watch-rustdesk-submap-test.sh`: fixture-driven routing, mode ownership, failure, and event-filter tests.
- Create `Linux/mako/rustdesk-notification-cue`: validate one original Mako notification and emit one symbol-only synthetic cue.
- Create `Linux/mako/tests/rustdesk-notification-cue-test.sh`: mock Mako/notification command behavior and test suppression/privacy rules.
- Modify `Linux/mako/config`: add fail-closed routes, cue trigger/rendering, DND-safe exceptions, and recursion guards.
- Create `Linux/mako/tests/config-test.sh`: assert required criteria ordering/properties and exercise Mako's config parser.

---

### Task 1: Pure Notification Route Calculation

**Files:**
- Modify: `Linux/hypr/watch-rustdesk-submap.sh`
- Create: `Linux/hypr/tests/watch-rustdesk-submap-test.sh`

**Interfaces:**
- Consumes: Hyprland monitor JSON and client JSON matching `hyprctl monitors -j` and `hyprctl clients -j`.
- Produces: `notification_route_state MONITORS_JSON CLIENTS_JSON`, which prints exactly `ROUTE_MODE|CUE_OUTPUT|DIRECTION`.
- State values: route is `rustdesk-route-DVI-D-1`, `rustdesk-route-HDMI-A-1`, `rustdesk-route-DP-2`, or `rustdesk-route-hidden`; cue output is one supported output or `none`; direction is `left`, `right`, `up`, `down`, or `none`.

- [ ] **Step 1: Add a source-safe test harness and failing route cases**

Start `Linux/hypr/tests/watch-rustdesk-submap-test.sh` with the repository's existing shell-test pattern:

```bash
#!/bin/bash
set -euo pipefail

SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
WATCHER="$SCRIPT_DIR/../watch-rustdesk-submap.sh"

fail() {
  printf 'FAIL: %s\n' "$1" >&2
  exit 1
}

assert_equal() {
  local expected=$1
  local actual=$2
  local message=$3
  [[ $actual == "$expected" ]] || fail "$message: expected '$expected', got '$actual'"
}

# The watcher must define functions but not enter its event loop when sourced.
source "$WATCHER"
```

Use fixture builders that emit complete monitor objects with `id`, `name`, `x`, `y`, `width`, `height`, `focused`, `disabled`, and `dpmsStatus`, plus client objects with `monitor`, `mapped`, `visible`, `class`, and `title`. Add these exact assertions:

```bash
assert_equal 'rustdesk-route-HDMI-A-1|none|none' \
  "$(notification_route_state "$MONITORS_HDMI_FOCUSED" '[]')" \
  'focused safe output'

assert_equal 'rustdesk-route-DVI-D-1|HDMI-A-1|left' \
  "$(notification_route_state "$MONITORS_HDMI_FOCUSED" "$RUSTDESK_ON_HDMI")" \
  'RustDesk focus routes left'

assert_equal 'rustdesk-route-DP-2|DVI-D-1|right' \
  "$(notification_route_state "$MONITORS_DVI_FOCUSED_WITH_DP_ONLY_SAFE" "$RUSTDESK_ON_DVI")" \
  'RustDesk focus routes right'

assert_equal 'rustdesk-route-HDMI-A-1|DVI-D-1|down' \
  "$(notification_route_state "$MONITORS_VERTICAL_DOWN" "$RUSTDESK_ON_DVI")" \
  'vertical destination routes down'

assert_equal 'rustdesk-route-HDMI-A-1|DVI-D-1|up' \
  "$(notification_route_state "$MONITORS_VERTICAL_UP" "$RUSTDESK_ON_DVI")" \
  'vertical destination routes up'

assert_equal 'rustdesk-route-hidden|DP-2|none' \
  "$(notification_route_state "$MONITORS_DP_FOCUSED" "$RUSTDESK_ON_ALL")" \
  'all occupied hides real notification'

assert_equal 'rustdesk-route-DP-2|none|none' \
  "$(notification_route_state "$MONITORS_DP_FOCUSED" "$HIDDEN_RUSTDESK_ON_DP")" \
  'hidden-workspace RustDesk does not exclude output'
```

Include a tie-break fixture with the focused output excluded and two safe outputs; assert that the lower X coordinate wins, then Y, then output name. Include unknown/disabled/DPMS-off outputs and assert they are never selected.

- [ ] **Step 2: Run the new test and verify the source/undefined-function failure**

Run:

```bash
bash Linux/hypr/tests/watch-rustdesk-submap-test.sh
```

Expected: failure because sourcing the current watcher enters runtime setup or because `notification_route_state` is undefined.

- [ ] **Step 3: Make the watcher source-safe**

Move current startup/socket/event-loop work into `main()` and end the file with:

```bash
if [[ ${BASH_SOURCE[0]} == "$0" ]]; then
  main "$@"
fi
```

Do not change the existing `is_rustdesk_remote`, second-window placement, or clean-submap behavior in this step.

- [ ] **Step 4: Implement the pure route function**

Add a readonly supported-output JSON constant and implement the calculation in one `jq` invocation:

```bash
SUPPORTED_NOTIFICATION_OUTPUTS_JSON='["DVI-D-1","HDMI-A-1","DP-2"]'

notification_route_state() {
  local monitors_json=$1
  local clients_json=$2

  jq -rnc \
    --argjson monitors "$monitors_json" \
    --argjson clients "$clients_json" \
    --argjson supported "$SUPPORTED_NOTIFICATION_OUTPUTS_JSON" '
      def center: {
        x: (.x + (.width / 2)),
        y: (.y + (.height / 2))
      };

      [$monitors[]
        | select((.disabled // false) == false)
        | select((.dpmsStatus // true) == true)
        | select(.name as $name | ($supported | index($name)) != null)
      ] as $active
      | [$clients[]
          | select((.mapped // false) == true)
          | select((.visible // false) == true)
          | select((.class // "") | test("rustdesk"; "i"))
          | select((.title // "") | test("Remote Desktop"; "i"))
          | .monitor
        ] | unique as $excluded
      | [$active[]
          | select(.id as $id | ($excluded | index($id)) == null)
        ] as $safe
      | ([$active[] | select(.focused == true)][0] // null) as $focused
      | (if $focused == null then null
         elif ($focused.id as $id | ($excluded | index($id)) == null) then $focused
         else (($safe | sort_by([.x, .y, .name]))[0] // null)
         end) as $destination
      | if $focused == null then
          ["rustdesk-route-hidden", "none", "none"]
        elif $destination == null then
          ["rustdesk-route-hidden", $focused.name, "none"]
        elif $focused.id == $destination.id then
          ["rustdesk-route-\($destination.name)", "none", "none"]
        else
          ($focused | center) as $from
          | ($destination | center) as $to
          | ($to.x - $from.x) as $dx
          | ($to.y - $from.y) as $dy
          | (if ($dx | fabs) >= ($dy | fabs) then
               if $dx >= 0 then "right" else "left" end
             else
               if $dy >= 0 then "down" else "up" end
             end) as $direction
          | ["rustdesk-route-\($destination.name)", $focused.name, $direction]
        end
      | join("|")
    '
}
```

If the installed `jq` does not expose `fabs`, replace each use with an inline absolute-value helper (`def abs: if . < 0 then -. else . end;`) and keep the same output contract.

- [ ] **Step 5: Run route tests and syntax validation**

Run:

```bash
bash Linux/hypr/tests/watch-rustdesk-submap-test.sh
bash -n Linux/hypr/watch-rustdesk-submap.sh
bash -n Linux/hypr/tests/watch-rustdesk-submap-test.sh
```

Expected: all route assertions pass and both syntax checks exit zero.

---

### Task 2: Mako Mode And Runtime Cue-State Reconciliation

**Files:**
- Modify: `Linux/hypr/watch-rustdesk-submap.sh`
- Modify: `Linux/hypr/tests/watch-rustdesk-submap-test.sh`

**Interfaces:**
- Consumes: `notification_route_state` from Task 1 and live output from `makoctl mode`.
- Produces: `apply_notification_route_state STATE`, `reconcile_notification_routing`, and an atomic state file at `${RUSTDESK_NOTIFICATION_CUE_STATE:-$XDG_RUNTIME_DIR/rustdesk-notification-cue}`.
- Owns only `rustdesk-route-*` and `rustdesk-cue`; all other Mako modes are preserved.

- [ ] **Step 1: Add failing tests for mode ownership and state-file ordering**

Extend the test harness with a temporary runtime directory and a fake `makoctl` shell function that records arguments and can return configured mode output/failure. Test these cases:

```bash
apply_notification_route_state 'rustdesk-route-DVI-D-1|DP-2|left'
assert_equal 'DP-2|left' "$(<"$RUSTDESK_NOTIFICATION_CUE_STATE")" 'cue state'
assert_log_contains '-r rustdesk-route-DVI-D-1'
assert_log_contains '-r rustdesk-route-HDMI-A-1'
assert_log_contains '-r rustdesk-route-DP-2'
assert_log_contains '-r rustdesk-route-hidden'
assert_log_contains '-r rustdesk-cue'
assert_log_contains '-a rustdesk-route-DVI-D-1'
assert_log_contains '-a rustdesk-cue'
```

Also assert:

- Existing mode output `default\ndo-not-disturb` is never passed to `-r`.
- `rustdesk-route-hidden|DP-2|none` writes `DP-2|none`, activates hidden route plus cue, and does not activate a safe route.
- `rustdesk-route-DVI-D-1|none|none` removes `rustdesk-cue` and removes the state file only after successful `makoctl` application.
- Already-correct modes and cue state cause no mutation call.
- A `makoctl` failure leaves the state available for a future retry, returns nonzero, and does not terminate the test shell.
- If Mako restarts and loses watcher-owned modes, the same derived state is reapplied rather than skipped by an in-memory cache.

- [ ] **Step 2: Run the tests and verify reconciliation failures**

Run:

```bash
bash Linux/hypr/tests/watch-rustdesk-submap-test.sh
```

Expected: route-calculation tests pass; new reconciliation assertions fail because the functions/constants do not exist.

- [ ] **Step 3: Implement owned-mode reconciliation**

Add constants and an apply function using arrays so mode arguments are never word-split:

```bash
NOTIFICATION_ROUTE_MODES=(
  rustdesk-route-DVI-D-1
  rustdesk-route-HDMI-A-1
  rustdesk-route-DP-2
  rustdesk-route-hidden
)
NOTIFICATION_CUE_MODE=rustdesk-cue
: "${XDG_RUNTIME_DIR:=/run/user/$UID}"
RUSTDESK_NOTIFICATION_CUE_STATE=${RUSTDESK_NOTIFICATION_CUE_STATE:-$XDG_RUNTIME_DIR/rustdesk-notification-cue}
```

`apply_notification_route_state` must:

1. Parse and validate all three `|`-delimited fields against the fixed allowed values.
2. Read `makoctl mode`; a read failure returns nonzero without changing modes.
3. Compare actual owned modes and cue-state contents with the desired state.
4. When enabling a cue, write `OUTPUT|DIRECTION` to a `mktemp` file beside the target, set `umask 077`, and `mv` it atomically before enabling `rustdesk-cue`.
5. Build one `makoctl mode` command that removes every owned route and cue mode, adds exactly one route, and adds `rustdesk-cue` only when cue output is not `none`.
6. On success without a cue, remove the stale state file. On failure, log with `printf ... >&2`, return nonzero, and keep enough state for retry.

Do not use `makoctl mode -s`; replacing the complete mode list would clobber do-not-disturb and unrelated modes.

- [ ] **Step 4: Reconcile live Hyprland state and filter events**

Implement:

```bash
reconcile_notification_routing() {
  local monitors_json clients_json state
  if ! monitors_json=$(hyprctl monitors -j) || ! clients_json=$(hyprctl clients -j); then
    apply_notification_route_state 'rustdesk-route-hidden|none|none' || true
    return 1
  fi
  if ! state=$(notification_route_state "$monitors_json" "$clients_json"); then
    apply_notification_route_state 'rustdesk-route-hidden|none|none' || true
    return 1
  fi
  apply_notification_route_state "$state"
}

is_notification_routing_event() {
  case $1 in
    "openwindow>>"*|"closewindow>>"*|"movewindow>>"*|"moveworkspace>>"*|\
      "workspace>>"*|"workspacev2>>"*|"focusedmon>>"*|\
      "monitoradded>>"*|"monitorremoved>>"*) return 0 ;;
    *) return 1 ;;
  esac
}
```

Reconcile immediately for every newly connected stream, then every 30 seconds
using an absolute deadline so unrelated event traffic cannot postpone recovery.
On EOF, return to an outer two-second reconnect delay. In the event loop, call
reconciliation after all relevant Hyprland 0.56.0 events with `|| true` so a
Mako failure cannot kill the existing submap watcher under strict mode. Cover
window title/focus/minimize/move events, workspace/special-workspace visibility,
monitor focus/add/remove, config reload, fullscreen, pin/group changes, and
available v2 forms. Keep the existing open-window and active-window behavior,
passing persistent handler state explicitly rather than relying on dynamic
scope or a pipeline subshell.

- [ ] **Step 5: Run unit and syntax checks**

Run:

```bash
bash Linux/hypr/tests/watch-rustdesk-submap-test.sh
bash -n Linux/hypr/watch-rustdesk-submap.sh
```

Expected: route, mode ownership, startup recovery, failure handling, and event filter cases pass.

---

### Task 3: Privacy-Preserving Cue Helper

**Files:**
- Create: `Linux/mako/rustdesk-notification-cue`
- Create: `Linux/mako/tests/rustdesk-notification-cue-test.sh`

**Interfaces:**
- Consumes: one Mako notification ID and `OUTPUT|DIRECTION` from `RUSTDESK_NOTIFICATION_CUE_STATE`.
- Queries: `makoctl list -j` and `makoctl mode`.
- Produces: at most one `notify-send` call with app name `notify-send`, category `rustdesk-notification-cue-OUTPUT`, five-second timeout, and one symbol summary.

- [ ] **Step 1: Write failing helper tests with fake commands**

Create a temporary `bin`, prepend it to `PATH`, and provide fake `makoctl` and `notify-send` executables. The fake `makoctl list -j` should return fixture JSON such as:

```json
[
  {
    "id": 42,
    "app_name": "Signal",
    "category": null,
    "summary": "secret title",
    "body": "secret body"
  }
]
```

Write exact assertions for:

- `DP-2|left` emits only `--app-name=notify-send`, `--category=rustdesk-notification-cue-DP-2`, `--expire-time=5000`, `--`, and `←`.
- `DVI-D-1|right`, `HDMI-A-1|up`, `HDMI-A-1|down`, and `DP-2|none` map to `→`, `↑`, `↓`, and `•`.
- The fake log never contains `secret title`, `secret body`, or `Signal`.
- Missing state, malformed delimiters, unsupported outputs/directions, missing IDs, nonnumeric IDs, absent list entries, or failed `makoctl` calls emit nothing and return without exposing content.
- `app_name=Spotify` emits nothing.
- Active `do-not-disturb` with an ordinary app emits nothing.
- Active `do-not-disturb` with `app_name=notify-send` still emits a cue.
- An original category beginning `rustdesk-notification-cue-` emits nothing, even if Mako criteria are misordered.
- Failed `notify-send` does not print original notification content and does not recursively retry.

- [ ] **Step 2: Run the helper test and verify the missing-file failure**

Run:

```bash
bash Linux/mako/tests/rustdesk-notification-cue-test.sh
```

Expected: failure because `Linux/mako/rustdesk-notification-cue` does not exist.

- [ ] **Step 3: Implement the helper defensively**

Use this control flow:

```bash
#!/bin/bash
set -euo pipefail

if (($# != 1)) || [[ ! $1 =~ ^[0-9]+$ ]]; then
  exit 0
fi

: "${XDG_RUNTIME_DIR:=/run/user/$UID}"
state_file=${RUSTDESK_NOTIFICATION_CUE_STATE:-$XDG_RUNTIME_DIR/rustdesk-notification-cue}
[[ -r $state_file ]] || exit 0

state=$(<"$state_file")
[[ $state != *$'\n'* ]] || exit 0
IFS='|' read -r output direction extra <<<"$state"
[[ -z ${extra:-} ]] || exit 0

case $output in
  DVI-D-1|HDMI-A-1|DP-2) ;;
  *) exit 0 ;;
esac

case $direction in
  left) symbol='←' ;;
  right) symbol='→' ;;
  up) symbol='↑' ;;
  down) symbol='↓' ;;
  none) symbol='•' ;;
  *) exit 0 ;;
esac
```

Then query `makoctl list -j` once and use `jq -r --argjson id "$1"` to extract exactly the matching object's `app_name` and `category`. Reject no match, `Spotify`, and categories beginning `rustdesk-notification-cue-`. Query `makoctl mode`; when `do-not-disturb` is present, allow only `app_name=notify-send`.

The only notification command is:

```bash
notify-send \
  --app-name=notify-send \
  --category="rustdesk-notification-cue-$output" \
  --expire-time=5000 \
  -- "$symbol" >/dev/null 2>&1 || true
```

Do not log original notification fields on any path.

- [ ] **Step 4: Mark the helper and tests executable**

Run:

```bash
chmod +x Linux/mako/rustdesk-notification-cue \
  Linux/mako/tests/rustdesk-notification-cue-test.sh \
  Linux/hypr/tests/watch-rustdesk-submap-test.sh
```

Expected: Mako can execute the helper directly; Git records executable mode for the new scripts.

- [ ] **Step 5: Run helper tests and syntax validation**

Run:

```bash
bash Linux/mako/tests/rustdesk-notification-cue-test.sh
bash -n Linux/mako/rustdesk-notification-cue
bash -n Linux/mako/tests/rustdesk-notification-cue-test.sh
```

Expected: all helper privacy, suppression, validation, and symbol tests pass.

---

### Task 4: Fail-Closed Mako Criteria

**Files:**
- Modify: `Linux/mako/config`
- Create: `Linux/mako/tests/config-test.sh`

**Interfaces:**
- Consumes: modes `rustdesk-route-*`, mode `rustdesk-cue`, cue categories `rustdesk-notification-cue-*`, and helper path `~/.config/mako/rustdesk-notification-cue`.
- Produces: safe-output real toasts, hidden real toasts without a safe output, and symbol-only overlay cues.

- [ ] **Step 1: Write a failing config structure/parser test**

The test must read `Linux/mako/config`, assert ordering by line number, and check each required block. Required order:

```text
[] fail-closed
rustdesk-route-* sections
rustdesk-cue trigger
Spotify and do-not-disturb suppression
route-specific notify-send exceptions
rustdesk-notification-cue-* category sections
urgency and existing summary-specific styling
```

For each safe route, assert exact output and `invisible=false`. Assert the hidden route never sets `invisible=false`. For each cue category, assert `output`, `invisible=false`, `on-notify=none`, `icons=0`, `actions=0`, `history=0`, `format=%s`, `text-alignment=center`, `font=sans-serif 28px`, `default-timeout=5000`, and `layer=overlay`.

Run Mako against the file for at most one second:

```bash
set +e
parser_output=$(timeout 1 mako -c "$CONFIG" 2>&1)
parser_status=$?
set -e
[[ $parser_output != *'Failed to parse config'* ]] || fail "$parser_output"
[[ $parser_output != *'Invalid configuration'* ]] || fail "$parser_output"
((parser_status != 0)) || fail 'second mako instance unexpectedly exited successfully'
```

The two explicit parser-error assertions are authoritative; a timeout, an
already-owned D-Bus name, or a headless Wayland error is an acceptable nonzero
post-parse result.

- [ ] **Step 2: Run the config test and verify missing criteria failures**

Run:

```bash
bash Linux/mako/tests/config-test.sh
```

Expected: failure because no fail-closed, route, trigger, exception, or cue-category blocks exist.

- [ ] **Step 3: Add fail-closed routes and cue trigger before suppression rules**

Add these sections after global visual settings and before Spotify:

```ini
[]
invisible=true

[mode=rustdesk-route-DVI-D-1]
output=DVI-D-1
invisible=false

[mode=rustdesk-route-HDMI-A-1]
output=HDMI-A-1
invisible=false

[mode=rustdesk-route-DP-2]
output=DP-2
invisible=false

[mode=rustdesk-route-hidden]
invisible=true

[mode=rustdesk-cue]
on-notify=exec ~/.config/mako/rustdesk-notification-cue "$id"
```

Add `on-notify=none` to both Spotify and the generic `do-not-disturb` section so their suppression overrides the earlier cue trigger.

- [ ] **Step 4: Replace the broad DND exception with verified-route exceptions**

Remove the current broad `[mode=do-not-disturb app-name=notify-send]` block. After the generic do-not-disturb section, add one exception per safe route:

```ini
[mode=rustdesk-route-DVI-D-1 app-name=notify-send]
invisible=false
on-notify=exec ~/.config/mako/rustdesk-notification-cue "$id"
```

Repeat exactly for `HDMI-A-1` and `DP-2`. Add a hidden-route variant that restores only cue eligibility, not visibility:

```ini
[mode=rustdesk-route-hidden app-name=notify-send]
on-notify=exec ~/.config/mako/rustdesk-notification-cue "$id"
```

These criteria preserve the DND toggle confirmation only when the watcher has verified a route; all-occupied state still produces the neutral cue but hides the real confirmation.

- [ ] **Step 5: Add output-specific cue rendering and recursion guards**

After route-specific exceptions, add this block for each output, changing category and output together:

```ini
[category=rustdesk-notification-cue-DVI-D-1]
output=DVI-D-1
invisible=false
on-notify=none
icons=0
actions=0
history=0
format=%s
text-alignment=center
font=sans-serif 28px
default-timeout=5000
layer=overlay
```

Keep the current urgency and custom summary sections after cue rendering so existing styles remain effective for real notifications.

- [ ] **Step 6: Run all automated checks**

Run:

```bash
chmod +x Linux/mako/tests/config-test.sh
bash Linux/hypr/tests/watch-rustdesk-submap-test.sh
bash Linux/mako/tests/rustdesk-notification-cue-test.sh
bash Linux/mako/tests/config-test.sh
bash -n Linux/hypr/watch-rustdesk-submap.sh
bash -n Linux/hypr/tests/watch-rustdesk-submap-test.sh
bash -n Linux/mako/rustdesk-notification-cue
bash -n Linux/mako/tests/rustdesk-notification-cue-test.sh
bash -n Linux/mako/tests/config-test.sh
git diff --check
```

Expected: every test and syntax check exits zero; `git diff --check` prints nothing.

---

### Task 5: Activate And Verify The Live Policy

**Files:**
- No additional source files.
- Live symlink targets: `~/.config/hypr/watch-rustdesk-submap.sh`, `~/.config/mako/config`, `~/.config/mako/rustdesk-notification-cue`.

**Interfaces:**
- Consumes: all verified implementation artifacts from Tasks 1-4.
- Produces: active Mako routing and cue behavior in the current Hyprland session.

The directional cue rendering, one-cue-per-notification/no-cue-history check,
and do-not-disturb confirmation while `rustdesk-cue` is active require both a
visible RustDesk Remote Desktop window and a DPMS-active safe output. If that
state is unavailable, preserve these as residual live checks rather than
claiming visual evidence from a hidden or DPMS-off route.

- [ ] **Step 1: Confirm managed paths point to the intended repository files**

Run:

```bash
readlink -f ~/.config/hypr/watch-rustdesk-submap.sh
readlink -f ~/.config/mako/config
readlink -f ~/.config/mako/rustdesk-notification-cue
```

Expected: each path resolves to the configurations checkout being activated. If implementation happened in an isolated worktree, apply the reviewed patch to the shared configurations checkout before this step; do not repoint persistent dotfile symlinks into a temporary worktree.

- [ ] **Step 2: Reload Mako and restart the watcher**

Run:

```bash
makoctl reload
systemctl --user restart watch-rustdesk-submap.service
systemctl --user --no-pager status watch-rustdesk-submap.service
makoctl mode
```

Expected: reload and restart succeed; service is active; exactly one `rustdesk-route-*` mode exists, plus `rustdesk-cue` only if the focused output currently shows RustDesk. Existing unrelated modes remain present.

- [ ] **Step 3: Verify current computed state against Hyprland**

Run:

```bash
hyprctl monitors -j
hyprctl clients -j
makoctl mode
```

Expected for the observed layout from design time: RustDesk-visible `HDMI-A-1` and `DP-2` are excluded, and `DVI-D-1` is the real-toast route. If focus is on either RustDesk output, `$XDG_RUNTIME_DIR/rustdesk-notification-cue` names that output and `left`.

- [ ] **Step 4: Run a visible routing test and restore focus**

Record the currently focused output, focus one RustDesk output, send a test notification, observe for five seconds, then restore the original output:

```bash
original_output=$(hyprctl monitors -j | jq -r '.[] | select(.focused) | .name')
hyprctl dispatch focusmonitor DP-2
notify-send --app-name=rustdesk-routing-test 'Safe routing test' 'This text must appear only on DVI-D-1.'
sleep 6
hyprctl dispatch focusmonitor "$original_output"
```

Expected: `DP-2` shows only a centered left arrow; the complete title/body appears on `DVI-D-1`; no real content appears over RustDesk.

- [ ] **Step 5: Verify history, recursion, and DND behavior**

Run a test notification, then inspect:

```bash
makoctl list -j
makoctl history -j
```

Expected: no category beginning `rustdesk-notification-cue-` appears in history, and only one cue exists per real notification.

For DND, preserve the initial state, enable it if needed, send one ordinary app notification and one `notify-send` confirmation, then restore the initial state. Expected: the ordinary notification produces neither real toast nor cue; the `notify-send` confirmation follows safe routing and produces only the directional cue on focused RustDesk.

- [ ] **Step 6: Review only intended changes**

Run:

```bash
git status --short
git diff -- Linux/hypr/watch-rustdesk-submap.sh Linux/hypr/tests/watch-rustdesk-submap-test.sh Linux/mako/config Linux/mako/rustdesk-notification-cue Linux/mako/tests/rustdesk-notification-cue-test.sh Linux/mako/tests/config-test.sh docs/superpowers/specs/2026-07-30-rustdesk-safe-notification-routing-design.md docs/superpowers/plans/2026-07-30-rustdesk-safe-notification-routing.md
```

Expected: only the approved routing feature and its design/plan are shown. Do not alter or stage unrelated pre-existing changes.
