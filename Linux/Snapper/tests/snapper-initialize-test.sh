#!/usr/bin/env bash
set -Eeuo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
SCRIPT="${SCRIPT_DIR}/../snapper-initialize"
TEST_ROOT="$(mktemp -d)"
BIN="$TEST_ROOT/bin"
FIXTURE_ROOT="$TEST_ROOT/system"
ROOT_MOUNT="$FIXTURE_ROOT/root"
HOME_MOUNT="$FIXTURE_ROOT/home"
CONFIG_DIR="$FIXTURE_ROOT/etc/snapper/configs"
CONF_DIR="$FIXTURE_ROOT/etc/conf.d"
REGISTRATION_FILE="$CONF_DIR/snapper"
COMMAND_LOG="$TEST_ROOT/commands.log"
SUBVOLUME_STATE="$TEST_ROOT/subvolumes"
CONFIG_TEMPLATE="$TEST_ROOT/default-template"
RECOVERY_DIRECTORY="$TEST_ROOT/snapper-bootstrap"
ORIGINAL_PATH="$PATH"
UNSHARE="$(command -v unshare || true)"
BASH_PATH="$BASH"

LAST_OUTPUT=""
LAST_STATUS=0
TEST_FSTYPE="btrfs"
TEST_ROOT_FSROOT="/@"
TEST_HOME_FSROOT="/@home"
TEST_UUID="test-btrfs-uuid"
TEST_ROOT_UUID="test-btrfs-uuid"
TEST_HOME_UUID="test-btrfs-uuid"
TEST_SNAPPER_FAIL=false
TEST_SNAPPER_FAIL_IF_SNAPSHOT_EXISTS=false
TEST_ROOT_SUBVOLUME_ID="256"
TEST_HOME_SUBVOLUME_ID="257"
TEST_ROOT_SNAPSHOT_SUBVOLUME_ID="258"
TEST_HOME_SNAPSHOT_SUBVOLUME_ID="259"
TEST_ROOT_SNAPSHOT_PARENT_ID="256"
TEST_HOME_SNAPSHOT_PARENT_ID="257"
TEST_ROOT_SNAPSHOT_FSROOT="/@"
TEST_HOME_SNAPSHOT_FSROOT="/@home"
TEST_ROOT_SNAPSHOT_UID="0"
TEST_HOME_SNAPSHOT_UID="0"
TEST_ROOT_SNAPSHOT_GID="0"
TEST_HOME_SNAPSHOT_GID="0"
TEST_ROOT_SNAPSHOT_MODE="750"
TEST_HOME_SNAPSHOT_MODE="750"
TEST_INITIAL_SNAPSHOT_NUMBER="1"
TEST_INITIAL_SNAPSHOT_VALID=true
TEST_INITIAL_SNAPSHOT_EXISTS=false

trap 'rm -rf -- "$TEST_ROOT"' EXIT

fail() {
  printf 'FAIL: %s\n' "$*" >&2
  exit 1
}

assert_status() {
  local -r expected="$1"
  local -r actual="$2"
  local -r context="$3"

  [[ "$actual" == "$expected" ]] || fail "$context: expected exit $expected, got $actual\n$LAST_OUTPUT\n$(<"$COMMAND_LOG")"
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
  local log_contents

  log_contents="$(<"$COMMAND_LOG")"
  assert_contains "$log_contents" "$needle" "$context"
}

assert_log_not_contains() {
  local -r needle="$1"
  local -r context="$2"
  local log_contents

  log_contents="$(<"$COMMAND_LOG")"
  assert_not_contains "$log_contents" "$needle" "$context"
}

write_executable() {
  local -r path="$1"
  shift

  printf '%s\n' '#!/usr/bin/env bash' 'set -Eeuo pipefail' "$@" >"$path"
  chmod +x -- "$path"
}

