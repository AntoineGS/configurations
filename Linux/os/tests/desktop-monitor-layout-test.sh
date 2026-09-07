#!/usr/bin/env bash
set -Eeuo pipefail

repo_root=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../../.." && pwd -P)
readonly ACTION_HELPER="$repo_root/Linux/os/helpers/desktop-hardware-action"
test_root=$(mktemp -d)
readonly BIN_DIR="$test_root/bin"
readonly STATE_DIR="$test_root/state"
readonly FAKE_STATE="$test_root/hyprland.json"
readonly FAKE_LOG="$test_root/hyprctl.log"
readonly CONTROL_DIR="$test_root/control"
trap 'rm -rf -- "$test_root"' EXIT

fail() {
  printf 'FAIL: %s\n' "$1" >&2
  exit 1
}

mkdir -p -- "$BIN_DIR" "$STATE_DIR" "$CONTROL_DIR"

cat >"$BIN_DIR/hyprctl" <<'EOF'
#!/usr/bin/env bash
set -Eeuo pipefail

state_file=${FAKE_HYPR_STATE:?FAKE_HYPR_STATE is required}
log_file=${FAKE_HYPR_LOG:?FAKE_HYPR_LOG is required}
control_dir=${FAKE_HYPR_CONTROL_DIR:?FAKE_HYPR_CONTROL_DIR is required}
printf '%s\n' "$*" >>"$log_file"

state=$(<"$state_file")

if [[ ${1:-} == -j && -f $control_dir/hang-query ]]; then
  sleep "$(<"$control_dir/hang-query")"
fi

fail_if_requested() {
  [[ ! -e $control_dir/$1 ]] || exit 1
}

