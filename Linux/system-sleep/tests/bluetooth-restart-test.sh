#!/bin/bash

set -euo pipefail

repo_root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../../.." && pwd)"
hook="$repo_root/Linux/system-sleep/bluetooth-restart"
tmp_dir="$(mktemp -d)"
systemctl_log="$tmp_dir/systemctl.log"

trap 'rm -rf "$tmp_dir"' EXIT

mkdir -p "$tmp_dir/bin"
cat > "$tmp_dir/bin/systemctl" <<'EOF'
#!/bin/bash
printf '%s\n' "$*" >> "$SYSTEMCTL_LOG"
exit "${SYSTEMCTL_EXIT_CODE:-0}"
EOF
chmod +x "$tmp_dir/bin/systemctl"

fail() {
  printf 'FAIL: %s\n' "$1" >&2
  exit 1
}

run_hook() {
  SYSTEMCTL_LOG="$systemctl_log" PATH="$tmp_dir/bin:$PATH" "$hook" "$@"
}

assert_no_restart() {
  local phase="$1"
  local state="$2"

  : > "$systemctl_log"
  run_hook "$phase" "$state"
  [[ ! -s "$systemctl_log" ]] || fail "$phase $state unexpectedly called systemctl"
}

assert_restart() {
  local state="$1"
  local actual

  : > "$systemctl_log"
  run_hook post "$state"
  actual="$(<"$systemctl_log")"
  [[ "$actual" == "restart --no-block bluetooth.service" ]] || fail "post $state called: $actual"
}

[[ -x "$hook" ]] || fail "$hook must exist and be executable"

assert_no_restart pre suspend
assert_no_restart post freeze

for state in suspend hibernate hybrid-sleep suspend-then-hibernate; do
  assert_restart "$state"
done

: > "$systemctl_log"
SYSTEMCTL_EXIT_CODE=1 run_hook post suspend || fail "systemctl failure propagated from hook"
[[ "$(<"$systemctl_log")" == "restart --no-block bluetooth.service" ]] || fail "failure path skipped restart"

printf 'PASS: bluetooth resume hook\n'
