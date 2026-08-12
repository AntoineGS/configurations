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
ORIGINAL_PATH="$PATH"
UNSHARE="$(command -v unshare || true)"
BASH_PATH="$BASH"

LAST_OUTPUT=""
LAST_STATUS=0
TEST_FSTYPE="btrfs"
TEST_ROOT_FSROOT="/@"
TEST_HOME_FSROOT="/@home"
TEST_UUID="test-btrfs-uuid"
TEST_SNAPPER_FAIL=false
TEST_SNAPPER_FAIL_IF_SNAPSHOT_EXISTS=false

trap 'rm -rf -- "$TEST_ROOT"' EXIT

fail() {
  printf 'FAIL: %s\n' "$*" >&2
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
    'case "$property:$target" in' \
    '  FSTYPE:*) printf "%s\\n" "$SNAPPER_TEST_FSTYPE" ;;' \
    '  FSROOT:'"$ROOT_MOUNT"') printf "%s\\n" "$SNAPPER_TEST_ROOT_FSROOT" ;;' \
    '  FSROOT:'"$HOME_MOUNT"') printf "%s\\n" "$SNAPPER_TEST_HOME_FSROOT" ;;' \
    '  UUID:*) printf "%s\\n" "$SNAPPER_TEST_UUID" ;;' \
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
    '    while IFS= read -r subvolume; do [[ "$subvolume" == "$path" ]] && exit 0; done < "$SNAPPER_TEST_SUBVOLUMES"' \
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
  write_executable "$BIN/snapper" \
    'printf "snapper" >> "$SNAPPER_TEST_COMMAND_LOG"' \
    'for argument in "$@"; do printf " %s" "$argument" >> "$SNAPPER_TEST_COMMAND_LOG"; done' \
    'printf "\\n" >> "$SNAPPER_TEST_COMMAND_LOG"' \
    '[[ "$SNAPPER_TEST_FAIL" == false ]] || exit 1' \
    'config=""' \
    'command_name=""' \
    'subvolume=""' \
    'while [[ $# -gt 0 ]]; do' \
    '  case "$1" in' \
    '    --config|-c) config="$2"; shift 2 ;;' \
    '    create-config) command_name="$1"; shift ;;' \
    '    --fstype) shift 2 ;;' \
    '    *) subvolume="$1"; shift ;;' \
    '  esac' \
    'done' \
    '[[ "$command_name" == create-config && -n "$config" && -n "$subvolume" ]] || exit 2' \
    'if [[ "$SNAPPER_TEST_FAIL_IF_SNAPSHOT_EXISTS" == true && -e "$subvolume/.snapshots" ]]; then exit 1; fi' \
    '/usr/bin/mkdir -p -- "$SNAPPER_TEST_CONFIG_DIR" "$subvolume/.snapshots"' \
    'printf "SUBVOLUME=\\\"%s\\\"\\nFSTYPE=\\\"btrfs\\\"\\n" "$([[ "$config" == root ]] && printf / || printf /home)" > "$SNAPPER_TEST_CONFIG_DIR/$config"' \
    'printf "%s\\n" "$subvolume/.snapshots" >> "$SNAPPER_TEST_SUBVOLUMES"' \
    'printf "SNAPPER_CONFIGS=\\\"root home\\\"\\n" > "$SNAPPER_TEST_REGISTRATION"'
}

reset_fixture() {
  rm -rf -- "$FIXTURE_ROOT"
  mkdir -p -- "$ROOT_MOUNT" "$HOME_MOUNT" "$CONFIG_DIR" "$CONF_DIR"
  : >"$COMMAND_LOG"
  : >"$SUBVOLUME_STATE"
  printf 'SUBVOLUME="/"\nFSTYPE="btrfs"\nNUMBER_CLEANUP="yes"\n' >"$CONFIG_TEMPLATE"
  TEST_FSTYPE="btrfs"
  TEST_ROOT_FSROOT="/@"
  TEST_HOME_FSROOT="/@home"
  TEST_UUID="test-btrfs-uuid"
  TEST_SNAPPER_FAIL=false
  TEST_SNAPPER_FAIL_IF_SNAPSHOT_EXISTS=false
}

write_config() {
  local -r name="$1"
  local -r subvolume="$2"

  printf 'SUBVOLUME="%s"\nFSTYPE="btrfs"\n' "$subvolume" >"$CONFIG_DIR/$name"
}

