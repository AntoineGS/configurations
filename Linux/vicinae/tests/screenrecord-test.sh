#!/bin/bash

set -euo pipefail

SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
WRAPPER="$SCRIPT_DIR/../scripts/screenrecord.sh"
TEST_ROOT=$(mktemp -d)
trap 'rm -rf "$TEST_ROOT"' EXIT

export HOME="$TEST_ROOT/home"
export STDOUT_MARKER="$TEST_ROOT/stdout-survived"
export STDERR_MARKER="$TEST_ROOT/stderr-survived"
mkdir -p "$HOME/.local/share/helpers"

cat >"$HOME/.local/share/helpers/menu" <<'EOF'
#!/bin/bash

set -e

(
  sleep 0.05
  printf 'recorder stdout status\n'
  : >"$STDOUT_MARKER"
) &

(
  sleep 0.05
  printf 'recorder stderr status\n' >&2
  : >"$STDERR_MARKER"
) &
EOF
chmod +x "$HOME/.local/share/helpers/menu"

"$WRAPPER" |& true

for ((attempt = 0; attempt < 50; attempt++)); do
  [[ -f $STDOUT_MARKER && -f $STDERR_MARKER ]] && exit 0
  sleep 0.02
done

[[ -f $STDOUT_MARKER ]] || printf 'background recorder did not survive closed stdout\n' >&2
[[ -f $STDERR_MARKER ]] || printf 'background recorder did not survive closed stderr\n' >&2
exit 1
