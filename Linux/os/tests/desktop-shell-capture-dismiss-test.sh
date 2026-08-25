#!/usr/bin/env bash
set -Eeuo pipefail

repo_root=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../../.." && pwd)
helper=$repo_root/Linux/os/helpers/desktop-shell-action
test_root=$(mktemp -d)
bin=$test_root/bin
count_file=$test_root/count
call_log=$test_root/calls.log

trap 'rm -rf "$test_root"' EXIT

fail() {
  printf 'FAIL: %s\n' "$1" >&2
  exit 1
}

install -d -m 700 "$bin"
printf '0\n' >"$count_file"

cat >"$bin/hyprctl" <<'EOF'
#!/usr/bin/env bash
count=$(<"$CAPTURE_TEST_COUNT")
count=$((count + 1))
printf '%s\n' "$count" >"$CAPTURE_TEST_COUNT"
printf 'hyprctl %s\n' "$*" >>"$CAPTURE_TEST_LOG"
if (( count < 3 )); then
  printf '{"levels":{"0":{"layers":[{"namespace":"desktop-menu"}]}}}\n'
else
  printf '{"levels":{"0":{"layers":[]}}}\n'
fi
EOF
cat >"$bin/hyprpicker" <<'EOF'
#!/usr/bin/env bash
printf 'hyprpicker %s\n' "$*" >>"$CAPTURE_TEST_LOG"
EOF
cat >"$bin/sleep" <<'EOF'
#!/usr/bin/env bash
printf 'sleep %s\n' "$*" >>"$CAPTURE_TEST_LOG"
EOF
chmod +x "$bin"/*

CAPTURE_TEST_COUNT=$count_file CAPTURE_TEST_LOG=$call_log PATH="$bin:$PATH" "$helper" trigger.color

[[ $(<"$count_file") -eq 3 ]] || fail "capture action did not wait for the menu layer to disappear"
[[ $(tail -n 1 "$call_log") == 'hyprpicker -a' ]] || fail "color picker started before layer teardown completed"

printf 'PASS: capture waits for menu dismissal\n'
