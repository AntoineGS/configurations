#!/usr/bin/env bash
set -Eeuo pipefail

script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
script="$script_dir/../setup-context-tokenizers.sh"
tmp_dir="$(mktemp -d)"
stub_dir="$tmp_dir/bin"
prefix="$tmp_dir/vendor"
npm_log="$tmp_dir/npm.log"
original_path="$PATH"

trap 'rm -rf -- "$tmp_dir"' EXIT

fail() {
  printf 'FAIL: %s\n' "$*" >&2
  exit 1
}

mkdir -p -- "$stub_dir"
: > "$npm_log"

# The generated stub must receive these expansions at runtime, not while it is written.
# shellcheck disable=SC2016
printf '%s\n' \
  '#!/usr/bin/env bash' \
  'set -Eeuo pipefail' \
  ': "${NPM_LOG:?}"' \
  ': "${NPM_PREFIX:?}"' \
  'printf "%s\\n" "$*" >> "$NPM_LOG"' \
  'if [[ "${NPM_FAIL_STATUS:-0}" -ne 0 ]]; then exit "$NPM_FAIL_STATUS"; fi' \
  'mkdir -p -- "$NPM_PREFIX/node_modules/js-tiktoken" "$NPM_PREFIX/node_modules/@huggingface/transformers"' \
  ': > "$NPM_PREFIX/node_modules/js-tiktoken/package.json"' \
  ': > "$NPM_PREFIX/node_modules/@huggingface/transformers/package.json"' \
  > "$stub_dir/npm"
chmod +x -- "$stub_dir/npm"

[[ -x "$script" ]] || fail "$script must exist and be executable"

run_script() {
  OPENCODE_TOKENIZER_PREFIX="$prefix" \
    NPM_LOG="$npm_log" \
    NPM_PREFIX="$prefix" \
    NPM_FAIL_STATUS="${NPM_FAIL_STATUS:-0}" \
    PATH="$stub_dir:$original_path" \
    "$script" "$@"
}

clear_log() {
  : > "$npm_log"
}

assert_log() {
  local expected="$1"
  local actual

  actual="$(<"$npm_log")"
  [[ "$actual" == "$expected" ]] || {
    printf 'Expected npm calls:\n%s\nActual npm calls:\n%s\n' "$expected" "$actual" >&2
    fail "npm call log differs"
  }
}

if ! help_output="$(run_script --help 2>&1)"; then
  fail "--help did not exit successfully"
fi
[[ "$help_output" == *"Usage:"* ]] || fail "--help did not print usage"

if run_script --unknown >/dev/null 2>&1; then
  fail "unknown option unexpectedly succeeded"
else
  unknown_status=$?
fi
[[ "$unknown_status" -eq 2 ]] || fail "unknown option exited with $unknown_status instead of 2"

clear_log
if run_script --check; then
  fail "--check succeeded without both tokenizer packages"
else
  check_status=$?
fi
[[ "$check_status" -ne 0 ]] || fail "--check returned zero for missing tokenizer packages"
[[ ! -s "$npm_log" ]] || fail "--check invoked npm"

clear_log
run_script --apply || fail "--apply failed with a working npm"
assert_log "install js-tiktoken@latest @huggingface/transformers@^3.3.3 --omit=dev --no-audit --loglevel=error --prefix $prefix"
run_script --check || fail "--check failed after --apply"

rm -f -- "$prefix/node_modules/js-tiktoken/package.json" "$prefix/node_modules/@huggingface/transformers/package.json"
clear_log
NPM_FAIL_STATUS=19
if run_script --apply; then
  fail "--apply succeeded after npm failed"
else
  apply_status=$?
fi
[[ "$apply_status" -eq 19 ]] || fail "--apply exited with $apply_status instead of npm status 19"

printf 'PASS: context tokenizer setup\n'
