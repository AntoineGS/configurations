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
readonly PREREQUISITE_BIN="$TEST_ROOT/prerequisite-bin"
readonly PREREQUISITE_TEMP_ROOT="$TEST_ROOT/prerequisite-temp"
readonly YAY_STUB_TEMPLATE="$TEST_ROOT/yay-stub"
readonly TIDYDOTS_STUB_TEMPLATE="$TEST_ROOT/tidydots-stub"
readonly BASH_PATH="$BASH"
UNSHARE="$(command -v unshare || true)"
readonly UNSHARE

LAST_OUTPUT=""
LAST_STATUS=0
CURL_FAIL=false
PREREQUISITE_GIT_FAIL=false
PREREQUISITE_MAKEPKG_FAIL=false
PREREQUISITE_YAY_FAIL=false
PREREQUISITE_CREATE_YAY=false
PREREQUISITE_CREATE_TIDYDOTS=false

shopt -s nullglob

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

  for command_name in pacman yay git tidydots makepkg mktemp rm systemctl sudo; do
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
    BOOTSTRAP_STUB_BIN="$path" \
    BOOTSTRAP_MKTEMP_ROOT="$PREREQUISITE_TEMP_ROOT" \
    BOOTSTRAP_YAY_STUB="$YAY_STUB_TEMPLATE" \
    BOOTSTRAP_TIDYDOTS_STUB="$TIDYDOTS_STUB_TEMPLATE" \
    BOOTSTRAP_GIT_FAIL="$PREREQUISITE_GIT_FAIL" \
    BOOTSTRAP_MAKEPKG_FAIL="$PREREQUISITE_MAKEPKG_FAIL" \
    BOOTSTRAP_YAY_FAIL="$PREREQUISITE_YAY_FAIL" \
    BOOTSTRAP_CREATE_YAY="$PREREQUISITE_CREATE_YAY" \
    BOOTSTRAP_CREATE_TIDYDOTS="$PREREQUISITE_CREATE_TIDYDOTS" \
    "$BASH_PATH" "$BOOTSTRAP" "$@" 2>&1); then
    LAST_STATUS=0
  else
    LAST_STATUS=$?
  fi
}

run_bootstrap_with_input() {
  local -r input="$1"
  local -r path="$2"
  local -r os_release="$3"
  local -r hostname="$4"
  shift 4

  if LAST_OUTPUT=$(printf '%s\n' "$input" | \
    PATH="$path" \
    BOOTSTRAP_OS_RELEASE="$os_release" \
    BOOTSTRAP_HOSTNAME="$hostname" \
    BOOTSTRAP_STUB_LOG="$STUB_LOG" \
    BOOTSTRAP_CURL_FAIL="$CURL_FAIL" \
    BOOTSTRAP_STUB_BIN="$path" \
    BOOTSTRAP_MKTEMP_ROOT="$PREREQUISITE_TEMP_ROOT" \
    BOOTSTRAP_YAY_STUB="$YAY_STUB_TEMPLATE" \
    BOOTSTRAP_TIDYDOTS_STUB="$TIDYDOTS_STUB_TEMPLATE" \
    BOOTSTRAP_GIT_FAIL="$PREREQUISITE_GIT_FAIL" \
    BOOTSTRAP_MAKEPKG_FAIL="$PREREQUISITE_MAKEPKG_FAIL" \
    BOOTSTRAP_YAY_FAIL="$PREREQUISITE_YAY_FAIL" \
    BOOTSTRAP_CREATE_YAY="$PREREQUISITE_CREATE_YAY" \
    BOOTSTRAP_CREATE_TIDYDOTS="$PREREQUISITE_CREATE_TIDYDOTS" \
    "$BASH_PATH" "$BOOTSTRAP" "$@" 2>&1); then
    LAST_STATUS=0
  else
    LAST_STATUS=$?
  fi
}

assert_log_count() {
  local -r log_contents="$1"
  local -r needle="$2"
  local -r expected="$3"
  local context="$4"
  local count=0
  local line

  while IFS= read -r line || [[ -n "$line" ]]; do
    if [[ "$line" == *"$needle"* ]]; then
      count=$((count + 1))
    fi
  done <<<"$log_contents"

  [[ "$count" == "$expected" ]] || fail "$context: expected $expected '$needle' entries, got $count\n$log_contents"
}