create_stubs() {
  mkdir -p -- "$BIN"

  # shellcheck disable=SC2016
  write_executable "$BIN/findmnt" \
    'printf "findmnt" >> "$SNAPPER_TEST_COMMAND_LOG"' \
    'for argument in "$@"; do printf " %s" "$argument" >> "$SNAPPER_TEST_COMMAND_LOG"; done' \
    'printf "\\n" >> "$SNAPPER_TEST_COMMAND_LOG"' \
    'property=""' \
    'target=""' \
    'while [[ $# -gt 0 ]]; do' \
    '  case "$1" in' \
    '    --output) property="$2"; shift 2 ;;' \
    '    --target) target="$2"; shift 2 ;;' \
    '    *) shift ;;' \
    '  esac' \
    'done' \
    'case "$property" in' \
    '  FSTYPE) printf "%s\\n" "$SNAPPER_TEST_FSTYPE" ;;' \
    '  FSROOT)' \
    '    if [[ "$target" == "$SNAPPER_TEST_ROOT_MOUNT" ]]; then' \
    '      printf "%s\\n" "$SNAPPER_TEST_ROOT_FSROOT"' \
    '    elif [[ "$target" == "$SNAPPER_TEST_HOME_MOUNT" ]]; then' \
    '      printf "%s\\n" "$SNAPPER_TEST_HOME_FSROOT"' \
    '    elif [[ "$target" == "$SNAPPER_TEST_ROOT_MOUNT/.snapshots"* ]]; then' \
    '      printf "%s\\n" "$SNAPPER_TEST_ROOT_SNAPSHOT_FSROOT"' \
    '    elif [[ "$target" == "$SNAPPER_TEST_HOME_MOUNT/.snapshots"* ]]; then' \
    '      printf "%s\\n" "$SNAPPER_TEST_HOME_SNAPSHOT_FSROOT"' \
    '    else' \
    '      exit 1' \
    '    fi' \
    '    ;;' \
    '  UUID)' \
    '    if [[ "$target" == "$SNAPPER_TEST_HOME_MOUNT" || "$target" == "$SNAPPER_TEST_HOME_MOUNT/.snapshots"* ]]; then' \
    '      printf "%s\\n" "$SNAPPER_TEST_HOME_UUID"' \
    '    else' \
    '      printf "%s\\n" "$SNAPPER_TEST_ROOT_UUID"' \
    '    fi' \
    '    ;;' \
    '  *) exit 1 ;;' \
    'esac'

  # shellcheck disable=SC2016
  write_executable "$BIN/btrfs" \
    'printf "btrfs" >> "$SNAPPER_TEST_COMMAND_LOG"' \
    'for argument in "$@"; do printf " %s" "$argument" >> "$SNAPPER_TEST_COMMAND_LOG"; done' \
    'printf "\\n" >> "$SNAPPER_TEST_COMMAND_LOG"' \
    '[[ "${1:-}" == subvolume ]] || exit 2' \
    'case "${2:-}" in' \
    '  show)' \
    '    path="${3:-}"' \
    '    if [[ "$path" == "$SNAPPER_TEST_ROOT_MOUNT" ]]; then' \
    '      printf "Subvolume ID: %s\\nParent ID: 5\\n" "$SNAPPER_TEST_ROOT_SUBVOLUME_ID"' \
    '      exit 0' \
    '    fi' \
    '    if [[ "$path" == "$SNAPPER_TEST_HOME_MOUNT" ]]; then' \
    '      printf "Subvolume ID: %s\\nParent ID: 5\\n" "$SNAPPER_TEST_HOME_SUBVOLUME_ID"' \
    '      exit 0' \
    '    fi' \
    '    if [[ "$path" == "$SNAPPER_TEST_ROOT_MOUNT/.snapshots" ]]; then' \
    '      while IFS= read -r subvolume; do [[ "$subvolume" == "$path" ]] || continue; printf "Subvolume ID: %s\\nParent ID: %s\\n" "$SNAPPER_TEST_ROOT_SNAPSHOT_SUBVOLUME_ID" "$SNAPPER_TEST_ROOT_SNAPSHOT_PARENT_ID"; exit 0; done < "$SNAPPER_TEST_SUBVOLUMES"' \
    '      exit 1' \
    '    fi' \
    '    if [[ "$path" == "$SNAPPER_TEST_HOME_MOUNT/.snapshots" ]]; then' \
    '      while IFS= read -r subvolume; do [[ "$subvolume" == "$path" ]] || continue; printf "Subvolume ID: %s\\nParent ID: %s\\n" "$SNAPPER_TEST_HOME_SNAPSHOT_SUBVOLUME_ID" "$SNAPPER_TEST_HOME_SNAPSHOT_PARENT_ID"; exit 0; done < "$SNAPPER_TEST_SUBVOLUMES"' \
    '      exit 1' \
    '    fi' \
    '    while IFS= read -r subvolume; do' \
    '      if [[ "$subvolume" == "$path" ]]; then' \
    '        if [[ "$path" == "$SNAPPER_TEST_ROOT_MOUNT/.snapshots/"* ]]; then' \
    '          printf "Subvolume ID: 300\\nParent ID: %s\\n" "$SNAPPER_TEST_ROOT_SNAPSHOT_SUBVOLUME_ID"' \
    '        elif [[ "$path" == "$SNAPPER_TEST_HOME_MOUNT/.snapshots/"* ]]; then' \
    '          printf "Subvolume ID: 301\\nParent ID: %s\\n" "$SNAPPER_TEST_HOME_SNAPSHOT_SUBVOLUME_ID"' \
    '        fi' \
    '        exit 0' \
    '      fi' \
    '    done < "$SNAPPER_TEST_SUBVOLUMES"' \
    '    if [[ "$path" == "$SNAPPER_TEST_ROOT_MOUNT/.snapshots/"* && "$SNAPPER_TEST_INITIAL_SNAPSHOT_VALID" == true ]]; then' \
    '      printf "Subvolume ID: 300\\nParent ID: %s\\n" "$SNAPPER_TEST_ROOT_SNAPSHOT_SUBVOLUME_ID"' \
    '      exit 0' \
    '    fi' \
    '    if [[ "$path" == "$SNAPPER_TEST_HOME_MOUNT/.snapshots/"* && "$SNAPPER_TEST_INITIAL_SNAPSHOT_VALID" == true ]]; then' \
    '      printf "Subvolume ID: 301\\nParent ID: %s\\n" "$SNAPPER_TEST_HOME_SNAPSHOT_SUBVOLUME_ID"' \
    '      exit 0' \
    '    fi' \
    '    exit 1' \
    '    ;;' \
    '  create)' \
    '    path="${3:-}"' \
    '    printf "%s\\n" "$path" >> "$SNAPPER_TEST_SUBVOLUMES"' \
    '    /usr/bin/mkdir -p -- "$path"' \
    '    ;;' \
    '  *) exit 2 ;;' \
    'esac'

  # shellcheck disable=SC2016
  write_executable "$BIN/stat" \
    'printf "stat" >> "$SNAPPER_TEST_COMMAND_LOG"' \
    'for argument in "$@"; do printf " %s" "$argument" >> "$SNAPPER_TEST_COMMAND_LOG"; done' \
    'printf "\\n" >> "$SNAPPER_TEST_COMMAND_LOG"' \
    'format=""' \
    'path=""' \
    'while [[ $# -gt 0 ]]; do' \
    '  case "$1" in' \
    '    -c) format="$2"; shift 2 ;;' \
    '    --) shift; path="$1"; shift ;;' \
    '    *) path="$1"; shift ;;' \
    '  esac' \
    'done' \
    'if [[ "$path" == "$SNAPPER_TEST_ROOT_MOUNT/.snapshots"* ]]; then' \
    '  case "$format" in' \
    '    %u) printf "%s\\n" "$SNAPPER_TEST_ROOT_SNAPSHOT_UID" ;;' \
    '    %g) printf "%s\\n" "$SNAPPER_TEST_ROOT_SNAPSHOT_GID" ;;' \
    '    %a) printf "%s\\n" "$SNAPPER_TEST_ROOT_SNAPSHOT_MODE" ;;' \
    '    *) exit 1 ;;' \
    '  esac' \
    'elif [[ "$path" == "$SNAPPER_TEST_HOME_MOUNT/.snapshots"* ]]; then' \
    '  case "$format" in' \
    '    %u) printf "%s\\n" "$SNAPPER_TEST_HOME_SNAPSHOT_UID" ;;' \
    '    %g) printf "%s\\n" "$SNAPPER_TEST_HOME_SNAPSHOT_GID" ;;' \
    '    %a) printf "%s\\n" "$SNAPPER_TEST_HOME_SNAPSHOT_MODE" ;;' \
    '    *) exit 1 ;;' \
    '  esac' \
    'else' \
    '  case "$format" in' \
    '    %u|%g) printf "0\\n" ;;' \
    '    %a) printf "644\\n" ;;' \
    '    *) exit 1 ;;' \
    '  esac' \
    'fi'

  # shellcheck disable=SC2016
  write_executable "$BIN/chmod" \
    'printf "chmod" >> "$SNAPPER_TEST_COMMAND_LOG"' \
    'for argument in "$@"; do printf " %s" "$argument" >> "$SNAPPER_TEST_COMMAND_LOG"; done' \
    'printf "\\n" >> "$SNAPPER_TEST_COMMAND_LOG"'

  # shellcheck disable=SC2016
  write_executable "$BIN/chown" \
    'printf "chown" >> "$SNAPPER_TEST_COMMAND_LOG"' \
    'for argument in "$@"; do printf " %s" "$argument" >> "$SNAPPER_TEST_COMMAND_LOG"; done' \
    'printf "\\n" >> "$SNAPPER_TEST_COMMAND_LOG"'

  # shellcheck disable=SC2016
  write_executable "$BIN/mv" \
    'printf "mv" >> "$SNAPPER_TEST_COMMAND_LOG"' \
    'for argument in "$@"; do printf " %s" "$argument" >> "$SNAPPER_TEST_COMMAND_LOG"; done' \
    'printf "\\n" >> "$SNAPPER_TEST_COMMAND_LOG"' \
    '/usr/bin/mv "$@"'

  # shellcheck disable=SC2016
  write_executable "$BIN/mktemp" \
    'printf "mktemp" >> "$SNAPPER_TEST_COMMAND_LOG"' \
    'for argument in "$@"; do printf " %s" "$argument" >> "$SNAPPER_TEST_COMMAND_LOG"; done' \
    'printf "\\n" >> "$SNAPPER_TEST_COMMAND_LOG"' \
    '/usr/bin/mktemp "$@"'

  # shellcheck disable=SC2016
  write_executable "$BIN/snapper" \
    'printf "snapper" >> "$SNAPPER_TEST_COMMAND_LOG"' \
    'for argument in "$@"; do printf " %s" "$argument" >> "$SNAPPER_TEST_COMMAND_LOG"; done' \
    'printf "\\n" >> "$SNAPPER_TEST_COMMAND_LOG"' \
    '[[ "$SNAPPER_TEST_FAIL" == false ]] || exit 1' \
    'config=""' \
    'command_name=""' \
    'subvolume=""' \
    'print_number=false' \
    'while [[ $# -gt 0 ]]; do' \
    '  case "$1" in' \
    '    --no-dbus) shift ;;' \
    '    --config|-c) config="$2"; shift 2 ;;' \
    '    create-config|create|list) command_name="$1"; shift ;;' \
    '    --fstype|--description|--cleanup-algorithm|--columns) shift 2 ;;' \
    '    --print-number) print_number=true; shift ;;' \
    '    *) subvolume="$1"; shift ;;' \
    '  esac' \
    'done' \
    'if [[ "$command_name" == list ]]; then' \
    '  mount_path="$([[ "$config" == root ]] && printf "%s" "$SNAPPER_TEST_ROOT_MOUNT" || printf "%s" "$SNAPPER_TEST_HOME_MOUNT")"' \
    '  if [[ "$SNAPPER_TEST_INITIAL_SNAPSHOT_EXISTS" == true ]] || /usr/bin/grep -Fq "$mount_path/.snapshots/" "$SNAPPER_TEST_SUBVOLUMES"; then' \
    '    printf "%s,initial recovery snapshot\\n" "$SNAPPER_TEST_INITIAL_SNAPSHOT_NUMBER"' \
    '  fi' \
    '  exit 0' \
    'fi' \
    'if [[ "$command_name" == create-config ]]; then' \
    '  [[ -n "$config" && -n "$subvolume" ]] || exit 2' \
    '  if [[ "$SNAPPER_TEST_FAIL_IF_SNAPSHOT_EXISTS" == true && -e "$subvolume/.snapshots" ]]; then exit 1; fi' \
    '  /usr/bin/mkdir -p -- "$SNAPPER_TEST_CONFIG_DIR" "$subvolume/.snapshots"' \
    '  printf "SUBVOLUME=\\\"%s\\\"\\nFSTYPE=\\\"btrfs\\\"\\nTIMELINE_CREATE=\\\"yes\\\"\\nTIMELINE_CLEANUP=\\\"yes\\\"\\nTIMELINE_LIMIT_HOURLY=\\\"6\\\"\\nTIMELINE_LIMIT_DAILY=\\\"7\\\"\\nTIMELINE_LIMIT_WEEKLY=\\\"4\\\"\\nTIMELINE_LIMIT_MONTHLY=\\\"6\\\"\\nTIMELINE_LIMIT_QUARTERLY=\\\"4\\\"\\nTIMELINE_LIMIT_YEARLY=\\\"2\\\"\\n" "$([[ "$config" == root ]] && printf / || printf /home)" > "$SNAPPER_TEST_CONFIG_DIR/$config"' \
    '  printf "%s\\n" "$subvolume/.snapshots" >> "$SNAPPER_TEST_SUBVOLUMES"' \
    '  printf "SNAPPER_CONFIGS=\\\"root home\\\"\\n" > "$SNAPPER_TEST_REGISTRATION"' \
    '  exit 0' \
    'fi' \
    '[[ "$command_name" == create && -n "$config" ]] || exit 2' \
    'mount_path="$([[ "$config" == root ]] && printf "%s" "$SNAPPER_TEST_ROOT_MOUNT" || printf "%s" "$SNAPPER_TEST_HOME_MOUNT")"' \
    'snapshot_path="$mount_path/.snapshots/$SNAPPER_TEST_INITIAL_SNAPSHOT_NUMBER/snapshot"' \
    '/usr/bin/mkdir -p -- "$snapshot_path"' \
    'if [[ "$SNAPPER_TEST_INITIAL_SNAPSHOT_VALID" == true ]]; then printf "%s\\n" "$snapshot_path" >> "$SNAPPER_TEST_SUBVOLUMES"; fi' \
    '[[ "$print_number" == true ]] && printf "%s\\n" "$SNAPPER_TEST_INITIAL_SNAPSHOT_NUMBER"'
}

