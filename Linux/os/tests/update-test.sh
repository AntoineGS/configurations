#!/bin/bash

set -euo pipefail

repo_root=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../../.." && pwd)
helpers="$repo_root/Linux/os/helpers"
test_root=$(mktemp -d)
bin="$test_root/bin"
log="$test_root/calls.log"

trap 'rm -rf "$test_root"' EXIT
mkdir -p "$bin"

fail() {
  printf 'FAIL: %s\n' "$1" >&2
  exit 1
}

audited_helpers=(
  "$helpers/update"
  "$helpers/update-perform"
  "$helpers/update-keyring"
  "$helpers/desktop-shell"
  "$helpers/desktop-shell-status"
)

for helper in "${audited_helpers[@]}"; do
  [[ -r $helper ]] || fail "audited helper is missing or unreadable: $helper"
done

stub() {
  local name=$1
  cat >"$bin/$name" <<'EOF'
#!/bin/bash
printf '%s %s\n' "$(basename "$0")" "$*" >>"$UPDATE_TEST_LOG"
if [[ ${UPDATE_TEST_FAIL_COMMAND:-} == "$(basename "$0")" ]]; then
  exit "${UPDATE_TEST_FAIL_STATUS:-1}"
fi
EOF
  chmod +x "$bin/$name"
}

assert_calls() {
  local expected=$1
  local actual
  actual=$(<"$log")
  [[ $actual == "$expected" ]] || fail "expected calls:\n$expected\nactual calls:\n$actual"
}

for command in snapshot update-time update-perform; do
  stub "$command"
done

: >"$log"
PATH="$bin:$PATH" UPDATE_TEST_LOG="$log" "$helpers/update" -y
assert_calls $'snapshot create\nupdate-time \nupdate-perform '

for command in hyprctl update-keyring update-available-reset update-system-pkgs update-aur-pkgs \
  update-orphan-pkgs hook update-analyze-logs update-restart; do
  stub "$command"
done

: >"$log"
PATH="$bin:$PATH" UPDATE_TEST_LOG="$log" "$helpers/update-perform"
assert_calls $'hyprctl eval hl.dispatch(hl.dsp.window.tag({tag="+noidle"}))\nupdate-keyring \nupdate-system-pkgs \nupdate-aur-pkgs \nupdate-orphan-pkgs \nupdate-analyze-logs \nhyprctl eval hl.dispatch(hl.dsp.window.tag({tag="-noidle"}))'

cat >"$bin/sudo" <<'EOF'
#!/bin/bash
printf 'sudo %s\n' "$*" >>"$UPDATE_TEST_LOG"
EOF
chmod +x "$bin/sudo"

: >"$log"
PATH="$bin:$PATH" UPDATE_TEST_LOG="$log" "$helpers/update-keyring"
assert_calls 'sudo pacman -Sy --noconfirm archlinux-keyring'

if grep -Eq 'OMARCHY_PATH|40DFB630FF42BCFFB047046CF0134EE680CAC571|pkg-(missing|add) keyring' \
  "${audited_helpers[@]}"; then
  fail "update flow still contains Omarchy repository or signing-key dependencies"
else
  grep_status=$?
  ((grep_status == 1)) || fail "could not audit update helpers (grep status $grep_status)"
fi

failure_output="$test_root/failure-output"
failure_status=0
if PATH="$bin:$PATH" UPDATE_TEST_LOG="$log" UPDATE_TEST_FAIL_COMMAND=update-time UPDATE_TEST_FAIL_STATUS=23 \
  "$helpers/update" -y >"$failure_output" 2>&1; then
  fail "update unexpectedly succeeded after update-time failed"
else
  failure_status=$?
fi
[[ "$failure_status" -eq 23 ]] || fail "update failure returned status $failure_status instead of 23"
grep -Fq 'Something went wrong during the update!' "$failure_output" ||
  fail "update failure did not print its error message"

command -v python3 >/dev/null 2>&1 || fail "python3 is required to test the interactive failure pause"
interactive_output="$test_root/interactive-output"
interactive_status=0
if PATH="$bin:$PATH" UPDATE_TEST_LOG="$log" UPDATE_TEST_FAIL_COMMAND=update-time UPDATE_TEST_FAIL_STATUS=23 \
  python3 - "$helpers/update" >"$interactive_output" 2>&1 <<'PY'
import os
import pty
import select
import signal
import sys
import time

pid, master = pty.fork()
if pid == 0:
    os.execv(sys.argv[1], [sys.argv[1], "-y"])

os.write(master, b"x")
output = bytearray()
child_status = None
deadline = time.monotonic() + 10
while child_status is None:
    readable, _, _ = select.select([master], [], [], max(0, deadline - time.monotonic()))
    if not readable:
        os.kill(pid, signal.SIGKILL)
        os.waitpid(pid, 0)
        sys.exit(124)
    try:
        output.extend(os.read(master, 4096))
    except OSError:
        pass
    waited, child_status = os.waitpid(pid, os.WNOHANG)
    if not waited:
        child_status = None

sys.stdout.buffer.write(output)
sys.exit(os.waitstatus_to_exitcode(child_status))
PY
then
  fail "interactive update unexpectedly succeeded after update-time failed"
else
  interactive_status=$?
fi
[[ "$interactive_status" -eq 23 ]] ||
  fail "interactive update failure returned status $interactive_status instead of 23"
grep -Fq 'Press any key to close...' "$interactive_output" ||
  fail "interactive update failure did not pause before closing"

printf 'PASS: Arch/AUR update flow\n'
