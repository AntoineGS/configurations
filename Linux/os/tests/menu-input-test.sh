#!/usr/bin/env bash
set -Eeuo pipefail

repo_root=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../../.." && pwd)
helpers=$repo_root/Linux/os/helpers
result_helper=$helpers/desktop-shell-menu-result
test_root=$(mktemp -d)
runtime=$test_root/runtime

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

[[ -x $result_helper ]] || fail "result helper is missing or not executable: $result_helper"

install -d -m 700 "$runtime" "$runtime/desktop-shell-menu"
request=$runtime/desktop-shell-menu/request.good
install -d -m 700 "$request"

XDG_RUNTIME_DIR=$runtime "$result_helper" "$request" value '15'
[[ $(<"$request/selection") == 15 ]] || fail "result helper did not persist selected value"
[[ $(<"$request/done") == selected ]] || fail "result helper did not mark selection complete"
[[ $(stat -c '%a' "$request/selection") == 600 ]] || fail "selection file is not private"
[[ $(stat -c '%a' "$request/done") == 600 ]] || fail "completion file is not private"

rm -f "$request/selection" "$request/done"
XDG_RUNTIME_DIR=$runtime "$result_helper" "$request" cancel
[[ ! -e $request/selection ]] || fail "cancel created a selection file"
[[ $(<"$request/done") == cancelled ]] || fail "result helper did not mark cancellation"

outside=$test_root/request.outside
install -d -m 700 "$outside"
expect_failure env XDG_RUNTIME_DIR="$runtime" "$result_helper" "$outside" cancel

insecure=$runtime/desktop-shell-menu/request.insecure
install -d -m 755 "$insecure"
expect_failure env XDG_RUNTIME_DIR="$runtime" "$result_helper" "$insecure" cancel

real_request=$runtime/desktop-shell-menu/request.real
install -d -m 700 "$real_request"
symlink_request=$runtime/desktop-shell-menu/request.symlink
ln -s "$real_request" "$symlink_request"
expect_failure env XDG_RUNTIME_DIR="$runtime" "$result_helper" "$symlink_request" cancel

expect_failure env XDG_RUNTIME_DIR="$runtime" "$result_helper" "$request" unknown
expect_failure env XDG_RUNTIME_DIR="$runtime" "$result_helper" "$request" value

printf 'PASS: desktop shell menu result validation\n'

rm -rf -- "$runtime/desktop-shell-menu"/request.*

menu_input=$helpers/menu-input
menu_select=$helpers/menu-select
bin=$test_root/bin
payload_log=$test_root/payload.json
mode_log=$test_root/request-mode

install -d -m 700 "$bin"

cat >"$bin/desktop-shell" <<'EOF'
#!/usr/bin/env bash
set -Eeuo pipefail

case ${1-} in
  summon)
    payload=${3-}
    printf '%s\n' "$payload" >"$MENU_TEST_PAYLOAD_LOG"
    request_dir=$(jq -er '.requestDir' <<<"$payload")
    stat -c '%a' -- "$request_dir" >"$MENU_TEST_MODE_LOG"
    case ${MENU_TEST_ACTION:-complete} in
      complete) "$MENU_TEST_RESULT_HELPER" "$request_dir" value "${MENU_TEST_SELECTION:-selected}" ;;
      cancel) "$MENU_TEST_RESULT_HELPER" "$request_dir" cancel ;;
      wait) ;;
      *) exit 2 ;;
    esac
    ;;
  ping)
    [[ ${MENU_TEST_PING:-ok} == ok ]]
    ;;
  *) exit 2 ;;
esac
EOF
chmod +x "$bin/desktop-shell"

[[ -x $menu_input ]] || fail "menu-input is missing or not executable: $menu_input"
[[ -x $menu_select ]] || fail "menu-select is missing or not executable: $menu_select"

run_menu_env=(
  XDG_RUNTIME_DIR="$runtime"
  PATH="$bin:$PATH"
  MENU_TEST_PAYLOAD_LOG="$payload_log"
  MENU_TEST_MODE_LOG="$mode_log"
  MENU_TEST_RESULT_HELPER="$result_helper"
)

selection=$(env "${run_menu_env[@]}" MENU_TEST_SELECTION='15 minutes' "$menu_input" 'Minutes until suspend')
[[ $selection == '15 minutes' ]] || fail "menu-input did not print the selected value"
[[ $(jq -r '.mode' "$payload_log") == input ]] || fail "menu-input sent the wrong mode"
[[ $(jq -r '.prompt' "$payload_log") == 'Minutes until suspend' ]] || fail "menu-input lost its prompt"
[[ $(<"$mode_log") == 700 ]] || fail "menu-input request directory is not private"

selection=$(env "${run_menu_env[@]}" MENU_TEST_SELECTION=two "$menu_select" Choose one two three)
[[ $selection == two ]] || fail "menu-select did not print the selected option"
[[ $(jq -r '.mode' "$payload_log") == select ]] || fail "menu-select sent the wrong mode"
jq -e '.options == ["one", "two", "three"]' "$payload_log" >/dev/null || fail "menu-select lost its options"

expect_failure env "${run_menu_env[@]}" MENU_TEST_ACTION=cancel "$menu_input" Cancel
expect_failure env "${run_menu_env[@]}" MENU_TEST_ACTION=wait MENU_TEST_PING=fail "$menu_input" Lost

started_at=$(date +%s)
expect_failure env "${run_menu_env[@]}" MENU_TEST_ACTION=wait DESKTOP_SHELL_MENU_TIMEOUT=1 "$menu_input" Timeout
elapsed=$(( $(date +%s) - started_at ))
(( elapsed < 5 )) || fail "menu-input timeout was not bounded"

if compgen -G "$runtime/desktop-shell-menu/request.*" >/dev/null; then
  fail "menu callers left request directories behind"
fi

printf 'PASS: desktop shell menu input and selection callers\n'
