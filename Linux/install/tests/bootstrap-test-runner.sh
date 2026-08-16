#!/usr/bin/env bash
set -Eeuo pipefail

if [[ $# -lt 1 || "$1" == --* ]]; then
  printf 'Usage: %s LOCK_PATH [bootstrap options...]\n' "${BASH_SOURCE[0]##*/}" >&2
  exit 2
fi

readonly TEST_LIFECYCLE_LOCK="$1"
shift

[[ "$TEST_LIFECYCLE_LOCK" == /* ]] || {
  printf '%s: lock path must be absolute\n' "${BASH_SOURCE[0]##*/}" >&2
  exit 2
}

SCRIPT_DIR="${BASH_SOURCE[0]%/*}"
[[ "$SCRIPT_DIR" == /* ]] || SCRIPT_DIR="$PWD/$SCRIPT_DIR"
SCRIPT_DIR="$(cd -- "$SCRIPT_DIR" && pwd -P)"
readonly SCRIPT_DIR
readonly BOOTSTRAP="$SCRIPT_DIR/../bootstrap"
readonly TEST_ROOT="${BOOTSTRAP_TEST_ROOT:-}"
readonly TEST_MARKER="${BOOTSTRAP_TEST_MARKER:-}"
readonly TEST_BIN="${BOOTSTRAP_TEST_BIN:-}"
readonly TEST_REPO="${BOOTSTRAP_TEST_REPO:-}"
readonly TEST_OS_RELEASE="${BOOTSTRAP_TEST_OS_RELEASE:-}"
readonly TEST_HOSTNAME="${BOOTSTRAP_TEST_HOSTNAME:-}"
readonly TEST_MISSING_COMMANDS="${BOOTSTRAP_TEST_MISSING_COMMANDS:-}"

readonly MARKER_CONTENT=bootstrap-test-fixture-v1
readonly REQUIRED_COMMANDS=(
  awk bash curl dirname env find flock git hostname hostnamectl makepkg mktemp pacman rm sudo sync systemctl tee tidydots yay
)

runner_reject() {
  printf 'bootstrap-test-runner: %s\n' "$1" >&2
  exit 2
}

canonical_directory() {
  local -r path="$1"

  [[ "$path" == /* && -d "$path" && ! -L "$path" ]] || return 1
  (cd -- "$path" && pwd -P)
}

canonical_file() {
  local -r path="$1"
  local -r parent="${path%/*}"
  local -r name="${path##*/}"
  local canonical_parent

  [[ "$path" == /* && -f "$path" && ! -L "$path" ]] || return 1
  canonical_parent="$(canonical_directory "$parent")" || return 1
  printf '%s/%s\n' "$canonical_parent" "$name"
}

path_is_below_root() {
  local -r path="$1"
  local -r root="$2"

  [[ "$path" == "$root"/* ]]
}

validate_fixture_path() {
  local -r label="$1"
  local -r path="$2"
  local canonical_path

  canonical_path="$(canonical_directory "$path" 2>/dev/null)" || runner_reject "$label is not a real directory inside the fixture"
  path_is_below_root "$canonical_path" "$TEST_ROOT_CANONICAL" ||
    runner_reject "$label is outside the fixture root: $path"
  printf '%s\n' "$canonical_path"
}

validate_fixture_file() {
  local -r label="$1"
  local -r path="$2"
  local canonical_path

  canonical_path="$(canonical_file "$path" 2>/dev/null)" || runner_reject "$label is not a regular fixture file: $path"
  path_is_below_root "$canonical_path" "$TEST_ROOT_CANONICAL" ||
    runner_reject "$label is outside the fixture root: $path"
  printf '%s\n' "$canonical_path"
}

[[ -n "$TEST_ROOT" && -n "$TEST_MARKER" && -n "$TEST_BIN" && -n "$TEST_REPO" ]] ||
  runner_reject 'fixture root, marker, bin, and repository are required'

TEST_ROOT_CANONICAL="$(canonical_directory "$TEST_ROOT" 2>/dev/null)" ||
  runner_reject 'fixture root is not a real directory'
readonly TEST_ROOT_CANONICAL

[[ "$TEST_MARKER" == "$TEST_ROOT/.bootstrap-test-fixture" ]] ||
  runner_reject 'fixture marker must be the root marker file'
TEST_MARKER_CANONICAL="$(validate_fixture_file 'fixture marker' "$TEST_MARKER")"
readonly TEST_MARKER_CANONICAL
[[ "$(<"$TEST_MARKER_CANONICAL")" == "$MARKER_CONTENT" ]] || runner_reject 'fixture marker content is invalid'

TEST_BIN_CANONICAL="$(validate_fixture_path 'fixture bin' "$TEST_BIN")"
readonly TEST_BIN_CANONICAL
TEST_REPO_CANONICAL="$(validate_fixture_path 'fixture repository' "$TEST_REPO")"
readonly TEST_REPO_CANONICAL
TEST_OS_RELEASE_CANONICAL="$(validate_fixture_file 'os-release fixture' "$TEST_OS_RELEASE")"
readonly TEST_OS_RELEASE_CANONICAL

[[ "${PATH:-}" == "$TEST_BIN_CANONICAL" ]] || runner_reject 'PATH must contain only the fixture bin'

TEST_LOCK_PARENT="${TEST_LIFECYCLE_LOCK%/*}"
TEST_LOCK_PARENT_CANONICAL="$(canonical_directory "$TEST_LOCK_PARENT" 2>/dev/null)" ||
  runner_reject 'lifecycle lock must be inside the fixture root'
[[ "$TEST_LOCK_PARENT_CANONICAL" == "$TEST_ROOT_CANONICAL" ||
  "$TEST_LOCK_PARENT_CANONICAL" == "$TEST_ROOT_CANONICAL"/* ]] ||
  runner_reject 'lifecycle lock must be inside the fixture root'
[[ -f "$TEST_REPO_CANONICAL/tidydots.yaml" && ! -L "$TEST_REPO_CANONICAL/tidydots.yaml" ]] ||
  runner_reject 'fixture repository is missing tidydots.yaml'
[[ -f "$TEST_REPO_CANONICAL/Linux/Snapper/snapper-initialize" &&
  ! -L "$TEST_REPO_CANONICAL/Linux/Snapper/snapper-initialize" &&
  -x "$TEST_REPO_CANONICAL/Linux/Snapper/snapper-initialize" ]] ||
  runner_reject 'Snapper helper must be executable inside the fixture repository'

for command_name in "${REQUIRED_COMMANDS[@]}"; do
  command_path="$TEST_BIN_CANONICAL/$command_name"
  [[ -f "$command_path" && ! -L "$command_path" && -x "$command_path" ]] ||
    runner_reject "missing executable stub: $command_name"
  resolved_command="$(command -v "$command_name" || true)"
  [[ "$resolved_command" == "$command_path" ]] ||
    runner_reject "command does not resolve to fixture stub: $command_name"
done

# shellcheck disable=SC2086
for missing_command in $TEST_MISSING_COMMANDS; do
  case "$missing_command" in
    awk|bash|curl|dirname|env|find|flock|git|hostname|hostnamectl|makepkg|mktemp|pacman|rm|sudo|sync|systemctl|tee|tidydots|yay)
      ;;
    *)
      runner_reject "unknown test command mask: $missing_command"
      ;;
  esac
done

validate_repo_option() {
  local option_index
  local option_value
  local canonical_option
  local -a options=("$@")

  for ((option_index = 0; option_index < ${#options[@]}; option_index++)); do
    case "${options[$option_index]}" in
      --repo)
        option_index=$((option_index + 1))
        [[ "$option_index" -lt "${#options[@]}" ]] || return 0
        option_value="${options[$option_index]}"
        [[ "$option_value" == --* ]] && return 0
        canonical_option="$(canonical_directory "$option_value" 2>/dev/null)" ||
          runner_reject "repository is outside the fixture root: $option_value"
        [[ "$canonical_option" == "$TEST_REPO_CANONICAL" ]] ||
          runner_reject "repository is outside the fixture root: $option_value"
        ;;
    esac
  done
}

validate_repo_option "$@"

[[ -n "$TEST_HOSTNAME" ]] || {
  printf '%s: missing BOOTSTRAP_TEST_HOSTNAME fixture\n' "${BASH_SOURCE[0]##*/}" >&2
  exit 2
}

# Sourcing is the explicit test-only boundary; production bootstrap never parses a lock selector.
# shellcheck disable=SC1090
source "$BOOTSTRAP"

# Test fixtures are injected only after production functions have been loaded.
check_arch() {
  local line=""
  local os_id=""

  while IFS= read -r line || [[ -n "$line" ]]; do
    if [[ "$line" == ID=* ]]; then
      os_id="${line#ID=}"
      os_id="${os_id#\"}"
      os_id="${os_id%\"}"
      break
    fi
  done <"$TEST_OS_RELEASE_CANONICAL"

  [[ "$os_id" == arch ]] || die 'unsupported operating system: require ID=arch'
}

resolve_hostname() {
  printf '%s\n' "$TEST_HOSTNAME"
}

command_available() {
  local -r command_name="$1"

  # shellcheck disable=SC2086
  case " $TEST_MISSING_COMMANDS " in
    *" $command_name "*) return 1 ;;
  esac
  command -v "$command_name" >/dev/null 2>&1
}

# shellcheck disable=SC2034
SNAPPER_LIFECYCLE_LOCK="$TEST_LIFECYCLE_LOCK"
# shellcheck disable=SC2034
REPO_ROOT="$TEST_REPO_CANONICAL"
bootstrap_main "$@"
