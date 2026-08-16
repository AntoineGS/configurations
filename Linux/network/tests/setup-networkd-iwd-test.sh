#!/usr/bin/env bash
set -Eeuo pipefail

script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
script="$script_dir/../setup-networkd-iwd"
tmp_dir="$(mktemp -d)"
stub_dir="$tmp_dir/bin"
systemctl_log="$tmp_dir/systemctl.log"
enabled_units="$tmp_dir/enabled-units"
original_path="$PATH"

trap 'rm -rf -- "$tmp_dir"' EXIT

fail() {
  printf 'FAIL: %s\n' "$*" >&2
  exit 1
}

mkdir -p -- "$stub_dir"
: > "$systemctl_log"
: > "$enabled_units"

# The generated stub must receive these expansions at runtime, not while it is written.
# shellcheck disable=SC2016
printf '%s\n' \
  '#!/usr/bin/env bash' \
  'set -Eeuo pipefail' \
  ': "${SYSTEMCTL_LOG:?}"' \
  ': "${SYSTEMCTL_ENABLED:?}"' \
  'printf "%s\\n" "$*" >> "$SYSTEMCTL_LOG"' \
  'case "${1:-}" in' \
  '  is-enabled)' \
  '    [[ "${2:-}" == "--quiet" ]] || exit 2' \
  '    unit="${3:-}"' \
  '    while IFS= read -r enabled_unit; do' \
  '      if [[ "$enabled_unit" == "$unit" ]]; then' \
  '        exit 0' \
  '      fi' \
  '    done < "$SYSTEMCTL_ENABLED"' \
  '    exit 1' \
  '    ;;' \
  '  daemon-reload)' \
  '    exit 0' \
  '    ;;' \
  '  enable)' \
  '    [[ "${2:-}" == "--now" ]] || exit 2' \
  '    [[ $# -eq 5 ]] || exit 2' \
  '    exit 0' \
  '    ;;' \
  '  *)' \
  '    exit 2' \
  '    ;;' \
  'esac' > "$stub_dir/systemctl"
chmod +x -- "$stub_dir/systemctl"

[[ -x "$script" ]] || fail "$script must exist and be executable"

run_script() {
  SYSTEMCTL_LOG="$systemctl_log" \
    SYSTEMCTL_ENABLED="$enabled_units" \
    PATH="$stub_dir:$original_path" \
    "$script" "$@"
}

set_enabled_units() {
  printf '%s\n' "$@" > "$enabled_units"
}

clear_log() {
  : > "$systemctl_log"
}

assert_log() {
  local expected="$1"
  local actual

  actual="$(<"$systemctl_log")"
  [[ "$actual" == "$expected" ]] || {
    printf 'Expected systemctl calls:\n%s\nActual systemctl calls:\n%s\n' "$expected" "$actual" >&2
    fail "systemctl call log differs"
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

all_units=(
  systemd-networkd.service
  systemd-resolved.service
  iwd.service
)
set_enabled_units "${all_units[@]}"
clear_log
run_script --check || fail "--check failed when all units were enabled"
assert_log $'is-enabled --quiet systemd-networkd.service\nis-enabled --quiet systemd-resolved.service\nis-enabled --quiet iwd.service'

for missing_unit in "${all_units[@]}"; do
  enabled_for_check=()
  for unit in "${all_units[@]}"; do
    [[ "$unit" == "$missing_unit" ]] || enabled_for_check+=("$unit")
  done
  set_enabled_units "${enabled_for_check[@]}"
  clear_log
  if run_script --check; then
    fail "--check succeeded while $missing_unit was disabled"
  else
    check_status=$?
  fi
  [[ "$check_status" -ne 0 ]] || fail "--check returned zero for missing $missing_unit"
  while IFS= read -r call; do
    case "$call" in
      enable\ *|start\ *|restart\ *) fail "--check attempted a mutating systemctl action" ;;
    esac
  done < "$systemctl_log"
done

set_enabled_units "${all_units[@]}"
clear_log
run_script --apply || fail "--apply failed when all units were already enabled"
assert_log $'daemon-reload\nenable --now systemd-networkd.service systemd-resolved.service iwd.service'

printf 'PASS: networkd and iwd setup\n'
