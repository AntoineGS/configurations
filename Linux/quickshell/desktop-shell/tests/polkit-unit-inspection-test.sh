#!/usr/bin/env bash
set -Eeuo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../../.." && pwd)"
HELPER="$ROOT/Linux/quickshell/desktop-shell/tests/polkit-runtime-unit.sh"
fixture=$(mktemp -d)
trap 'rm -rf -- "$fixture"' EXIT

fake_bin="$fixture/bin"
output="$fixture/unit.snapshot"
mkdir -p -- "$fake_bin" "$fixture/empty-bin"

unit_properties='LoadState,ActiveState,SubState,UnitFileState,MainPID,ExecMainStartTimestamp,ExecMainStartTimestampMonotonic,ActiveEnterTimestamp,ActiveEnterTimestampMonotonic,FragmentPath,Result,NeedDaemonReload'
export unit_properties

cat >"$fake_bin/systemctl" <<'FAKE_SYSTEMCTL'
#!/usr/bin/env bash
set -Eeuo pipefail

print_snapshot() {
  local load_state=$1
  local active_state=$2
  local main_pid=$3
  local include_reload=${4:-1}

  printf '%s\n' \
    "LoadState=$load_state" \
    "ActiveState=$active_state" \
    'SubState=running' \
    'UnitFileState=enabled' \
    "MainPID=$main_pid" \
    'ExecMainStartTimestamp=' \
    'ExecMainStartTimestampMonotonic=' \
    'ActiveEnterTimestamp=' \
    'ActiveEnterTimestampMonotonic=' \
    'FragmentPath=/home/test/.config/systemd/user/desktop-shell.service' \
    'Result='
  if ((include_reload)); then
    printf '%s\n' 'NeedDaemonReload=no'
  fi
}

case ${POLKIT_FAKE_SYSTEMCTL_MODE:?} in
  absent)
    if [[ $* == *--value* ]]; then
      printf '%s\n' not-found
    else
      printf '%s\n' LoadState=not-found
    fi
    ;;
  loaded)
    if [[ $* == *--value* ]]; then
      printf '%s\n' loaded
    else
      print_snapshot loaded active 123
    fi
    ;;
  masked)
    if [[ $* == *--value* ]]; then
      printf '%s\n' masked
    else
      print_snapshot masked inactive 0
    fi
    ;;
  partial)
    if [[ $* == *--value* ]]; then
      printf '%s\n' loaded
    else
      print_snapshot loaded active 123 0
    fi
    ;;
  duplicate)
    if [[ $* == *--value* ]]; then
      printf '%s\n' loaded
    else
      print_snapshot loaded active 123
      printf '%s\n' 'ActiveState=active'
    fi
    ;;
  mismatched)
    if [[ $* == *--value* ]]; then
      printf '%s\n' loaded
    else
      print_snapshot masked inactive 0
    fi
    ;;
  malformed)
    if [[ $* == *--value* ]]; then
      printf '%s\n' loaded
    else
      printf '%s\n' ActiveState=active
    fi
    ;;
  error)
    printf '%s\n' 'user manager unavailable' >&2
    exit 1
    ;;
  full-error)
    if [[ $* == *--value* ]]; then
      printf '%s\n' loaded
    else
      printf '%s\n' 'unit detail unavailable' >&2
      exit 1
    fi
    ;;
  *)
    printf 'unknown fake mode: %s\n' "$POLKIT_FAKE_SYSTEMCTL_MODE" >&2
    exit 2
    ;;
esac
FAKE_SYSTEMCTL
chmod +x "$fake_bin/systemctl"

# shellcheck disable=SC1090
source "$HELPER"

run_snapshot() {
  local mode=$1
  local expected_status=$2
  local expected_presence=$3
  local status=0

  rm -f -- "$output"
  export live_xdg_runtime_dir="$fixture/runtime"
  export live_dbus_address="unix:path=$fixture/bus"
  PATH="$fake_bin:$PATH" POLKIT_FAKE_SYSTEMCTL_MODE="$mode" \
    polkit_snapshot_unit "$output" || status=$?
  [[ $status == "$expected_status" ]] || {
    printf 'FAIL: mode %s returned %s, expected %s\n' "$mode" "$status" "$expected_status" >&2
    return 1
  }
  if [[ $expected_presence == present ]]; then
    [[ -s $output ]] || {
      printf 'FAIL: mode %s did not write a unit snapshot\n' "$mode" >&2
      return 1
    }
  else
    [[ ! -e $output ]] || {
      printf 'FAIL: mode %s wrote a snapshot for an absent/error unit\n' "$mode" >&2
      return 1
    }
  fi
}

run_snapshot absent "$POLKIT_UNIT_ABSENT_STATUS" absent
run_snapshot loaded 0 present
grep -Fqx 'LoadState=loaded' "$output"
run_snapshot masked 0 present
grep -Fqx 'LoadState=masked' "$output"
run_snapshot partial "$POLKIT_UNIT_INSPECTION_FAILED_STATUS" absent
run_snapshot duplicate "$POLKIT_UNIT_INSPECTION_FAILED_STATUS" absent
run_snapshot mismatched "$POLKIT_UNIT_INSPECTION_FAILED_STATUS" absent
run_snapshot malformed "$POLKIT_UNIT_INSPECTION_FAILED_STATUS" absent
run_snapshot error "$POLKIT_UNIT_INSPECTION_FAILED_STATUS" absent
run_snapshot full-error "$POLKIT_UNIT_INSPECTION_FAILED_STATUS" absent

rm -f -- "$output"
export live_xdg_runtime_dir=''
export live_dbus_address=''
status=0
PATH="$fake_bin:$PATH" POLKIT_FAKE_SYSTEMCTL_MODE=loaded \
  polkit_snapshot_unit "$output" || status=$?
[[ $status == "$POLKIT_UNIT_INSPECTION_FAILED_STATUS" ]]
[[ ! -e $output ]]

printf 'PASS: unit LoadState=not-found is absent; inspection errors fail closed\n'