seed_monitor_rule() {
  local input=$1
  local name=$2

  jq -ce --arg name "$name" '
    . as $state
    | ($state.rules // {}) as $rules
    | ($state.monitors[] | select(.name == $name)) as $monitor
    | ($rules[$name] // {}) as $existing
    | .rules = $rules
    | .rules[$name] = (
        {
          disabled: (if ($existing | has("disabled")) then $existing.disabled else $monitor.disabled end),
          mirror: (if ($existing | has("mirror")) then $existing.mirror else $monitor.mirrorOf end)
        }
        + $existing
      )
  ' <<<"$input"
}

apply_monitor_rule() {
  local input=$1
  local name=$2

  jq -ce --arg name "$name" '
    .rules[$name] as $rule
    | .monitors |= map(if .name == $name then
        .disabled = $rule.disabled
        | .mirrorOf = (if $rule.mirror == "" then "none" else $rule.mirror end)
      else . end)
  ' <<<"$input"
}

case ${1:-} in
  -j)
    fail_if_requested fail-query
    case ${2:-} in
      monitors)
        jq -ce '.monitors' <<<"$state"
        ;;
      workspaces)
        jq -ce '.workspaces' <<<"$state"
        ;;
      activeworkspace)
        jq -ce '.activeworkspace' <<<"$state"
        ;;
      *)
        exit 2
        ;;
    esac
    ;;
  eval)
    [[ $# == 2 ]] || exit 2
    code=$2
    move_pattern='^hl\.dispatch\(hl\.dsp\.workspace\.move\([\{]workspace=([1-9][0-9]*),monitor="([[:alnum:]_.:@+-]+)"[\}]\)\)$'
    disable_pattern='^hl\.monitor\([\{]output="([[:alnum:]_.:@+-]+)",disabled=true[\}]\)$'
    preferred_pattern='^hl\.monitor\([\{]output="([[:alnum:]_.:@+-]+)",mode="preferred",position="auto",scale="auto",disabled=false,mirror=""[\}]\)$'
    geometry_pattern='^hl\.monitor\([\{]output="([[:alnum:]_.:@+-]+)",disabled=false,mode="([0-9]+x[0-9]+@[0-9]+([.][0-9]+)?)",position="(-?[0-9]+x-?[0-9]+)",scale=([0-9]+([.][0-9]+)?),transform=([0-7])((,mirror="([[:alnum:]_.:@+-]*)")?)[\}]\)$'
    if [[ $code =~ $move_pattern ]]; then
      workspace_id=${BASH_REMATCH[1]}
      destination=${BASH_REMATCH[2]}
      fail_if_requested fail-move
      source_monitor=$(jq -er --argjson id "$workspace_id" \
        '.workspaces[] | select(.id == $id) | .monitor' <<<"$state")
      active_workspace=$(jq -r --arg monitor "$source_monitor" \
        '.activeWorkspaceIds[$monitor] // ""' <<<"$state")
      if [[ -e $control_dir/no-move-state ]]; then
        next=$state
      else
        next=$(jq -ce --argjson id "$workspace_id" --arg monitor "$destination" --arg source_monitor "$source_monitor" '
          .workspaces |= map(if .id == $id then .monitor = $monitor else . end)
          | .workspaceRehome = (.workspaceRehome // {})
          | .workspaceRehome[$source_monitor] = $monitor
        ' <<<"$state")
        if [[ -e $control_dir/create-active-replacement && $active_workspace == "$workspace_id" ]]; then
          replacement_id=$(jq -er '[.workspaces[] | .id | select(type == "number" and . > 0 and floor == .)] | max + 1' <<<"$next")
          next=$(jq -ce --arg monitor "$source_monitor" --argjson id "$replacement_id" '
            .workspaces += [{id: $id, monitor: $monitor, windows: 0, ispersistent: false}]
            | .activeWorkspaceIds = (.activeWorkspaceIds // {})
            | .activeWorkspaceIds[$monitor] = $id
          ' <<<"$next")
        fi
        if [[ -r $control_dir/drop-monitor ]]; then
          drop_monitor=$(<"$control_dir/drop-monitor")
          next=$(jq -ce --arg name "$drop_monitor" '
            .monitors |= map(if .name == $name then .disabled = true else . end)
          ' <<<"$next")
        fi
        if [[ -r $control_dir/add-workspace ]]; then
          read -r added_id added_monitor <"$control_dir/add-workspace"
          [[ $added_id =~ ^[1-9][0-9]*$ && $added_monitor =~ ^[[:alnum:]_.:@+-]+$ ]] || exit 2
          next=$(jq -ce --argjson id "$added_id" --arg monitor "$added_monitor" '
            .workspaces += [{id: $id, monitor: $monitor, windows: 1, ispersistent: false}]
          ' <<<"$next")
          rm -f -- "$control_dir/add-workspace"
        fi
        if [[ -r $control_dir/add-persistent-workspace ]]; then
          read -r persistent_id persistent_monitor <"$control_dir/add-persistent-workspace"
          [[ $persistent_id =~ ^[1-9][0-9]*$ && $persistent_monitor =~ ^[[:alnum:]_.:@+-]+$ ]] || exit 2
          next=$(jq -ce --argjson id "$persistent_id" --arg monitor "$persistent_monitor" '
            .workspaces += [{id: $id, monitor: $monitor, windows: 0, ispersistent: true}]
          ' <<<"$next")
          rm -f -- "$control_dir/add-persistent-workspace"
        fi
        if [[ -r $control_dir/churn-populated-workspace ]]; then
          churn_id=$(<"$control_dir/churn-populated-workspace")
          [[ $churn_id =~ ^[1-9][0-9]*$ ]] || exit 2
          next=$(jq -ce --argjson id "$churn_id" --arg monitor "$source_monitor" '
            .workspaces += [{id: $id, monitor: $monitor, windows: 1, ispersistent: false}]
          ' <<<"$next")
          churn_id=$((churn_id + 1))
          printf '%s\n' "$churn_id" >"$control_dir/churn-populated-workspace"
        fi
      fi
    elif [[ $code =~ $disable_pattern ]]; then
      name=${BASH_REMATCH[1]}
      fail_if_requested fail-disable
      if [[ -e $control_dir/no-disable-state ]]; then
        next=$state
      else
        next=$(seed_monitor_rule "$state" "$name")
        next=$(jq -ce --arg name "$name" '
          .rules[$name].disabled = true
          | .monitors |= map(if .name == $name then .disabled = true else . end)
        ' <<<"$next")
        next=$(apply_monitor_rule "$next" "$name")
        if [[ -r $control_dir/drop-on-disable ]]; then
          drop_monitor=$(<"$control_dir/drop-on-disable")
          next=$(jq -ce --arg name "$drop_monitor" '
            .monitors |= map(if .name == $name then .disabled = true else . end)
           ' <<<"$next")
           rm -f -- "$control_dir/drop-on-disable"
         fi
         rehome_monitor=$(jq -r --arg name "$name" '.workspaceRehome[$name] // ""' <<<"$next")
         if [[ -z $rehome_monitor ]] || ! jq -e --arg name "$rehome_monitor" '
           any(.monitors[]; .name == $name and .disabled == false and .mirrorOf == "none")
         ' <<<"$next" >/dev/null 2>&1; then
           rehome_monitor=$(jq -r --arg name "$name" '
             [.monitors[] | select(.name != $name and .disabled == false and .mirrorOf == "none") | .name][0] // ""
           ' <<<"$next")
         fi
         if [[ -n $rehome_monitor ]]; then
           next=$(jq -ce --arg source "$name" --arg destination "$rehome_monitor" '
             .workspaces |= map(if .monitor == $source and (.id | type) == "number" and .id < 0 then
               .monitor = $destination
             else . end)
           ' <<<"$next")
         fi
       fi
    elif [[ $code =~ $preferred_pattern ]]; then
      name=${BASH_REMATCH[1]}
      fail_if_requested fail-enable
      if [[ -e $control_dir/no-enable-state ]]; then
        next=$state
      else
        next=$(seed_monitor_rule "$state" "$name")
        next=$(jq -ce --arg name "$name" '
          .rules[$name].disabled = false
          | .rules[$name].mirror = ""
          | .monitors |= map(if .name == $name then .disabled = false else . end)
        ' <<<"$next")
        next=$(apply_monitor_rule "$next" "$name")
      fi
    elif [[ $code =~ $geometry_pattern ]]; then
      name=${BASH_REMATCH[1]}
      mode=${BASH_REMATCH[2]}
      position=${BASH_REMATCH[4]}
      scale=${BASH_REMATCH[5]}
      transform=${BASH_REMATCH[7]}
      mirror=${BASH_REMATCH[10]:-none}
      [[ $mirror =~ ^[[:alnum:]_.:@+-]+$ ]] || exit 2
      width=${mode%%x*}
      remainder=${mode#*x}
      height=${remainder%%@*}
      refresh_rate=${remainder#*@}
      x=${position%%x*}
      y=${position#*x}
      fail_if_requested fail-enable
      if [[ -e $control_dir/no-enable-state ]]; then
        next=$state
      else
        next=$(seed_monitor_rule "$state" "$name")
        next=$(jq -ce \
          --arg name "$name" \
          --argjson width "$width" \
          --argjson height "$height" \
          --argjson refreshRate "$refresh_rate" \
          --argjson x "$x" \
          --argjson y "$y" \
          --argjson scale "$scale" \
          --argjson transform "$transform" \
          --arg mode "$mode" \
          --arg mirror "$mirror" '
          .rules[$name] = (.rules[$name] + {
            disabled: false,
            mode: $mode,
            width: $width,
            height: $height,
            refreshRate: $refreshRate,
            x: $x,
            y: $y,
            scale: $scale,
            transform: $transform,
            mirror: (if $mirror == "none" then "" else $mirror end)
          })
          | .monitors |= map(if .name == $name then
            .width = $width
            | .height = $height
            | .refreshRate = $refreshRate
            | .x = $x
            | .y = $y
            | .scale = $scale
            | .transform = $transform
          else . end)
        ' <<<"$state")
        next=$(apply_monitor_rule "$next" "$name")
      fi
    else
      exit 2
    fi
    printf '%s\n' "$next" >"$state_file"
    ;;
  keyword|dispatch)
    exit 2
    ;;
  *)
    exit 2
    ;;
esac
EOF
chmod 0755 -- "$BIN_DIR/hyprctl"

write_state() {
  printf '%s\n' "$1" >"$FAKE_STATE"
  : >"$FAKE_LOG"
}

run_action() {
  env \
    PATH="$BIN_DIR:$PATH" \
    DESKTOP_HARDWARE_HELPER_DIR="$repo_root/Linux/os/helpers" \
    DESKTOP_MONITOR_LAYOUT_STATE_DIR="$STATE_DIR" \
    HYPRLAND_INSTANCE_SIGNATURE=layout-test-session \
    FAKE_HYPR_STATE="$FAKE_STATE" \
    FAKE_HYPR_LOG="$FAKE_LOG" \
    FAKE_HYPR_CONTROL_DIR="$CONTROL_DIR" \
    "$ACTION_HELPER" "$@"
}

run_action_session() {
  local session=$1
  shift
  env \
    PATH="$BIN_DIR:$PATH" \
    DESKTOP_HARDWARE_HELPER_DIR="$repo_root/Linux/os/helpers" \
    DESKTOP_MONITOR_LAYOUT_STATE_DIR="$STATE_DIR" \
    HYPRLAND_INSTANCE_SIGNATURE="$session" \
    FAKE_HYPR_STATE="$FAKE_STATE" \
    FAKE_HYPR_LOG="$FAKE_LOG" \
    FAKE_HYPR_CONTROL_DIR="$CONTROL_DIR" \
    "$ACTION_HELPER" "$@"
}

assert_monitor() {
  local name=$1
  local filter=$2
  local expected=$3
  local actual
  actual=$(jq -r --arg name "$name" ".monitors[] | select(.name == \$name) | $filter" "$FAKE_STATE") ||
    fail "monitor $name is missing"
  [[ $actual == "$expected" ]] || fail "monitor $name $filter was $actual, expected $expected"
}

assert_log_contains() {
  local expected=$1
  grep -Fqx -- "$expected" "$FAKE_LOG" || fail "hyprctl log did not contain: $expected"
}

assert_log_absent() {
  local unexpected=$1
  ! grep -Fqx -- "$unexpected" "$FAKE_LOG" || fail "hyprctl log unexpectedly contained: $unexpected"
}

log_line() {
  local expected=$1
  local line
  local number=0
  while IFS= read -r line; do
    number=$((number + 1))
    if [[ $line == "$expected" ]]; then
      printf '%s\n' "$number"
      return 0
    fi
  done <"$FAKE_LOG"
  return 1
}

assert_log_before() {
  local first=$1
  local second=$2
  local first_line
  local second_line
  first_line=$(log_line "$first") || fail "hyprctl log did not contain: $first"
  second_line=$(log_line "$second") || fail "hyprctl log did not contain: $second"
  (( first_line < second_line )) || fail "'$first' did not precede '$second'"
}

expect_status() {
  local expected_status=$1
  shift
  local output
  local actual_status
  if output=$(run_action "$@" 2>&1); then
    actual_status=0
  else
    actual_status=$?
  fi
  [[ $actual_status -eq $expected_status ]] ||
    fail "$* returned $actual_status instead of $expected_status: $output"
}

expect_status_session() {
  local expected_status=$1
  local session=$2
  shift 2
  local output
  local actual_status
  if output=$(run_action_session "$session" "$@" 2>&1); then
    actual_status=0
  else
    actual_status=$?
  fi
  [[ $actual_status -eq $expected_status ]] ||
    fail "$* returned $actual_status instead of $expected_status: $output"
}

clear_controls() {
  local control
  for control in "$CONTROL_DIR"/*; do
    [[ -e $control ]] || continue
    rm -f -- "$control"
  done
}

set_fake_monitor_disabled() {
  local name=$1
  local disabled=$2
  local temporary="$test_root/state.XXXXXX"
  temporary=$(mktemp "$temporary")
  jq -ce --arg name "$name" --argjson disabled "$disabled" \
    '.monitors |= map(if .name == $name then .disabled = $disabled else . end)' \
    "$FAKE_STATE" >"$temporary"
  mv -f -- "$temporary" "$FAKE_STATE"
  : >"$FAKE_LOG"
}

set_fake_monitor_identity() {
  local name=$1
  local description=$2
  local model=$3
  local temporary
  temporary=$(mktemp "$test_root/state.XXXXXX")
  jq -ce --arg name "$name" --arg description "$description" --arg model "$model" \
    '.monitors |= map(if .name == $name then .description = $description | .model = $model else . end)' \
    "$FAKE_STATE" >"$temporary"
  mv -f -- "$temporary" "$FAKE_STATE"
  : >"$FAKE_LOG"
}

set_fake_identity_fields() {
  local name=$1
  local description=$2
  local make=$3
  local model=$4
  local serial=$5
  local temporary
  temporary=$(mktemp "$test_root/state.XXXXXX")
  jq -ce \
    --arg name "$name" \
    --arg description "$description" \
    --arg make "$make" \
    --arg model "$model" \
    --arg serial "$serial" \
    '.monitors |= map(if .name == $name then
      .description = $description
      | .make = $make
      | .model = $model
      | .serial = $serial
    else . end)' \
    "$FAKE_STATE" >"$temporary"
  mv -f -- "$temporary" "$FAKE_STATE"
  : >"$FAKE_LOG"
}

set_fake_monitor_mirror() {
  local name=$1
  local mirror=$2
  local temporary
  temporary=$(mktemp "$test_root/state.XXXXXX")
  jq -ce --arg name "$name" --arg mirror "$mirror" \
    '.monitors |= map(if .name == $name then .mirrorOf = $mirror else . end)' \
    "$FAKE_STATE" >"$temporary"
  mv -f -- "$temporary" "$FAKE_STATE"
  : >"$FAKE_LOG"
}

set_fake_monitor_geometry() {
  local name=$1
  local x=$2
  local y=$3
  local scale=$4
  local transform=$5
  local temporary
  temporary=$(mktemp "$test_root/state.XXXXXX")
  jq -ce \
    --arg name "$name" \
    --argjson x "$x" \
    --argjson y "$y" \
    --argjson scale "$scale" \
    --argjson transform "$transform" \
    '.monitors |= map(if .name == $name then
      .x = $x
      | .y = $y
      | .scale = $scale
      | .transform = $transform
    else . end)' \
    "$FAKE_STATE" >"$temporary"
  mv -f -- "$temporary" "$FAKE_STATE"
  : >"$FAKE_LOG"
}

set_fake_monitor_rule_geometry() {
  local name=$1
  local x=$2
  local y=$3
  local scale=$4
  local transform=$5
  local temporary
  temporary=$(mktemp "$test_root/state.XXXXXX")
  jq -ce \
    --arg name "$name" \
    --argjson x "$x" \
    --argjson y "$y" \
    --argjson scale "$scale" \
    --argjson transform "$transform" \
    '.rules = (.rules // {})
     | .rules[$name] = {x: $x, y: $y, scale: $scale, transform: $transform}' \
    "$FAKE_STATE" >"$temporary"
  mv -f -- "$temporary" "$FAKE_STATE"
  : >"$FAKE_LOG"
}

set_fake_monitor_order_dependent_first() {
  local temporary
  temporary=$(mktemp "$test_root/state.XXXXXX")
  jq -ce '.monitors |= [.[1], .[0], .[2], .[3]]' "$FAKE_STATE" >"$temporary"
  mv -f -- "$temporary" "$FAKE_STATE"
  : >"$FAKE_LOG"
}

set_fake_invalid_geometry() {
  local name=$1
  local temporary
  temporary=$(mktemp "$test_root/state.XXXXXX")
  jq -ce --arg name "$name" \
    '.monitors |= map(if .name == $name then .x = "not-a-coordinate" else . end)' \
    "$FAKE_STATE" >"$temporary"
  mv -f -- "$temporary" "$FAKE_STATE"
  : >"$FAKE_LOG"
}

assert_workspace_monitor() {
  local id=$1
  local expected=$2
  local actual
  actual=$(jq -r --argjson id "$id" '.workspaces[] | select(.id == $id) | .monitor' "$FAKE_STATE") ||
    fail "workspace $id is missing"
  [[ $actual == "$expected" ]] || fail "workspace $id was on $actual, expected $expected"
}

last_output_state='{
  "monitors": [
    {
      "name": "USB-C-9",
      "description": "USB-C panel",
      "make": "PanelCo",
      "model": "Panel 9",
      "serial": "one",
      "width": 1920,
      "height": 1080,
      "refreshRate": 60,
      "x": -1920,
      "y": -40,
      "scale": 1.25,
      "transform": 2,
      "mirrorOf": "none",
      "focused": true,
      "disabled": false
    },
    {
      "name": "DP-7",
      "description": "Dock panel",
      "make": "DockCo",
      "model": "Dock 7",
      "serial": "two",
      "width": 2560,
      "height": 1440,
      "refreshRate": 144,
      "x": 0,
      "y": 0,
      "scale": 1,
      "transform": 0,
      "mirrorOf": "none",
      "focused": false,
      "disabled": true
    }
  ],
  "workspaces": [{"id": 1, "monitor": "USB-C-9", "windows": 1, "ispersistent": false}],
  "activeworkspace": {"id": 1},
  "activeWorkspaceIds": {"USB-C-9": 1}
}'

base_state='{
  "monitors": [
    {
      "name": "eDP-1",
      "description": "Internal panel",
      "make": "PanelCo",
      "model": "Internal 1",
      "serial": "internal",
      "width": 1920,
      "height": 1080,
      "refreshRate": 60,
      "x": 0,
      "y": 0,
      "scale": 1,
      "transform": 0,
      "mirrorOf": "none",
      "focused": true,
      "disabled": false
    },
    {
      "name": "HDMI-A-42",
      "description": "Target panel",
      "make": "PanelCo",
      "model": "Target 42",
      "serial": "target",
      "width": 2560,
      "height": 1440,
      "refreshRate": 144,
      "x": -2560,
      "y": -100,
      "scale": 1.5,
      "transform": 3,
      "mirrorOf": "eDP-1",
      "focused": false,
      "disabled": false
    },
    {
      "name": "DP-3",
      "description": "Dock panel",
      "make": "DockCo",
      "model": "Dock 3",
      "serial": "dock",
      "width": 1920,
      "height": 1080,
      "refreshRate": 60,
      "x": 0,
      "y": 980,
      "scale": 1.25,
      "transform": 0,
      "mirrorOf": "none",
      "focused": false,
      "disabled": false
    },
    {
      "name": "HEADLESS-1",
      "description": "Virtual headless output",
      "make": "Virtual",
      "model": "Headless",
      "serial": "virtual",
      "width": 2560,
      "height": 1440,
      "refreshRate": 60,
      "x": 4000,
      "y": 0,
      "scale": 1,
      "transform": 0,
      "mirrorOf": "none",
      "focused": false,
      "disabled": true
    }
  ],
  "workspaces": [
    {"id": 1, "monitor": "eDP-1", "windows": 1, "ispersistent": false},
    {"id": 2, "monitor": "HDMI-A-42", "windows": 1, "ispersistent": false},
    {"id": 3, "monitor": "DP-3", "windows": 1, "ispersistent": false},
    {"id": 4, "monitor": "HDMI-A-42", "windows": 1, "ispersistent": false}
  ],
  "activeworkspace": {"id": 1},
  "activeWorkspaceIds": {"eDP-1": 1, "HDMI-A-42": 2, "DP-3": 3}
}'

special_workspace_state=$(jq -ce '
  .workspaces += [{id: -99, name: "special:scratchpad", monitor: "HDMI-A-42", windows: 1, ispersistent: false}]
' <<<"$base_state")

# Last-output protection must happen before any workspace or monitor mutation.
clear_controls
write_state "$last_output_state"
expect_status 1 monitor set-enabled USB-C-9 false
if grep -Eq '^eval ' "$FAKE_LOG"; then
  fail 'last-output protection issued a mutation'
fi
assert_monitor USB-C-9 .disabled false

# Lua monitor rules are provider state, not a fresh replacement object. A
# prior disabled/mirrored rule must be cleared by a preferred enable as well
# as by a geometry restore.
clear_controls
provider_rule_state=$(jq -ce '
  .rules = {"HDMI-A-42": {disabled: true, mirror: "eDP-1"}}
  | .monitors |= map(if .name == "HDMI-A-42" then .disabled = true else . end)
' <<<"$base_state")
write_state "$provider_rule_state"
expect_status_session 0 provider-rule-enable-session monitor set-enabled HDMI-A-42 true
assert_monitor HDMI-A-42 .disabled false
assert_monitor HDMI-A-42 .mirrorOf none
assert_log_contains 'eval hl.monitor({output="HDMI-A-42",mode="preferred",position="auto",scale="auto",disabled=false,mirror=""})'

# Generic actions accept connectors that are not hard-coded preset names and
# restore all saved geometry, including negative positions and transforms.
clear_controls
write_state "$base_state"
expect_status 0 monitor set-enabled HDMI-A-42 false DP-3
assert_monitor HDMI-A-42 .disabled true
assert_workspace_monitor 2 DP-3
assert_workspace_monitor 4 DP-3
assert_log_before 'eval hl.dispatch(hl.dsp.workspace.move({workspace=2,monitor="DP-3"}))' 'eval hl.monitor({output="HDMI-A-42",disabled=true})'
cache_file="$STATE_DIR/layout-test-session.json"
jq -e '
  .session == "layout-test-session"
  and .monitors["HDMI-A-42"].x == -2560
  and .monitors["HDMI-A-42"].y == -100
  and .monitors["HDMI-A-42"].mode == "2560x1440@144"
  and .monitors["HDMI-A-42"].scale == 1.5
  and .monitors["HDMI-A-42"].transform == 3
  and .monitors["HDMI-A-42"].mirrorOf == "eDP-1"
' "$cache_file" >/dev/null || fail 'saved monitor geometry was incomplete'
[[ $(stat -c '%a' "$STATE_DIR") == 700 ]] || fail 'monitor state directory is not private'
[[ $(stat -c '%a' "$cache_file") == 600 ]] || fail 'monitor cache is not private'

set_fake_monitor_disabled HDMI-A-42 true
expect_status 0 monitor set-enabled HDMI-A-42 true
assert_monitor HDMI-A-42 .disabled false
assert_monitor HDMI-A-42 .x -2560
assert_monitor HDMI-A-42 .y -100
assert_monitor HDMI-A-42 .scale 1.5
assert_monitor HDMI-A-42 .transform 3
assert_monitor HDMI-A-42 .mirrorOf eDP-1
assert_log_contains 'eval hl.monitor({output="HDMI-A-42",disabled=false,mode="2560x1440@144",position="-2560x-100",scale=1.5,transform=3,mirror="eDP-1"})'

# A mirrored output is not an independently usable fallback. The helper ignores
# that dependent candidate and evacuates onto an independent output instead.
clear_controls
write_state "$base_state"
set_fake_monitor_mirror HDMI-A-42 eDP-1
expect_status_session 0 mirror-fallback-session monitor set-enabled eDP-1 false
assert_monitor eDP-1 .disabled true
fallback_monitor=$(jq -r '.workspaces[] | select(.id == 1) | .monitor' "$FAKE_STATE")
assert_monitor "$fallback_monitor" .mirrorOf none
assert_log_before "eval hl.dispatch(hl.dsp.workspace.move({workspace=1,monitor=\"$fallback_monitor\"}))" 'eval hl.monitor({output="eDP-1",disabled=true})'

# Special workspaces use negative IDs and are rehomed by the compositor when
# their source monitor is disabled; the helper must still drain regular ones.
clear_controls
write_state "$special_workspace_state"
expect_status_session 0 special-workspace-session monitor set-enabled HDMI-A-42 false DP-3
assert_workspace_monitor 2 DP-3
assert_workspace_monitor 4 DP-3
assert_workspace_monitor -99 DP-3
jq -e '([.workspaces[] | select(.id == -99 and .windows == 1)] | length) == 1' "$FAKE_STATE" >/dev/null \
  || fail 'special workspace windows were lost during monitor disable'

# Workspace state is re-read while evacuating, so a workspace arriving after
# the first move is handled before the source output is disabled.
clear_controls
write_state "$base_state"
printf '%s\n' '99 HDMI-A-42' >"$CONTROL_DIR/add-workspace"
printf '%s\n' '100 HDMI-A-42' >"$CONTROL_DIR/add-persistent-workspace"
touch "$CONTROL_DIR/create-active-replacement"
expect_status_session 0 workspace-churn-session monitor set-enabled HDMI-A-42 false DP-3
assert_workspace_monitor 2 DP-3
assert_workspace_monitor 4 DP-3
assert_workspace_monitor 99 DP-3
assert_workspace_monitor 100 DP-3
jq -e 'any(.workspaces[]; .monitor == "HDMI-A-42" and .windows == 0 and .ispersistent == false)' "$FAKE_STATE" >/dev/null \
  || fail 'empty active-workspace replacement was not tolerated'
assert_log_before 'eval hl.dispatch(hl.dsp.workspace.move({workspace=99,monitor="DP-3"}))' 'eval hl.monitor({output="HDMI-A-42",disabled=true})'

# An empty non-persistent replacement created for the old active workspace may
# remain, but continuous populated arrivals must fail safe before disable.
clear_controls
write_state "$base_state"
touch "$CONTROL_DIR/create-active-replacement"
printf '%s\n' '100' >"$CONTROL_DIR/churn-populated-workspace"
expect_status_session 1 continuous-populated-churn-session monitor set-enabled HDMI-A-42 false DP-3
assert_monitor HDMI-A-42 .disabled false
assert_workspace_monitor 2 DP-3
assert_workspace_monitor 4 DP-3
assert_log_absent 'eval hl.monitor({output="HDMI-A-42",disabled=true})'

# A fallback that disappears during the final disable is detected after the
# mutation rather than reported as a successful action.
clear_controls
write_state "$base_state"
printf '%s\n' 'DP-3' >"$CONTROL_DIR/drop-on-disable"
expect_status_session 1 disappeared-after-disable-session monitor set-enabled HDMI-A-42 false DP-3
assert_monitor HDMI-A-42 .disabled true
assert_monitor DP-3 .disabled true
assert_log_contains 'eval hl.monitor({output="HDMI-A-42",disabled=true})'
clear_controls

# Only mode enables its target first, migrates every other enabled workspace,
# and then disables those outputs one at a time.
clear_controls
write_state "$base_state"
set_fake_monitor_disabled HDMI-A-42 true
expect_status_session 0 only-session monitor set-layout only HDMI-A-42
assert_monitor HDMI-A-42 .disabled false
assert_monitor eDP-1 .disabled true
assert_monitor DP-3 .disabled true
assert_workspace_monitor 1 HDMI-A-42
assert_workspace_monitor 3 HDMI-A-42
assert_log_before 'eval hl.monitor({output="HDMI-A-42",mode="preferred",position="auto",scale="auto",disabled=false,mirror=""})' 'eval hl.dispatch(hl.dsp.workspace.move({workspace=1,monitor="HDMI-A-42"}))'
assert_log_before 'eval hl.dispatch(hl.dsp.workspace.move({workspace=1,monitor="HDMI-A-42"}))' 'eval hl.monitor({output="eDP-1",disabled=true})'
assert_log_before 'eval hl.dispatch(hl.dsp.workspace.move({workspace=3,monitor="HDMI-A-42"}))' 'eval hl.monitor({output="DP-3",disabled=true})'

# Enable-all is restricted to physical connectors and never creates or
# enables a headless output.
clear_controls
write_state "$base_state"
set_fake_monitor_disabled HDMI-A-42 true
set_fake_monitor_disabled DP-3 true
expect_status_session 0 all-session monitor set-layout all
assert_monitor HDMI-A-42 .disabled false
assert_monitor DP-3 .disabled false
assert_monitor HEADLESS-1 .disabled true
assert_log_absent 'eval hl.monitor({output="HEADLESS-1",mode="preferred",position="auto",scale="auto",disabled=false,mirror=""})'
if grep -Eq 'output create|HEADLESS-1' "$FAKE_LOG"; then
  fail 'enable-all touched a headless output'
fi

# A disabled connector with no valid session record uses preferred/auto rather
# than inventing geometry.
clear_controls
write_state "$base_state"
set_fake_monitor_disabled HDMI-A-42 true
rm -f -- "$STATE_DIR/no-geometry-session.json"
expect_status_session 0 no-geometry-session monitor set-enabled HDMI-A-42 true
assert_log_contains 'eval hl.monitor({output="HDMI-A-42",mode="preferred",position="auto",scale="auto",disabled=false,mirror=""})'

# Unknown, disconnected, and unsafe connector names fail before mutation.
clear_controls
write_state "$base_state"
expect_status_session 1 unknown-session monitor set-enabled MISSING-1 true
expect_status_session 1 unknown-only-session monitor set-layout only MISSING-1
expect_status_session 2 invalid-session monitor set-enabled 'bad/name' true
if grep -Eq '^eval ' "$FAKE_LOG"; then
  fail 'unknown or unsafe connector was mutated'
fi

# Failed enable and failed workspace moves must never be followed by a
# dangerous disable.
clear_controls
write_state "$base_state"
set_fake_monitor_disabled HDMI-A-42 true
touch "$CONTROL_DIR/fail-enable"
expect_status_session 1 failed-enable-session monitor set-layout only HDMI-A-42
assert_monitor eDP-1 .disabled false
assert_monitor DP-3 .disabled false
if grep -Eq 'eval hl\.monitor\(\{output="(eDP-1|DP-3)",disabled=true\}\)' "$FAKE_LOG"; then
  fail 'failed target enable was followed by a disable'
fi
clear_controls

write_state "$base_state"
touch "$CONTROL_DIR/fail-move"
expect_status_session 1 failed-move-session monitor set-enabled HDMI-A-42 false DP-3
assert_monitor HDMI-A-42 .disabled false
assert_log_absent 'eval hl.monitor({output="HDMI-A-42",disabled=true})'
clear_controls

# A fallback that disappears after a move aborts before the source output is
# disabled.
write_state "$base_state"
printf '%s\n' 'DP-3' >"$CONTROL_DIR/drop-monitor"
expect_status_session 1 disappeared-fallback-session monitor set-enabled HDMI-A-42 false DP-3
assert_monitor HDMI-A-42 .disabled false
assert_monitor DP-3 .disabled true
assert_log_absent 'eval hl.monitor({output="HDMI-A-42",disabled=true})'
clear_controls

# A successful IPC command whose state does not change is still a failure.
write_state "$base_state"
set_fake_monitor_disabled HDMI-A-42 true
touch "$CONTROL_DIR/no-enable-state"
expect_status_session 1 failed-enable-state-session monitor set-enabled HDMI-A-42 true
assert_monitor HDMI-A-42 .disabled true
clear_controls

write_state "$base_state"
touch "$CONTROL_DIR/no-move-state"
expect_status_session 1 failed-move-state-session monitor set-enabled HDMI-A-42 false DP-3
assert_monitor HDMI-A-42 .disabled false
assert_log_absent 'eval hl.monitor({output="HDMI-A-42",disabled=true})'
clear_controls

write_state "$base_state"
touch "$CONTROL_DIR/no-disable-state"
expect_status_session 1 failed-disable-state-session monitor set-layout only HDMI-A-42
assert_monitor eDP-1 .disabled false
assert_monitor DP-3 .disabled false
assert_log_contains 'eval hl.monitor({output="eDP-1",disabled=true})'
assert_log_absent 'eval hl.monitor({output="DP-3",disabled=true})'
clear_controls

# Invalid geometry is not persisted and therefore blocks a disable rather
# than leaving an output with no safe way back.
write_state "$base_state"
set_fake_invalid_geometry HDMI-A-42
expect_status_session 1 invalid-geometry-session monitor set-enabled HDMI-A-42 false DP-3
assert_monitor HDMI-A-42 .disabled false
if grep -Eq '^eval ' "$FAKE_LOG"; then
  fail 'invalid geometry caused a monitor mutation'
fi

# A changed identity cannot reuse the old connector's session geometry.
clear_controls
write_state "$base_state"
expect_status_session 0 identity-session monitor set-enabled HDMI-A-42 false DP-3
set_fake_monitor_disabled HDMI-A-42 true
set_fake_monitor_identity HDMI-A-42 'Replacement panel' 'Replacement 42'
expect_status_session 0 identity-session monitor set-enabled HDMI-A-42 true
assert_log_contains 'eval hl.monitor({output="HDMI-A-42",mode="preferred",position="auto",scale="auto",disabled=false,mirror=""})'
assert_log_absent 'eval hl.monitor({output="HDMI-A-42",disabled=false,mode="2560x1440@144",position="-2560x-100",scale=1.5,transform=3,mirror="eDP-1"})'

# Blank identity data, including a common model without a serial, is not
# credible enough to apply session geometry to a reused connector.
clear_controls
write_state "$base_state"
set_fake_identity_fields HDMI-A-42 '' '' 'Common 42' ''
expect_status_session 0 weak-identity-session monitor set-enabled HDMI-A-42 false DP-3
set_fake_monitor_disabled HDMI-A-42 true
expect_status_session 0 weak-identity-session monitor set-enabled HDMI-A-42 true
assert_log_contains 'eval hl.monitor({output="HDMI-A-42",mode="preferred",position="auto",scale="auto",disabled=false,mirror=""})'
assert_log_absent 'eval hl.monitor({output="HDMI-A-42",disabled=false,mode="2560x1440@144",position="-2560x-100",scale=1.5,transform=3,mirror="eDP-1"})'

clear_controls
write_state "$base_state"
set_fake_identity_fields HDMI-A-42 '' '' '' ''
expect_status_session 0 blank-identity-session monitor set-enabled HDMI-A-42 false DP-3
set_fake_monitor_disabled HDMI-A-42 true
expect_status_session 0 blank-identity-session monitor set-enabled HDMI-A-42 true
assert_log_contains 'eval hl.monitor({output="HDMI-A-42",mode="preferred",position="auto",scale="auto",disabled=false,mirror=""})'
assert_log_absent 'eval hl.monitor({output="HDMI-A-42",disabled=false,mode="2560x1440@144",position="-2560x-100",scale=1.5,transform=3,mirror="eDP-1"})'

# Placeholder serials must not authorize cached geometry when a connector is
# reused with otherwise identical identity fields.
for placeholder_serial in 000000000000 0x00000000 'not specified'; do
  clear_controls
  write_state "$base_state"
  set_fake_identity_fields HDMI-A-42 'Target panel' 'PanelCo' 'Target 42' "$placeholder_serial"
  expect_status_session 0 placeholder-serial-session monitor set-enabled HDMI-A-42 false DP-3
  set_fake_monitor_disabled HDMI-A-42 true
  expect_status_session 0 placeholder-serial-session monitor set-enabled HDMI-A-42 true
  assert_log_contains 'eval hl.monitor({output="HDMI-A-42",mode="preferred",position="auto",scale="auto",disabled=false,mirror=""})'
  assert_log_absent 'eval hl.monitor({output="HDMI-A-42",disabled=false,mode="2560x1440@144",position="-2560x-100",scale=1.5,transform=3,mirror="eDP-1"})'
done

# If a cached mirror source is disabled, re-enable the connector with its
# saved geometry but without recreating the unsafe mirror relationship.
clear_controls
write_state "$base_state"
expect_status_session 0 mirror-source-session monitor set-enabled HDMI-A-42 false DP-3
set_fake_monitor_disabled eDP-1 true
expect_status_session 0 mirror-source-session monitor set-enabled HDMI-A-42 true
assert_monitor HDMI-A-42 .disabled false
assert_monitor HDMI-A-42 .x -2560
assert_monitor HDMI-A-42 .y -100
assert_monitor HDMI-A-42 .scale 1.5
assert_monitor HDMI-A-42 .transform 3
assert_monitor HDMI-A-42 .mirrorOf none
assert_log_contains 'eval hl.monitor({output="HDMI-A-42",disabled=false,mode="2560x1440@144",position="-2560x-100",scale=1.5,transform=3,mirror=""})'
assert_log_absent 'eval hl.monitor({output="HDMI-A-42",mode="preferred",position="auto",scale="auto",disabled=false,mirror=""})'
assert_log_absent 'eval hl.monitor({output="HDMI-A-42",disabled=false,mode="2560x1440@144",position="-2560x-100",scale=1.5,transform=3,mirror="eDP-1"})'

# Enable-all first restores disabled outputs unmirrored, then restores cached
# mirror relationships after every possible source has been enabled.
clear_controls
write_state "$base_state"
expect_status_session 0 mirror-all-session monitor set-enabled HDMI-A-42 false DP-3
expect_status_session 0 mirror-all-session monitor set-enabled eDP-1 false DP-3
set_fake_monitor_order_dependent_first
expect_status_session 0 mirror-all-session monitor set-layout all
assert_monitor eDP-1 .disabled false
assert_monitor HDMI-A-42 .disabled false
assert_monitor HDMI-A-42 .mirrorOf eDP-1
assert_log_contains 'eval hl.monitor({output="HDMI-A-42",disabled=false,mode="2560x1440@144",position="-2560x-100",scale=1.5,transform=3,mirror="eDP-1"})'
assert_log_before \
  'eval hl.monitor({output="eDP-1",disabled=false,mode="1920x1080@60",position="0x0",scale=1,transform=0,mirror=""})' \
  'eval hl.monitor({output="HDMI-A-42",disabled=false,mode="2560x1440@144",position="-2560x-100",scale=1.5,transform=3,mirror="eDP-1"})'

# A dependent that stayed enabled while its cached source was disabled must be
# restored after the source is enabled, without replaying the dependent's old
# geometry over its current layout.
clear_controls
write_state "$base_state"
expect_status_session 0 deferred-mirror-session monitor set-enabled HDMI-A-42 false DP-3
set_fake_monitor_disabled HDMI-A-42 false
set_fake_monitor_disabled eDP-1 true
set_fake_monitor_mirror HDMI-A-42 none
set_fake_monitor_geometry HDMI-A-42 777 888 1.75 1
set_fake_monitor_rule_geometry HDMI-A-42 -111 -222 1.25 0
expect_status_session 0 deferred-mirror-session monitor set-layout all
assert_monitor eDP-1 .disabled false
assert_monitor HDMI-A-42 .disabled false
assert_monitor HDMI-A-42 .mirrorOf eDP-1
assert_monitor HDMI-A-42 .x 777
assert_monitor HDMI-A-42 .y 888
assert_monitor HDMI-A-42 .scale 1.75
assert_monitor HDMI-A-42 .transform 1
assert_log_contains 'eval hl.monitor({output="HDMI-A-42",disabled=false,mode="2560x1440@144",position="777x888",scale=1.75,transform=1,mirror="eDP-1"})'
assert_log_absent 'eval hl.monitor({output="HDMI-A-42",mirror="eDP-1"})'
assert_log_absent 'eval hl.monitor({output="HDMI-A-42",disabled=false,mode="2560x1440@144",position="-2560x-100",scale=1.5,transform=3,mirror="eDP-1"})'

# A different compositor session cannot consume the previous session cache.
clear_controls
write_state "$base_state"
set_fake_monitor_disabled HDMI-A-42 true
expect_status_session 0 other-session monitor set-enabled HDMI-A-42 true
assert_log_contains 'eval hl.monitor({output="HDMI-A-42",mode="preferred",position="auto",scale="auto",disabled=false,mirror=""})'

# Corrupt cache data is ignored rather than sent to the compositor.
clear_controls
write_state "$base_state"
set_fake_monitor_disabled HDMI-A-42 true
printf '%s\n' 'not json' >"$STATE_DIR/stale-session.json"
expect_status_session 0 stale-session monitor set-enabled HDMI-A-42 true
assert_log_contains 'eval hl.monitor({output="HDMI-A-42",mode="preferred",position="auto",scale="auto",disabled=false,mirror=""})'

# Generic calls serialize on a session lock.
clear_controls
write_state "$base_state"
set_fake_monitor_disabled HDMI-A-42 true
printf '%s\n' '0.5' >"$CONTROL_DIR/hang-query"
(run_action_session concurrent-session monitor set-enabled HDMI-A-42 true >"$test_root/concurrent-first.out" 2>&1) &
first_pid=$!
sleep 0.1
expect_status_session 1 concurrent-session monitor set-enabled HDMI-A-42 true
if ! wait "$first_pid"; then
  fail "serialized first call failed: $(<"$test_root/concurrent-first.out")"
fi
rm -f -- "$CONTROL_DIR/hang-query"
assert_monitor HDMI-A-42 .disabled false

# Every compositor IPC is bounded.
clear_controls
write_state "$base_state"
set_fake_monitor_disabled HDMI-A-42 true
printf '%s\n' '3' >"$CONTROL_DIR/hang-query"
export DESKTOP_MONITOR_LAYOUT_IPC_TIMEOUT_SECONDS=1
expect_status_session 1 timeout-session monitor set-enabled HDMI-A-42 true
unset DESKTOP_MONITOR_LAYOUT_IPC_TIMEOUT_SECONDS
rm -f -- "$CONTROL_DIR/hang-query"
assert_monitor HDMI-A-42 .disabled true

printf 'desktop monitor layout tests passed\n'
