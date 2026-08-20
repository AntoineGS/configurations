#!/usr/bin/env bash
set -Eeuo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../../.." && pwd)"
HELPER="$ROOT/Linux/os/helpers/desktop-shell-status"
CONFIG="$ROOT/Linux/quickshell/desktop-shell/config/shell.json.tmpl"
AGENT_PANEL="$ROOT/Linux/quickshell/desktop-shell/plugins/agents/Panel.qml"

command -v jq >/dev/null 2>&1 || {
  printf 'status-test: jq is required\n' >&2
  exit 1
}

fixture="$(mktemp -d)"
trap 'rm -rf "$fixture"' EXIT

fake_bin="$fixture/bin"
failing_bin="$fixture/failing-bin"
proc_root="$fixture/proc"
cache_home="$fixture/cache"
home_root="$fixture/home"
mkdir -p "$fake_bin" "$failing_bin" "$proc_root" "$cache_home" "$home_root"

sleep_trace="$fixture/sleep.trace"
pgrep_trace="$fixture/pgrep.trace"
voxtype_trace="$fixture/voxtype.trace"
codex_trace="$fixture/codex.trace"
command_trace="$fixture/command.trace"

cat >"$failing_bin/mktemp" <<'FAKE_MKTEMP'
#!/usr/bin/env bash
set -Eeuo pipefail

printf 'mktemp fixture failure\n' >&2
exit 1
FAKE_MKTEMP
chmod +x "$failing_bin/mktemp"

printf '%s\n' 'cpu 100 0 100 800 0 0 0 0 0 0' >"$proc_root/stat"
printf '%s\n' 'MemTotal:       100000 kB' 'MemAvailable:    25000 kB' >"$proc_root/meminfo"

cat >"$fake_bin/sleep" <<'FAKE_SLEEP'
#!/usr/bin/env bash
set -Eeuo pipefail

printf '%s\n' "$*" >>"$DESKTOP_SHELL_SLEEP_TRACE"
if [[ ${1:-} == "0.2" ]]; then
  printf '%s\n' 'cpu 120 0 120 840 0 0 0 0 0 0' >"$DESKTOP_SHELL_PROC_ROOT/stat"
fi
FAKE_SLEEP

cat >"$fake_bin/pgrep" <<'FAKE_PGREP'
#!/usr/bin/env bash
set -Eeuo pipefail

printf '%s\n' "$*" >>"$DESKTOP_SHELL_PGREP_TRACE"
if [[ ${RECORDING_ACTIVE:-0} == 1 ]]; then
  exit 0
fi
exit 1
FAKE_PGREP

cat >"$fake_bin/voxtype" <<'FAKE_VOXTYPE'
#!/usr/bin/env bash
set -Eeuo pipefail

printf '%s\n' "$*" >>"$DESKTOP_SHELL_VOXTYPE_TRACE"
case ${VOXTYPE_STATE:-idle} in
idle)
  printf '%s\n' '{"text":"ignored","tooltip":"Idle tooltip","class":"idle"}'
  ;;
recording)
  printf '%s\n' '{"text":"ignored","tooltip":"Recording tooltip","class":"recording"}'
  ;;
transcribing)
  printf '%s\n' '{"text":"ignored","tooltip":"Transcribing tooltip","class":"transcribing"}'
  ;;
*)
  printf 'unknown voxtype fixture state\n' >&2
  exit 1
  ;;
esac
FAKE_VOXTYPE

cat >"$fake_bin/voxtype-status" <<'FAKE_VOXTYPE_STATUS'
#!/usr/bin/env bash
set -Eeuo pipefail

printf 'voxtype-status must not be invoked\n' >>"$DESKTOP_SHELL_COMMAND_TRACE"
exit 99
FAKE_VOXTYPE_STATUS

cat >"$fake_bin/codexbar" <<'FAKE_CODEXBAR'
#!/usr/bin/env bash
set -Eeuo pipefail

printf '%s\n' "$*" >>"$DESKTOP_SHELL_CODEX_TRACE"
if [[ ${CODEX_FAIL:-0} == 1 ]]; then
  printf 'codexbar fixture failure\n' >&2
  exit 1
fi
case ${CODEX_PAYLOAD:-valid} in
valid)
  printf '%s\n' '{"text":"1%/4d 7h 03m","tooltip":"Codex quota","class":"source","extra":"preserve"}'
  ;;
