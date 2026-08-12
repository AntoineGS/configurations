#!/usr/bin/env bash
set -Eeuo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
readonly ROOT
readonly BOOTSTRAP="$ROOT/Linux/install/bootstrap"
TEST_ROOT="$(mktemp -d)"
readonly TEST_ROOT
readonly ARCH_RELEASE="$TEST_ROOT/arch-release"
readonly NON_ARCH_RELEASE="$TEST_ROOT/non-arch-release"
readonly REPO_WITH_SPACES="$TEST_ROOT/repository with spaces"
readonly OUTSIDE_REPOSITORY="$TEST_ROOT/outside"
readonly STUB_BIN="$TEST_ROOT/bin"
readonly STUB_LOG="$TEST_ROOT/stub.log"
readonly BASH_PATH="$BASH"
UNSHARE="$(command -v unshare || true)"
readonly UNSHARE

LAST_OUTPUT=""
LAST_STATUS=0
CURL_FAIL=false

cleanup() {
  rm -rf -- "$TEST_ROOT"
}
trap cleanup EXIT

fail() {
  printf 'FAIL: %s\n' "$1" >&2
  exit 1
}

assert_status() {
  local -r expected="$1"
  local -r actual="$2"
  local -r context="$3"

  [[ "$actual" == "$expected" ]] || fail "$context: expected exit $expected, got $actual\n$LAST_OUTPUT"
}

assert_contains() {
  local -r haystack="$1"
  local -r needle="$2"
  local -r context="$3"

  [[ "$haystack" == *"$needle"* ]] || fail "$context: output did not contain '$needle'\n$haystack"
}

assert_not_contains() {
  local -r haystack="$1"
  local -r needle="$2"
  local -r context="$3"

  [[ "$haystack" != *"$needle"* ]] || fail "$context: output contained '$needle'\n$haystack"
}

assert_no_mutation_commands() {
  local -r log_contents="$1"

  for command_name in pacman yay git tidydots systemctl sudo; do
    assert_not_contains "$log_contents" "$command_name " "mutation command log"
  done
}

write_executable() {
  local -r path="$1"
  shift

  printf '%s\n' '#!/usr/bin/bash' "$@" >"$path"
  chmod +x -- "$path"
}

create_stub_path() {
  local -r path="$1"
  local command_name

  mkdir -p -- "$path"
  for command_name in bash curl git pacman sudo systemctl yay tidydots; do
    if [[ "$command_name" == curl ]]; then
      write_executable "$path/$command_name" \
        "printf \"%s\\\\n\" \"\${0##*/} \$*\" >> \"\$BOOTSTRAP_STUB_LOG\"" \
        "if [[ \"\${BOOTSTRAP_CURL_FAIL:-false}\" == true ]]; then exit 1; fi"
    elif [[ "$command_name" == bash ]]; then
      write_executable "$path/$command_name" 'exit 0'
    else
      write_executable "$path/$command_name" \
        "printf \"%s\\\\n\" \"\${0##*/} \$*\" >> \"\$BOOTSTRAP_STUB_LOG\""
    fi
  done

  write_executable "$path/dirname" "printf \"%s\\\\n\" \"\${1%/*}\""
  write_executable "$path/pwd" '/usr/bin/pwd "$@"'
}

run_bootstrap() {
  local -r path="$1"
  local -r os_release="$2"
  local -r hostname="$3"
  shift 3

  if LAST_OUTPUT=$(PATH="$path" \
    BOOTSTRAP_OS_RELEASE="$os_release" \
    BOOTSTRAP_HOSTNAME="$hostname" \
    BOOTSTRAP_STUB_LOG="$STUB_LOG" \
    BOOTSTRAP_CURL_FAIL="$CURL_FAIL" \
    "$BASH_PATH" "$BOOTSTRAP" "$@" 2>&1); then
    LAST_STATUS=0
  else
    LAST_STATUS=$?
  fi
}

assert_preflight_success() {
  assert_status 0 "$LAST_STATUS" "successful preflight"
  assert_contains "$LAST_OUTPUT" "preflight passed" "successful preflight"
}

