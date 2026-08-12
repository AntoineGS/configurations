#!/usr/bin/env bash
set -Eeuo pipefail

script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
script="$script_dir/../setup-shell-picker.sh"
tmp_dir="$(mktemp -d)"
stub_dir="$tmp_dir/bin"
source_dir="$tmp_dir/source"
bin_dir="$tmp_dir/user-bin"
binary="$bin_dir/shell-picker"
command_log="$tmp_dir/commands.log"
make_log="$tmp_dir/make.log"
original_path="$PATH"

trap 'rm -rf -- "$tmp_dir"' EXIT

fail() {
  printf 'FAIL: %s\n' "$*" >&2
  exit 1
}

mkdir -p -- "$stub_dir" "$source_dir" "$bin_dir"
: > "$command_log"
: > "$make_log"

# The generated stubs must receive these expansions at runtime, not while they are written.
# shellcheck disable=SC2016
printf '%s\n' \
  '#!/usr/bin/env bash' \
  'set -Eeuo pipefail' \
  ': "${COMMAND_LOG:?}"' \
  'printf "git %s\\n" "$*" >> "$COMMAND_LOG"' \
  '[[ -d "${2:-}" ]] || exit 1' \
  '[[ "${1:-}" == "-C" && "${3:-}" == "rev-parse" && "${4:-}" == "HEAD" ]] || exit 2' \
  'printf "%s\\n" "${GIT_HEAD:?}"' \
  > "$stub_dir/git"
chmod +x -- "$stub_dir/git"

# shellcheck disable=SC2016
printf '%s\n' \
  '#!/usr/bin/env bash' \
  'set -Eeuo pipefail' \
  ': "${COMMAND_LOG:?}"' \
  'printf "go %s\\n" "$*" >> "$COMMAND_LOG"' \
  '[[ "${1:-}" == "version" && "${2:-}" == "-m" ]] || exit 2' \
  'if [[ "${GO_METADATA_MATCH:-1}" -eq 1 ]]; then printf "path example\\nvcs.revision=%s\\n" "${GIT_HEAD:?}"; else printf "path example\\nvcs.revision=wrong\\n"; fi' \
  > "$stub_dir/go"
chmod +x -- "$stub_dir/go"

# shellcheck disable=SC2016
printf '%s\n' \
  '#!/usr/bin/env bash' \
  'set -Eeuo pipefail' \
  ': "${MAKE_LOG:?}"' \
  'printf "%s:%s\\n" "$PWD" "$*" >> "$MAKE_LOG"' \
  '[[ "${1:-}" == build || "${1:-}" == install ]] || exit 2' \
  'if [[ "${1:-}" == install ]]; then' \
  '  mkdir -p -- "${GOBIN:?}"' \
  '  printf "%s\\n" "#!/usr/bin/env bash" "[[ \"\${1:-}\" == version ]] && printf \"shell-picker dev\\n\"" > "${GOBIN}/shell-picker"' \
  '  chmod +x -- "${GOBIN}/shell-picker"' \
  'fi' \
  > "$stub_dir/make"
chmod +x -- "$stub_dir/make"

# shellcheck disable=SC2016
printf '%s\n' \
  '#!/usr/bin/env bash' \
  'set -Eeuo pipefail' \
  '[[ "${1:-}" == version ]] && printf "%s\\n" "${SHELL_PICKER_VERSION:-shell-picker dev}"' \
  > "$binary"
chmod +x -- "$binary"

[[ -x "$script" ]] || fail "$script must exist and be executable"

run_script() {
  SHELL_PICKER_SOURCE_DIR="$source_dir" \
    SHELL_PICKER_BIN_DIR="$bin_dir" \
    SHELL_PICKER_BINARY="$binary" \
    COMMAND_LOG="$command_log" \
    MAKE_LOG="$make_log" \
    GIT_HEAD="${GIT_HEAD:-abc123}" \
    GO_METADATA_MATCH="${GO_METADATA_MATCH:-1}" \
    SHELL_PICKER_VERSION="${SHELL_PICKER_VERSION:-}" \
    PATH="$stub_dir:$original_path" \
    "$script" "$@"
}

clear_logs() {
  : > "$command_log"
  : > "$make_log"
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

clear_logs
run_script --check || fail "--check failed for a matching shell-picker binary"
[[ ! -s "$make_log" ]] || fail "--check invoked make"

GO_METADATA_MATCH=0
if run_script --check; then
  fail "--check succeeded with mismatched build metadata"
fi
GO_METADATA_MATCH=1

SHELL_PICKER_VERSION="shell-picker wrong"
if run_script --check; then
  fail "--check succeeded with an unexpected binary version"
fi
unset SHELL_PICKER_VERSION

rm -- "$binary"
clear_logs
run_script --apply || fail "--apply failed with a working make"
[[ -x "$binary" ]] || fail "--apply did not install an executable binary"
[[ "$(<"$make_log")" == "$source_dir:build"$'\n'"$source_dir:install" ]] || fail "--apply make calls differ"
run_script --check || fail "--check failed after --apply"

rm -rf -- "$source_dir"
if run_script --check; then
  fail "--check succeeded without the source repository"
fi

printf 'PASS: shell-picker setup\n'