missing-tooltip)
  printf '%s\n' '{"text":"1%/4d 7h","class":"source"}'
  ;;
non-string-tooltip)
  printf '%s\n' '{"text":"1%/4d 7h","tooltip":42,"class":"source"}'
  ;;
two-valid)
  printf '%s\n' '{"text":"first","tooltip":"First tooltip","class":"source"}'
  printf '%s\n' '{"text":"second","tooltip":"Second tooltip","class":"source"}'
  ;;
empty)
  ;;
esac
FAKE_CODEXBAR

cat >"$fake_bin/df" <<'FAKE_DF'
#!/usr/bin/env bash
set -Eeuo pipefail

if [[ ${DF_FAIL:-0} == 1 ]]; then
  printf 'df fixture failure\n' >&2
  exit 1
fi
printf '%s\n' 'Filesystem 1024-blocks Used Available Capacity Mounted on' '/dev/mock 1000 420 580 42% /'
FAKE_DF

cat >"$fake_bin/cmd-screenrecord" <<'FAKE_SCREENRECORD'
#!/usr/bin/env bash
set -Eeuo pipefail

printf 'cmd-screenrecord must not be invoked\n' >>"$DESKTOP_SHELL_COMMAND_TRACE"
exit 99
FAKE_SCREENRECORD