mkdir -p -- "$REPO_WITH_SPACES" "$OUTSIDE_REPOSITORY"
printf '%s\n' 'name: bootstrap-test-fixture' >"$REPO_WITH_SPACES/tidydots.yaml"
printf '%s\n' 'ID=arch' >"$ARCH_RELEASE"
printf '%s\n' 'ID=debian' >"$NON_ARCH_RELEASE"
create_stub_path "$STUB_BIN"
write_executable "$STUB_BIN/hostnamectl" \
  'printf "%s\\n" server' \
  'exit 1'
: >"$STUB_LOG"

[[ -n "$UNSHARE" ]] || fail 'unshare is required for the root execution test'

test_help() {
  run_bootstrap "$STUB_BIN" "$ARCH_RELEASE" server --help

  assert_status 0 "$LAST_STATUS" '--help'
  assert_contains "$LAST_OUTPUT" 'Usage:' '--help'
}

test_unknown_option() {
  run_bootstrap "$STUB_BIN" "$ARCH_RELEASE" server --unknown

  assert_status 2 "$LAST_STATUS" 'unknown option'
  assert_contains "$LAST_OUTPUT" 'unknown option' 'unknown option'
}

test_missing_repo_value() {
  run_bootstrap "$STUB_BIN" "$ARCH_RELEASE" server --repo

  assert_status 2 "$LAST_STATUS" 'missing --repo value'
  assert_contains "$LAST_OUTPUT" 'missing value for --repo' 'missing --repo value'
}

test_missing_repository_is_environment_failure() {
  run_bootstrap "$STUB_BIN" "$ARCH_RELEASE" server --dry-run --repo "$TEST_ROOT/missing-repository"

  assert_status 1 "$LAST_STATUS" 'missing repository'
  assert_contains "$LAST_OUTPUT" 'repository directory does not exist' 'missing repository'
}

test_root_execution_rejected() {
  : >"$STUB_LOG"
  if LAST_OUTPUT=$(PATH="$STUB_BIN" \
    BOOTSTRAP_OS_RELEASE="$ARCH_RELEASE" \
    BOOTSTRAP_HOSTNAME=server \
    BOOTSTRAP_STUB_LOG="$STUB_LOG" \
    "$UNSHARE" --user --map-root-user "$BASH_PATH" "$BOOTSTRAP" \
    --dry-run --repo "$REPO_WITH_SPACES" 2>&1); then
    LAST_STATUS=0
  else
    LAST_STATUS=$?
  fi

  assert_status 1 "$LAST_STATUS" 'root execution'
  assert_contains "$LAST_OUTPUT" 'must not run as root' 'root execution'
}

test_non_arch_rejected() {
  run_bootstrap "$STUB_BIN" "$NON_ARCH_RELEASE" server --dry-run --repo "$REPO_WITH_SPACES"

  assert_status 1 "$LAST_STATUS" 'non-Arch os-release'
  assert_contains "$LAST_OUTPUT" 'ID=arch' 'non-Arch os-release'
}

test_hostname_command_failure_is_not_masked() {
  : >"$STUB_LOG"
  if LAST_OUTPUT=$(env -u BOOTSTRAP_HOSTNAME \
    PATH="$STUB_BIN" \
    BOOTSTRAP_OS_RELEASE="$ARCH_RELEASE" \
    BOOTSTRAP_STUB_LOG="$STUB_LOG" \
    BOOTSTRAP_CURL_FAIL=false \
    "$BASH_PATH" "$BOOTSTRAP" --dry-run --repo "$REPO_WITH_SPACES" 2>&1); then
    LAST_STATUS=0
  else
    LAST_STATUS=$?
  fi

  assert_status 1 "$LAST_STATUS" 'hostname command failure'
  assert_contains "$LAST_OUTPUT" 'could not resolve the static hostname' 'hostname command failure'
  assert_no_mutation_commands "$(<"$STUB_LOG")"
  assert_not_contains "$(<"$STUB_LOG")" 'curl ' 'hostname command failure network check'
}

