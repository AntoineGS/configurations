#!/bin/bash

set -euo pipefail

SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
WRAPPER="$SCRIPT_DIR/../scripts/suspend-in.sh"
TEST_ROOT=$(mktemp -d)
trap 'rm -rf "$TEST_ROOT"' EXIT

export HOME="$TEST_ROOT/home"
export ARG_LOG="$TEST_ROOT/argument.log"
BIN="$TEST_ROOT/bin"
FIFO="$TEST_ROOT/stdin"
mkdir -p "$HOME/.local/share/helpers" "$BIN"
mkfifo "$FIFO"

for command in systemctl systemd-run notify-send; do
  cat >"$BIN/$command" <<'EOF'
#!/bin/bash
exit 0
EOF
done

cat >"$BIN/date" <<'EOF'
#!/bin/bash
printf '23:45\n'
EOF
chmod +x "$BIN/systemctl" "$BIN/systemd-run" "$BIN/notify-send" "$BIN/date"
export PATH="$BIN:/usr/bin:/bin"

cat >"$HOME/.local/share/helpers/suspend-in" <<'EOF'
#!/bin/bash
printf '%s\n' "$*" >"$ARG_LOG"
[[ $(readlink /proc/$$/fd/0) == "/dev/null" ]]
EOF
chmod +x "$HOME/.local/share/helpers/suspend-in"

exec 9<>"$FIFO"
if ! "$WRAPPER" 25 <"$FIFO"; then
  printf 'wrapper did not detach stdin before invoking suspend-in\n' >&2
  exit 1
fi
exec 9>&-

[[ $(<"$ARG_LOG") == "25" ]] || {
  printf 'wrapper did not forward the minutes argument\n' >&2
  exit 1
}

printf 'PASS: vicinae suspend timer wrapper\n'