chmod +x "$fake_bin"/*

export DESKTOP_SHELL_PROC_ROOT="$proc_root"
export DESKTOP_SHELL_SLEEP_TRACE="$sleep_trace"
export DESKTOP_SHELL_PGREP_TRACE="$pgrep_trace"
export DESKTOP_SHELL_VOXTYPE_TRACE="$voxtype_trace"
export DESKTOP_SHELL_CODEX_TRACE="$codex_trace"
export DESKTOP_SHELL_COMMAND_TRACE="$command_trace"
export RECORDING_ACTIVE=0
export VOXTYPE_STATE=idle
export CODEX_FAIL=0
export CODEX_PAYLOAD=valid
export DF_FAIL=0

original_path="$PATH"
last_output=""
last_status=0
last_stderr=""

invoke() {
  local label=$1
  local kind=$2
  local selected_cache_home=${3:-$cache_home}
  local stderr_file="$fixture/$label.stderr"

  if last_output=$(PATH="$fake_bin:$original_path" HOME="$home_root" XDG_CACHE_HOME="$selected_cache_home" \
    "$HELPER" "$kind" 2>"$stderr_file"); then
    last_status=0
  else
    last_status=$?
  fi
  last_stderr=$(<"$stderr_file")
}

invoke_arguments() {
  local label=$1
  shift
  local stderr_file="$fixture/$label.stderr"

  if last_output=$(PATH="$failing_bin:$original_path" HOME="$home_root" XDG_CACHE_HOME="$fixture/invalid-args-cache" \
    "$HELPER" "$@" 2>"$stderr_file"); then
    last_status=0
  else
    last_status=$?
  fi
  last_stderr=$(<"$stderr_file")
}

assert_equal() {
  local expected=$1
  local actual=$2
  local message=$3
  if [[ $actual != "$expected" ]]; then
    printf 'status-test: %s: expected %q, got %q\n' "$message" "$expected" "$actual" >&2
    exit 1
  fi
}

assert_json_field() {
  local expression=$1
  local expected=$2
  local message=$3
  local actual
  actual=$(jq -er "$expression" <<<"$last_output") || {
    printf 'status-test: invalid JSON while checking %s: %s\n' "$message" "$last_output" >&2
    exit 1
  }
  assert_equal "$expected" "$actual" "$message"
}

assert_status() {
  assert_equal "$1" "$last_status" "$2 exit status"
}

assert_no_output() {
  local message=$1
  if [[ -n $last_output ]]; then
    printf 'status-test: %s unexpectedly produced stdout: %s\n' "$message" "$last_output" >&2
    exit 1
  fi
}

assert_no_command_side_effects() {
  if [[ -s $command_trace ]]; then
    printf 'status-test: mutating or follow-mode command was invoked:\n%s\n' "$(<"$command_trace")" >&2
    exit 1
  fi
}

invoke recording-inactive recording
assert_status 0 recording-inactive
assert_json_field '.text' '' 'recording inactive has zero-width text'
assert_json_field '.tooltip' '' 'recording inactive tooltip'
assert_json_field '.class' '' 'recording inactive class'

RECORDING_ACTIVE=1
invoke recording-active recording
assert_status 0 recording-active
assert_json_field '.text' '󰻂' 'recording active icon'
assert_json_field '.tooltip' 'Stop recording' 'recording active tooltip'
assert_json_field '.class' 'active' 'recording active class'
assert_equal 2 "$(wc -l <"$pgrep_trace")" 'recording read-only process checks'
while IFS= read -r pgrep_args; do
  assert_equal '-f ^gpu-screen-recorder' "$pgrep_args" 'recording process convention'
done <"$pgrep_trace"

VOXTYPE_STATE=idle
invoke voxtype-idle voxtype
assert_status 0 voxtype-idle
assert_json_field '.text' '' 'voxtype idle has zero-width text'
assert_json_field '.tooltip' 'Idle tooltip' 'voxtype idle tooltip'
assert_json_field '.class' 'idle' 'voxtype idle class'

VOXTYPE_STATE=recording
invoke voxtype-recording voxtype
assert_status 0 voxtype-recording
assert_json_field '.text' '󰍬' 'voxtype recording icon'
assert_json_field '.tooltip' 'Recording tooltip' 'voxtype recording tooltip'
assert_json_field '.class' 'recording' 'voxtype recording class'

VOXTYPE_STATE=transcribing
invoke voxtype-transcribing voxtype
assert_status 0 voxtype-transcribing
assert_json_field '.text' '󱔟' 'voxtype transcribing icon'
assert_json_field '.tooltip' 'Transcribing tooltip' 'voxtype transcribing tooltip'
assert_json_field '.class' 'transcribing' 'voxtype transcribing class'
while IFS= read -r voxtype_args; do
  assert_equal 'status --extended --format json' "$voxtype_args" 'one-shot Voxtype query'
done <"$voxtype_trace"

invoke codex-success codex
assert_status 0 codex-success
assert_json_field '.text' '1%/4d7h03m' 'Codex reset normalization'
assert_json_field '.tooltip' 'Codex quota' 'Codex tooltip preservation'
assert_json_field '.class' 'muted' 'Codex muted class'
assert_json_field '.extra' 'preserve' 'Codex top-level field preservation'
while IFS= read -r codex_args; do
  [[ $codex_args == *"--format {weekly_pct}%/{weekly_reset}"* ]] || {
    printf 'status-test: codex command contract missing format: %s\n' "$codex_args" >&2
    exit 1
  }
  [[ $codex_args == *"--color-low #7f849c"* && $codex_args == *"--color-mid #7f849c"* && \
    $codex_args == *"--color-high #7f849c"* && $codex_args == *"--color-critical #7f849c"* ]] || {
    printf 'status-test: codex command contract missing neutral colors: %s\n' "$codex_args" >&2
    exit 1
  }
done <"$codex_trace"

invoke disk disk
assert_status 0 disk
assert_json_field '.text' $' 42%' 'disk glyph and percentage separation'

invoke memory memory
assert_status 0 memory
assert_json_field '.text' $'\uefc5 75%' 'Waybar memory glyph and percentage separation'
assert_json_field '.percentage' '75' 'memory numeric percentage'

invoke cpu cpu
assert_status 0 cpu
assert_json_field '.text' $' 50%' 'CPU glyph and percentage separation'
assert_json_field '.percentage' '50' 'CPU numeric percentage'
assert_equal '0.2' "$(<"$sleep_trace")" 'CPU sample interval'

status_cache="$cache_home/desktop-shell/status"
[[ -s "$status_cache/codex.json" && -s "$status_cache/cpu.json" ]] || {
  printf 'status-test: successful adapter results were not cached\n' >&2
  exit 1
}
shopt -s nullglob
temporary_cache_files=("$status_cache"/*.tmp "$status_cache"/.*.??????)
shopt -u nullglob
assert_equal 0 "${#temporary_cache_files[@]}" 'atomic cache leaves no temporary files'

CODEX_PAYLOAD=two-valid
invoke codex-multiple-live codex "$fixture/no-cache-multiple-live"
assert_status 1 codex-multiple-live
assert_no_output 'multiple valid live payloads'

CODEX_PAYLOAD=empty
invoke codex-empty-live codex "$fixture/no-cache-empty-live"
assert_status 1 codex-empty-live
assert_no_output 'empty live payload'

CODEX_PAYLOAD=missing-tooltip
invoke codex-missing-field codex "$fixture/no-cache-missing-field"
assert_status 1 codex-missing-field
assert_no_output 'malformed successful payload with a missing field'
[[ -n $last_stderr ]] || {
  printf 'status-test: missing-field payload did not report its schema error\n' >&2
  exit 1
}

CODEX_PAYLOAD=non-string-tooltip
invoke codex-non-string-field codex "$fixture/no-cache-non-string-field"
assert_status 1 codex-non-string-field
assert_no_output 'malformed successful payload with a non-string field'
[[ -n $last_stderr ]] || {
  printf 'status-test: non-string payload did not report its schema error\n' >&2
  exit 1
}

CODEX_PAYLOAD=valid
CODEX_FAIL=1
invoke codex-stale codex
assert_status 0 codex-stale
assert_json_field '.text' '1%/4d7h03m' 'stale Codex text fallback'
assert_json_field '.class' 'stale' 'stale Codex class'
stale_tooltip=$(jq -er '.tooltip' <<<"$last_output")
[[ $stale_tooltip == *'Codex quota'* && $stale_tooltip == *'codexbar fixture failure'* ]] || {
  printf 'status-test: stale tooltip did not preserve and append the adapter error: %s\n' "$stale_tooltip" >&2
  exit 1
}
assert_equal 'muted' "$(jq -er '.class' "$status_cache/codex.json")" 'good Codex cache remains fresh'

printf '%s\n' '{"text":"cached-first","tooltip":"Cached first tooltip","class":"muted"}' \
  '{"text":"cached-second","tooltip":"Cached second tooltip","class":"muted"}' >"$status_cache/codex.json"
invoke codex-multiple-cache codex
assert_status 1 codex-multiple-cache
assert_no_output 'multiple valid cached payloads'

printf '%s\n' '{"text":"cached","class":"muted"}' >"$status_cache/codex.json"
invoke codex-cache-missing-field codex
assert_status 1 codex-cache-missing-field
assert_no_output 'malformed cached payload with a missing field'
[[ -n $last_stderr ]] || {
  printf 'status-test: missing-field cache did not report its schema error\n' >&2
  exit 1
}

printf '%s\n' '{"text":"cached","tooltip":42,"class":"muted"}' >"$status_cache/codex.json"
invoke codex-cache-non-string-field codex
assert_status 1 codex-cache-non-string-field
assert_no_output 'malformed cached payload with a non-string field'
[[ -n $last_stderr ]] || {
  printf 'status-test: non-string cache did not report its schema error\n' >&2
  exit 1
}

DF_FAIL=1
invoke disk-no-cache disk "$fixture/no-cache"
[[ $last_status -ne 0 ]] || {
  printf 'status-test: adapter without a cache unexpectedly succeeded\n' >&2
  exit 1
}
[[ -n $last_stderr ]] || {
  printf 'status-test: adapter without a cache did not report its error\n' >&2
  exit 1
}

invoke unknown unknown
assert_status 2 unknown

invoke_arguments missing-arguments
assert_status 2 missing-arguments
assert_no_output 'missing arguments'
[[ $last_stderr != *'mktemp fixture failure'* ]] || {
  printf 'status-test: missing-argument validation attempted mktemp\n' >&2
  exit 1
}

invoke_arguments extra-arguments recording extra
assert_status 2 extra-arguments
assert_no_output 'extra arguments'
[[ $last_stderr != *'mktemp fixture failure'* ]] || {
  printf 'status-test: extra-argument validation attempted mktemp\n' >&2
  exit 1
}

assert_no_command_side_effects

grep -Fq '"exec": "desktop-shell-status recording"' "$CONFIG"
grep -Fq '"onClick": "cmd-screenrecord"' "$CONFIG"
grep -Fq '"exec": "desktop-shell-status voxtype"' "$CONFIG"
grep -Fq '"onClick": "voxtype-model"' "$CONFIG"
grep -Fq '"onRightClick": "voxtype-config"' "$CONFIG"
grep -Fq 'command: ["desktop-shell-status", "codex"]' "$AGENT_PANEL"
grep -Fq 'https://chatgpt.com/codex/settings/usage' "$AGENT_PANEL"
if grep -Fq 'onClickRight' "$CONFIG"; then
  printf 'status-test: obsolete onClickRight key remains in the command config\n' >&2
  exit 1
fi

printf 'status-test: six command status adapters, cache fallback, and click contracts verified\n'