reset_fixture() {
  rm -rf -- "$FIXTURE_ROOT"
  rm -rf -- "$RECOVERY_DIRECTORY"
  mkdir -p -- "$ROOT_MOUNT" "$HOME_MOUNT" "$CONFIG_DIR" "$CONF_DIR"
  : >"$COMMAND_LOG"
  : >"$SUBVOLUME_STATE"
  printf 'SUBVOLUME="/"\nFSTYPE="btrfs"\nNUMBER_CLEANUP="yes"\nTIMELINE_CREATE="yes"\nTIMELINE_CLEANUP="yes"\nTIMELINE_LIMIT_HOURLY="6"\nTIMELINE_LIMIT_DAILY="7"\nTIMELINE_LIMIT_WEEKLY="4"\nTIMELINE_LIMIT_MONTHLY="6"\nTIMELINE_LIMIT_QUARTERLY="4"\nTIMELINE_LIMIT_YEARLY="2"\n' >"$CONFIG_TEMPLATE"
  TEST_FSTYPE="btrfs"
  TEST_ROOT_FSROOT="/@"
  TEST_HOME_FSROOT="/@home"
  TEST_UUID="test-btrfs-uuid"
  TEST_ROOT_UUID="test-btrfs-uuid"
  TEST_HOME_UUID="test-btrfs-uuid"
  TEST_SNAPPER_FAIL=false
  TEST_SNAPPER_FAIL_IF_SNAPSHOT_EXISTS=false
  TEST_ROOT_SUBVOLUME_ID="256"
  TEST_HOME_SUBVOLUME_ID="257"
  TEST_ROOT_SNAPSHOT_SUBVOLUME_ID="258"
  TEST_HOME_SNAPSHOT_SUBVOLUME_ID="259"
  TEST_ROOT_SNAPSHOT_PARENT_ID="256"
  TEST_HOME_SNAPSHOT_PARENT_ID="257"
  TEST_ROOT_SNAPSHOT_FSROOT="/@"
  TEST_HOME_SNAPSHOT_FSROOT="/@home"
  TEST_ROOT_SNAPSHOT_UID="0"
  TEST_HOME_SNAPSHOT_UID="0"
  TEST_ROOT_SNAPSHOT_GID="0"
  TEST_HOME_SNAPSHOT_GID="0"
  TEST_ROOT_SNAPSHOT_MODE="750"
  TEST_HOME_SNAPSHOT_MODE="750"
  TEST_INITIAL_SNAPSHOT_NUMBER="1"
  TEST_INITIAL_SNAPSHOT_VALID=true
  TEST_INITIAL_SNAPSHOT_EXISTS=false
}

