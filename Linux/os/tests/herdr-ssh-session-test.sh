#!/bin/sh
set -eu

repo_root=$(CDPATH= cd -- "$(dirname -- "$0")/../../.." && pwd)
wrapper=$repo_root/Both/Herdr/ssh-session.sh
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT HUP INT TERM

mkdir -p "$tmp/bin"

cat >"$tmp/bin/herdr" <<'MOCK'
#!/bin/sh
set -eu

if [ "$#" -eq 2 ] && [ "$1" = pane ] && [ "$2" = list ]; then
  printf '%s\n' '{"result":{"panes":[{"pane_id":"w1:p1","agent":"opencode","agent_status":"idle"},{"pane_id":"w1:p2","agent":"OpenCode","agent_status":"working"},{"pane_id":"w2:p1","agent":"opencode","agent_status":"done"},{"pane_id":"w2:p2","agent":"opencode","agent_status":"blocked"},{"pane_id":"w3:p1","agent":"opencode","agent_status":"unknown"},{"pane_id":"w3:p2","agent":"claude","agent_status":"idle"}]}}'
  exit 0
fi

if [ "$#" -eq 0 ]; then
  printf '%s\n' attach >>"$HERDR_TEST_LOG"
else
  printf '%s\n' "$*" >>"$HERDR_TEST_LOG"
fi
MOCK

cat >"$tmp/bin/herdr-waypipe-env" <<'MOCK'
#!/bin/sh
printf '%s\n' "$*" >>"$HERDR_TEST_CLIPBOARD_LOG"
MOCK
chmod +x "$tmp/bin/herdr" "$tmp/bin/herdr-waypipe-env"

assert_log() {
  label=$1
  expected=$2
  actual=$(cat "$HERDR_TEST_LOG")
  if [ "$actual" != "$expected" ]; then
    printf '%s\n' "$label produced unexpected Herdr commands" >&2
    printf '%s\n' 'expected:' "$expected" 'actual:' "$actual" >&2
    exit 1
  fi
}

export HERDR_TEST_LOG=$tmp/herdr.log
export HERDR_TEST_CLIPBOARD_LOG=$tmp/clipboard.log
export HERDR_BIN_PATH=$tmp/bin/herdr
PATH="$tmp/bin:$PATH"
export PATH

sh "$wrapper" disable
assert_log disable "$(cat <<'EXPECTED'
pane send-keys w1:p1 ctrl+p
pane send-text w1:p1 Disable animations
pane send-keys w1:p1 enter
pane send-keys w1:p2 ctrl+p
pane send-text w1:p2 Disable animations
pane send-keys w1:p2 enter
pane send-keys w2:p1 ctrl+p
pane send-text w2:p1 Disable animations
pane send-keys w2:p1 enter
EXPECTED
)"

: >"$HERDR_TEST_LOG"
sh "$wrapper" attach
assert_log attach "$(cat <<'EXPECTED'
pane send-keys w1:p1 ctrl+p
pane send-text w1:p1 Disable animations
pane send-keys w1:p1 enter
pane send-keys w1:p2 ctrl+p
pane send-text w1:p2 Disable animations
pane send-keys w1:p2 enter
pane send-keys w2:p1 ctrl+p
pane send-text w2:p1 Disable animations
pane send-keys w2:p1 enter
attach
pane send-keys w1:p1 ctrl+p
pane send-text w1:p1 Enable animations
pane send-keys w1:p1 enter
pane send-keys w1:p2 ctrl+p
pane send-text w1:p2 Enable animations
pane send-keys w1:p2 enter
pane send-keys w2:p1 ctrl+p
pane send-text w2:p1 Enable animations
pane send-keys w2:p1 enter
EXPECTED
)"
clipboard_log=$(cat "$HERDR_TEST_CLIPBOARD_LOG")
if [ "$clipboard_log" != clear ]; then
  printf '%s\n' 'attach cleanup did not clear the Waypipe environment' >&2
  exit 1
fi

if sh "$wrapper" invalid >/dev/null 2>&1; then
  printf '%s\n' 'invalid mode unexpectedly succeeded' >&2
  exit 1
fi

printf '%s\n' 'Herdr SSH session tests passed'
