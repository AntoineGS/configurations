#!/usr/bin/env bash
set -Eeuo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../../.." && pwd)"
HELPER="$ROOT/Linux/quickshell/desktop-shell/tests/polkit-runtime-unit.sh"
fixture=$(mktemp -d)
trap 'rm -rf -- "$fixture"' EXIT

fake_bin="$fixture/bin"
output="$fixture/unit.snapshot"
mkdir -p -- "$fake_bin" "$fixture/empty-bin"

cat >"$fake_bin/systemctl" <<'FAKE_SYSTEMCTL'
#!/usr/bin/env bash
set -Eeuo pipefail

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
      printf '%s\n' LoadState=loaded ActiveState=active MainPID=123
    fi
    ;;
  masked)
    if [[ $* == *--value* ]]; then
      printf '%s\n' masked
    else
      printf '%s\n' LoadState=masked ActiveState=inactive MainPID=0
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
