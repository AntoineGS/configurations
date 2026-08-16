#!/usr/bin/env bash
set -Eeuo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../../.." && pwd)"
LAUNCHER="$ROOT/Linux/os/helpers/desktop-shell-launch"
TOGGLE_HELPER="$ROOT/Linux/os/helpers/toggle-desktop-shell-bar"
UNIT="$ROOT/Linux/quickshell/desktop-shell/systemd/desktop-shell.service"
CONFIG="$ROOT/tidydots.yaml"
AUTOSTART="$ROOT/Linux/hypr/autostart.lua"
BINDINGS="$ROOT/Linux/hypr/bindings/utilities.lua"
VICINAE_TOGGLE="$ROOT/Linux/vicinae/scripts/toggle-top-bar.sh"
WAYBAR_TOGGLE_HELPER="$ROOT/Linux/os/helpers/toggle-waybar"
TEST_ROOT=$(mktemp -d)
trap 'rm -rf "$TEST_ROOT"' EXIT HUP INT TERM

BIN="$TEST_ROOT/bin"
HOME_DIR="$TEST_ROOT/home"
SHELL_DIR="$HOME_DIR/.config/quickshell/desktop-shell"
ARGS_FILE="$TEST_ROOT/quickshell-args"
EXECUTED_FILE="$TEST_ROOT/quickshell-executed"

mkdir -p "$BIN" "$SHELL_DIR/config"

cat >"$BIN/quickshell" <<'EOF'
#!/usr/bin/env bash
set -Eeuo pipefail

printf '%s\n' "$@" >"$QUICKSHELL_ARGS_FILE"
: >"$QUICKSHELL_EXECUTED_FILE"
EOF
chmod +x "$BIN/quickshell"

fail() {
  printf 'FAIL: %s\n' "$1" >&2
  exit 1
}

assert_launcher_mapping() {
  awk '
    function check_entry() {
      if (target && entry_name && backup && file_count == 9 && has_launcher && has_toggle &&
          has_shell_action && has_connectivity_action && has_hardware_state && has_hardware_action &&
          has_usage_update && has_usage_codex && has_usage_claude && !has_cli && !has_status) {
        found = 1
      }
    }
    /^  - / {
      if (in_app) check_entry()
      in_app = 0
      next
    }
    /^    name: desktop-shell$/ {
      in_app = 1
      next
    }
    !in_app { next }
    /^      - / {
      check_entry()
      target = 0
      entry_name = 0
      backup = 0
      has_launcher = 0
      has_toggle = 0
      has_shell_action = 0
      has_connectivity_action = 0
      has_hardware_state = 0
      has_hardware_action = 0
      has_usage_update = 0
      has_usage_codex = 0
      has_usage_claude = 0
      has_cli = 0
      has_status = 0
      file_count = 0
      next
    }
    $0 == "          linux: ~/.local/share/helpers" { target = 1 }
    $0 == "        name: desktop-shell-service-helpers" { entry_name = 1 }
    $0 == "        backup: ./Linux/os/helpers" { backup = 1 }
    /^          - / {
      file_count++
    }
    $0 == "          - desktop-shell-launch" { has_launcher = 1 }
    $0 == "          - toggle-desktop-shell-bar" { has_toggle = 1 }
    $0 == "          - desktop-shell-action" { has_shell_action = 1 }
    $0 == "          - desktop-connectivity-action" { has_connectivity_action = 1 }
    $0 == "          - desktop-hardware-state" { has_hardware_state = 1 }
    $0 == "          - desktop-hardware-action" { has_hardware_action = 1 }
    $0 == "          - desktop-agent-usage-update" { has_usage_update = 1 }
    $0 == "          - desktop-agent-usage-codex" { has_usage_codex = 1 }
    $0 == "          - desktop-agent-usage-claude" { has_usage_claude = 1 }
    $0 == "          - desktop-shell" { has_cli = 1 }
    $0 == "          - desktop-shell-status" { has_status = 1 }
    END {
      if (in_app) check_entry()
      exit !found
    }
  ' "$CONFIG" || fail 'desktop-shell helper mapping is missing or incorrect'
}