mark_subvolumes() {
  printf '%s\n' "$ROOT_MOUNT/.snapshots" "$HOME_MOUNT/.snapshots" >"$SUBVOLUME_STATE"
  mkdir -p -- "$ROOT_MOUNT/.snapshots" "$HOME_MOUNT/.snapshots"
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
    SNAPPER_TEST_FAIL="$TEST_SNAPPER_FAIL" \
    SNAPPER_TEST_FAIL_IF_SNAPSHOT_EXISTS="$TEST_SNAPPER_FAIL_IF_SNAPSHOT_EXISTS" \
    SNAPPER_INITIALIZER_ROOT_MOUNT="$ROOT_MOUNT" \
    SNAPPER_INITIALIZER_HOME_MOUNT="$HOME_MOUNT" \
    SNAPPER_INITIALIZER_CONFIG_DIR="$CONFIG_DIR" \
    SNAPPER_INITIALIZER_REGISTRATION_FILE="$REGISTRATION_FILE" \
    SNAPPER_INITIALIZER_TEMPLATE="$CONFIG_TEMPLATE" \
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
    "$BASH_PATH" "$SCRIPT" "$@" 2>&1); then
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
  assert_contains "$LAST_OUTPUT" '--check|--apply' '--help modes'

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

test_check_is_read_only_when_layout_is_ready() {
  reset_fixture
  write_config root /
  write_config home /home
  write_registration
  mark_subvolumes

  run_as_root --check

  assert_status 0 "$LAST_STATUS" 'ready check'
  assert_contains "$LAST_OUTPUT" 'Snapper layout is ready' 'ready check output'
  assert_log_not_contains 'subvolume create' 'read-only check'
  assert_log_not_contains 'snapper ' 'read-only check'
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
  assert_log_contains 'snapper --no-dbus --config root create-config --fstype btrfs ' 'root config creation'
  assert_log_contains 'snapper --no-dbus --config home create-config --fstype btrfs ' 'home config creation'
  assert_log_not_contains 'btrfs subvolume create' 'snapper creates missing subvolumes'

  run_as_root --check
  assert_status 0 "$LAST_STATUS" 'fresh apply convergence'

  : >"$COMMAND_LOG"
  run_as_root --apply
  assert_status 0 "$LAST_STATUS" 'fresh apply rerun'
  assert_log_not_contains 'snapper ' 'fresh apply rerun'
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
  assert_log_not_contains 'snapper ' 'existing config apply'
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
  assert_log_not_contains 'snapper ' 'partial registration repair'
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
}

test_apply_creates_config_from_template_when_snapshot_subvolume_exists() {
  reset_fixture
  TEST_SNAPPER_FAIL_IF_SNAPSHOT_EXISTS=true
  mark_subvolumes

  run_as_root --apply

  assert_status 0 "$LAST_STATUS" 'existing snapshot subvolume config creation'
  assert_contains "$(<"$CONFIG_DIR/root")" 'SUBVOLUME="/"' 'root template config'
  assert_contains "$(<"$CONFIG_DIR/home")" 'SUBVOLUME="/home"' 'home template config'
  assert_log_not_contains 'snapper ' 'template config creation'
  assert_log_not_contains 'subvolume create' 'template config creation'
}

test_apply_creates_missing_config_through_managed_config_symlink() {
  local managed_config_dir="$TEST_ROOT/managed-configs"

  reset_fixture
  rm -rf -- "$CONFIG_DIR"
  mkdir -p -- "$managed_config_dir"
  ln -s -- "$managed_config_dir" "$CONFIG_DIR"
  TEST_SNAPPER_FAIL_IF_SNAPSHOT_EXISTS=true
  mark_subvolumes

  run_as_root --apply

  assert_status 0 "$LAST_STATUS" 'managed config symlink'
  [[ -f "$managed_config_dir/root" && -f "$managed_config_dir/home" ]] ||
    fail 'managed config symlink did not receive both configs'
  assert_log_not_contains 'snapper ' 'managed config symlink'
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
  assert_log_not_contains 'subvolume create' 'idempotent apply'
  assert_log_not_contains 'snapper ' 'idempotent apply'
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

test_apply_propagates_snapper_failure() {
  reset_fixture
  TEST_SNAPPER_FAIL=true

  run_as_root --apply

  assert_status 1 "$LAST_STATUS" 'snapper failure'
  assert_contains "$LAST_OUTPUT" 'create-config' 'snapper failure message'
  assert_log_contains 'snapper --no-dbus --config root create-config' 'snapper failure command'
}

test_script_is_executable
[[ -n "$UNSHARE" ]] || fail 'unshare is required for the root execution tests'
create_stubs

test_help_and_unknown_option
test_non_root_is_rejected_before_commands
test_check_is_read_only_when_layout_is_ready
test_check_rejects_non_btrfs_without_mutation
test_check_rejects_wrong_archinstall_subvolume_layout
test_apply_creates_missing_configs_and_snapshot_subvolumes
test_apply_creates_missing_snapshot_subvolumes_for_existing_configs
test_apply_repairs_partial_registration_without_replacing_it
test_apply_adds_missing_registration_line_without_replacing_file
test_apply_creates_config_from_template_when_snapshot_subvolume_exists
test_apply_creates_missing_config_through_managed_config_symlink
test_apply_rejects_malformed_registration_before_mutation
test_apply_is_idempotent_after_convergence
test_apply_rejects_existing_non_subvolume_snapshot_directory
test_apply_propagates_snapper_failure

printf 'PASS: Snapper initializer safety and idempotency\n'