assert_prerequisite_temp_empty() {
  local entries=("$PREREQUISITE_TEMP_ROOT"/*)

  [[ "${#entries[@]}" -eq 0 ]] || fail "temporary prerequisite files remain: ${entries[*]}"
}

reset_prerequisite_flags() {
  PREREQUISITE_GIT_FAIL=false
  PREREQUISITE_MAKEPKG_FAIL=false
  PREREQUISITE_YAY_FAIL=false
  PREREQUISITE_CREATE_YAY=false
  PREREQUISITE_CREATE_TIDYDOTS=false
}

prepare_prerequisite_fixture() {
  local -r yay_state="$1"
  local -r tidydots_state="$2"

  rm -rf -- "$PREREQUISITE_BIN" "$PREREQUISITE_TEMP_ROOT"
  mkdir -p -- "$PREREQUISITE_TEMP_ROOT"
  create_stub_path "$PREREQUISITE_BIN"
  write_executable "$PREREQUISITE_BIN/rm" \
    "printf \"%s\\\\n\" \"\${0##*/} \$*\" >> \"\$BOOTSTRAP_STUB_LOG\"" \
    '/usr/bin/rm "$@"'
  write_executable "$PREREQUISITE_BIN/mktemp" \
    "printf \"%s\\\\n\" \"\${0##*/} \$*\" >> \"\$BOOTSTRAP_STUB_LOG\"" \
    "if [[ \"\${1:-}\" == -d ]]; then /usr/bin/mktemp -d \"\$BOOTSTRAP_MKTEMP_ROOT/bootstrap.XXXXXX\"; else /usr/bin/mktemp \"\$@\"; fi"
  write_executable "$PREREQUISITE_BIN/git" \
    "printf \"%s\\\\n\" \"\${0##*/} \$*\" >> \"\$BOOTSTRAP_STUB_LOG\"" \
    "if [[ \"\${BOOTSTRAP_GIT_FAIL:-false}\" == true ]]; then exit 1; fi" \
    "if [[ \"\${1:-}\" == clone ]]; then /usr/bin/mkdir -p -- \"\$3\"; fi"
  write_executable "$PREREQUISITE_BIN/makepkg" \
    "printf \"%s\\\\n\" \"\${0##*/} \$*\" >> \"\$BOOTSTRAP_STUB_LOG\"" \
    "if [[ \"\${BOOTSTRAP_MAKEPKG_FAIL:-false}\" == true ]]; then exit 1; fi" \
    "if [[ \"\${BOOTSTRAP_CREATE_YAY:-false}\" == true ]]; then /usr/bin/cp -- \"\$BOOTSTRAP_YAY_STUB\" \"\$BOOTSTRAP_STUB_BIN/yay\"; /usr/bin/chmod +x -- \"\$BOOTSTRAP_STUB_BIN/yay\"; fi"

  if [[ "$yay_state" == present ]]; then
    /usr/bin/cp -- "$YAY_STUB_TEMPLATE" "$PREREQUISITE_BIN/yay"
    chmod +x -- "$PREREQUISITE_BIN/yay"
  else
    rm -f -- "$PREREQUISITE_BIN/yay"
  fi

  if [[ "$tidydots_state" == present ]]; then
    /usr/bin/cp -- "$TIDYDOTS_STUB_TEMPLATE" "$PREREQUISITE_BIN/tidydots"
    chmod +x -- "$PREREQUISITE_BIN/tidydots"
  else
    rm -f -- "$PREREQUISITE_BIN/tidydots"
  fi

  reset_prerequisite_flags
  : >"$STUB_LOG"
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
write_executable "$YAY_STUB_TEMPLATE" \
  "printf \"%s\\\\n\" \"\${0##*/} \$*\" >> \"\$BOOTSTRAP_STUB_LOG\"" \
  "if [[ \"\${BOOTSTRAP_YAY_FAIL:-false}\" == true ]]; then exit 1; fi" \
  "if [[ \"\${1:-}\" == -S && \"\${4:-}\" == tidydots-git && \"\${BOOTSTRAP_CREATE_TIDYDOTS:-false}\" == true ]]; then /usr/bin/cp -- \"\$BOOTSTRAP_TIDYDOTS_STUB\" \"\$BOOTSTRAP_STUB_BIN/tidydots\"; /usr/bin/chmod +x -- \"\$BOOTSTRAP_STUB_BIN/tidydots\"; fi"
write_executable "$TIDYDOTS_STUB_TEMPLATE" \
  "printf \"%s\\\\n\" \"\${0##*/} \$*\" >> \"\$BOOTSTRAP_STUB_LOG\""
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

test_prerequisites_dry_run_prints_only_missing_commands() {
  prepare_prerequisite_fixture missing missing
  run_bootstrap "$PREREQUISITE_BIN" "$ARCH_RELEASE" server --dry-run --repo "$REPO_WITH_SPACES"

  assert_status 0 "$LAST_STATUS" 'prerequisite dry-run'
  assert_contains "$LAST_OUTPUT" 'git clone https://aur.archlinux.org/yay-bin.git' 'prerequisite dry-run yay clone'
  assert_contains "$LAST_OUTPUT" 'makepkg -si --needed --noconfirm' 'prerequisite dry-run makepkg'
  assert_contains "$LAST_OUTPUT" 'yay -S --needed --noconfirm tidydots-git' 'prerequisite dry-run tidydots'
  assert_not_contains "$LAST_OUTPUT" 'pacman' 'prerequisite dry-run pacman'
  assert_no_mutation_commands "$(<"$STUB_LOG")"
  assert_prerequisite_temp_empty
}

test_declining_prerequisites_exits_before_mutation() {
  prepare_prerequisite_fixture missing missing
  run_bootstrap_with_input no "$PREREQUISITE_BIN" "$ARCH_RELEASE" server --repo "$REPO_WITH_SPACES"

  assert_status 3 "$LAST_STATUS" 'declined prerequisite confirmation'
  assert_contains "$LAST_OUTPUT" 'declined' 'declined prerequisite confirmation'
  assert_no_mutation_commands "$(<"$STUB_LOG")"
  assert_prerequisite_temp_empty
}

test_existing_yay_is_not_reinstalled() {
  prepare_prerequisite_fixture present missing
  PREREQUISITE_CREATE_TIDYDOTS=true
  run_bootstrap_with_input yes "$PREREQUISITE_BIN" "$ARCH_RELEASE" server --repo "$REPO_WITH_SPACES"

  assert_status 0 "$LAST_STATUS" 'existing yay prerequisite installation'
  assert_not_contains "$LAST_OUTPUT" 'git clone' 'existing yay clone plan'
  assert_not_contains "$LAST_OUTPUT" 'makepkg' 'existing yay makepkg plan'
  assert_contains "$LAST_OUTPUT" 'yay -S --needed --noconfirm tidydots-git' 'existing yay tidydots plan'
  assert_log_count "$(<"$STUB_LOG")" 'git ' 0 'existing yay clone'
  assert_log_count "$(<"$STUB_LOG")" 'makepkg ' 0 'existing yay makepkg'
  assert_log_count "$(<"$STUB_LOG")" 'yay -S --needed --noconfirm tidydots-git' 1 'existing yay tidydots install'
  assert_prerequisite_temp_empty
}

test_existing_tidydots_is_not_reinstalled() {
  prepare_prerequisite_fixture missing present
  PREREQUISITE_CREATE_YAY=true
  run_bootstrap_with_input yes "$PREREQUISITE_BIN" "$ARCH_RELEASE" server --repo "$REPO_WITH_SPACES"

  assert_status 0 "$LAST_STATUS" 'existing tidydots prerequisite installation'
  assert_contains "$LAST_OUTPUT" 'git clone https://aur.archlinux.org/yay-bin.git' 'existing tidydots clone plan'
  assert_contains "$LAST_OUTPUT" 'makepkg -si --needed --noconfirm' 'existing tidydots makepkg plan'
  assert_not_contains "$LAST_OUTPUT" 'tidydots-git' 'existing tidydots install plan'
  assert_log_count "$(<"$STUB_LOG")" 'git clone https://aur.archlinux.org/yay-bin.git' 1 'existing tidydots clone'
  assert_log_count "$(<"$STUB_LOG")" 'makepkg -si --needed --noconfirm' 1 'existing tidydots makepkg'
  assert_log_count "$(<"$STUB_LOG")" 'yay -S --needed --noconfirm tidydots-git' 0 'existing tidydots reinstall'
  assert_prerequisite_temp_empty
}

test_missing_prerequisites_install_once_and_second_run_is_idempotent() {
  prepare_prerequisite_fixture missing missing
  PREREQUISITE_CREATE_YAY=true
  PREREQUISITE_CREATE_TIDYDOTS=true
  run_bootstrap_with_input yes "$PREREQUISITE_BIN" "$ARCH_RELEASE" server --repo "$REPO_WITH_SPACES"

  assert_status 0 "$LAST_STATUS" 'missing prerequisite installation'
  assert_contains "$(<"$STUB_LOG")" 'mktemp -d' 'missing prerequisite temporary directory'
  assert_contains "$(<"$STUB_LOG")" "git clone https://aur.archlinux.org/yay-bin.git $PREREQUISITE_TEMP_ROOT/" \
    'missing prerequisite clone directory'
  assert_log_count "$(<"$STUB_LOG")" 'git clone https://aur.archlinux.org/yay-bin.git' 1 'missing prerequisite clone'
  assert_log_count "$(<"$STUB_LOG")" 'makepkg -si --needed --noconfirm' 1 'missing prerequisite makepkg'
  assert_log_count "$(<"$STUB_LOG")" 'yay -S --needed --noconfirm tidydots-git' 1 'missing prerequisite tidydots'
  assert_log_count "$(<"$STUB_LOG")" "rm -rf -- $PREREQUISITE_TEMP_ROOT/" 1 'missing prerequisite cleanup trap'
  assert_prerequisite_temp_empty

  : >"$STUB_LOG"
  run_bootstrap "$PREREQUISITE_BIN" "$ARCH_RELEASE" server --repo "$REPO_WITH_SPACES"

  assert_status 0 "$LAST_STATUS" 'second prerequisite run'
  assert_not_contains "$LAST_OUTPUT" 'Prerequisite installation plan' 'second prerequisite plan'
  assert_log_count "$(<"$STUB_LOG")" 'git clone ' 0 'second prerequisite clone'
  assert_log_count "$(<"$STUB_LOG")" 'makepkg ' 0 'second prerequisite makepkg'
  assert_log_count "$(<"$STUB_LOG")" 'yay -S ' 0 'second prerequisite tidydots'
}

test_failed_yay_clone_names_failed_step() {
  prepare_prerequisite_fixture missing missing
  PREREQUISITE_GIT_FAIL=true
  run_bootstrap_with_input yes "$PREREQUISITE_BIN" "$ARCH_RELEASE" server --repo "$REPO_WITH_SPACES"

  assert_status 1 "$LAST_STATUS" 'failed yay clone'
  assert_contains "$LAST_OUTPUT" 'failed to clone yay-bin' 'failed yay clone'
  assert_log_count "$(<"$STUB_LOG")" 'git clone ' 1 'failed yay clone command'
  assert_log_count "$(<"$STUB_LOG")" 'makepkg ' 0 'failed yay clone makepkg'
  assert_log_count "$(<"$STUB_LOG")" 'yay -S ' 0 'failed yay clone tidydots'
  assert_prerequisite_temp_empty
}

test_failed_makepkg_names_failed_step() {
  prepare_prerequisite_fixture missing missing
  PREREQUISITE_MAKEPKG_FAIL=true
  run_bootstrap_with_input yes "$PREREQUISITE_BIN" "$ARCH_RELEASE" server --repo "$REPO_WITH_SPACES"

  assert_status 1 "$LAST_STATUS" 'failed yay makepkg'
  assert_contains "$LAST_OUTPUT" 'failed to build yay-bin' 'failed yay makepkg'
  assert_log_count "$(<"$STUB_LOG")" 'git clone ' 1 'failed yay makepkg clone'
  assert_log_count "$(<"$STUB_LOG")" 'makepkg -si --needed --noconfirm' 1 'failed yay makepkg command'
  assert_log_count "$(<"$STUB_LOG")" 'yay -S ' 0 'failed yay makepkg tidydots'
  assert_prerequisite_temp_empty
}

test_failed_yay_install_names_failed_step() {
  prepare_prerequisite_fixture present missing
  PREREQUISITE_YAY_FAIL=true
  run_bootstrap_with_input yes "$PREREQUISITE_BIN" "$ARCH_RELEASE" server --repo "$REPO_WITH_SPACES"

  assert_status 1 "$LAST_STATUS" 'failed tidydots installation'
  assert_contains "$LAST_OUTPUT" 'failed to install tidydots-git' 'failed tidydots installation'
  assert_log_count "$(<"$STUB_LOG")" 'git clone ' 0 'failed tidydots clone'
  assert_log_count "$(<"$STUB_LOG")" 'makepkg ' 0 'failed tidydots makepkg'
  assert_log_count "$(<"$STUB_LOG")" 'yay -S --needed --noconfirm tidydots-git' 1 'failed tidydots command'
  assert_prerequisite_temp_empty
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

run_prerequisite_tests() {
  test_prerequisites_dry_run_prints_only_missing_commands
  test_declining_prerequisites_exits_before_mutation
  test_existing_yay_is_not_reinstalled
  test_existing_tidydots_is_not_reinstalled
  test_missing_prerequisites_install_once_and_second_run_is_idempotent
  test_failed_yay_clone_names_failed_step
  test_failed_makepkg_names_failed_step
  test_failed_yay_install_names_failed_step
  printf 'bootstrap prerequisite tests passed\n'
}

case "${1:-}" in
  preflight)
    run_preflight_tests
    ;;
  prerequisites)
    run_prerequisite_tests
    ;;
  *)
    printf 'Usage: %s {preflight|prerequisites}\n' "${BASH_SOURCE[0]##*/}" >&2
    exit 2
    ;;
esac