write_config() {
  local -r name="$1"
  local -r subvolume="$2"

  printf 'SUBVOLUME="%s"\nFSTYPE="btrfs"\nTIMELINE_CREATE="yes"\nTIMELINE_CLEANUP="yes"\nTIMELINE_LIMIT_HOURLY="6"\nTIMELINE_LIMIT_DAILY="7"\nTIMELINE_LIMIT_WEEKLY="4"\nTIMELINE_LIMIT_MONTHLY="6"\nTIMELINE_LIMIT_QUARTERLY="4"\nTIMELINE_LIMIT_YEARLY="2"\n' "$subvolume" >"$CONFIG_DIR/$name"
}

mark_subvolumes() {
  printf '%s\n' "$ROOT_MOUNT/.snapshots" "$HOME_MOUNT/.snapshots" >"$SUBVOLUME_STATE"
  mkdir -p -- "$ROOT_MOUNT/.snapshots" "$HOME_MOUNT/.snapshots"
}

mark_initial_snapshots() {
  printf '%s\n' "$ROOT_MOUNT/.snapshots/$TEST_INITIAL_SNAPSHOT_NUMBER/snapshot" \
    "$HOME_MOUNT/.snapshots/$TEST_INITIAL_SNAPSHOT_NUMBER/snapshot" >>"$SUBVOLUME_STATE"
  mkdir -p -- "$ROOT_MOUNT/.snapshots/$TEST_INITIAL_SNAPSHOT_NUMBER/snapshot" \
    "$HOME_MOUNT/.snapshots/$TEST_INITIAL_SNAPSHOT_NUMBER/snapshot"
}

write_registration() {
  printf 'SNAPPER_CONFIGS="root home"\n' >"$REGISTRATION_FILE"
}

