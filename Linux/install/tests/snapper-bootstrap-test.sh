#!/usr/bin/env bash
set -Eeuo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
ROOT="$(cd -- "$SCRIPT_DIR/../../.." && pwd -P)"
BOOTSTRAP="$ROOT/Linux/install/bootstrap"
BOOTSTRAP_TEST_RUNNER="$ROOT/Linux/install/tests/bootstrap-test-runner.sh"
TEST_ROOT="$(mktemp -d)"
STUB_BIN="$TEST_ROOT/bin"
LOG="$TEST_ROOT/commands.log"
ARCH_RELEASE="$TEST_ROOT/arch-release"
ORIGINAL_PATH="$PATH"
BASH_PATH="$BASH"
readonly RECOVERY_DIRECTORY=/var/lib/configurations/snapper-bootstrap
readonly BACKUP_DIRECTORY=/var/lib/configurations/snapper-bootstrap/backups
readonly LIFECYCLE_LOCK="$TEST_ROOT/snapper-bootstrap-lifecycle.lock"
readonly CALLER_LIFECYCLE_LOCK="$TEST_ROOT/caller-selected.lock"

LAST_OUTPUT=""
LAST_STATUS=0

cleanup() {
  rm -rf -- "$TEST_ROOT"
}
trap cleanup EXIT

fail() {
  printf 'FAIL: %s\n' "$*" >&2
  exit 1
}

