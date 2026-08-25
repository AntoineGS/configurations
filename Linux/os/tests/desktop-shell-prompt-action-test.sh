#!/usr/bin/env bash
set -Eeuo pipefail

repo_root=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../../.." && pwd)
helper=$repo_root/Linux/os/helpers/desktop-shell-prompt-action
test_root=$(mktemp -d)
bin=$test_root/bin
call_log=$test_root/call.log
prompt_log=$test_root/prompt.log

trap 'rm -rf "$test_root"' EXIT

fail() {
  printf 'FAIL: %s\n' "$1" >&2
  exit 1
}

expect_failure() {
  if "$@" >/dev/null 2>&1; then
    fail "command unexpectedly succeeded: $*"
  fi
}

[[ -x $helper ]] || fail "prompt action helper is missing or not executable: $helper"
install -d -m 700 "$bin"

cat >"$bin/menu-input" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "$1" >"$PROMPT_LOG"
[[ ${MENU_INPUT_CANCEL:-0} == 0 ]] || exit 1
printf '%s\n' "${MENU_INPUT_RESULT-15}"
EOF
cat >"$bin/action-stub" <<'EOF'
#!/usr/bin/env bash
printf '%s' "${0##*/}" >"$CALL_LOG"
if (( $# > 0 )); then printf ' %s' "$@" >>"$CALL_LOG"; fi
printf '\n' >>"$CALL_LOG"
EOF
cat >"$bin/notify-send" <<'EOF'
#!/usr/bin/env bash
exit 0
EOF
chmod +x "$bin"/*
ln -s action-stub "$bin/suspend-in"
ln -s action-stub "$bin/close-rustdesk-windows-in"

run_env=(PATH="$bin:$PATH" CALL_LOG="$call_log" PROMPT_LOG="$prompt_log")

env "${run_env[@]}" MENU_INPUT_RESULT=15 "$helper" system.suspend-in
[[ $(<"$call_log") == 'suspend-in 15' ]] || fail "suspend action invoked the wrong helper"
[[ $(<"$prompt_log") == 'Minutes until suspend' ]] || fail "suspend action used the wrong prompt"

env "${run_env[@]}" MENU_INPUT_RESULT=30 "$helper" system.close-rustdesk-in
[[ $(<"$call_log") == 'close-rustdesk-windows-in 30' ]] || fail "RustDesk action invoked the wrong helper"
[[ $(<"$prompt_log") == 'Minutes until RustDesk windows close' ]] || fail "RustDesk action used the wrong prompt"

for invalid in 0 -1 1.5 text ''; do
  rm -f "$call_log"
  expect_failure env "${run_env[@]}" MENU_INPUT_RESULT="$invalid" "$helper" system.suspend-in
  [[ ! -e $call_log ]] || fail "invalid input '$invalid' invoked a helper"
done

rm -f "$call_log"
expect_failure env "${run_env[@]}" MENU_INPUT_CANCEL=1 "$helper" system.suspend-in
[[ ! -e $call_log ]] || fail "cancelled input invoked a helper"

expect_failure env "${run_env[@]}" "$helper" unknown.action
expect_failure env "${run_env[@]}" "$helper" system.suspend-in extra

printf 'PASS: trusted parameterized action prompts\n'