run_as_root() {
  if LAST_OUTPUT=$(env \
    PATH="$BIN:$ORIGINAL_PATH" \
    SNAPPER_TEST_COMMAND_LOG="$COMMAND_LOG" \
    SNAPPER_TEST_SUBVOLUMES="$SUBVOLUME_STATE" \
    SNAPPER_TEST_CONFIG_DIR="$CONFIG_DIR" \
    SNAPPER_TEST_REGISTRATION="$REGISTRATION_FILE" \
    SNAPPER_TEST_FSTYPE="$TEST_FSTYPE" \
    SNAPPER_TEST_ROOT_FSROOT="$TEST_ROOT_FSROOT" \
    SNAPPER_TEST_HOME_FSROOT="$TEST_HOME_FSROOT" \
    SNAPPER_TEST_UUID="$TEST_UUID" \
    SNAPPER_TEST_ROOT_UUID="$TEST_ROOT_UUID" \
    SNAPPER_TEST_HOME_UUID="$TEST_HOME_UUID" \
    SNAPPER_TEST_ROOT_MOUNT="$ROOT_MOUNT" \
    SNAPPER_TEST_HOME_MOUNT="$HOME_MOUNT" \
    SNAPPER_TEST_ROOT_SUBVOLUME_ID="$TEST_ROOT_SUBVOLUME_ID" \
    SNAPPER_TEST_HOME_SUBVOLUME_ID="$TEST_HOME_SUBVOLUME_ID" \
    SNAPPER_TEST_ROOT_SNAPSHOT_SUBVOLUME_ID="$TEST_ROOT_SNAPSHOT_SUBVOLUME_ID" \
    SNAPPER_TEST_HOME_SNAPSHOT_SUBVOLUME_ID="$TEST_HOME_SNAPSHOT_SUBVOLUME_ID" \
    SNAPPER_TEST_ROOT_SNAPSHOT_PARENT_ID="$TEST_ROOT_SNAPSHOT_PARENT_ID" \
    SNAPPER_TEST_HOME_SNAPSHOT_PARENT_ID="$TEST_HOME_SNAPSHOT_PARENT_ID" \
    SNAPPER_TEST_ROOT_SNAPSHOT_FSROOT="$TEST_ROOT_SNAPSHOT_FSROOT" \
    SNAPPER_TEST_HOME_SNAPSHOT_FSROOT="$TEST_HOME_SNAPSHOT_FSROOT" \
    SNAPPER_TEST_ROOT_SNAPSHOT_UID="$TEST_ROOT_SNAPSHOT_UID" \
    SNAPPER_TEST_HOME_SNAPSHOT_UID="$TEST_HOME_SNAPSHOT_UID" \
    SNAPPER_TEST_ROOT_SNAPSHOT_GID="$TEST_ROOT_SNAPSHOT_GID" \
    SNAPPER_TEST_HOME_SNAPSHOT_GID="$TEST_HOME_SNAPSHOT_GID" \
    SNAPPER_TEST_ROOT_SNAPSHOT_MODE="$TEST_ROOT_SNAPSHOT_MODE" \
    SNAPPER_TEST_HOME_SNAPSHOT_MODE="$TEST_HOME_SNAPSHOT_MODE" \
    SNAPPER_TEST_INITIAL_SNAPSHOT_NUMBER="$TEST_INITIAL_SNAPSHOT_NUMBER" \
    SNAPPER_TEST_INITIAL_SNAPSHOT_VALID="$TEST_INITIAL_SNAPSHOT_VALID" \
    SNAPPER_TEST_INITIAL_SNAPSHOT_EXISTS="$TEST_INITIAL_SNAPSHOT_EXISTS" \
    SNAPPER_TEST_FAIL="$TEST_SNAPPER_FAIL" \
    SNAPPER_TEST_FAIL_IF_SNAPSHOT_EXISTS="$TEST_SNAPPER_FAIL_IF_SNAPSHOT_EXISTS" \
    SNAPPER_INITIALIZER_TEST_MODE=1 \
    SNAPPER_INITIALIZER_ROOT_MOUNT="$ROOT_MOUNT" \
    SNAPPER_INITIALIZER_HOME_MOUNT="$HOME_MOUNT" \
    SNAPPER_INITIALIZER_TEST_MODE=1 \
    SNAPPER_INITIALIZER_CONFIG_DIR="$CONFIG_DIR" \
    SNAPPER_INITIALIZER_REGISTRATION_FILE="$REGISTRATION_FILE" \
    SNAPPER_INITIALIZER_TEMPLATE="$CONFIG_TEMPLATE" \
    SNAPPER_INITIALIZER_RECOVERY_DIRECTORY="$RECOVERY_DIRECTORY" \
    "$UNSHARE" --user --map-root-user "$BASH_PATH" "$SCRIPT" "$@" 2>&1); then
    LAST_STATUS=0
  else
    LAST_STATUS=$?
  fi
}

run_as_current_user() {
  if LAST_OUTPUT=$(env \
    PATH="$BIN:$ORIGINAL_PATH" \
    SNAPPER_TEST_COMMAND_LOG="$COMMAND_LOG" \
    SNAPPER_TEST_SUBVOLUMES="$SUBVOLUME_STATE" \
    SNAPPER_TEST_CONFIG_DIR="$CONFIG_DIR" \
    SNAPPER_TEST_REGISTRATION="$REGISTRATION_FILE" \
    SNAPPER_INITIALIZER_ROOT_MOUNT="$ROOT_MOUNT" \
    SNAPPER_INITIALIZER_HOME_MOUNT="$HOME_MOUNT" \
    SNAPPER_INITIALIZER_CONFIG_DIR="$CONFIG_DIR" \
    SNAPPER_INITIALIZER_REGISTRATION_FILE="$REGISTRATION_FILE" \
    SNAPPER_INITIALIZER_TEMPLATE="$CONFIG_TEMPLATE" \
    SNAPPER_INITIALIZER_RECOVERY_DIRECTORY="$RECOVERY_DIRECTORY" \
    "$BASH_PATH" "$SCRIPT" "$@" 2>&1); then
    LAST_STATUS=0
  else
    LAST_STATUS=$?
  fi
}

run_without_test_mode() {
  if LAST_OUTPUT=$(env -u SNAPPER_INITIALIZER_TEST_MODE \
    PATH="$BIN:$ORIGINAL_PATH" \
    SNAPPER_TEST_COMMAND_LOG="$COMMAND_LOG" \
    SNAPPER_TEST_SUBVOLUMES="$SUBVOLUME_STATE" \
    SNAPPER_TEST_CONFIG_DIR="$CONFIG_DIR" \
    SNAPPER_TEST_REGISTRATION="$REGISTRATION_FILE" \
    SNAPPER_INITIALIZER_ROOT_MOUNT="$ROOT_MOUNT" \
    SNAPPER_INITIALIZER_HOME_MOUNT="$HOME_MOUNT" \
    SNAPPER_INITIALIZER_CONFIG_DIR="$CONFIG_DIR" \
    SNAPPER_INITIALIZER_REGISTRATION_FILE="$REGISTRATION_FILE" \
    SNAPPER_INITIALIZER_TEMPLATE="$CONFIG_TEMPLATE" \
    SNAPPER_INITIALIZER_RECOVERY_DIRECTORY="$RECOVERY_DIRECTORY" \
    "$UNSHARE" --user --map-root-user "$BASH_PATH" "$SCRIPT" "$@" 2>&1); then
    LAST_STATUS=0
  else
    LAST_STATUS=$?
  fi
}

test_script_is_executable() {
  [[ -x "$SCRIPT" ]] || fail "$SCRIPT must exist and be executable"
}

test_help_and_unknown_option() {
  run_as_root --help
  assert_status 0 "$LAST_STATUS" '--help'
  assert_contains "$LAST_OUTPUT" 'Usage:' '--help usage'
  assert_contains "$LAST_OUTPUT" '--check|--apply|--create-initial-snapshots' '--help modes'

  run_as_root --unknown
  assert_status 2 "$LAST_STATUS" 'unknown option'
  assert_contains "$LAST_OUTPUT" 'unknown option' 'unknown option message'
}

