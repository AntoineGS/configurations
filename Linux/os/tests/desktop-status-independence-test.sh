#!/usr/bin/env bash
set -Eeuo pipefail

ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../../.." && pwd)"

for file in \
  "$ROOT/Linux/os/helpers/screenrecording-status" \
  "$ROOT/Linux/os/helpers/update-available"; do
  test -x "$file"
  bash -n "$file"
done

grep -Fq '"type": "os"' "$ROOT/Linux/fastfetch/config.jsonc"
if grep -Eiq 'omarchy|OMARCHY_PATH|\.config/omarchy|\.local/share/omarchy' \
  "$ROOT/Linux/fastfetch/config.jsonc" \
  "$ROOT/Linux/os/helpers/update-available"; then
  exit 1
fi

printf '%s\n' 'desktop status independence tests passed'
