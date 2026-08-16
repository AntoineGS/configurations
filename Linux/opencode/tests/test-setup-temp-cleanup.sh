#!/usr/bin/env bash
set -Eeuo pipefail

script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
script="$script_dir/../setup-temp-cleanup.sh"
tmp_dir="$(mktemp -d)"
stub_dir="$tmp_dir/bin"
temp_dir="$tmp_dir/opencode"
config="$tmp_dir/opencode.conf"
systemctl_log="$tmp_dir/systemctl.log"
systemctl_state="$tmp_dir/systemctl.state"
tmpfiles_log="$tmp_dir/tmpfiles.log"
original_path="$PATH"

trap 'rm -rf -- "$tmp_dir"' EXIT

fail() {
  printf 'FAIL: %s\n' "$*" >&2
  exit 1
}

mkdir -p -- "$stub_dir" "$temp_dir"
chmod 700 -- "$temp_dir"
: > "$config"
: > "$systemctl_log"
: > "$systemctl_state"
: > "$tmpfiles_log"

# The generated stubs must receive these expansions at runtime, not while they are written.
# shellcheck disable=SC2016
printf '%s\n' \
  '#!/usr/bin/env bash' \
  'set -Eeuo pipefail' \
  ': "${SYSTEMCTL_LOG:?}"' \
  ': "${SYSTEMCTL_STATE:?}"' \
  'printf "%s\\n" "$*" >> "$SYSTEMCTL_LOG"' \
  'has_state() {' \
  '  local wanted="$1" state' \
  '  while IFS= read -r state; do [[ "$state" == "$wanted" ]] && return 0; done < "$SYSTEMCTL_STATE"' \
  '  return 1' \
  '}' \
  'case "${1:-}" in' \
  '  --user)' \
  '    case "${2:-}" in' \
  '      is-enabled) [[ "${3:-}" == "--quiet" && "${4:-}" == "systemd-tmpfiles-clean.timer" ]] && has_state enabled ;;' \
  '      is-active) [[ "${3:-}" == "--quiet" && "${4:-}" == "systemd-tmpfiles-clean.timer" ]] && has_state active ;;' \
  '      enable) [[ "${3:-}" == "--now" && "${4:-}" == "systemd-tmpfiles-clean.timer" ]] ;;' \
  '      *) exit 2 ;;' \
  '    esac' \
  '    ;;' \
  '  *) exit 2 ;;' \
  'esac' \
  > "$stub_dir/systemctl"
chmod +x -- "$stub_dir/systemctl"

# shellcheck disable=SC2016
printf '%s\n' \
  '#!/usr/bin/env bash' \
  'set -Eeuo pipefail' \
  ': "${TMPFILES_CONFIG:?}"' \
  ': "${TMPFILES_LOG:?}"' \
  'printf "%s\\n" "$*" >> "$TMPFILES_LOG"' \
  '[[ "$*" == "--user --create $TMPFILES_CONFIG" ]]' \
  > "$stub_dir/systemd-tmpfiles"
chmod +x -- "$stub_dir/systemd-tmpfiles"

[[ -x "$script" ]] || fail "$script must exist and be executable"

run_script() {
  OPENCODE_TEMP_DIR="$temp_dir" \
    OPENCODE_TMPFILES_CONFIG="$config" \
    SYSTEMCTL_LOG="$systemctl_log" \
    SYSTEMCTL_STATE="$systemctl_state" \
    TMPFILES_CONFIG="$config" \
    TMPFILES_LOG="$tmpfiles_log" \
    PATH="$stub_dir:$original_path" \
    "$script" "$@"
}

clear_logs() {
  : > "$systemctl_log"
  : > "$tmpfiles_log"
}

assert_logs() {
  local expected_systemctl="$1"
  local expected_tmpfiles="$2"
  local actual_systemctl actual_tmpfiles

  actual_systemctl="$(<"$systemctl_log")"
  actual_tmpfiles="$(<"$tmpfiles_log")"
  [[ "$actual_systemctl" == "$expected_systemctl" ]] || {
    printf 'Expected systemctl calls:\n%s\nActual systemctl calls:\n%s\n' "$expected_systemctl" "$actual_systemctl" >&2
    fail "systemctl call log differs"
  }
  [[ "$actual_tmpfiles" == "$expected_tmpfiles" ]] || {
    printf 'Expected tmpfiles calls:\n%s\nActual tmpfiles calls:\n%s\n' "$expected_tmpfiles" "$actual_tmpfiles" >&2
    fail "tmpfiles call log differs"
  }
}

if ! help_output="$(run_script --help 2>&1)"; then
  fail "--help did not exit successfully"
fi
[[ "$help_output" == *"Usage:"* ]] || fail "--help did not print usage"

if run_script --unknown >/dev/null 2>&1; then
  fail "unknown option unexpectedly succeeded"
else
  unknown_status=$?
fi
[[ "$unknown_status" -eq 2 ]] || fail "unknown option exited with $unknown_status instead of 2"

printf '%s\n' enabled active > "$systemctl_state"
clear_logs
run_script --check || fail "--check failed for a valid temp directory and timer"
assert_logs $'--user is-enabled --quiet systemd-tmpfiles-clean.timer\n--user is-active --quiet systemd-tmpfiles-clean.timer' ''

rm -rf -- "$temp_dir"
ln -s -- "$tmp_dir/missing" "$temp_dir"
clear_logs
if run_script --check; then
  fail "--check succeeded for a symlinked temp directory"
else
  check_status=$?
fi
[[ "$check_status" -ne 0 ]] || fail "symlinked temp directory returned zero"
assert_logs '' ''
rm -- "$temp_dir"
mkdir -- "$temp_dir"
chmod 700 -- "$temp_dir"

chmod 755 -- "$temp_dir"
clear_logs
if run_script --check; then
  fail "--check succeeded for a temp directory with mode 755"
fi
assert_logs '' ''
chmod 700 -- "$temp_dir"

printf '%s\n' active > "$systemctl_state"
clear_logs
if run_script --check; then
  fail "--check succeeded while the cleanup timer was disabled"
fi
assert_logs '--user is-enabled --quiet systemd-tmpfiles-clean.timer' ''

printf '%s\n' enabled > "$systemctl_state"
clear_logs
if run_script --check; then
  fail "--check succeeded while the cleanup timer was inactive"
fi
assert_logs $'--user is-enabled --quiet systemd-tmpfiles-clean.timer\n--user is-active --quiet systemd-tmpfiles-clean.timer' ''

printf '%s\n' enabled active > "$systemctl_state"
clear_logs
run_script --apply || fail "--apply failed for valid prerequisites"
assert_logs '--user enable --now systemd-tmpfiles-clean.timer' "--user --create $config"

printf 'PASS: opencode temp cleanup setup\n'