test_non_root_is_rejected_before_commands() {
  reset_fixture
  run_as_current_user --check

  assert_status 1 "$LAST_STATUS" 'non-root check'
  assert_contains "$LAST_OUTPUT" 'must run as root' 'non-root message'
  assert_log_not_contains 'findmnt ' 'non-root command log'
  assert_log_not_contains 'btrfs ' 'non-root command log'
  assert_log_not_contains 'snapper ' 'non-root command log'
}

test_initializer_overrides_require_test_mode() {
  reset_fixture
  run_without_test_mode --check

  assert_status 1 "$LAST_STATUS" 'initializer override gate'
  assert_not_contains "$LAST_OUTPUT" "$ROOT_MOUNT" 'initializer override gate root path'
  assert_log_not_contains "$ROOT_MOUNT" 'initializer override gate command path'
}

test_check_is_read_only_when_layout_is_ready() {
  reset_fixture
  write_config root /
  write_config home /home
  write_registration
  mark_subvolumes
  mark_initial_snapshots

  run_as_root --check

  assert_status 0 "$LAST_STATUS" 'ready check'
  assert_contains "$LAST_OUTPUT" 'Snapper layout is ready' 'ready check output'
  assert_log_not_contains 'subvolume create' 'read-only check'
  assert_log_not_contains 'snapper --no-dbus --config root create' 'read-only check'
  assert_log_not_contains 'snapper --no-dbus --config home create' 'read-only check'
  assert_log_not_contains 'chmod ' 'read-only check'
  assert_log_not_contains 'chown ' 'read-only check'
  assert_log_not_contains 'mv ' 'read-only check'
}

test_check_rejects_non_btrfs_without_mutation() {
  reset_fixture
  TEST_FSTYPE="ext4"

  run_as_root --check

  assert_status 1 "$LAST_STATUS" 'non-Btrfs check'
  assert_contains "$LAST_OUTPUT" 'Btrfs' 'non-Btrfs message'
  assert_log_not_contains 'btrfs ' 'non-Btrfs check'
  assert_log_not_contains 'snapper ' 'non-Btrfs check'
}

test_check_rejects_mismatched_btrfs_uuid_without_mutation() {
  reset_fixture
  TEST_HOME_UUID="different-btrfs-uuid"

  run_as_root --check

  assert_status 1 "$LAST_STATUS" 'mismatched Btrfs UUID check'
  assert_contains "$LAST_OUTPUT" 'same Btrfs filesystem' 'mismatched Btrfs UUID message'
  assert_log_not_contains 'btrfs ' 'mismatched Btrfs UUID check'
  assert_log_not_contains 'snapper ' 'mismatched Btrfs UUID check'
}

test_check_rejects_wrong_archinstall_subvolume_layout() {
  reset_fixture
  TEST_ROOT_FSROOT="/"

  run_as_root --check

  assert_status 1 "$LAST_STATUS" 'wrong root subvolume check'
  assert_contains "$LAST_OUTPUT" '/@' 'wrong root subvolume message'
  assert_log_not_contains 'btrfs ' 'wrong layout check'
  assert_log_not_contains 'snapper ' 'wrong layout check'
}

test_apply_creates_missing_configs_and_snapshot_subvolumes() {
  reset_fixture

  run_as_root --apply

  assert_status 0 "$LAST_STATUS" 'fresh apply'
  assert_contains "$LAST_OUTPUT" 'Snapper layout initialized' 'fresh apply output'
  assert_log_contains 'mktemp ' 'atomic config creation'
  assert_log_not_contains 'snapper --no-dbus --config root create --description initial recovery snapshot' 'apply defers root initial snapshot creation'
  assert_log_not_contains 'snapper --no-dbus --config home create --description initial recovery snapshot' 'apply defers home initial snapshot creation'
  assert_log_contains 'btrfs subvolume create' 'snapshot subvolume creation'

  run_as_root --create-initial-snapshots
  assert_status 0 "$LAST_STATUS" 'initial snapshot phase'
  assert_log_contains 'snapper --no-dbus --config root create --description initial recovery snapshot --cleanup-algorithm number --print-number' 'root initial snapshot creation'
  assert_log_contains 'snapper --no-dbus --config home create --description initial recovery snapshot --cleanup-algorithm number --print-number' 'home initial snapshot creation'

  run_as_root --check
  assert_status 0 "$LAST_STATUS" 'fresh apply convergence'

  : >"$COMMAND_LOG"
  run_as_root --apply
  assert_status 0 "$LAST_STATUS" 'fresh apply rerun'
  assert_log_not_contains 'snapper --no-dbus --config root create' 'fresh apply rerun'
  assert_log_not_contains 'snapper --no-dbus --config home create' 'fresh apply rerun'
  assert_log_not_contains 'subvolume create' 'fresh apply rerun'
}

test_apply_creates_missing_snapshot_subvolumes_for_existing_configs() {
  reset_fixture
  write_config root /
  write_config home /home
  write_registration

  run_as_root --apply

  assert_status 0 "$LAST_STATUS" 'partial apply'
  assert_log_contains "btrfs subvolume create $ROOT_MOUNT/.snapshots" 'root snapshot subvolume creation'
  assert_log_contains "btrfs subvolume create $HOME_MOUNT/.snapshots" 'home snapshot subvolume creation'

  run_as_root --create-initial-snapshots
  assert_status 0 "$LAST_STATUS" 'partial initial snapshot phase'
  assert_log_contains 'snapper --no-dbus --config root create --description initial recovery snapshot --cleanup-algorithm number --print-number' 'existing config root snapshot'
  assert_log_contains 'snapper --no-dbus --config home create --description initial recovery snapshot --cleanup-algorithm number --print-number' 'existing config home snapshot'
}

