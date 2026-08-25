#!/usr/bin/env bash
set -Eeuo pipefail

repo_root=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../../.." && pwd)
helper=$repo_root/Linux/os/helpers/start-all-terminals
test_root=$(mktemp -d)
bin=$test_root/bin
home=$test_root/home
runtime=$test_root/runtime
clients=$test_root/clients.json
active=$test_root/active.json
log=$test_root/terminal.log
state_lock=$test_root/state.lock

trap 'rm -rf "$test_root"' EXIT

fail() {
  printf 'FAIL: %s\n' "$1" >&2
  exit 1
}

[[ -x $helper ]] || fail "start-all-terminals helper is missing or not executable: $helper"
install -d -m 700 "$bin" "$home" "$runtime"
printf '[]\n' >"$clients"
printf '{}\n' >"$active"

cat >"$bin/add-client" <<'EOF'
#!/usr/bin/env bash
set -Eeuo pipefail
class=$1
address=$2
(
  flock 9
  jq --arg class "$class" --arg address "$address" '. + [{class:$class,address:$address}]' "$CLIENTS_FILE" >"$CLIENTS_FILE.next"
  mv "$CLIENTS_FILE.next" "$CLIENTS_FILE"
  jq -n --arg class "$class" --arg address "$address" '{class:$class,address:$address}' >"$ACTIVE_FILE"
) 9>"$STATE_LOCK"
EOF

cat >"$bin/hyprctl" <<'EOF'
#!/usr/bin/env bash
set -Eeuo pipefail
case "$*" in
  "clients -j") cat "$CLIENTS_FILE" ;;
  "activewindow -j") cat "$ACTIVE_FILE" ;;
  eval*) printf 'hyprctl %s\n' "$*" >>"$TERMINAL_TEST_LOG" ;;
  *) exit 2 ;;
esac
EOF

cat >"$bin/uwsm-app" <<'EOF'
#!/usr/bin/env bash
set -Eeuo pipefail
printf 'uwsm-app %s\n' "$*" >>"$TERMINAL_TEST_LOG"
case "$*" in
  *--app-id=desktop-shell-local*) class=desktop-shell-local; address=0x101 ;;
  *--app-id=desktop-shell-pc*) class=desktop-shell-pc; address=0x102 ;;
  *--app-id=desktop-shell-work*) class=desktop-shell-work; address=0x103 ;;
  *) exit 2 ;;
esac
/usr/bin/sleep 0.3
add-client "$class" "$address"
EOF

cat >"$bin/launch-or-focus" <<'EOF'
#!/usr/bin/env bash
set -Eeuo pipefail
printf 'launch-or-focus %s\n' "$*" >>"$TERMINAL_TEST_LOG"
add-client brave-browser 0x104
EOF

cat >"$bin/sleep" <<'EOF'
#!/usr/bin/env bash
/usr/bin/sleep 0.01
EOF
cat >"$bin/notify-send" <<'EOF'
#!/usr/bin/env bash
printf 'notify-send %s\n' "$*" >>"$TERMINAL_TEST_LOG"
EOF
chmod +x "$bin"/*

run_env=(
  HOME="$home"
  XDG_RUNTIME_DIR="$runtime"
  PATH="$bin:$PATH"
  CLIENTS_FILE="$clients"
  ACTIVE_FILE="$active"
  STATE_LOCK="$state_lock"
  TERMINAL_TEST_LOG="$log"
)

env "${run_env[@]}" "$helper"
grep -F -- '--app-id=desktop-shell-local' "$log" >/dev/null || fail "local terminal app ID was not neutralized"
grep -F -- '--app-id=desktop-shell-pc' "$log" >/dev/null || fail "PC terminal app ID was not neutralized"
grep -F -- '--app-id=desktop-shell-work' "$log" >/dev/null || fail "work terminal app ID was not neutralized"
for expected in 'workspace=1' 'name="local"' 'workspace=2' 'name="pc"' 'workspace=3' 'name="work"' 'workspace=4' 'name="browser"'; do
  grep -F -- "$expected" "$log" >/dev/null || fail "missing workspace dispatch: $expected"
done
[[ $(grep -Fc "hl.dsp.focus({workspace=1})" "$log") -ge 2 ]] || fail "final focus did not return to workspace 1"

printf '[]\n' >"$clients"
printf '{}\n' >"$active"
: >"$log"
env "${run_env[@]}" "$helper" &
first_pid=$!
env "${run_env[@]}" "$helper" &
second_pid=$!
wait "$first_pid"
wait "$second_pid"
[[ $(grep -Fc -- '--app-id=desktop-shell-local' "$log") -eq 1 ]] || fail "concurrent invocation bypassed the nonblocking lock"

printf 'PASS: terminal workspace launcher\n'