test_unknown_hostname_rejected_before_commands() {
  : >"$STUB_LOG"
  run_bootstrap "$STUB_BIN" "$ARCH_RELEASE" unknown-host --dry-run --repo "$REPO_WITH_SPACES"

  assert_status 1 "$LAST_STATUS" 'unknown hostname'
  assert_contains "$LAST_OUTPUT" 'unknown hostname' 'unknown hostname'
  assert_no_mutation_commands "$(<"$STUB_LOG")"
  assert_not_contains "$(<"$STUB_LOG")" 'curl ' 'unknown hostname network check'
}

test_missing_command_names_command() {
  local -r missing_bin="$TEST_ROOT/missing-pacman-bin"
  local command_name

  mkdir -p -- "$missing_bin"
  for command_name in bash curl git sudo systemctl yay tidydots dirname pwd; do
    cp -- "$STUB_BIN/$command_name" "$missing_bin/$command_name"
  done

  run_bootstrap "$missing_bin" "$ARCH_RELEASE" server --dry-run --repo "$REPO_WITH_SPACES"

  assert_status 1 "$LAST_STATUS" 'missing required command'
  assert_contains "$LAST_OUTPUT" 'missing required command: pacman' 'missing required command'
}

test_repository_path_with_spaces() {
  : >"$STUB_LOG"
  CURL_FAIL=false
  run_bootstrap "$STUB_BIN" "$ARCH_RELEASE" server --dry-run --repo "$REPO_WITH_SPACES"

  assert_preflight_success
  assert_contains "$LAST_OUTPUT" "$REPO_WITH_SPACES" 'repository path with spaces'
  assert_no_mutation_commands "$(<"$STUB_LOG")"
}

test_default_mode_does_not_prompt() {
  : >"$STUB_LOG"
  CURL_FAIL=false
  run_bootstrap "$STUB_BIN" "$ARCH_RELEASE" server --repo "$REPO_WITH_SPACES"

  assert_preflight_success
  assert_contains "$LAST_OUTPUT" 'read-only' 'default mode'
  assert_no_mutation_commands "$(<"$STUB_LOG")"
}

test_invocation_outside_repository_resolves_repo() {
  : >"$STUB_LOG"
  CURL_FAIL=false
  if LAST_OUTPUT=$(cd -- "$OUTSIDE_REPOSITORY" && \
    PATH="$STUB_BIN" \
    BOOTSTRAP_OS_RELEASE="$ARCH_RELEASE" \
    BOOTSTRAP_HOSTNAME=server \
    BOOTSTRAP_STUB_LOG="$STUB_LOG" \
    BOOTSTRAP_CURL_FAIL="$CURL_FAIL" \
    "$BASH_PATH" "$BOOTSTRAP" --dry-run 2>&1); then
    LAST_STATUS=0
  else
    LAST_STATUS=$?
  fi

  assert_preflight_success
  assert_contains "$LAST_OUTPUT" "$ROOT" 'invocation outside repository'
  assert_no_mutation_commands "$(<"$STUB_LOG")"
}

test_network_failure_stops_before_mutation() {
  : >"$STUB_LOG"
  CURL_FAIL=true
  run_bootstrap "$STUB_BIN" "$ARCH_RELEASE" server --dry-run --repo "$REPO_WITH_SPACES"
  CURL_FAIL=false

  assert_status 1 "$LAST_STATUS" 'network failure'
  assert_contains "$LAST_OUTPUT" 'network check failed' 'network failure'
  assert_no_mutation_commands "$(<"$STUB_LOG")"
  assert_contains "$(<"$STUB_LOG")" 'curl --fail --silent --show-error --head https://aur.archlinux.org/' \
    'network failure curl invocation'
}

run_preflight_tests() {
  test_help
  test_unknown_option
  test_missing_repo_value
  test_missing_repository_is_environment_failure
  test_root_execution_rejected
  test_non_arch_rejected
  test_hostname_command_failure_is_not_masked
  test_unknown_hostname_rejected_before_commands
  test_missing_command_names_command
  test_repository_path_with_spaces
  test_default_mode_does_not_prompt
  test_invocation_outside_repository_resolves_repo
  test_network_failure_stops_before_mutation
  printf 'bootstrap preflight tests passed\n'
}

case "${1:-}" in
  preflight)
    run_preflight_tests
    ;;
  *)
    printf 'Usage: %s preflight\n' "${BASH_SOURCE[0]##*/}" >&2
    exit 2
    ;;
esac