test_apply_repairs_partial_registration_without_replacing_it() {
  reset_fixture
  write_config root /
  write_config home /home
  printf '# keep this setting\nSNAPPER_CONFIGS="root"\n' >"$REGISTRATION_FILE"
  mark_subvolumes

  run_as_root --apply

  assert_status 0 "$LAST_STATUS" 'partial registration repair'
  assert_contains "$(<"$REGISTRATION_FILE")" '# keep this setting' 'partial registration preservation'
  assert_contains "$(<"$REGISTRATION_FILE")" 'SNAPPER_CONFIGS="root home"' 'partial registration completion'
  assert_log_not_contains 'subvolume create' 'partial registration repair'

  run_as_root --create-initial-snapshots
  assert_status 0 "$LAST_STATUS" 'partial registration initial snapshot phase'
  assert_log_contains 'snapper --no-dbus --config root create --description initial recovery snapshot --cleanup-algorithm number --print-number' 'partial registration root snapshot'
  assert_log_contains 'snapper --no-dbus --config home create --description initial recovery snapshot --cleanup-algorithm number --print-number' 'partial registration home snapshot'
}

test_apply_adds_missing_registration_line_without_replacing_file() {
  reset_fixture
  write_config root /
  write_config home /home
  printf '# keep this setting\n' >"$REGISTRATION_FILE"
  mark_subvolumes

  run_as_root --apply

  assert_status 0 "$LAST_STATUS" 'missing registration line repair'
  assert_contains "$(<"$REGISTRATION_FILE")" '# keep this setting' 'missing registration line preservation'
  assert_contains "$(<"$REGISTRATION_FILE")" 'SNAPPER_CONFIGS="root home"' 'missing registration line completion'
  assert_log_contains 'mv -f' 'missing registration atomic replacement'

  run_as_root --create-initial-snapshots
  assert_status 0 "$LAST_STATUS" 'missing registration initial snapshot phase'
}

test_apply_creates_config_from_template_when_snapshot_subvolume_exists() {
  reset_fixture
  TEST_SNAPPER_FAIL_IF_SNAPSHOT_EXISTS=true
  mark_subvolumes

  run_as_root --apply

  assert_status 0 "$LAST_STATUS" 'existing snapshot subvolume config creation'
  assert_contains "$(<"$CONFIG_DIR/root")" 'SUBVOLUME="/"' 'root template config'
  assert_contains "$(<"$CONFIG_DIR/home")" 'SUBVOLUME="/home"' 'home template config'
  assert_log_not_contains 'snapper --no-dbus --config root create-config' 'template root config creation'
  assert_log_not_contains 'subvolume create' 'template config creation'

  run_as_root --create-initial-snapshots
  assert_status 0 "$LAST_STATUS" 'template initial snapshot phase'
}

test_apply_rejects_managed_config_symlink() {
  local managed_config_dir="$TEST_ROOT/managed-configs"

  reset_fixture
  rm -rf -- "$CONFIG_DIR"
  mkdir -p -- "$managed_config_dir"
  ln -s -- "$managed_config_dir" "$CONFIG_DIR"
  TEST_SNAPPER_FAIL_IF_SNAPSHOT_EXISTS=true
  mark_subvolumes

  run_as_root --apply

  assert_status 1 "$LAST_STATUS" 'managed config symlink'
  assert_contains "$LAST_OUTPUT" 'must not be a symlink' 'managed config symlink message'
  assert_log_not_contains 'snapper --no-dbus --config root create' 'managed config symlink safety'
  assert_log_not_contains 'subvolume create' 'managed config symlink'
}

test_apply_rejects_malformed_registration_before_mutation() {
  reset_fixture
  printf 'SNAPPER_CONFIGS=""\n' >"$REGISTRATION_FILE"

  run_as_root --apply

  assert_status 1 "$LAST_STATUS" 'malformed registration'
  assert_contains "$LAST_OUTPUT" 'malformed SNAPPER_CONFIGS' 'malformed registration message'
  assert_log_not_contains 'snapper ' 'malformed registration safety'
  assert_log_not_contains 'subvolume create' 'malformed registration safety'
}

test_apply_is_idempotent_after_convergence() {
  reset_fixture
  write_config root /
  write_config home /home
  write_registration
  mark_subvolumes

  run_as_root --apply

  assert_status 0 "$LAST_STATUS" 'idempotent apply'

  run_as_root --create-initial-snapshots
  assert_status 0 "$LAST_STATUS" 'idempotent initial snapshot phase'
  assert_log_contains 'snapper --no-dbus --config root create --description initial recovery snapshot --cleanup-algorithm number --print-number' 'idempotent initial root snapshot'
  assert_log_contains 'snapper --no-dbus --config home create --description initial recovery snapshot --cleanup-algorithm number --print-number' 'idempotent initial home snapshot'
  : >"$COMMAND_LOG"
  run_as_root --apply
  assert_status 0 "$LAST_STATUS" 'idempotent apply rerun'
  assert_log_not_contains 'subvolume create' 'idempotent apply rerun'
  assert_log_not_contains 'snapper --no-dbus --config root create' 'idempotent root snapshot rerun'
  assert_log_not_contains 'snapper --no-dbus --config home create' 'idempotent home snapshot rerun'
}

test_apply_rejects_existing_non_subvolume_snapshot_directory() {
  reset_fixture
  write_config root /
  write_config home /home
  write_registration
  mkdir -p -- "$ROOT_MOUNT/.snapshots" "$HOME_MOUNT/.snapshots"

  run_as_root --apply

  assert_status 1 "$LAST_STATUS" 'regular snapshot directory'
  assert_contains "$LAST_OUTPUT" 'not a Btrfs subvolume' 'regular snapshot directory message'
  assert_log_not_contains 'subvolume create' 'regular snapshot directory safety'
  assert_log_not_contains 'snapper ' 'regular snapshot directory safety'
}

test_check_rejects_snapshot_sibling_mount() {
  reset_fixture
  write_config root /
  write_config home /home
  write_registration
  mark_subvolumes
  TEST_ROOT_SNAPSHOT_FSROOT="/@.snapshots"

  run_as_root --check

  assert_status 1 "$LAST_STATUS" 'snapshot sibling mount'
  assert_contains "$LAST_OUTPUT" 'snapshot mount' 'snapshot sibling mount message'
  assert_log_not_contains 'snapper ' 'snapshot sibling mount safety'
}

test_check_rejects_home_snapshot_sibling_mount() {
  reset_fixture
  write_config root /
  write_config home /home
  write_registration
  mark_subvolumes
  TEST_HOME_SNAPSHOT_FSROOT="/@home.snapshots"

  run_as_root --check

  assert_status 1 "$LAST_STATUS" 'home snapshot sibling mount'
  assert_contains "$LAST_OUTPUT" 'snapshot mount' 'home snapshot sibling mount message'
  assert_log_not_contains 'snapper ' 'home snapshot sibling mount safety'
}

