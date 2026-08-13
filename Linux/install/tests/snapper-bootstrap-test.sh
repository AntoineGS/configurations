#!/usr/bin/env bash
set -Eeuo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
ROOT="$(cd -- "$SCRIPT_DIR/../../.." && pwd -P)"
BOOTSTRAP="$ROOT/Linux/install/bootstrap"
TEST_ROOT="$(mktemp -d)"
STUB_BIN="$TEST_ROOT/bin"
LOG="$TEST_ROOT/commands.log"
ARCH_RELEASE="$TEST_ROOT/arch-release"
ORIGINAL_PATH="$PATH"
BASH_PATH="$BASH"

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
    'if [[ "$command_name" == test ]]; then' \
    '  negate=false' \
    '  [[ "${1:-}" == ! ]] && negate=true && shift' \
    '  operator="${1:-}"' \
    '  path="${2:-}"' \
    '  result=false' \
    '  case "$operator:$path" in' \
    '    -e:/run/antoinews-linux-snapper-bootstrap|-d:/run/antoinews-linux-snapper-bootstrap)' \
    '      [[ -n "${SNAPPER_BOOTSTRAP_TEST_JOURNAL_STATE:-}" ]] && result=true' \
    '      ;;' \
    '    -e:/run/antoinews-linux-snapper-bootstrap/state|-f:/run/antoinews-linux-snapper-bootstrap/state)' \
    '      [[ -n "${SNAPPER_BOOTSTRAP_TEST_JOURNAL_STATE:-}" ]] && result=true' \
    '      ;;' \
    '    -e:/run/antoinews-linux-snapper-bootstrap/manifest|-f:/run/antoinews-linux-snapper-bootstrap/manifest)' \
    '      [[ -n "${SNAPPER_BOOTSTRAP_TEST_JOURNAL_MANIFEST:-}" ]] && result=true' \
    '      ;;' \
    '    -e:/run/antoinews-linux-snapper-bootstrap/backups/legacy-*)' \
      '      [[ "${SNAPPER_BOOTSTRAP_TEST_LEGACY_LINKS:-false}" == true ]] && result=true' \
      '      ;;' \
    '    -e:/run/antoinews-linux-snapper-bootstrap/backups/legacy-configs|-e:/run/antoinews-linux-snapper-bootstrap/backups/legacy-conf.d)' \
    '      [[ "${SNAPPER_BOOTSTRAP_TEST_LEGACY_LINKS:-false}" == true ]] && result=true' \
    '      ;;' \
    '    -e:/run/antoinews-linux-snapper-bootstrap/backups/*.acl|-e:/run/antoinews-linux-snapper-bootstrap/backups/*.xattr)' \
    '      [[ "${SNAPPER_BOOTSTRAP_TEST_METADATA_TOOLS:-false}" == true ]] && result=true' \
    '      ;;' \
    '    -e:/run/antoinews-linux-snapper-bootstrap/backups/root|-e:/run/antoinews-linux-snapper-bootstrap/backups/home|-e:/run/antoinews-linux-snapper-bootstrap/backups/registration|-e:/run/antoinews-linux-snapper-bootstrap/backups/initializer)' \
      '      [[ "${SNAPPER_BOOTSTRAP_TEST_EXISTING_TARGETS:-false}" == true ]] && result=true' \
      '      ;;' \
    '    -e:/run/antoinews-linux-snapper-bootstrap/backups/*)' \
    '      [[ -n "${SNAPPER_BOOTSTRAP_TEST_JOURNAL_MANIFEST:-}" ]] && result=true' \
    '      ;;' \
    '    -L:/etc/snapper/configs|-L:/etc/conf.d)' \
      '      [[ "${SNAPPER_BOOTSTRAP_TEST_LEGACY_LINKS:-false}" == true ]] && result=true' \
      '      ;;' \
    '    -e:/etc/snapper/configs|-e:/etc/conf.d)' \
    '      [[ "${SNAPPER_BOOTSTRAP_TEST_LEGACY_LINKS:-false}" == true || "${SNAPPER_BOOTSTRAP_TEST_EXISTING_TARGETS:-false}" == true ]] && result=true' \
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
    '    /run/antoinews-linux-snapper-bootstrap/state) printf "%s\n" "${SNAPPER_BOOTSTRAP_TEST_JOURNAL_STATE:-}" ;;' \
    '    /run/antoinews-linux-snapper-bootstrap/manifest) printf "%s\n" "${SNAPPER_BOOTSTRAP_TEST_JOURNAL_MANIFEST:-}" ;;' \
    '    *) exit 1 ;;' \
    '  esac' \
    '  exit 0' \
    'fi' \
    'if [[ "$command_name" == chmod && "${SNAPPER_BOOTSTRAP_TEST_RECOVERY_SETUP_FAILURE:-}" == chmod && "${!#}" == /run/antoinews-linux-snapper-bootstrap ]]; then exit 1; fi' \
    'if [[ "$command_name" == chown && "${SNAPPER_BOOTSTRAP_TEST_RECOVERY_SETUP_FAILURE:-}" == chown && "${!#}" == /run/antoinews-linux-snapper-bootstrap ]]; then exit 1; fi' \
    'if [[ "$command_name" == stat ]]; then' \
    '  format="${2:-}"' \
    '  path="${!#}"' \
    '  if [[ "${SNAPPER_BOOTSTRAP_TEST_EXISTING_TARGETS:-false}" == true && "$path" == /etc/snapper/configs/root || "${SNAPPER_BOOTSTRAP_TEST_EXISTING_TARGETS:-false}" == true && "$path" == /etc/snapper/configs/home || "${SNAPPER_BOOTSTRAP_TEST_EXISTING_TARGETS:-false}" == true && "$path" == /etc/conf.d/snapper ]]; then' \
    '    case "$format" in' \
    '      %u) printf "1001\n" ;;' \
    '      %g) printf "1002\n" ;;' \
    '      %a) printf "640\n" ;;' \
    '      *) exit 1 ;;' \
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
    'if [[ "$command_name" == cp && "${SNAPPER_BOOTSTRAP_TEST_DEPLOY_FAILURE:-false}" == true && "$*" == *"/Linux/Snapper/"* ]]; then exit 1; fi' \
    'if [[ "${SNAPPER_BOOTSTRAP_TEST_ROLLBACK_FAILURE:-false}" == true && "$command_name" == cp && "$*" == *"/backups/"* ]]; then exit 1; fi' \
    'if [[ "$command_name" == rm && "${SNAPPER_BOOTSTRAP_TEST_CLEANUP_FAILURE:-false}" == true && "${1:-}" == -rf && "${!#}" == /run/antoinews-linux-snapper-bootstrap* ]]; then exit 1; fi' \
    'if [[ "$command_name" == *snapper-initialize && "${1:-}" == --apply && "${SNAPPER_BOOTSTRAP_TEST_INITIALIZER_FAILURE:-false}" == true ]]; then exit 1; fi' \
    'exit 0'
}