assert_status() {
  local -r expected="$1"
  local -r actual="$2"
  local -r context="$3"

  [[ "$actual" == "$expected" ]] || fail "$context: expected exit $expected, got $actual\n$LAST_OUTPUT\n$(<"$LOG")"
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

assert_log_contains() {
  local -r needle="$1"
  local -r context="$2"

  assert_contains "$(<"$LOG")" "$needle" "$context"
}

assert_log_not_contains() {
  local -r needle="$1"
  local -r context="$2"

  assert_not_contains "$(<"$LOG")" "$needle" "$context"
}

assert_log_not_contains_after() {
  local -r marker="$1"
  local -r needle="$2"
  local -r context="$3"
  local log_contents
  local after_marker

  log_contents="$(<"$LOG")"
  after_marker="${log_contents#*"$marker"}"

  [[ "$after_marker" != "$log_contents" ]] || fail "$context: marker was not found: $marker"
  assert_not_contains "$after_marker" "$needle" "$context"
}

assert_source_contains() {
  local -r needle="$1"
  local -r context="$2"

  assert_contains "$(<"$BOOTSTRAP")" "$needle" "$context"
}

assert_log_sequence() {
  local log_contents
  local line
  local expected
  local index=1
  local -a lines=()

  log_contents="$(<"$LOG")"
  while IFS= read -r line || [[ -n "$line" ]]; do
    lines+=("$line")
  done <<<"$log_contents"

  for expected in "$@"; do
    while [[ "$index" -le "${#lines[@]}" && "${lines[$((index - 1))]}" != *"$expected"* ]]; do
      index=$((index + 1))
    done
    [[ "$index" -le "${#lines[@]}" ]] || fail "command sequence missing '$expected'\n$log_contents"
    index=$((index + 1))
  done
}

write_executable() {
  local -r path="$1"
  shift

  printf '%s\n' '#!/usr/bin/env bash' 'set -Eeuo pipefail' "$@" >"$path"
  chmod +x -- "$path"
}

create_stubs() {
  mkdir -p -- "$STUB_BIN"

  write_executable "$STUB_BIN/curl" 'exit 0'
  write_executable "$STUB_BIN/pacman" 'exit 0'
  write_executable "$STUB_BIN/systemctl" 'exit 0'
  write_executable "$STUB_BIN/yay" 'exit 0'
  write_executable "$STUB_BIN/git" 'exit 0'

  # shellcheck disable=SC2016
  write_executable "$STUB_BIN/flock" \
    'printf "flock %s\n" "$*" >>"$SNAPPER_BOOTSTRAP_TEST_LOG"' \
    'if [[ "${SNAPPER_BOOTSTRAP_TEST_LOCK_FAILURE:-false}" == true && "${1:-}" == -n ]]; then exit 1; fi' \
    '/usr/bin/flock "$@"'

  # shellcheck disable=SC2016
  write_executable "$STUB_BIN/tidydots" \
    'printf "tidydots %s\n" "$*" >>"$SNAPPER_BOOTSTRAP_TEST_LOG"' \
    'exit 0'

  # shellcheck disable=SC2016
  write_executable "$STUB_BIN/sudo" \
    'printf "sudo %s\n" "$*" >>"$SNAPPER_BOOTSTRAP_TEST_LOG"' \
    '[[ "${1:-}" == -n ]] || exit 2' \
    'shift' \
    '[[ "${1:-}" == -- ]] && shift' \
    'command_name="${1:-}"' \
    'shift || true' \
    'for variable in SNAPPER_INITIALIZER_TEST_MODE SNAPPER_INITIALIZER_ROOT_MOUNT SNAPPER_INITIALIZER_HOME_MOUNT SNAPPER_INITIALIZER_CONFIG_DIR; do' \
    '  [[ -v "$variable" ]] && printf "sudo inherited %s=%s\n" "$variable" "${!variable}" >>"$SNAPPER_BOOTSTRAP_TEST_LOG"' \
    'done' \
    'if [[ "$command_name" == env ]]; then' \
    '  for variable in SNAPPER_INITIALIZER_TEST_MODE SNAPPER_INITIALIZER_ROOT_MOUNT SNAPPER_INITIALIZER_HOME_MOUNT SNAPPER_INITIALIZER_CONFIG_DIR; do' \
    '    [[ -v "$variable" ]] && printf "sudo inherited %s=%s\n" "$variable" "${!variable}" >>"$SNAPPER_BOOTSTRAP_TEST_LOG"' \
    '  done' \
    'fi' \
    'if [[ "$command_name" == test ]]; then' \
    '  negate=false' \
    '  [[ "${1:-}" == ! ]] && negate=true && shift' \
    '  operator="${1:-}"' \
    '  path="${2:-}"' \
    '  result=false' \
    '  if [[ "$path" == "$SNAPPER_BOOTSTRAP_TEST_LIFECYCLE_LOCK" ]]; then' \
    '    case "$operator" in' \
    '      -L) result=false ;;' \
    '      -e|-f) [[ -e "$path" ]] && result=true ;;' \
    '      *) result=false ;;' \
    '    esac' \
    '  else' \
    '  case "$operator:$path" in' \
    '    -e:/var/lib/configurations/snapper-bootstrap)' \
      '      [[ -n "${SNAPPER_BOOTSTRAP_TEST_JOURNAL_STATE:-}" ]] && result=true' \
      '      ;;' \
    '    -d:/var/lib/configurations/snapper-bootstrap)' \
      '      result=true' \
      '      ;;' \
    '    -e:/var/lib/configurations/snapper-bootstrap/state|-f:/var/lib/configurations/snapper-bootstrap/state)' \
      '      [[ -n "${SNAPPER_BOOTSTRAP_TEST_JOURNAL_STATE:-}" ]] && result=true' \
      '      ;;' \
    '    -e:/var/lib/configurations/snapper-bootstrap/manifest|-f:/var/lib/configurations/snapper-bootstrap/manifest)' \
      '      [[ -n "${SNAPPER_BOOTSTRAP_TEST_JOURNAL_MANIFEST:-}" ]] && result=true' \
      '      ;;' \
    '    -e:/var/lib/configurations/snapper-bootstrap/backups/legacy-*)' \
      '      [[ "${SNAPPER_BOOTSTRAP_TEST_LEGACY_LINKS:-false}" == true ]] && result=true' \
      '      ;;' \
    '    -e:/var/lib/configurations/snapper-bootstrap/backups/legacy-configs|-e:/var/lib/configurations/snapper-bootstrap/backups/legacy-conf.d)' \
      '      [[ "${SNAPPER_BOOTSTRAP_TEST_LEGACY_LINKS:-false}" == true ]] && result=true' \
      '      ;;' \
    '    -e:/var/lib/configurations/snapper-bootstrap/backups/*.acl|-e:/var/lib/configurations/snapper-bootstrap/backups/*.xattr)' \
      '      [[ "${SNAPPER_BOOTSTRAP_TEST_METADATA_TOOLS:-false}" == true ]] && result=true' \
      '      ;;' \
    '    -e:/var/lib/configurations/snapper-bootstrap/backups/root|-e:/var/lib/configurations/snapper-bootstrap/backups/home|-e:/var/lib/configurations/snapper-bootstrap/backups/registration|-e:/var/lib/configurations/snapper-bootstrap/backups/initializer)' \
      '      [[ "${SNAPPER_BOOTSTRAP_TEST_EXISTING_TARGETS:-false}" == true ]] && result=true' \
      '      ;;' \
    '    -e:/var/lib/configurations/snapper-bootstrap/backups/*)' \
      '      [[ -n "${SNAPPER_BOOTSTRAP_TEST_JOURNAL_MANIFEST:-}" ]] && result=true' \
      '      ;;' \
    '    -e:/etc/snapper/configs|-e:/etc/conf.d)' \
    '      [[ "${SNAPPER_BOOTSTRAP_TEST_LEGACY_LINKS:-false}" == true || "${SNAPPER_BOOTSTRAP_TEST_EXISTING_TARGETS:-false}" == true || "${SNAPPER_BOOTSTRAP_TEST_PLANNED_DIRECTORIES:-false}" == true ]] && result=true' \
      '      ;;' \
    '    -L:/etc/snapper/configs|-L:/etc/conf.d)' \
      '      [[ "${SNAPPER_BOOTSTRAP_TEST_LEGACY_LINKS:-false}" == true ]] && result=true' \
      '      ;;' \
    '    -e:/etc/snapper/configs/root|-e:/etc/snapper/configs/home|-e:/etc/conf.d/snapper)' \
    '      [[ "${SNAPPER_BOOTSTRAP_TEST_EXISTING_TARGETS:-false}" == true ]] && result=true' \
    '      ;;' \
    '    -f:/etc/snapper/configs/root|-f:/etc/snapper/configs/home|-f:/etc/conf.d/snapper)' \
    '      [[ "${SNAPPER_BOOTSTRAP_TEST_EXISTING_TARGETS:-false}" == true ]] && result=true' \
    '      ;;' \
    '    -L:/usr/local/libexec/antoinews-linux/snapper-initialize)' \
    '      [[ "${SNAPPER_BOOTSTRAP_TEST_PATH_FAILURE:-}" == symlink-target ]] && result=true' \
    '      ;;' \
    '    -L:/usr/local/libexec/antoinews-linux)' \
    '      [[ "${SNAPPER_BOOTSTRAP_TEST_PATH_FAILURE:-}" == symlink-parent ]] && result=true' \
    '      ;;' \
    '    -f:/usr/local/libexec/antoinews-linux/snapper-initialize)' \
    '      [[ "${SNAPPER_BOOTSTRAP_TEST_PATH_FAILURE:-}" != not-regular ]] && result=true' \
    '      ;;' \
    '    -x:/usr/local/libexec/antoinews-linux/snapper-initialize)' \
      '      [[ "${SNAPPER_BOOTSTRAP_TEST_PATH_FAILURE:-}" != not-executable ]] && result=true' \
      '      ;;' \
    '    -x:/usr/bin/getfacl|-x:/usr/bin/getfattr)' \
    '      [[ "${SNAPPER_BOOTSTRAP_TEST_METADATA_TOOLS:-false}" == true ]] && result=true' \
    '      ;;' \
    '    -d:/usr/local/libexec|-d:/usr/local/libexec/antoinews-linux)' \
    '      [[ "${SNAPPER_BOOTSTRAP_TEST_PATH_FAILURE:-}" != missing-parent ]] && result=true' \
    '      ;;' \
    '    -e:/usr/local/libexec/antoinews-linux/snapper-initialize)' \
    '      result=true' \
    '      ;;' \
    '    !-L:/etc/snapper/configs|-L:/etc/conf.d)' \
    '      result=false' \
    '      ;;' \
    '    !-L:/usr/local/libexec/antoinews-linux/snapper-initialize)' \
    '      [[ "${SNAPPER_BOOTSTRAP_TEST_PATH_FAILURE:-}" != symlink-target ]] && result=true' \
    '      ;;' \
    '    !-L:/usr/local/libexec/antoinews-linux)' \
    '      [[ "${SNAPPER_BOOTSTRAP_TEST_PATH_FAILURE:-}" != symlink-parent ]] && result=true' \
    '      ;;' \
    '    !-e:/usr/local/libexec/antoinews-linux/snapper-initialize)' \
    '      result=false' \
    '      ;;' \
    '    !-d:*)' \
    '      result=true' \
    '      ;;' \
    '    -d:*)' \
    '      result=true' \
    '      ;;' \
    '    !-e:*)' \
    '      result=true' \
    '      ;;' \
    '    -e:*)' \
    '      result=false' \
    '      ;;' \
    '  esac' \
    '  fi' \
    '  [[ "$negate" == true ]] && [[ "$result" == false ]] && exit 0' \
    '  [[ "$negate" == false ]] && [[ "$result" == true ]] && exit 0' \
    '  exit 1' \
    'fi' \
    'if [[ "$command_name" == readlink ]]; then' \
    '  [[ "${1:-}" == -- ]] && shift' \
    '  case "${1:-}" in' \
    '    /etc/snapper/configs) printf "%s/Linux/Snapper/configs\n" "$SNAPPER_BOOTSTRAP_TEST_ROOT" ;;' \
    '    /etc/conf.d) printf "%s/Linux/Snapper/conf.d\n" "$SNAPPER_BOOTSTRAP_TEST_ROOT" ;;' \
    '    *) exit 1 ;;' \
    '  esac' \
    '  exit 0' \
    'fi' \
    'if [[ "$command_name" == cat ]]; then' \
    '  path="${!#}"' \
    '  case "$path" in' \
    '    /var/lib/configurations/snapper-bootstrap/state) printf "%s\n" "${SNAPPER_BOOTSTRAP_TEST_JOURNAL_STATE:-}" ;;' \
    '    /var/lib/configurations/snapper-bootstrap/manifest) printf "%s\n" "${SNAPPER_BOOTSTRAP_TEST_JOURNAL_MANIFEST:-}" ;;' \
    '    *) exit 1 ;;' \
    '  esac' \
    '  exit 0' \
    'fi' \
    'if [[ "$command_name" == touch ]]; then' \
    '  /usr/bin/touch "$@"' \
    '  exit 0' \
    'fi' \
    'if [[ "$command_name" == chmod && "${SNAPPER_BOOTSTRAP_TEST_RECOVERY_SETUP_FAILURE:-}" == chmod && "${!#}" == /var/lib/configurations/snapper-bootstrap ]]; then exit 1; fi' \
    'if [[ "$command_name" == chown && "${SNAPPER_BOOTSTRAP_TEST_RECOVERY_SETUP_FAILURE:-}" == chown && "${!#}" == /var/lib/configurations/snapper-bootstrap ]]; then exit 1; fi' \
    'if [[ "$command_name" == stat ]]; then' \
    '  format="${2:-}"' \
    '  path="${!#}"' \
    '  if [[ "${SNAPPER_BOOTSTRAP_TEST_EXISTING_TARGETS:-false}" == true && "$path" == /etc/snapper/configs/root || "${SNAPPER_BOOTSTRAP_TEST_EXISTING_TARGETS:-false}" == true && "$path" == /etc/snapper/configs/home || "${SNAPPER_BOOTSTRAP_TEST_EXISTING_TARGETS:-false}" == true && "$path" == /etc/conf.d/snapper ]]; then' \
    '    case "$format" in' \
    '      %u) printf "1001\n" ;;' \
    '      %g) printf "1002\n" ;;' \
    '      %a) printf "%s\n" "${SNAPPER_BOOTSTRAP_TEST_EXISTING_TARGET_MODE:-640}" ;;' \
    '      *) exit 1 ;;' \
    '    esac' \
    '  elif [[ "$path" == "$SNAPPER_BOOTSTRAP_TEST_LIFECYCLE_LOCK" ]]; then' \
    '    case "$format" in' \
    '      %u|%g) printf "0\\n" ;;' \
    '      %a) printf "644\\n" ;;' \
    '      *) exit 1 ;;' \
    '    esac' \
    '  elif [[ "$path" == /var/lib/configurations/snapper-bootstrap || "$path" == /var/lib/configurations/snapper-bootstrap/backups ]]; then' \
    '    case "$format:${SNAPPER_BOOTSTRAP_TEST_RECOVERY_DIRECTORY_MODE:-}" in' \
    '      %a:bad) printf "777\n" ;;' \
    '      %a:*) printf "700\n" ;;' \
    '      *) printf "0\n" ;;' \
    '    esac' \
    '  elif [[ "$path" == /usr/local/libexec/antoinews-linux/snapper-initialize ]]; then' \
    '    case "$format:${SNAPPER_BOOTSTRAP_TEST_PATH_FAILURE:-}" in' \
    '      %u:owner|%g:owner) printf "1000\n" ;;' \
    '      %a:mode) printf "666\n" ;;' \
    '      *) printf "%s\n" "$([[ "$format" == %a ]] && printf 755 || printf 0)" ;;' \
    '    esac' \
    '  elif [[ "${SNAPPER_BOOTSTRAP_TEST_PATH_FAILURE:-}" == parent-owner && "$format" == %u ]]; then' \
    '    printf "1000\n"' \
    '  elif [[ "${SNAPPER_BOOTSTRAP_TEST_PATH_FAILURE:-}" == parent-owner && "$format" == %g ]]; then' \
    '    printf "1000\n"' \
    '  elif [[ "${SNAPPER_BOOTSTRAP_TEST_PATH_FAILURE:-}" == parent-mode && "$format" == %a ]]; then' \
    '    printf "777\n"' \
    '  elif [[ "$format" == %a ]]; then' \
    '    printf "755\n"' \
    '  else' \
    '    printf "0\n"' \
    '  fi' \
    '  exit 0' \
    'fi' \
    'if [[ "$command_name" == /usr/bin/getfacl ]]; then' \
    '  printf "# file: %s\\nuser::rw-\\ngroup::r--\\nother::---\\n" "${!#}"' \
    '  exit 0' \
    'fi' \
    'if [[ "$command_name" == /usr/bin/getfattr ]]; then' \
    '  printf "# file: %s\\nuser.test=0sAQI=\\n" "${!#}"' \
    '  exit 0' \
    'fi' \
    'if [[ "$command_name" == mktemp ]]; then' \
    '  template="${!#}"' \
    '  if [[ "${1:-}" == -d ]]; then' \
    '    printf "%s\n" "$SNAPPER_BOOTSTRAP_TEST_ROOT/rollback"' \
    '  else' \
    '    printf "%s\n" "${template/XXXXXX/staged}"' \
    '  fi' \
    '  exit 0' \
    'fi' \
    'if [[ "$command_name" == env && "$*" == *snapper-initialize\ --apply ]]; then' \
    '  [[ "${SNAPPER_BOOTSTRAP_TEST_INITIALIZER_FAILURE:-false}" == true ]] && exit 1' \
    '  exit 0' \
    'fi' \
    'if [[ "$command_name" == env && "$*" == *snapper-initialize\ --create-initial-snapshots ]]; then' \
    '  [[ "${SNAPPER_BOOTSTRAP_TEST_INITIALIZER_FAILURE:-false}" == true ]] && exit 1' \
    '  exit 0' \
    'fi' \
    'if [[ "$command_name" == rmdir && "${SNAPPER_BOOTSTRAP_TEST_PREPARATION_RECOVERY_FAILURE:-false}" == true && "${!#}" == /etc/conf.d ]]; then exit 1; fi' \
    'if [[ "$command_name" == cp && "${SNAPPER_BOOTSTRAP_TEST_DEPLOY_FAILURE:-false}" == true && "$*" == *"/Linux/Snapper/"* ]]; then exit 1; fi' \
    'if [[ "${SNAPPER_BOOTSTRAP_TEST_ROLLBACK_FAILURE:-false}" == true && "$command_name" == cp && "$*" == *"/backups/"* ]]; then exit 1; fi' \
    'if [[ "$command_name" == rm && ( "${SNAPPER_BOOTSTRAP_TEST_CLEANUP_FAILURE:-false}" == true || "${SNAPPER_BOOTSTRAP_TEST_CLEANUP_FAILURE:-}" == backup ) && "${1:-}" == -rf && "${!#}" == /var/lib/configurations/snapper-bootstrap/backups ]]; then exit 1; fi' \
    'if [[ "$command_name" == rm && "${SNAPPER_BOOTSTRAP_TEST_CLEANUP_FAILURE:-}" == journal && "${1:-}" == -f && "$*" == *snapper-bootstrap/state* ]]; then exit 1; fi' \
    'if [[ "$command_name" == rmdir && "${SNAPPER_BOOTSTRAP_TEST_CLEANUP_FAILURE:-}" == rmdir && "${!#}" == /var/lib/configurations/snapper-bootstrap ]]; then exit 1; fi' \
    'if [[ "$command_name" == *snapper-initialize && "${1:-}" == --apply && "${SNAPPER_BOOTSTRAP_TEST_INITIALIZER_FAILURE:-false}" == true ]]; then exit 1; fi' \
    'exit 0'
}

reset_fixture() {
  : >"$LOG"
  rm -f -- "$LIFECYCLE_LOCK" "$CALLER_LIFECYCLE_LOCK"
  unset \
    SNAPPER_BOOTSTRAP_TEST_LEGACY_LINKS \
    SNAPPER_BOOTSTRAP_TEST_DEPLOY_FAILURE \
    SNAPPER_BOOTSTRAP_TEST_ROLLBACK_FAILURE \
    SNAPPER_BOOTSTRAP_TEST_INITIALIZER_FAILURE \
    SNAPPER_BOOTSTRAP_TEST_CLEANUP_FAILURE \
    SNAPPER_BOOTSTRAP_TEST_EXISTING_TARGETS \
    SNAPPER_BOOTSTRAP_TEST_METADATA_TOOLS \
    SNAPPER_BOOTSTRAP_TEST_RECOVERY_SETUP_FAILURE \
    SNAPPER_BOOTSTRAP_TEST_RECOVERY_DIRECTORY_MODE \
    SNAPPER_BOOTSTRAP_TEST_EXISTING_TARGET_MODE \
    SNAPPER_BOOTSTRAP_TEST_PLANNED_DIRECTORIES \
    SNAPPER_BOOTSTRAP_TEST_PREPARATION_RECOVERY_FAILURE \
    SNAPPER_BOOTSTRAP_TEST_PATH_FAILURE \
    SNAPPER_BOOTSTRAP_TEST_LOCK_FAILURE
  unset SNAPPER_BOOTSTRAP_TEST_JOURNAL_STATE SNAPPER_BOOTSTRAP_TEST_JOURNAL_MANIFEST
}

run_bootstrap() {
  local -r input="$1"
  shift

  if LAST_OUTPUT=$(printf '%s\n' "$input" | \
    PATH="$STUB_BIN:$ORIGINAL_PATH" \
    BOOTSTRAP_OS_RELEASE="$ARCH_RELEASE" \
    BOOTSTRAP_HOSTNAME=antoinews-linux \
    SNAPPER_BOOTSTRAP_TEST_LOG="$LOG" \
    SNAPPER_BOOTSTRAP_TEST_ROOT="$ROOT" \
    SNAPPER_BOOTSTRAP_TEST_LEGACY_LINKS="${SNAPPER_BOOTSTRAP_TEST_LEGACY_LINKS:-false}" \
    SNAPPER_BOOTSTRAP_TEST_DEPLOY_FAILURE="${SNAPPER_BOOTSTRAP_TEST_DEPLOY_FAILURE:-false}" \
    SNAPPER_BOOTSTRAP_TEST_ROLLBACK_FAILURE="${SNAPPER_BOOTSTRAP_TEST_ROLLBACK_FAILURE:-false}" \
    SNAPPER_BOOTSTRAP_TEST_INITIALIZER_FAILURE="${SNAPPER_BOOTSTRAP_TEST_INITIALIZER_FAILURE:-false}" \
    SNAPPER_BOOTSTRAP_TEST_CLEANUP_FAILURE="${SNAPPER_BOOTSTRAP_TEST_CLEANUP_FAILURE:-false}" \
    SNAPPER_BOOTSTRAP_TEST_EXISTING_TARGETS="${SNAPPER_BOOTSTRAP_TEST_EXISTING_TARGETS:-false}" \
    SNAPPER_BOOTSTRAP_TEST_METADATA_TOOLS="${SNAPPER_BOOTSTRAP_TEST_METADATA_TOOLS:-false}" \
    SNAPPER_BOOTSTRAP_TEST_RECOVERY_SETUP_FAILURE="${SNAPPER_BOOTSTRAP_TEST_RECOVERY_SETUP_FAILURE:-}" \
    SNAPPER_BOOTSTRAP_TEST_RECOVERY_DIRECTORY_MODE="${SNAPPER_BOOTSTRAP_TEST_RECOVERY_DIRECTORY_MODE:-}" \
    SNAPPER_BOOTSTRAP_TEST_EXISTING_TARGET_MODE="${SNAPPER_BOOTSTRAP_TEST_EXISTING_TARGET_MODE:-640}" \
    SNAPPER_BOOTSTRAP_TEST_PLANNED_DIRECTORIES="${SNAPPER_BOOTSTRAP_TEST_PLANNED_DIRECTORIES:-false}" \
    SNAPPER_BOOTSTRAP_TEST_PREPARATION_RECOVERY_FAILURE="${SNAPPER_BOOTSTRAP_TEST_PREPARATION_RECOVERY_FAILURE:-false}" \
    SNAPPER_BOOTSTRAP_TEST_JOURNAL_STATE="${SNAPPER_BOOTSTRAP_TEST_JOURNAL_STATE:-}" \
    SNAPPER_BOOTSTRAP_TEST_JOURNAL_MANIFEST="${SNAPPER_BOOTSTRAP_TEST_JOURNAL_MANIFEST:-}" \
    SNAPPER_BOOTSTRAP_TEST_PATH_FAILURE="${SNAPPER_BOOTSTRAP_TEST_PATH_FAILURE:-}" \
    SNAPPER_BOOTSTRAP_TEST_LOCK_FAILURE="${SNAPPER_BOOTSTRAP_TEST_LOCK_FAILURE:-false}" \
    SNAPPER_BOOTSTRAP_TEST_LIFECYCLE_LOCK="$LIFECYCLE_LOCK" \
    SNAPPER_BOOTSTRAP_LIFECYCLE_LOCK="$CALLER_LIFECYCLE_LOCK" \
    SNAPPER_BOOTSTRAP_TEST_MODE=1 \
    SNAPPER_LIFECYCLE_LOCK="$CALLER_LIFECYCLE_LOCK" \
    "$BASH_PATH" "$BOOTSTRAP_TEST_RUNNER" "$LIFECYCLE_LOCK" --repo "$ROOT" "$@" 2>&1); then
    LAST_STATUS=0
  else
    LAST_STATUS=$?
  fi
}

test_snapper_decline_preserves_legacy_links() {
  reset_fixture
  SNAPPER_BOOTSTRAP_TEST_LEGACY_LINKS=true
  run_bootstrap $'yes\nno'

  assert_status 3 "$LAST_STATUS" 'Snapper dry-run decline'
  assert_contains "$LAST_OUTPUT" 'custom Snapper deployment declined' 'Snapper dry-run decline message'
  assert_contains "$LAST_OUTPUT" 'Snapper deployment plan:' 'Snapper deployment plan before decline'
  assert_log_not_contains 'restore snapper' 'custom plan does not invoke tidydots Snapper restore'
  assert_log_not_contains 'sudo -n -- mktemp ' 'no root deployment after Snapper decline'
  assert_log_not_contains 'sudo -n -- rm ' 'no destructive root command after Snapper decline'
  assert_log_not_contains 'sudo -n -- mv ' 'no root replacement after Snapper decline'
  assert_log_not_contains 'sudo -n -- cp ' 'no root backup after Snapper decline'
  assert_log_not_contains 'tidydots restore' 'no broad restore after Snapper decline'
}

test_snapper_deployment_is_rollback_assisted_and_after_confirmation() {
  reset_fixture
  SNAPPER_BOOTSTRAP_TEST_LEGACY_LINKS=true
  run_bootstrap $'yes\nyes\nyes'

  assert_status 0 "$LAST_STATUS" 'Snapper deployment'
  assert_contains "$LAST_OUTPUT" 'Snapper deployment plan:' 'Snapper deployment plan before confirmation'
  assert_contains "$LAST_OUTPUT" 'persistent recovery state' 'persistent recovery wording'
  assert_contains "$LAST_OUTPUT" 'power-loss durability still depends on the filesystem' 'power-loss durability wording'
  assert_log_sequence \
    'sudo -n -- env -i PATH=/usr/bin:/bin ' \
    'flock -n' \
    "sudo -n -- test -e ${RECOVERY_DIRECTORY}" \
    'tidydots --dir ' \
    'tidydots --dir ' \
    "sudo -n -- mktemp ${RECOVERY_DIRECTORY}/.manifest." \
    "sudo -n -- mv -f -- ${RECOVERY_DIRECTORY}/.state.staged ${RECOVERY_DIRECTORY}/state" \
    "sudo -n -- mv -- /etc/snapper/configs ${BACKUP_DIRECTORY}/legacy-configs" \
    'sudo -n -- mktemp /etc/snapper/configs/.root.' \
    'sudo -n -- cp' \
    'sudo -n -- chown root:root' \
    'sudo -n -- chmod 0644' \
    'sudo -n -- mv -f' \
    'sudo -n -- test ! -L /usr/local/libexec/antoinews-linux/snapper-initialize' \
    'sudo -n -- env -i PATH=/usr/bin:/bin SNAPPER_INTERNAL_LIFECYCLE_LOCK_HELD=1 /usr/local/libexec/antoinews-linux/snapper-initialize --apply' \
    "sudo -n -- rm -rf -- ${BACKUP_DIRECTORY}" \
    "sudo -n -- rm -f -- ${RECOVERY_DIRECTORY}/state ${RECOVERY_DIRECTORY}/manifest" \
    "sudo -n -- rmdir -- ${RECOVERY_DIRECTORY}" \
    'sudo -n -- env -i PATH=/usr/bin:/bin SNAPPER_INTERNAL_LIFECYCLE_LOCK_HELD=1 /usr/local/libexec/antoinews-linux/snapper-initialize --create-initial-snapshots' \
    'sudo -n -- env -i PATH=/usr/bin:/bin /usr/local/libexec/antoinews-linux/snapper-initialize --check' \
    'restore -n' \
    'restore' \
    'flock -u'
  assert_log_not_contains 'restore snapper' 'custom deployment has no tidydots Snapper restore'
  assert_log_contains 'sudo -n -- chmod 0755' 'initializer mode correction'
  assert_log_contains 'sudo -n -- chown root:root' 'root ownership correction'
}

test_snapper_lifecycle_lock_failure_stops_before_recovery() {
  reset_fixture
  SNAPPER_BOOTSTRAP_TEST_LOCK_FAILURE=true
  run_bootstrap $'yes\nyes\nyes'

  assert_status 1 "$LAST_STATUS" 'Snapper lifecycle lock failure'
  assert_contains "$LAST_OUTPUT" 'could not acquire Snapper lifecycle lock' 'Snapper lifecycle lock failure message'
  assert_log_contains 'flock -n' 'Snapper lifecycle lock attempt'
  assert_log_not_contains "sudo -n -- cat -- ${RECOVERY_DIRECTORY}/state" 'no recovery inspection after lock failure'
  assert_log_not_contains 'tidydots ' 'no tidydots phase after lock failure'
}

test_snapper_lifecycle_lock_contention_stops_before_recovery() {
  reset_fixture
  : >"$LIFECYCLE_LOCK"
  exec {held_lock_fd}<"$LIFECYCLE_LOCK"
  flock -n "$held_lock_fd"

  run_bootstrap $'yes\nyes\nyes'

  flock -u "$held_lock_fd"
  exec {held_lock_fd}<&-

  assert_status 1 "$LAST_STATUS" 'Snapper lifecycle lock contention'
  assert_contains "$LAST_OUTPUT" 'could not acquire Snapper lifecycle lock' 'Snapper lifecycle lock contention message'
  assert_log_contains 'flock -n' 'Snapper lifecycle lock contention attempt'
  assert_log_not_contains "sudo -n -- cat -- ${RECOVERY_DIRECTORY}/state" 'no recovery inspection during lock contention'
  assert_log_not_contains 'tidydots ' 'no tidydots phase during lock contention'
}

test_caller_environment_cannot_select_snapper_lifecycle_lock() {
  reset_fixture
  run_bootstrap $'yes\nyes\nyes'

  assert_status 0 "$LAST_STATUS" 'caller lock override isolation'
  assert_log_contains "sudo -n -- test -e $LIFECYCLE_LOCK" 'fixed test-selected lifecycle lock'
  assert_log_not_contains "$CALLER_LIFECYCLE_LOCK" 'caller-selected lifecycle lock'
  [[ ! -e "$CALLER_LIFECYCLE_LOCK" ]] || fail 'caller-selected lifecycle lock was created'
}

test_existing_snapper_directories_are_not_misclassified_as_legacy_links() {
  reset_fixture
  SNAPPER_BOOTSTRAP_TEST_EXISTING_TARGETS=true
  run_bootstrap $'yes\nyes\nyes'

  assert_status 0 "$LAST_STATUS" 'existing Snapper directories'
  assert_log_not_contains 'sudo -n -- readlink -- /etc/snapper/configs' 'existing configs directory is not treated as link'
  assert_log_not_contains 'sudo -n -- readlink -- /etc/conf.d' 'existing conf.d directory is not treated as link'
}

test_initializer_integrity_fails_closed() {
  local failure

  for failure in symlink-target symlink-parent not-regular owner mode parent-owner parent-mode missing-parent; do
    reset_fixture
    SNAPPER_BOOTSTRAP_TEST_PATH_FAILURE="$failure"
    run_bootstrap $'yes\nyes'

    assert_status 1 "$LAST_STATUS" "initializer integrity: $failure"
    assert_contains "$LAST_OUTPUT" 'bootstrap:' "initializer integrity message: $failure"
    assert_log_not_contains 'snapper-initialize --apply' "initializer not executed: $failure"
    assert_log_not_contains 'tidydots restore -n' "broad restore not planned: $failure"
  done
}

test_deployment_failure_rolls_back_before_initializer() {
  reset_fixture
  SNAPPER_BOOTSTRAP_TEST_LEGACY_LINKS=true
  SNAPPER_BOOTSTRAP_TEST_DEPLOY_FAILURE=true
  run_bootstrap $'yes\nyes'

  assert_status 1 "$LAST_STATUS" 'Snapper deployment failure'
  assert_contains "$LAST_OUTPUT" 'Snapper' 'Snapper deployment failure message'
  assert_log_contains "sudo -n -- cp --preserve=all -- ${BACKUP_DIRECTORY}/initializer" \
    'file state rollback after deployment failure'
  assert_log_not_contains 'snapper-initialize --apply' 'initializer not executed after deployment failure'
  assert_log_not_contains 'tidydots restore -n' 'broad restore not planned after deployment failure'
}

test_initializer_failure_rolls_back_before_broad_restore() {
  reset_fixture
  SNAPPER_BOOTSTRAP_TEST_INITIALIZER_FAILURE=true
  SNAPPER_BOOTSTRAP_TEST_EXISTING_TARGETS=true
  run_bootstrap $'yes\nyes'

  assert_status 1 "$LAST_STATUS" 'Snapper initializer failure'
  assert_contains "$LAST_OUTPUT" 'initializer' 'Snapper initializer failure message'
  assert_log_contains "sudo -n -- cp --preserve=all -- ${BACKUP_DIRECTORY}/root /etc/snapper/configs/root" \
    'file state rollback after initializer failure'
  assert_log_not_contains 'snapper-initialize --check' 'initializer check after apply failure'
  assert_log_not_contains 'tidydots restore -n' 'broad restore not planned after initializer failure'
}

test_rollback_preserves_original_metadata() {
  reset_fixture
  SNAPPER_BOOTSTRAP_TEST_EXISTING_TARGETS=true
  SNAPPER_BOOTSTRAP_TEST_METADATA_TOOLS=true
  SNAPPER_BOOTSTRAP_TEST_INITIALIZER_FAILURE=true
  run_bootstrap $'yes\nyes'

  assert_status 1 "$LAST_STATUS" 'Snapper metadata rollback'
  assert_log_contains 'sudo -n -- cp --preserve=all' 'metadata-preserving backup and restore'
  assert_log_contains 'sudo -n -- chown 1001:1002 -- /etc/snapper/configs/root' 'rollback restores original owner'
  assert_log_contains 'sudo -n -- chmod 640 -- /etc/snapper/configs/root' 'rollback restores original mode'
  assert_log_contains 'sudo -n -- /usr/bin/setfacl --set-file=' 'rollback restores ACL'
  assert_log_contains 'sudo -n -- /usr/bin/setfattr --restore=' 'rollback restores xattrs'
}

test_cleanup_failure_keeps_journal_and_stops_without_destructive_rollback() {
  reset_fixture
  SNAPPER_BOOTSTRAP_TEST_LEGACY_LINKS=true
  SNAPPER_BOOTSTRAP_TEST_CLEANUP_FAILURE=true
  run_bootstrap $'yes\nyes\nyes'

  assert_status 1 "$LAST_STATUS" 'Snapper cleanup failure'
  assert_contains "$LAST_OUTPUT" 'manual recovery' 'cleanup failure manual recovery message'
  assert_log_contains "sudo -n -- rm -rf -- ${BACKUP_DIRECTORY}" 'cleanup failure backup deletion'
  assert_log_not_contains_after "sudo -n -- rm -rf -- ${BACKUP_DIRECTORY}" \
    "sudo -n -- cp --preserve=all ${BACKUP_DIRECTORY}" \
    'cleanup failure must not restore after backup deletion starts'
  assert_not_contains "$LAST_OUTPUT" 'backups retained' 'cleanup failure must not claim backups retained'
  assert_contains "$LAST_OUTPUT" 'backup contents may be partial' 'cleanup failure partial backup wording'
  assert_log_not_contains 'tidydots restore -n' 'broad restore after cleanup failure'
}

test_partial_install_journal_recovers_before_new_deployment() {
  reset_fixture
  SNAPPER_BOOTSTRAP_TEST_LEGACY_LINKS=true
  SNAPPER_BOOTSTRAP_TEST_JOURNAL_STATE=$'version=1\nphase=deploying\n'
  SNAPPER_BOOTSTRAP_TEST_JOURNAL_MANIFEST="legacy|/etc/snapper/configs|${BACKUP_DIRECTORY}/legacy-configs|$ROOT/Linux/Snapper/configs
file|/etc/snapper/configs/root|${BACKUP_DIRECTORY}/root|yes|1001|1002|640
"
  run_bootstrap $'yes\nyes\nyes'

  assert_status 0 "$LAST_STATUS" 'Snapper journal recovery'
  assert_log_sequence \
    "sudo -n -- test -e ${RECOVERY_DIRECTORY}" \
    "sudo -n -- cat -- ${RECOVERY_DIRECTORY}/state" \
    "sudo -n -- cp --preserve=all -- ${BACKUP_DIRECTORY}/root /etc/snapper/configs/root" \
    "sudo -n -- mktemp ${RECOVERY_DIRECTORY}/.manifest."
}

test_preparation_recovery_removes_only_manifest_directories() {
  reset_fixture
  SNAPPER_BOOTSTRAP_TEST_PLANNED_DIRECTORIES=true
  SNAPPER_BOOTSTRAP_TEST_JOURNAL_STATE=$'version=1\nphase=preparing\n'
  SNAPPER_BOOTSTRAP_TEST_JOURNAL_MANIFEST=$'dir|/etc/snapper/configs\ndir|/etc/conf.d\n'
  run_bootstrap $'yes\nyes\nyes'

  assert_status 0 "$LAST_STATUS" 'Snapper preparation recovery'
  assert_log_sequence \
    "sudo -n -- cat -- ${RECOVERY_DIRECTORY}/state" \
    "sudo -n -- cat -- ${RECOVERY_DIRECTORY}/manifest" \
    'sudo -n -- rmdir -- /etc/conf.d' \
    'sudo -n -- rmdir -- /etc/snapper/configs' \
    "sudo -n -- rm -rf -- ${RECOVERY_DIRECTORY}"
  assert_log_not_contains 'sudo -n -- rmdir -- /etc/snapper ' \
    'preparation recovery does not remove unplanned parent directories'
}

test_preparation_recovery_failure_retains_journal() {
  reset_fixture
  SNAPPER_BOOTSTRAP_TEST_PLANNED_DIRECTORIES=true
  SNAPPER_BOOTSTRAP_TEST_PREPARATION_RECOVERY_FAILURE=true
  SNAPPER_BOOTSTRAP_TEST_JOURNAL_STATE=$'version=1\nphase=preparing\n'
  SNAPPER_BOOTSTRAP_TEST_JOURNAL_MANIFEST=$'dir|/etc/snapper/configs\ndir|/etc/conf.d\n'
  run_bootstrap $'yes\nyes\nyes'

  assert_status 1 "$LAST_STATUS" 'Snapper preparation recovery failure'
  assert_contains "$LAST_OUTPUT" 'preparation recovery failed' 'preparation recovery failure message'
  assert_log_contains 'sudo -n -- rmdir -- /etc/conf.d' 'preparation directory removal attempt'
  assert_log_not_contains "sudo -n -- rm -rf -- ${RECOVERY_DIRECTORY}" \
    'preparation recovery failure retains journal state'
  assert_log_not_contains 'tidydots --dir' 'preparation recovery failure stops before deployment'
}

test_production_initializer_rejects_inherited_overrides() {
  reset_fixture
  SNAPPER_INITIALIZER_TEST_MODE=1 \
    SNAPPER_INITIALIZER_ROOT_MOUNT=/untrusted/root \
    SNAPPER_INITIALIZER_HOME_MOUNT=/untrusted/home \
    SNAPPER_INITIALIZER_CONFIG_DIR=/untrusted/configs \
    run_bootstrap $'yes\nyes\nyes'

  assert_status 0 "$LAST_STATUS" 'production initializer environment isolation'
  assert_log_contains 'sudo -n -- env -i PATH=/usr/bin:/bin SNAPPER_INTERNAL_LIFECYCLE_LOCK_HELD=1 /usr/local/libexec/antoinews-linux/snapper-initialize --apply' \
    'production initializer clean environment'
  assert_log_not_contains 'SNAPPER_INITIALIZER_' 'inherited initializer override'
  assert_log_not_contains '/untrusted/' 'inherited initializer path redirect'
  assert_log_not_contains 'sudo inherited ' 'initializer override inherited by any sudo command'
}

test_stale_staging_files_are_cleaned_before_new_deployment() {
  reset_fixture
  run_bootstrap $'yes\nyes\nyes'

  assert_status 0 "$LAST_STATUS" 'stale Snapper staging cleanup'
  assert_log_contains 'sudo -n -- find -- /etc/snapper/configs -maxdepth 1 -type f -name .root.?????? -delete' \
    'stale root config staging cleanup'
  assert_log_contains 'sudo -n -- find -- /etc/snapper/configs -maxdepth 1 -type f -name .home.?????? -delete' \
    'stale home config staging cleanup'
  assert_log_contains 'sudo -n -- find -- /etc/conf.d -maxdepth 1 -type f -name .snapper.?????? -delete' \
    'stale registration staging cleanup'
  assert_log_contains 'sudo -n -- find -- /usr/local/libexec/antoinews-linux -maxdepth 1 -type f -name .snapper-initialize.?????? -delete' \
    'stale initializer staging cleanup'
}

test_recovery_setup_failure_cleans_unjournaled_directory() {
  reset_fixture
  export SNAPPER_BOOTSTRAP_TEST_RECOVERY_SETUP_FAILURE=chmod
  run_bootstrap $'yes\nyes'

  assert_status 1 "$LAST_STATUS" 'Snapper recovery setup failure'
  assert_contains "$LAST_OUTPUT" 'could not secure Snapper recovery directory' 'Snapper recovery setup failure message'
  assert_log_contains "sudo -n -- rm -rf -- ${RECOVERY_DIRECTORY}" \
    'cleanup of unjournaled recovery directory'
  assert_log_not_contains 'snapper-initialize --apply' 'initializer after recovery setup failure'
}

test_repository_paths_reject_manifest_delimiters() {
  local bad_repo
  local suffix

  for suffix in '|bad' $'\nbad'; do
    reset_fixture
    bad_repo="$TEST_ROOT/repository${suffix}"
    mkdir -p -- "$bad_repo"
    printf 'name: invalid-manifest-path\n' >"$bad_repo/tidydots.yaml"
    run_bootstrap $'yes\nyes\nyes' --repo "$bad_repo"

    assert_status 1 "$LAST_STATUS" "manifest delimiter in repository path: ${suffix@Q}"
    assert_contains "$LAST_OUTPUT" 'repository path cannot contain manifest delimiters' \
      "manifest delimiter message: ${suffix@Q}"
    assert_log_not_contains 'sudo ' "no root command for manifest delimiter: ${suffix@Q}"
  done
}

test_metadata_restore_passes_target_explicitly() {
  # shellcheck disable=SC2016
  assert_source_contains 'restore_optional_metadata "$backup" "$target"' \
    'metadata restore target argument'
  # shellcheck disable=SC2016
  assert_source_contains 'local -r target="$2"' 'metadata restore target local'
}

test_recovery_directories_are_root_owned_before_mode_lockdown() {
  reset_fixture
  run_bootstrap $'yes\nyes\nyes'

  assert_status 0 "$LAST_STATUS" 'recovery directory metadata ordering'
  assert_log_sequence \
    "sudo -n -- chown root:root -- ${RECOVERY_DIRECTORY}" \
    "sudo -n -- chmod 0700 -- ${RECOVERY_DIRECTORY}" \
    "sudo -n -- chown root:root -- ${BACKUP_DIRECTORY}" \
    "sudo -n -- chmod 0700 -- ${BACKUP_DIRECTORY}"
}

test_restore_ownership_precedes_setuid_and_setgid_mode() {
  reset_fixture
  SNAPPER_BOOTSTRAP_TEST_EXISTING_TARGETS=true
  SNAPPER_BOOTSTRAP_TEST_EXISTING_TARGET_MODE=6755
  SNAPPER_BOOTSTRAP_TEST_INITIALIZER_FAILURE=true
  run_bootstrap $'yes\nyes'

  assert_status 1 "$LAST_STATUS" 'setuid and setgid metadata rollback'
  assert_log_sequence \
    "sudo -n -- cp --preserve=all -- ${BACKUP_DIRECTORY}/root /etc/snapper/configs/root" \
    'sudo -n -- chown 1001:1002 -- /etc/snapper/configs/root' \
    'sudo -n -- chmod 6755 -- /etc/snapper/configs/root'
}

test_cleanup_failure_reports_partial_backup_state() {
  reset_fixture
  SNAPPER_BOOTSTRAP_TEST_CLEANUP_FAILURE='backup'
  run_bootstrap $'yes\nyes\nyes'

  assert_status 1 "$LAST_STATUS" 'partial backup cleanup failure'
  assert_contains "$LAST_OUTPUT" 'backup contents may be partial' 'partial backup cleanup wording'
  assert_not_contains "$LAST_OUTPUT" 'backups retained' 'partial backup cleanup retention claim'
  assert_log_not_contains 'tidydots restore -n' 'broad restore after partial backup cleanup'
}

test_cleanup_rmdir_failure_rewrites_recoverable_journal() {
  reset_fixture
  SNAPPER_BOOTSTRAP_TEST_CLEANUP_FAILURE='rmdir'
  run_bootstrap $'yes\nyes\nyes'

  assert_status 1 "$LAST_STATUS" 'recovery directory cleanup failure'
  assert_contains "$LAST_OUTPUT" 'journal and manifest were retained' 'recovery directory cleanup wording'
  assert_log_contains "sudo -n -- rmdir -- ${RECOVERY_DIRECTORY}" 'recovery directory removal attempt'
  assert_log_contains "sudo -n -- mktemp ${RECOVERY_DIRECTORY}/.state." 'journal rewrite after rmdir failure'
  assert_log_contains "sudo -n -- mktemp ${RECOVERY_DIRECTORY}/.manifest." 'manifest rewrite after rmdir failure'
  assert_log_not_contains 'tidydots restore -n' 'broad restore after rmdir cleanup failure'
}

test_cleanup_journal_failure_rewrites_recoverable_journal() {
  reset_fixture
  SNAPPER_BOOTSTRAP_TEST_CLEANUP_FAILURE='journal'
  run_bootstrap $'yes\nyes\nyes'

  assert_status 1 "$LAST_STATUS" 'journal cleanup failure'
  assert_contains "$LAST_OUTPUT" 'journal and manifest were retained' 'journal cleanup failure wording'
  assert_log_contains "sudo -n -- rm -f -- ${RECOVERY_DIRECTORY}/state ${RECOVERY_DIRECTORY}/manifest" \
    'journal cleanup removal attempt'
  assert_log_contains "sudo -n -- mktemp ${RECOVERY_DIRECTORY}/.state." 'journal rewrite after journal cleanup failure'
  assert_log_contains "sudo -n -- mktemp ${RECOVERY_DIRECTORY}/.manifest." 'manifest rewrite after journal cleanup failure'
  assert_log_not_contains_after "sudo -n -- rm -f -- ${RECOVERY_DIRECTORY}/state ${RECOVERY_DIRECTORY}/manifest" \
    'sudo -n -- cp --preserve=all' \
    'journal cleanup failure must not roll back after cleanup starts'
  assert_log_not_contains 'tidydots restore -n' 'broad restore after journal cleanup failure'
}

test_recovery_directory_metadata_is_validated() {
  reset_fixture
  SNAPPER_BOOTSTRAP_TEST_RECOVERY_DIRECTORY_MODE='bad'
  run_bootstrap $'yes\nyes\nyes'

  assert_status 1 "$LAST_STATUS" 'recovery directory metadata validation'
  assert_contains "$LAST_OUTPUT" 'must not be group/world writable' 'recovery directory metadata validation message'
  assert_log_not_contains 'snapper-initialize --apply' 'initializer after recovery directory metadata failure'
}

test_cleanup_phase_blocks_restart_without_rollback() {
  reset_fixture
  SNAPPER_BOOTSTRAP_TEST_JOURNAL_STATE=$'version=1\nphase=cleanup\n'
  SNAPPER_BOOTSTRAP_TEST_JOURNAL_MANIFEST="file|/etc/snapper/configs/root|${BACKUP_DIRECTORY}/root|yes|1001|1002|6755
"
  run_bootstrap $'yes\nyes\nyes'

  assert_status 1 "$LAST_STATUS" 'cleanup phase restart safety'
  assert_contains "$LAST_OUTPUT" 'cleanup is incomplete' 'cleanup phase restart message'
  assert_log_not_contains 'tidydots ' 'cleanup phase restart before tidydots'
  assert_log_not_contains 'sudo -n -- cp --preserve=all' 'cleanup phase restart without rollback'
}

test_rollback_failure_stops_closed() {
  reset_fixture
  SNAPPER_BOOTSTRAP_TEST_LEGACY_LINKS=true
  SNAPPER_BOOTSTRAP_TEST_DEPLOY_FAILURE=true
  SNAPPER_BOOTSTRAP_TEST_ROLLBACK_FAILURE=true
  run_bootstrap $'yes\nyes'

  assert_status 1 "$LAST_STATUS" 'Snapper rollback failure'
  assert_contains "$LAST_OUTPUT" 'rollback' 'Snapper rollback failure message'
  assert_log_not_contains 'snapper-initialize --apply' 'initializer not executed after rollback failure'
  assert_log_not_contains 'tidydots restore -n' 'broad restore not planned after rollback failure'
}

mkdir -p -- "$STUB_BIN"
printf 'ID=arch\n' >"$ARCH_RELEASE"
create_stubs

run_test() {
  local -r test_name="$1"

  if [[ -n "${SNAPPER_BOOTSTRAP_TEST_ONLY:-}" && "$SNAPPER_BOOTSTRAP_TEST_ONLY" != "$test_name" ]]; then
    return 0
  fi
  "$test_name"
}

run_test test_snapper_decline_preserves_legacy_links
run_test test_snapper_deployment_is_rollback_assisted_and_after_confirmation
run_test test_snapper_lifecycle_lock_failure_stops_before_recovery
run_test test_snapper_lifecycle_lock_contention_stops_before_recovery
run_test test_caller_environment_cannot_select_snapper_lifecycle_lock
run_test test_existing_snapper_directories_are_not_misclassified_as_legacy_links
run_test test_initializer_integrity_fails_closed
run_test test_deployment_failure_rolls_back_before_initializer
run_test test_initializer_failure_rolls_back_before_broad_restore
run_test test_rollback_preserves_original_metadata
run_test test_cleanup_failure_keeps_journal_and_stops_without_destructive_rollback
run_test test_partial_install_journal_recovers_before_new_deployment
run_test test_preparation_recovery_removes_only_manifest_directories
run_test test_preparation_recovery_failure_retains_journal
run_test test_production_initializer_rejects_inherited_overrides
run_test test_stale_staging_files_are_cleaned_before_new_deployment
run_test test_recovery_setup_failure_cleans_unjournaled_directory
run_test test_repository_paths_reject_manifest_delimiters
run_test test_metadata_restore_passes_target_explicitly
run_test test_recovery_directories_are_root_owned_before_mode_lockdown
run_test test_restore_ownership_precedes_setuid_and_setgid_mode
run_test test_cleanup_failure_reports_partial_backup_state
run_test test_cleanup_rmdir_failure_rewrites_recoverable_journal
run_test test_cleanup_journal_failure_rewrites_recoverable_journal
run_test test_recovery_directory_metadata_is_validated
run_test test_cleanup_phase_blocks_restart_without_rollback
run_test test_rollback_failure_stops_closed

printf 'PASS: Snapper bootstrap deployment and integrity safety\n'