test_check_rejects_snapshot_with_wrong_parent_subvolume() {
  reset_fixture
  write_config root /
  write_config home /home
  write_registration
  mark_subvolumes
  TEST_ROOT_SNAPSHOT_PARENT_ID="5"

  run_as_root --check

  assert_status 1 "$LAST_STATUS" 'snapshot parent relationship'
  assert_contains "$LAST_OUTPUT" 'parent' 'snapshot parent relationship message'
  assert_log_not_contains 'snapper ' 'snapshot parent relationship safety'
}

test_check_rejects_snapshot_without_root_ownership() {
  reset_fixture
  write_config root /
  write_config home /home
  write_registration
  mark_subvolumes
  TEST_ROOT_SNAPSHOT_UID="1000"

  run_as_root --check

  assert_status 1 "$LAST_STATUS" 'snapshot owner'
  assert_contains "$LAST_OUTPUT" 'root:root' 'snapshot owner message'
  assert_log_not_contains 'snapper ' 'snapshot owner safety'
}

test_check_rejects_snapshot_without_0750_mode() {
  reset_fixture
  write_config root /
  write_config home /home
  write_registration
  mark_subvolumes
  TEST_ROOT_SNAPSHOT_MODE="755"

  run_as_root --check

  assert_status 1 "$LAST_STATUS" 'snapshot mode'
  assert_contains "$LAST_OUTPUT" '0750' 'snapshot mode message'
  assert_log_not_contains 'snapper ' 'snapshot mode safety'
}

test_apply_creates_initial_recovery_snapshots() {
  reset_fixture

  run_as_root --apply
  assert_status 0 "$LAST_STATUS" 'initial snapshot layout preparation'

  : >"$COMMAND_LOG"
  run_as_root --create-initial-snapshots

  assert_status 0 "$LAST_STATUS" 'initial recovery snapshots'
  assert_log_contains 'snapper --no-dbus --config root create --description initial recovery snapshot --cleanup-algorithm number --print-number' 'root initial snapshot'
  assert_log_contains 'snapper --no-dbus --config home create --description initial recovery snapshot --cleanup-algorithm number --print-number' 'home initial snapshot'
}

test_initial_snapshot_phase_rejects_recovery_state() {
  reset_fixture
  mkdir -p -- "$RECOVERY_DIRECTORY/backups"

  run_as_root --create-initial-snapshots

  assert_status 1 "$LAST_STATUS" 'initial snapshots with recovery state'
  assert_contains "$LAST_OUTPUT" 'recovery state exists' 'initial snapshots recovery state message'
  assert_log_not_contains 'snapper --no-dbus --config root create' 'initial snapshots recovery state safety'
  assert_log_not_contains 'snapper --no-dbus --config home create' 'initial snapshots recovery state safety'
}

test_apply_rejects_unvalidated_initial_snapshot() {
  reset_fixture
  TEST_INITIAL_SNAPSHOT_VALID=false

  run_as_root --apply
  assert_status 0 "$LAST_STATUS" 'invalid initial snapshot layout preparation'
  run_as_root --create-initial-snapshots

  assert_status 1 "$LAST_STATUS" 'invalid initial recovery snapshot'
  assert_contains "$LAST_OUTPUT" 'Btrfs subvolume' 'invalid initial snapshot message'
  assert_log_contains 'snapper --no-dbus --config root create --description initial recovery snapshot' 'invalid initial snapshot creation'
}

test_apply_uses_atomic_config_and_registration_replacements() {
  reset_fixture
  mark_subvolumes
  TEST_SNAPPER_FAIL_IF_SNAPSHOT_EXISTS=true

  run_as_root --apply

  assert_status 0 "$LAST_STATUS" 'atomic config and registration writes'
  assert_log_contains 'chmod 644 ' 'atomic file mode'
  assert_log_contains 'chown root:root' 'atomic file owner'
  assert_log_contains 'mv -f' 'atomic file replacement'
}

test_apply_propagates_snapper_failure() {
  reset_fixture
  TEST_SNAPPER_FAIL=true

  run_as_root --apply
  assert_status 0 "$LAST_STATUS" 'Snapper failure layout preparation'
  run_as_root --create-initial-snapshots

  assert_status 1 "$LAST_STATUS" 'snapper failure'
  assert_contains "$LAST_OUTPUT" 'list Snapper snapshots' 'snapper failure message'
  assert_log_contains 'snapper --no-dbus --config root --csvout' 'snapper failure command'
}

test_script_is_executable
[[ -n "$UNSHARE" ]] || fail 'unshare is required for the root execution tests'
create_stubs

test_help_and_unknown_option
test_non_root_is_rejected_before_commands
test_initializer_overrides_require_test_mode
test_check_is_read_only_when_layout_is_ready
test_check_rejects_non_btrfs_without_mutation
test_check_rejects_mismatched_btrfs_uuid_without_mutation
test_check_rejects_wrong_archinstall_subvolume_layout
test_apply_creates_missing_configs_and_snapshot_subvolumes
test_apply_creates_missing_snapshot_subvolumes_for_existing_configs
test_apply_repairs_partial_registration_without_replacing_it
test_apply_adds_missing_registration_line_without_replacing_file
test_apply_creates_config_from_template_when_snapshot_subvolume_exists
test_apply_rejects_managed_config_symlink
test_apply_rejects_malformed_registration_before_mutation
test_apply_is_idempotent_after_convergence
test_apply_rejects_existing_non_subvolume_snapshot_directory
test_check_rejects_snapshot_sibling_mount
test_check_rejects_home_snapshot_sibling_mount
test_check_rejects_snapshot_with_wrong_parent_subvolume
test_check_rejects_snapshot_without_root_ownership
test_check_rejects_snapshot_without_0750_mode
test_apply_creates_initial_recovery_snapshots
test_initial_snapshot_phase_rejects_recovery_state
test_apply_rejects_unvalidated_initial_snapshot
test_apply_uses_atomic_config_and_registration_replacements
test_apply_propagates_snapper_failure

printf 'PASS: Snapper initializer safety and idempotency\n'