assert_binding() {
  local key=$1
  local command=$2
  local description=$3
  local label=$4

  awk -v key="$key" -v command="$command" -v description="$description" '
    index($0, "\"" key "\"") { in_binding = 1 }
    in_binding && index($0, command) { command_found = 1 }
    in_binding && index($0, description) { description_found = 1 }
    in_binding && $0 ~ /^[[:space:]]*hl[.]bind[(]/ && index($0, "\"" key "\"") == 0 { exit }
    END { exit !(in_binding && command_found && description_found) }
  ' "$BINDINGS" || fail "$label"
}

run_launcher() {
  local helper=$1
  shift
  PATH="$BIN:$PATH" HOME="$HOME_DIR" QUICKSHELL_ARGS_FILE="$ARGS_FILE" \
    QUICKSHELL_EXECUTED_FILE="$EXECUTED_FILE" "$helper" "$@"
}

expect_launcher_failure() {
  local label=$1
  shift
  local status=0

  rm -f "$ARGS_FILE" "$EXECUTED_FILE"
  run_launcher "$@" >/dev/null 2>&1 || status=$?
  ((status != 0)) || fail "$label unexpectedly succeeded"
  [[ ! -e $EXECUTED_FILE ]] || fail "$label executed quickshell"
}

expect_launcher_failure 'missing shell.qml' "$LAUNCHER"

printf '%s\n' '// test shell' >"$SHELL_DIR/shell.qml"
expect_launcher_failure 'missing config/shell.json' "$LAUNCHER"

printf '%s\n' '{}' >"$SHELL_DIR/config/shell.json"
expect_launcher_failure 'launcher arguments' "$LAUNCHER" unexpected

rm -f "$ARGS_FILE" "$EXECUTED_FILE"
run_launcher "$LAUNCHER" || fail 'launcher failed with readable shell and config files'
[[ -e $EXECUTED_FILE ]] || fail 'launcher did not execute quickshell'

expected_args=$(printf '%s\n' '-n' '-p' "$SHELL_DIR")
[[ -f $ARGS_FILE ]] || fail 'mock quickshell did not receive arguments'
[[ $(<"$ARGS_FILE") == "$expected_args" ]] || {
  printf 'expected argv:\n%s\nactual argv:\n%s\n' "$expected_args" "$(<"$ARGS_FILE")" >&2
  exit 1
}

rm -f "$ARGS_FILE" "$EXECUTED_FILE"
run_launcher "$TOGGLE_HELPER" || fail 'toggle helper failed'
[[ -e $EXECUTED_FILE ]] || fail 'toggle helper did not execute quickshell'
expected_args=$(printf '%s\n' 'ipc' '--any-display' '-p' "$SHELL_DIR" 'call' 'desktop-shell' 'toggleBar')
[[ $(<"$ARGS_FILE") == "$expected_args" ]] || {
  printf 'expected toggle argv:\n%s\nactual argv:\n%s\n' "$expected_args" "$(<"$ARGS_FILE")" >&2
  exit 1
}

rm -f "$ARGS_FILE" "$EXECUTED_FILE"
toggle_status=0
run_launcher "$TOGGLE_HELPER" unexpected >/dev/null 2>&1 || toggle_status=$?
((toggle_status != 0)) || fail 'toggle helper accepted an argument'
[[ ! -e $EXECUTED_FILE ]] || fail 'toggle helper executed quickshell after receiving an argument'

[[ -f $UNIT ]] || fail 'desktop-shell.service is absent'
grep -Fqx 'ExecStart=%h/.local/share/helpers/desktop-shell-launch' "$UNIT" || \
  fail 'unit does not use the repository launcher path'
grep -Fqx 'PartOf=graphical-session.target' "$UNIT" || fail 'unit is not part of graphical-session.target'
if grep -Fqx 'After=graphical-session.target' "$UNIT"; then
  fail 'unit orders after graphical-session.target and may create a cycle'
fi
grep -Fqx 'Restart=on-failure' "$UNIT" || fail 'unit does not restart on failure'
grep -Fqx 'WantedBy=graphical-session.target' "$UNIT" || \
  fail 'unit is not wanted by graphical-session.target'

[[ -f $CONFIG ]] || fail 'tidydots.yaml is absent'
grep -Fq 'systemctl --user is-enabled --quiet desktop-shell.service &&' "$CONFIG" || \
  fail 'tidydots check does not require the service to be enabled'
grep -Fq 'systemctl --user is-active --quiet desktop-shell.service &&' "$CONFIG" || \
  fail 'tidydots check does not require the service to be active'
grep -Fq "test \"\$(systemctl --user show desktop-shell.service --property=NeedDaemonReload --value)\" = no" "$CONFIG" || \
  fail 'tidydots check does not require NeedDaemonReload=no'
grep -Fq 'systemctl --user daemon-reload && systemctl --user enable --now desktop-shell.service' "$CONFIG" || \
  fail 'tidydots repair command changed'
assert_launcher_mapping

for active_route in "$AUTOSTART" "$BINDINGS" "$VICINAE_TOGGLE"; do
  [[ -f $active_route ]] || fail "active route is absent: $active_route"
  for forbidden_route in 'uwsm-app -- waybar' 'pkill waybar' 'toggle-waybar'; do
    if grep -Fq "$forbidden_route" "$active_route"; then
      fail "$forbidden_route remains in $active_route"
    fi
  done
done

grep -Fq 'hl.exec_cmd("uwsm-app -- hypridle")' "$AUTOSTART" || fail 'Hypridle autostart was removed'
grep -Fq 'hl.exec_cmd("uwsm-app -- mako")' "$AUTOSTART" || fail 'Mako autostart was removed'
grep -Fq 'hl.exec_cmd("uwsm-app -- swayosd-server")' "$AUTOSTART" || fail 'SwayOSD autostart was removed'
grep -Fq 'hl.exec_cmd("/usr/lib/polkit-gnome/polkit-gnome-authentication-agent-1")' "$AUTOSTART" || \
  fail 'polkit-gnome autostart was removed'
assert_binding 'SUPER + CTRL + W' 'systemctl --user restart desktop-shell.service' 'Reload top bar' \
  'top bar reload binding does not restart desktop-shell.service'
assert_binding 'SUPER + SHIFT + SPACE' 'toggle-desktop-shell-bar' 'Toggle top bar' \
  'top bar toggle binding does not use toggle-desktop-shell-bar'
grep -Fq 'toggle-desktop-shell-bar' "$VICINAE_TOGGLE" || fail 'Vicinae top bar action does not use toggle-desktop-shell-bar'
[[ ! -e $WAYBAR_TOGGLE_HELPER ]] || fail 'toggle-waybar helper still exists'

printf '%s\n' 'service launcher and unit contract passed'
