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
ROLLBACK_HELPER="$ROOT/Linux/os/helpers/desktop-shell-rollback"
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
      if (target && entry_name && backup && !files) {
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
      files = 0
      next
    }
    $0 == "          linux: ~/.local/share/helpers" { target = 1 }
    $0 == "        name: desktop-shell-helpers" { entry_name = 1 }
    $0 == "        backup: ./Linux/os/helpers" { backup = 1 }
    $0 == "        files:" { files = 1 }
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
run_launcher "$ROOT/Linux/os/helpers/desktop-shell" --pid 4242 ping || fail 'PID-bound helper failed'
[[ -e $EXECUTED_FILE ]] || fail 'PID-bound helper did not execute quickshell'
expected_args=$(printf '%s\n' 'ipc' '--pid' '4242' '-p' "$SHELL_DIR" 'call' '--' 'desktop-shell' 'ping')
[[ $(<"$ARGS_FILE") == "$expected_args" ]] || {
  printf 'expected PID-bound argv:\n%s\nactual argv:\n%s\n' "$expected_args" "$(<"$ARGS_FILE")" >&2
  exit 1
}

for invalid_pid in 0 -1 01 abc; do
  rm -f "$ARGS_FILE" "$EXECUTED_FILE"
  invalid_status=0
  run_launcher "$ROOT/Linux/os/helpers/desktop-shell" --pid "$invalid_pid" ping >/dev/null 2>&1 || invalid_status=$?
  ((invalid_status == 2)) || fail "invalid PID was accepted: $invalid_pid"
  [[ ! -e $EXECUTED_FILE ]] || fail "invalid PID executed quickshell: $invalid_pid"
done

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
grep -Fqx 'Environment=DESKTOP_SHELL_NOTIFICATIONS_REGISTER=1' "$UNIT" || \
  fail 'unit does not explicitly enable notification registration'
grep -Fqx 'Environment=DESKTOP_SHELL_POLKIT_REGISTER=1' "$UNIT" || \
  fail 'unit does not explicitly enable polkit registration'
grep -Fqx 'Restart=on-failure' "$UNIT" || fail 'unit does not restart on failure'
grep -Fqx 'WantedBy=graphical-session.target' "$UNIT" || \
  fail 'unit is not wanted by graphical-session.target'

[[ -f $CONFIG ]] || fail 'tidydots.yaml is absent'
grep -Fq 'systemctl --user is-enabled --quiet desktop-shell.service &&' "$CONFIG" || \
  fail 'tidydots check does not require the service to be enabled'
grep -Fq "test \"\$(systemctl --user show desktop-shell.service --property=NeedDaemonReload --value)\" = no" "$CONFIG" || \
  fail 'tidydots check does not require NeedDaemonReload=no'
grep -Fq 'systemctl --user stop desktop-shell.service && systemctl --user daemon-reload && systemctl --user enable desktop-shell.service' "$CONFIG" || \
  fail 'tidydots repair command does not stop before reloading and enabling'
if grep -Eq 'systemctl --user (start|restart|try-restart) desktop-shell\.service|--now desktop-shell\.service' "$CONFIG"; then
  fail 'tidydots setup starts or restarts desktop-shell.service'
fi
assert_launcher_mapping

[[ -x "$ROLLBACK_HELPER" ]] || fail 'desktop-shell rollback helper is absent or not executable'
rollback_source=$(<"$ROLLBACK_HELPER")
grep -Fq -- "readonly MAKO_INPUT=\"\${DESKTOP_SHELL_MAKO:-/usr/bin/mako}\"" <<<"$rollback_source" || \
  fail 'rollback Mako default path changed'
grep -Fq -- "readonly SWAYOSD_SERVER_INPUT=\"\${DESKTOP_SHELL_SWAYOSD_SERVER:-/usr/bin/swayosd-server}\"" <<<"$rollback_source" || \
  fail 'rollback SwayOSD default path changed'
grep -Fq -- 'query_exact_pids' <<<"$rollback_source" || \
  fail 'rollback does not use exact process identity lookup'
if grep -Fq -- 'pkill' <<<"$rollback_source"; then
  fail 'rollback contains broad process termination'
fi

for active_route in "$AUTOSTART" "$BINDINGS" "$VICINAE_TOGGLE"; do
  [[ -f $active_route ]] || fail "active route is absent: $active_route"
  for forbidden_route in 'uwsm-app -- waybar' 'pkill waybar' 'toggle-waybar'; do
    if grep -Fq "$forbidden_route" "$active_route"; then
      fail "$forbidden_route remains in $active_route"
    fi
  done
done

grep -Fq 'hl.exec_cmd("uwsm-app -- hypridle")' "$AUTOSTART" || fail 'Hypridle autostart was removed'
legacy_autostart_found=0
for legacy_autostart in \
  'hl.exec_cmd("uwsm-app -- mako")' \
  'hl.exec_cmd("uwsm-app -- swayosd-server")' \
  'hl.exec_cmd("/usr/lib/polkit-gnome/polkit-gnome-authentication-agent-1")'; do
  if grep -Fq -- "$legacy_autostart" "$AUTOSTART"; then
    printf 'FAIL: legacy desktop-service autostart remains in %s: %s\n' "$AUTOSTART" "$legacy_autostart" >&2
    legacy_autostart_found=1
  fi
done
if ((legacy_autostart_found)); then
  exit 1
fi
assert_binding 'SUPER + CTRL + W' 'desktop-shell-activate' 'Reload top bar' \
  'top bar reload binding does not use desktop-shell-activate'
assert_binding 'SUPER + SHIFT + SPACE' 'toggle-desktop-shell-bar' 'Toggle top bar' \
  'top bar toggle binding does not use toggle-desktop-shell-bar'
grep -Fq 'toggle-desktop-shell-bar' "$VICINAE_TOGGLE" || fail 'Vicinae top bar action does not use toggle-desktop-shell-bar'
[[ ! -e $WAYBAR_TOGGLE_HELPER ]] || fail 'toggle-waybar helper still exists'

printf '%s\n' 'service launcher and unit contract passed'