reset_fixture() {
  : >"$LOG"
  unset \
    SNAPPER_BOOTSTRAP_TEST_LEGACY_LINKS \
    SNAPPER_BOOTSTRAP_TEST_DEPLOY_FAILURE \
    SNAPPER_BOOTSTRAP_TEST_ROLLBACK_FAILURE \
    SNAPPER_BOOTSTRAP_TEST_INITIALIZER_FAILURE \
    SNAPPER_BOOTSTRAP_TEST_CLEANUP_FAILURE \
    SNAPPER_BOOTSTRAP_TEST_EXISTING_TARGETS \
    SNAPPER_BOOTSTRAP_TEST_METADATA_TOOLS \
    SNAPPER_BOOTSTRAP_TEST_RECOVERY_SETUP_FAILURE \
    SNAPPER_BOOTSTRAP_TEST_PATH_FAILURE
  unset SNAPPER_BOOTSTRAP_TEST_JOURNAL_STATE SNAPPER_BOOTSTRAP_TEST_JOURNAL_MANIFEST
}

run_bootstrap() {
  local -r input="$1"
  shift

  if LAST_OUTPUT=$(printf '%s\n' "$input" | \
    PATH="$STUB_BIN:$ORIGINAL_PATH" \
    BOOTSTRAP_OS_RELEASE="$ARCH_RELEASE" \
    BOOTSTRAP_HOSTNAME=server \
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
    SNAPPER_BOOTSTRAP_TEST_JOURNAL_STATE="${SNAPPER_BOOTSTRAP_TEST_JOURNAL_STATE:-}" \
    SNAPPER_BOOTSTRAP_TEST_JOURNAL_MANIFEST="${SNAPPER_BOOTSTRAP_TEST_JOURNAL_MANIFEST:-}" \
    SNAPPER_BOOTSTRAP_TEST_PATH_FAILURE="${SNAPPER_BOOTSTRAP_TEST_PATH_FAILURE:-}" \
    "$BASH_PATH" "$BOOTSTRAP" --repo "$ROOT" "$@" 2>&1); then
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
  assert_contains "$LAST_OUTPUT" 'tidydots restore snapper declined' 'Snapper dry-run decline message'
  assert_contains "$LAST_OUTPUT" 'Snapper deployment plan:' 'Snapper deployment plan before decline'
  assert_log_contains 'restore snapper -n' 'Snapper dry-run before decline'
  assert_log_not_contains_after 'restore snapper -n' 'sudo ' 'no root deployment after Snapper decline'
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
  assert_log_sequence \
    'restore snapper -n' \
    'restore snapper' \
    'sudo -n -- mktemp /run/antoinews-linux-snapper-bootstrap/.manifest.' \
    'sudo -n -- mv -f -- /run/antoinews-linux-snapper-bootstrap/.state.staged /run/antoinews-linux-snapper-bootstrap/state' \
    'sudo -n -- mv -- /etc/snapper/configs /run/antoinews-linux-snapper-bootstrap/backups/legacy-configs' \
    'sudo -n -- mktemp /etc/snapper/configs/.root.' \
    'sudo -n -- cp' \
    'sudo -n -- chmod 0644' \
    'sudo -n -- chown root:root' \
    'sudo -n -- mv -f' \
    'sudo -n -- test ! -L /usr/local/libexec/antoinews-linux/snapper-initialize' \
    'sudo -n -- env -i PATH=/usr/bin:/bin /usr/local/libexec/antoinews-linux/snapper-initialize --apply' \
    'sudo -n -- env -i PATH=/usr/bin:/bin /usr/local/libexec/antoinews-linux/snapper-initialize --check' \
    'restore -n' \
    'restore'
  assert_log_contains 'sudo -n -- chmod 0755' 'initializer mode correction'
  assert_log_contains 'sudo -n -- chown root:root' 'root ownership correction'
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
  assert_log_contains 'sudo -n -- cp --preserve=all -- /run/antoinews-linux-snapper-bootstrap/backups/initializer' \
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
  assert_log_contains 'sudo -n -- cp --preserve=all -- /run/antoinews-linux-snapper-bootstrap/backups/root /etc/snapper/configs/root' \
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
  assert_log_contains 'sudo -n -- chmod 640 -- /etc/snapper/configs/root' 'rollback restores original mode'
  assert_log_contains 'sudo -n -- chown 1001:1002 -- /etc/snapper/configs/root' 'rollback restores original owner'
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
  assert_log_contains 'sudo -n -- rm -rf -- /run/antoinews-linux-snapper-bootstrap/backups' 'cleanup failure backup deletion'
  assert_log_not_contains_after 'sudo -n -- rm -rf -- /run/antoinews-linux-snapper-bootstrap/backups' \
    'sudo -n -- cp --preserve=all /run/antoinews-linux-snapper-bootstrap/backups' \
    'cleanup failure must not restore after backup deletion starts'
  assert_log_not_contains 'tidydots restore -n' 'broad restore after cleanup failure'
}

