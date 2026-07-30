#!/bin/bash

set -euo pipefail

SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
WRAPPER="$SCRIPT_DIR/../scripts/close-rustdesk-windows-in.sh"
TEST_ROOT=$(mktemp -d)
trap 'rm -rf "$TEST_ROOT"' EXIT

export HOME="$TEST_ROOT/home"
export ARG_LOG="$TEST_ROOT/argument.log"
FIFO="$TEST_ROOT/stdin"
mkdir -p "$HOME/.local/share/helpers"
mkfifo "$FIFO"

cat >"$HOME/.local/share/helpers/close-rustdesk-windows-in" <<'EOF'
#!/bin/bash
printf '%s\n' "$*" >"$ARG_LOG"
[[ $(readlink /proc/$$/fd/0) == "/dev/null" ]]
IFS= read -r || true
EOF
chmod +x "$HOME/.local/share/helpers/close-rustdesk-windows-in"

exec 9<>"$FIFO"
if timeout 2s "$WRAPPER" 25 <"$FIFO"; then
  :
else
  status=$?
  if (( status == 124 )); then
    printf 'wrapper did not exit promptly while its stdin was held open\n' >&2
  else
    printf 'wrapper did not detach stdin before invoking close-rustdesk-windows-in (exit %s)\n' "$status" >&2
  fi
  exit 1
fi
exec 9>&-

[[ $(<"$ARG_LOG") == "25" ]] || {
  printf 'wrapper did not forward the minutes argument\n' >&2
  exit 1
}

printf 'PASS: vicinae RustDesk close timer wrapper\n'
