#!/usr/bin/env bash
set -Eeuo pipefail

ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../../.." && pwd -P)"
TEST_ROOT=$(mktemp -d)
trap 'rm -rf -- "$TEST_ROOT"' EXIT

printf '%s\n' \
  '#!/usr/bin/env bash' \
  'exit 2' \
  >"$TEST_ROOT/rg"
chmod +x -- "$TEST_ROOT/rg"

if output=$(RG_BIN="$TEST_ROOT/rg" bash "$ROOT/Linux/os/tests/no-omarchy-runtime-test.sh" 2>&1); then
  printf '%s\n' 'runtime audit accepted an rg operational error' >&2
  exit 1
else
  status=$?
fi

if [[ $status != 2 ]]; then
  printf 'runtime audit returned %s for an rg operational error:\n%s\n' "$status" "$output" >&2
  exit 1
fi

[[ $output == *'rg failed while auditing active sources (exit 2)'* ]]
