#!/usr/bin/env bash
set -Eeuo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../../.." && pwd)"
ACTION="$ROOT/Linux/os/helpers/desktop-shell-action"

if [[ ! -x $ACTION ]]; then
  printf 'menu-action-test: missing executable desktop-shell-action (expected RED)\n' >&2
  exit 1
fi

fixture=$(mktemp -d)
trap 'rm -rf "$fixture"' EXIT
fake_bin="$fixture/bin"
trace="$fixture/trace"
mkdir -p "$fake_bin"

make_fake() {
  local name=$1
  printf '%s\n' \
    '#!/usr/bin/env bash' \
    "if [[ \${DESKTOP_SHELL_ACTION_FAIL:-0} == 1 ]]; then exit 7; fi" \
    "printf \"%s\\\\0\" \"\${0##*/}\" \"\$@\" >>\"\$DESKTOP_SHELL_ACTION_TRACE\"" \
    >"$fake_bin/$name"
  chmod +x "$fake_bin/$name"
}

for command_name in \
  cmd-screenshot cmd-screenrecord cmd-share hyprpicker desktop-shell launch-tui-large setup-dns setup-fingerprint \
  pkg-install pkg-aur-install pkg-remove update restart-pipewire restart-wifi restart-bluetooth \
  systemctl lock-screen system-logout system-reboot system-shutdown; do
  make_fake "$command_name"
done

run_action() {
  : >"$trace"
  PATH="$fake_bin:$PATH" DESKTOP_SHELL_ACTION_TRACE="$trace" "$ACTION" "$@"
}

assert_trace() {
  local label=$1
  shift
  local -a expected=("$@")
  local -a actual=()
  mapfile -d '' -t actual <"$trace" || true
  if ((${#actual[@]} != ${#expected[@]})); then
    printf 'menu-action-test: %s: expected %d argv values, got %d\n' "$label" "${#expected[@]}" "${#actual[@]}" >&2
    exit 1
  fi
  for ((i = 0; i < ${#expected[@]}; i++)); do
    if [[ ${actual[i]} != "${expected[i]}" ]]; then
      printf 'menu-action-test: %s: argv[%d]=%q, want %q\n' "$label" "$i" "${actual[i]}" "${expected[i]}" >&2
      exit 1
    fi
  done
}

assert_action() {
  local id=$1
  shift
  run_action "$id"
  assert_trace "$id" "$@"
}

assert_action trigger.screenshot cmd-screenshot
assert_action trigger.screenrecord cmd-screenrecord
assert_action trigger.color hyprpicker -a
assert_action trigger.share-clipboard cmd-share clipboard
assert_action trigger.share-file launch-tui-large cmd-share file
assert_action trigger.share-folder launch-tui-large cmd-share folder

assert_action setup.audio desktop-shell summon desktop.audio '{}'
assert_action setup.wifi desktop-shell summon desktop.network '{}'
assert_action setup.bluetooth desktop-shell summon desktop.bluetooth '{}'
assert_action setup.power-profile desktop-shell summon desktop.power '{}'
assert_action setup.monitors desktop-shell summon desktop.monitor '{}'
assert_action setup.dns launch-tui-large setup-dns
assert_action setup.security launch-tui-large setup-fingerprint
assert_action setup.shell-config desktop-shell health

assert_action install.package launch-tui-large pkg-install
assert_action install.aur launch-tui-large pkg-aur-install
assert_action remove.package launch-tui-large pkg-remove

assert_action update.system launch-tui-large update
assert_action update.audio restart-pipewire
assert_action update.wifi restart-wifi
assert_action update.bluetooth restart-bluetooth
assert_action update.shell-restart systemctl --user restart desktop-shell.service
assert_action update.shell-reload desktop-shell reload-config

assert_action system.lock lock-screen
assert_action system.suspend systemctl suspend
assert_action system.hibernate systemctl hibernate
assert_action system.logout system-logout
assert_action system.reboot system-reboot
assert_action system.shutdown system-shutdown

: >"$trace"
set +e
PATH="$fake_bin:$PATH" DESKTOP_SHELL_ACTION_TRACE="$trace" DESKTOP_SHELL_ACTION_FAIL=1 "$ACTION" trigger.screenshot
runtime_status=$?
set -e
if ((runtime_status != 1)); then
  printf 'menu-action-test: runtime failure returned %d instead of 1\n' "$runtime_status" >&2
  exit 1
fi

assert_invalid() {
  local label=$1
  shift
  : >"$trace"
  set +e
  PATH="$fake_bin:$PATH" DESKTOP_SHELL_ACTION_TRACE="$trace" "$ACTION" "$@"
  local status=$?
  set -e
  if ((status != 2)); then
    printf 'menu-action-test: %s: expected exit 2, got %d\n' "$label" "$status" >&2
    exit 1
  fi
  if [[ -s $trace ]]; then
    printf 'menu-action-test: %s executed a command\n' "$label" >&2
    exit 1
  fi
}

assert_invalid unknown-action unknown.action
assert_invalid spaced-action 'trigger screenshot'
assert_invalid metacharacter-action 'trigger.screenshot;touch /tmp/menu-action-test'
assert_invalid extra-argument trigger.screenshot unexpected

printf 'menu-action-test: strict allow-list, fixed argv, and 0/1/2 dispatch verified\n'