test_partial_install_journal_recovers_before_new_deployment() {
  reset_fixture
  SNAPPER_BOOTSTRAP_TEST_LEGACY_LINKS=true
  SNAPPER_BOOTSTRAP_TEST_JOURNAL_STATE=$'version=1\nphase=deploying\n'
  SNAPPER_BOOTSTRAP_TEST_JOURNAL_MANIFEST="legacy|/etc/snapper/configs|/run/antoinews-linux-snapper-bootstrap/backups/legacy-configs|$ROOT/Linux/Snapper/configs
file|/etc/snapper/configs/root|/run/antoinews-linux-snapper-bootstrap/backups/root|yes|1001|1002|640
"
  run_bootstrap $'yes\nyes\nyes'

  assert_status 0 "$LAST_STATUS" 'Snapper journal recovery'
  assert_log_sequence \
    'sudo -n -- test -e /run/antoinews-linux-snapper-bootstrap' \
    'sudo -n -- cat -- /run/antoinews-linux-snapper-bootstrap/state' \
    'sudo -n -- cp --preserve=all -- /run/antoinews-linux-snapper-bootstrap/backups/root /etc/snapper/configs/root' \
    'sudo -n -- mktemp /run/antoinews-linux-snapper-bootstrap/.manifest.'
}

test_initializer_uses_clean_fixed_environment() {
  reset_fixture
  SNAPPER_BOOTSTRAP_TEST_INITIALIZER_ROOT_MOUNT=/untrusted \
    SNAPPER_INITIALIZER_ROOT_MOUNT=/untrusted \
    run_bootstrap $'yes\nyes\nyes'

  assert_status 0 "$LAST_STATUS" 'clean initializer environment'
  assert_log_contains 'sudo -n -- env -i PATH=/usr/bin:/bin /usr/local/libexec/antoinews-linux/snapper-initialize --apply' \
    'clean initializer environment'
  assert_log_not_contains 'SNAPPER_INITIALIZER_ROOT_MOUNT' 'inherited initializer override'
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
  assert_log_contains 'sudo -n -- rm -rf -- /run/antoinews-linux-snapper-bootstrap' \
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
run_test test_initializer_integrity_fails_closed
run_test test_deployment_failure_rolls_back_before_initializer
run_test test_initializer_failure_rolls_back_before_broad_restore
run_test test_rollback_preserves_original_metadata
run_test test_cleanup_failure_keeps_journal_and_stops_without_destructive_rollback
run_test test_partial_install_journal_recovers_before_new_deployment
run_test test_initializer_uses_clean_fixed_environment
run_test test_stale_staging_files_are_cleaned_before_new_deployment
run_test test_recovery_setup_failure_cleans_unjournaled_directory
run_test test_repository_paths_reject_manifest_delimiters
run_test test_metadata_restore_passes_target_explicitly
run_test test_rollback_failure_stops_closed

printf 'PASS: Snapper bootstrap deployment and integrity safety\n'
