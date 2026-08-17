#!/usr/bin/env bash
# shellcheck disable=SC2317 # Cleanup functions are invoked through EXIT traps.
set -Eeuo pipefail

SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
ADAPTER="$SCRIPT_DIR/../../../os/helpers/desktop-shell-mako-route"
ADAPTER_UNIT="$SCRIPT_DIR/../systemd/desktop-shell-mako-route.service"
SHELL_UNIT="$SCRIPT_DIR/../systemd/desktop-shell.service"
TIDYDOTS="$SCRIPT_DIR/../../../../tidydots.yaml"

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

assert_contains() {
  local haystack=$1
  local needle=$2
  local message=$3

  [[ $haystack == *"$needle"* ]] || fail "$message: missing '$needle'"
}

assert_not_contains() {
  local haystack=$1
  local needle=$2
  local message=$3

  [[ $haystack != *"$needle"* ]] || fail "$message: found '$needle'"
}

assert_file_mode() {
  local expected=$1
  local path=$2
  local actual

  [[ -e $path ]] || fail "missing path for mode assertion: $path"
  actual=$(stat -c '%a' -- "$path") || fail "could not inspect mode for $path"
  assert_equal "${expected#0}" "${actual#0}" "mode for $path"
}

assert_route_modes() {
  local expected=$1
  local actual

  actual=$(<"$MAKO_MODE_STATE")
  assert_equal "$expected" "$actual" 'Mako mode state'
}

assert_cue() {
  local expected=$1
  local actual

  [[ -f $CUE_FILE ]] || fail "missing cue file: $CUE_FILE"
  actual=$(<"$CUE_FILE")
  assert_equal "$expected" "$actual" 'cue contents'
  assert_file_mode 0600 "$CUE_FILE"
}

assert_no_cue() {
  [[ ! -e $CUE_FILE && ! -L $CUE_FILE ]] || fail "unexpected cue file: $CUE_FILE"
}

log_count() {
  wc -l <"$MAKOCTL_LOG"
}

last_mako_call() {
  local lines=()
  mapfile -t lines <"$MAKOCTL_LOG"
  [[ ${#lines[@]} -gt 0 ]] || fail 'expected at least one makoctl call'
  printf '%s' "${lines[${#lines[@]} - 1]}"
}

wait_for_log_count() {
  local expected=$1
  local deadline=$((SECONDS + 3))
  local actual

  while ((SECONDS < deadline)); do
    actual=$(log_count)
    [[ $actual -ge $expected ]] && return 0
    /usr/bin/sleep 0.01
  done

  fail "timed out waiting for $expected Mako calls; got $(log_count)"
}

assert_no_new_mako_call() {
  local expected=$1

  /usr/bin/sleep 0.08
  assert_equal "$expected" "$(log_count)" 'unchanged route did not call makoctl'
}

assert_last_call() {
  local expected=$1

  assert_equal "$expected" "$(last_mako_call)" 'makoctl mode arguments'
}

assert_atomic_cue_rename() {
  local log

  log=$(<"$MV_LOG")
  [[ $log == *"rustdesk-notification-cue."*" $CUE_FILE"* ]] || \
    fail 'cue file was not replaced with an atomic temporary-file rename'
  [[ $log != *"> $CUE_FILE"* ]] || fail 'cue file was written through shell redirection'
}

write_route() {
  local visible=$1
  local output=$2
  local cue_output=$3
  local direction=$4
  local updated_at=$5
  local temporary_file

  temporary_file=$(mktemp "$ROUTE_DIR/.test-notification-route.XXXXXX")
  jq -cn \
    --argjson visible "$visible" \
    --arg output "$output" \
    --arg cue_output "$cue_output" \
    --arg direction "$direction" \
    --argjson updated_at "$updated_at" \
    '{version: 1, visible: $visible,
      output: (if $output == "null" then null else $output end),
      cueOutput: (if $cue_output == "null" then null else $cue_output end),
      direction: (if $direction == "null" then null else $direction end),
      updatedAt: $updated_at}' >"$temporary_file"
  chmod 0600 -- "$temporary_file"
  mv -f -- "$temporary_file" "$ROUTE_FILE"
}

write_raw_route() {
  local content=$1
  local temporary_file

  temporary_file=$(mktemp "$ROUTE_DIR/.test-notification-route.XXXXXX")
  printf '%s\n' "$content" >"$temporary_file"
  chmod 0600 -- "$temporary_file"
  mv -f -- "$temporary_file" "$ROUTE_FILE"
}

force_visible_route() {
  local expected_count=$1

  write_route true DVI-D-1 null null "$FAKE_NOW"
  wait_for_log_count "$expected_count"
  assert_route_modes 'unrelated-mode rustdesk-route-DVI-D-1'
  assert_no_cue
}

expect_hidden_for_raw_route() {
  local content=$1
  local expected_count=$2

  force_visible_route "$((expected_count - 1))"
  write_raw_route "$content"
  wait_for_log_count "$expected_count"
  assert_route_modes 'unrelated-mode rustdesk-route-hidden'
  assert_no_cue
}

kill_descendants() {
  local root=$1
  local child
  local children=()

  mapfile -t children < <(pgrep -P "$root" 2>/dev/null || true)
  for child in "${children[@]}"; do
    kill_descendants "$child"
    kill -TERM "$child" 2>/dev/null || true
  done
}

cleanup_adapter() {
  local status=0

  if [[ -n ${adapter_pid:-} ]] && kill -0 "$adapter_pid" 2>/dev/null; then
    kill_descendants "$adapter_pid"
    kill -TERM "$adapter_pid" 2>/dev/null || true
    wait "$adapter_pid" || status=$?
    [[ $status -ne 0 ]] || true
  fi
  adapter_pid=""
}

cleanup() {
  cleanup_adapter
  rm -rf -- "$TEST_RUNTIME_DIR"
}

[[ -f $ADAPTER ]] || fail "adapter helper is missing: $ADAPTER"
[[ -f $ADAPTER_UNIT ]] || fail "adapter unit is missing: $ADAPTER_UNIT"

adapter_unit_text=$(<"$ADAPTER_UNIT")
shell_unit_text=$(<"$SHELL_UNIT")
tidydots_text=$(<"$TIDYDOTS")

assert_contains "$adapter_unit_text" 'Description=Rollback Mako adapter for desktop-shell notification routes' \
  'adapter unit description'
assert_contains "$adapter_unit_text" 'PartOf=graphical-session.target' 'adapter unit session relationship'
assert_contains "$adapter_unit_text" 'Conflicts=desktop-shell.service' 'adapter unit conflict'
assert_contains "$adapter_unit_text" 'Type=simple' 'adapter unit type'
assert_contains "$adapter_unit_text" 'ExecStart=%h/.local/share/helpers/desktop-shell-mako-route' \
  'adapter unit executable'
assert_contains "$adapter_unit_text" 'Restart=on-failure' 'adapter unit restart policy'
assert_contains "$adapter_unit_text" 'RestartSec=2' 'adapter unit restart delay'
assert_not_contains "$adapter_unit_text" '[Install]' 'adapter unit must remain dormant'
assert_not_contains "$adapter_unit_text" 'WantedBy=' 'adapter unit must not be enabled'
assert_contains "$shell_unit_text" 'Conflicts=desktop-shell-mako-route.service' 'desktop shell conflict'
assert_contains "$tidydots_text" '          - desktop-shell.service' 'tidydots maps desktop shell service'
assert_contains "$tidydots_text" '          - desktop-shell-mako-route.service' 'tidydots maps adapter service'
assert_not_contains "$tidydots_text" 'is-enabled --quiet desktop-shell-mako-route.service' \
  'tidydots must not enable the adapter'
assert_not_contains "$tidydots_text" 'enable --now desktop-shell-mako-route.service' \
  'tidydots must not start the adapter'

TEST_RUNTIME_DIR=$(mktemp -d)
TEST_BIN="$TEST_RUNTIME_DIR/bin"
ROUTE_DIR="$TEST_RUNTIME_DIR/desktop-shell"
ROUTE_FILE="$ROUTE_DIR/notification-route.json"
CUE_FILE="$TEST_RUNTIME_DIR/rustdesk-notification-cue"
MAKOCTL_LOG="$TEST_RUNTIME_DIR/makoctl.log"
MAKO_MODE_STATE="$TEST_RUNTIME_DIR/mako-modes"
MAKO_ALIVE_FILE="$TEST_RUNTIME_DIR/mako-alive"
MV_LOG="$TEST_RUNTIME_DIR/mv.log"
ADAPTER_STDOUT="$TEST_RUNTIME_DIR/adapter.stdout"
ADAPTER_STDERR="$TEST_RUNTIME_DIR/adapter.stderr"
FAKE_NOW=1786930000
adapter_pid=""

mkdir -p -- "$TEST_BIN" "$ROUTE_DIR"
chmod 0700 -- "$ROUTE_DIR"
: >"$MAKOCTL_LOG"
: >"$MV_LOG"
printf '%s\n' 'unrelated-mode rustdesk-route-DVI-D-1 rustdesk-route-HDMI-A-1 rustdesk-route-DP-2 rustdesk-route-hidden rustdesk-cue' \
  >"$MAKO_MODE_STATE"
: >"$MAKO_ALIVE_FILE"

cat >"$TEST_BIN/makoctl" <<'EOF'
#!/usr/bin/env bash
set -Eeuo pipefail

[[ ${1:-} == mode ]] || {
  printf 'unexpected makoctl command: %s\n' "$*" >&2
  exit 125
}
shift

printf 'mode' >>"${MAKOCTL_LOG:?}"
for argument in "$@"; do
  printf '|%s' "$argument" >>"${MAKOCTL_LOG:?}"
done
printf '\n' >>"${MAKOCTL_LOG:?}"

state=$(<"${MAKO_MODE_STATE:?}")
while (($# > 0)); do
  case $1 in
    -r|-a)
      [[ $# -ge 2 ]] || exit 125
      mode=$2
      read -r -a modes <<<"$state"
      next=()
      for existing in "${modes[@]}"; do
        [[ $existing == "$mode" && $1 == -r ]] && continue
        next+=("$existing")
      done
      state="${next[*]}"
      [[ $1 == -a ]] || {
        shift 2
        continue
      }
      read -r -a modes <<<"$state"
      present=false
      for existing in "${modes[@]}"; do
        [[ $existing == "$mode" ]] && present=true
      done
      [[ $present == true ]] || state="$state $mode"
      ;;
    *)
      printf 'unexpected makoctl mode argument: %s\n' "$1" >&2
      exit 125
      ;;
  esac
  shift 2
done

printf '%s\n' "$state" >"${MAKO_MODE_STATE:?}"
EOF

cat >"$TEST_BIN/date" <<'EOF'
#!/usr/bin/env bash
set -Eeuo pipefail

[[ ${1:-} == +%s ]] || exit 125
printf '%s\n' "${FAKE_NOW:?}"
EOF

cat >"$TEST_BIN/sleep" <<'EOF'
#!/usr/bin/env bash
set -Eeuo pipefail

/usr/bin/sleep "${1:-0.01}"
EOF

cat >"$TEST_BIN/mv" <<'EOF'
#!/usr/bin/env bash
set -Eeuo pipefail

printf '%s\n' "$*" >>"${MV_LOG:?}"
exec /usr/bin/mv "$@"
EOF

for forbidden_command in systemctl pkill killall mako swayosd-server; do
  cat >"$TEST_BIN/$forbidden_command" <<EOF
#!/usr/bin/env bash
printf 'forbidden command invoked: %s %s\n' '$forbidden_command' "\$*" >&2
exit 125
EOF
done

chmod 0700 -- "$TEST_BIN"/*
export XDG_RUNTIME_DIR="$TEST_RUNTIME_DIR"
export PATH="$TEST_BIN:/usr/bin:/bin"
export MAKOCTL_LOG MAKO_MODE_STATE MAKO_ALIVE_FILE MV_LOG FAKE_NOW POLL_INTERVAL=0.01
export ROUTE_FILE CUE_FILE
trap cleanup EXIT

bash "$ADAPTER" >"$ADAPTER_STDOUT" 2>"$ADAPTER_STDERR" &
adapter_pid=$!

wait_for_log_count 1
assert_last_call 'mode|-r|rustdesk-route-DVI-D-1|-r|rustdesk-route-HDMI-A-1|-r|rustdesk-route-DP-2|-r|rustdesk-route-hidden|-r|rustdesk-cue|-a|rustdesk-route-hidden'
assert_route_modes 'unrelated-mode rustdesk-route-hidden'
assert_no_cue

write_route true DVI-D-1 null null "$FAKE_NOW"
wait_for_log_count 2
assert_last_call 'mode|-r|rustdesk-route-DVI-D-1|-r|rustdesk-route-HDMI-A-1|-r|rustdesk-route-DP-2|-r|rustdesk-route-hidden|-r|rustdesk-cue|-a|rustdesk-route-DVI-D-1'
assert_route_modes 'unrelated-mode rustdesk-route-DVI-D-1'
assert_no_cue

write_route true DVI-D-1 null null "$FAKE_NOW"
assert_no_new_mako_call 2

write_route true DVI-D-1 HDMI-A-1 left "$FAKE_NOW"
wait_for_log_count 3
assert_last_call 'mode|-r|rustdesk-route-DVI-D-1|-r|rustdesk-route-HDMI-A-1|-r|rustdesk-route-DP-2|-r|rustdesk-route-hidden|-r|rustdesk-cue|-a|rustdesk-route-DVI-D-1|-a|rustdesk-cue'
assert_route_modes 'unrelated-mode rustdesk-route-DVI-D-1 rustdesk-cue'
assert_cue 'HDMI-A-1|left'
assert_atomic_cue_rename

write_route false null DP-2 null "$FAKE_NOW"
wait_for_log_count 4
assert_last_call 'mode|-r|rustdesk-route-DVI-D-1|-r|rustdesk-route-HDMI-A-1|-r|rustdesk-route-DP-2|-r|rustdesk-route-hidden|-r|rustdesk-cue|-a|rustdesk-route-hidden|-a|rustdesk-cue'
assert_route_modes 'unrelated-mode rustdesk-route-hidden rustdesk-cue'
assert_cue 'DP-2|none'

rm -f -- "$ROUTE_FILE"
wait_for_log_count 5
assert_last_call 'mode|-r|rustdesk-route-DVI-D-1|-r|rustdesk-route-HDMI-A-1|-r|rustdesk-route-DP-2|-r|rustdesk-route-hidden|-r|rustdesk-cue|-a|rustdesk-route-hidden'
assert_route_modes 'unrelated-mode rustdesk-route-hidden'
assert_no_cue

expect_hidden_for_raw_route '{' 7
expect_hidden_for_raw_route '{"version":2,"visible":true,"output":"DVI-D-1","updatedAt":1786930000}' 9
expect_hidden_for_raw_route '{"version":1,"visible":true,"output":"DVI-D-1;touch","updatedAt":1786930000}' 11
expect_hidden_for_raw_route '{"version":1,"visible":true,"output":"DVI-D-1","updatedAt":1786930001}' 13
expect_hidden_for_raw_route '{"version":1,"visible":true,"output":"DVI-D-1","updatedAt":1786929954}' 15
expect_hidden_for_raw_route '{"version":1,"visible":true,"output":"DVI-D-1","cueOutput":"HDMI-A-1","direction":"sideways","updatedAt":1786930000}' 17
expect_hidden_for_raw_route '{"version":1,"visible":true,"output":null,"updatedAt":1786930000}' 19

write_route true DVI-D-1 HDMI-A-1 left "$FAKE_NOW"
wait_for_log_count 20
assert_cue 'HDMI-A-1|left'
assert_file_mode 0600 "$CUE_FILE"

cleanup_adapter
assert_route_modes 'unrelated-mode rustdesk-route-hidden'
assert_no_cue
assert_last_call 'mode|-r|rustdesk-route-DVI-D-1|-r|rustdesk-route-HDMI-A-1|-r|rustdesk-route-DP-2|-r|rustdesk-route-hidden|-r|rustdesk-cue|-a|rustdesk-route-hidden'
[[ -f $MAKO_ALIVE_FILE ]] || fail 'adapter cleanup stopped the Mako sentinel'

printf 'PASS: fail-closed Mako route adapter contract\n'
