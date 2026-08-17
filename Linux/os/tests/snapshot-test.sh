#!/bin/bash

set -euo pipefail

repo_root=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../../.." && pwd)
wrapper_source="$repo_root/Linux/os/helpers/snapshot"
config_template="$repo_root/Linux/os/helpers/snapshot-config.tmpl"
tracked_config_link="$repo_root/Linux/os/helpers/snapshot-config"
update_helper="$repo_root/Linux/os/helpers/update"
test_root=$(mktemp -d)
bin="$test_root/bin"
sudo_log="$test_root/sudo.log"
update_log="$test_root/update.log"
home_dir="$test_root/home"
no_flock_path="$test_root/no-flock-path"
no_date_path="$test_root/no-date-path"
no_snapper_path="$test_root/no-snapper-path"
no_dirname_path="$test_root/no-dirname-path"
laptop_dir="$test_root/laptop"
desktop_dir="$test_root/desktop"
empty_config_dir="$test_root/empty-config"
invalid_config_dir="$test_root/invalid-config"
missing_config_dir="$test_root/missing-config"
laptop_helper="$laptop_dir/snapshot"
desktop_helper="$desktop_dir/snapshot"

trap 'rm -rf "$test_root"' EXIT

fail() {
  printf 'FAIL: %s\n' "$1" >&2
  exit 1
}

assert_file_equals() {
  local expected=$1
  local file=$2
  local actual
  actual=$(<"$file")
  [[ $actual == "$expected" ]] || fail "expected calls:\n$expected\nactual calls:\n$actual"
}

render_config() {
  local hostname=$1
  local output=$2
  local include=true
  local line

  while IFS= read -r line || [[ -n $line ]]; do
    case "$line" in
      '{{ if eq .Hostname "omarchbook" }}')
        [[ $hostname == omarchbook ]] && include=true || include=false
        ;;
      '{{ else }}')
        [[ $include == true ]] && include=false || include=true
        ;;
      '{{ end }}')
        include=true
        ;;
      *)
        [[ $include == true ]] && printf '%s\n' "$line"
        ;;
    esac
  done <"$config_template" >"$output"

  # Match tidydots' rendered-file mode; the wrapper sources this file.
  chmod 600 "$output"
}

prepare_helper() {
  local hostname=$1
  local helper_dir=$2
  local helper="$helper_dir/snapshot"
  local rendered_config="$helper_dir/snapshot-config.tmpl.rendered"

  mkdir -p -- "$helper_dir"
  cp -- "$wrapper_source" "$helper"
  render_config "$hostname" "$rendered_config"
  ln -s -- snapshot-config.tmpl.rendered "$helper_dir/snapshot-config"

  [[ -x $helper ]] || fail "rendered test wrapper is not executable: $helper"
  [[ -L $helper_dir/snapshot-config ]] || fail "missing stripped config symlink: $helper_dir/snapshot-config"
  [[ ! -x $rendered_config ]] || fail "rendered config unexpectedly executable: $rendered_config"
  [[ -r $rendered_config ]] || fail "rendered config is not readable: $rendered_config"
}

prepare_custom_config_helper() {
  local content=$1
  local helper_dir=$2
  local helper="$helper_dir/snapshot"
  local rendered_config="$helper_dir/snapshot-config.tmpl.rendered"

  mkdir -p -- "$helper_dir"
  cp -- "$wrapper_source" "$helper"
  if [[ $content == __EMPTY__ ]]; then
    : >"$rendered_config"
  else
    printf '%s\n' "$content" >"$rendered_config"
  fi
  chmod 600 "$rendered_config"
  ln -s -- snapshot-config.tmpl.rendered "$helper_dir/snapshot-config"
}

run_helper() {
  local helper=$1
  shift
  local helper_path="${RUN_HELPER_PATH:-$bin:$PATH}"
  local -a helper_command=("$helper" "$@")

  if [[ -n ${RUN_HELPER_TIMEOUT:-} ]]; then
    helper_command=(timeout "$RUN_HELPER_TIMEOUT" "${helper_command[@]}")
  fi

  SUDO_LOG="$sudo_log" \
    SNAPPER_CONFIGS_OUTPUT="${SNAPPER_CONFIGS_OUTPUT:-}" \
    SNAPPER_LIST_OUTPUT="${SNAPPER_LIST_OUTPUT:-}" \
    SNAPPER_LIST_STATUS="${SNAPPER_LIST_STATUS:-0}" \
    SNAPPER_CREATE_STATUS="${SNAPPER_CREATE_STATUS:-0}" \
    SNAPPER_DELETE_FAILURE_ID="${SNAPPER_DELETE_FAILURE_ID:-}" \
    SNAPPER_DELETE_STATUS="${SNAPPER_DELETE_STATUS:-1}" \
    SNAPPER_CONCURRENCY_STATE="${SNAPPER_CONCURRENCY_STATE:-}" \
    HOME="$home_dir" \
    PATH="$helper_path" \
    "${helper_command[@]}"
}

run_update() {
  local helper_path=$1
  local error_file=$2
  local output_file=$3

  printf '\n' |
    SNAPSHOT_HELPER="$laptop_helper" \
      SUDO_LOG="$sudo_log" \
      SNAPPER_CONFIGS_OUTPUT="" \
      SNAPPER_LIST_OUTPUT="" \
      SNAPPER_LIST_STATUS=0 \
      SNAPPER_CREATE_STATUS=0 \
      SNAPPER_DELETE_FAILURE_ID="" \
      SNAPPER_DELETE_STATUS=1 \
      SNAPPER_CONCURRENCY_STATE="" \
      HOME="$home_dir" \
      PATH="$helper_path" \
      UPDATE_TEST_LOG="$update_log" \
      "$update_helper" -y >"$output_file" 2>"$error_file"
}

[[ -x $wrapper_source ]] || fail "missing executable wrapper: $wrapper_source"
[[ -f $config_template ]] || fail "missing config template: $config_template"
[[ -L $tracked_config_link ]] || fail "missing tracked config symlink: $tracked_config_link"
[[ $(readlink -- "$tracked_config_link") == snapshot-config.tmpl.rendered ]] ||
  fail "config symlink does not target snapshot-config.tmpl.rendered"

mkdir -p -- "$bin" "$home_dir" "$no_flock_path" "$no_date_path" "$no_snapper_path" "$no_dirname_path"

cat >"$bin/snapper" <<'EOF'
#!/bin/bash
exit 99
EOF

cat >"$bin/date" <<'EOF'
#!/bin/bash
printf '2026-08-16T12:34:56-04:00\n'
EOF

cat >"$bin/sudo" <<'EOF'
#!/bin/bash
set -euo pipefail

state_lock() {
  local lock="$SNAPPER_CONCURRENCY_STATE/state.lock"

  while ! mkdir -- "$lock" 2>/dev/null; do
    sleep 0.01
  done
}

state_unlock() {
  rmdir -- "$SNAPPER_CONCURRENCY_STATE/state.lock"
}

read_concurrent_inventory() {
  local snapshot
  local state_file="$SNAPPER_CONCURRENCY_STATE/snapshots"

  [[ -f $state_file ]] || return 0
  while IFS= read -r snapshot; do
    [[ -n $snapshot ]] && printf '%s,number,\n' "$snapshot"
  done <"$state_file"
}

printf '%s\n' "$*" >>"$SUDO_LOG"

case " $* " in
  *' list-configs '*)
    printf '%s' "$SNAPPER_CONFIGS_OUTPUT"
    ;;
  *' list --type single '*)
    if [[ -n $SNAPPER_CONCURRENCY_STATE ]]; then
      if mkdir -- "$SNAPPER_CONCURRENCY_STATE/list-active" 2>/dev/null; then
        : >"$SNAPPER_CONCURRENCY_STATE/list-started"
        state_lock
        inventory=$(read_concurrent_inventory)
        state_unlock
        sleep 0.2
        rmdir -- "$SNAPPER_CONCURRENCY_STATE/list-active"
      else
        : >"$SNAPPER_CONCURRENCY_STATE/list-overlap"
        state_lock
        inventory=$(read_concurrent_inventory)
        state_unlock
      fi
      printf '%s' "$inventory"
    else
      printf '%s' "$SNAPPER_LIST_OUTPUT"
    fi
    exit "$SNAPPER_LIST_STATUS"
    ;;
  *' create '*)
    if [[ -n $SNAPPER_CONCURRENCY_STATE ]]; then
      state_lock
      printf '%s\n' "$$" >>"$SNAPPER_CONCURRENCY_STATE/snapshots"
      state_unlock
    fi
    exit "$SNAPPER_CREATE_STATUS"
    ;;
  *' delete '*)
    snapshot="${!#}"
    if [[ -n $SNAPPER_DELETE_FAILURE_ID && $snapshot == "$SNAPPER_DELETE_FAILURE_ID" ]]; then
      exit "$SNAPPER_DELETE_STATUS"
    fi
    if [[ -n $SNAPPER_CONCURRENCY_STATE ]]; then
      state_file="$SNAPPER_CONCURRENCY_STATE/snapshots"
      state_tmp="$state_file.tmp.$$"
      state_lock
      awk -v snapshot="$snapshot" '$0 != snapshot' "$state_file" >"$state_tmp"
      mv -- "$state_tmp" "$state_file"
      state_unlock
    fi
    ;;
esac
EOF

cat >"$bin/snapshot" <<'EOF'
#!/bin/bash
printf 'snapshot %s\n' "$*" >>"$UPDATE_TEST_LOG"
exec "$SNAPSHOT_HELPER" "$@"
EOF

cat >"$bin/update-time" <<'EOF'
#!/bin/bash
printf 'update-time %s\n' "$*" >>"$UPDATE_TEST_LOG"
EOF

cat >"$bin/update-perform" <<'EOF'
#!/bin/bash
printf 'update-perform %s\n' "$*" >>"$UPDATE_TEST_LOG"
EOF

chmod +x "$bin/snapper" "$bin/date" "$bin/sudo" "$bin/snapshot" \
  "$bin/update-time" "$bin/update-perform"

for command in snapper sudo snapshot update-time update-perform; do
  ln -s -- "$bin/$command" "$no_flock_path/$command"
  ln -s -- "$bin/$command" "$no_date_path/$command"
  ln -s -- "$bin/$command" "$no_dirname_path/$command"
done
ln -s -- "$bin/date" "$no_flock_path/date"
ln -s -- "$bin/date" "$no_dirname_path/date"
ln -s -- "$bin/snapshot" "$no_snapper_path/snapshot"
ln -s -- "$bin/update-time" "$no_snapper_path/update-time"
ln -s -- "$bin/update-perform" "$no_snapper_path/update-perform"
for command in awk flock mkdir; do
  ln -s -- "$(command -v "$command")" "$no_date_path/$command"
  ln -s -- "$(command -v "$command")" "$no_dirname_path/$command"
done
ln -s -- "$(command -v mkdir)" "$no_flock_path/mkdir"
for path in "$no_flock_path" "$no_date_path" "$no_snapper_path"; do
  for command in dirname pwd; do
    ln -s -- "$(command -v "$command")" "$path/$command"
  done
done

prepare_helper omarchbook "$laptop_dir"
prepare_helper DESKTOP-E07VTRN "$desktop_dir"
bash -n "$laptop_helper" "$desktop_helper"

: >"$sudo_log"
SNAPPER_LIST_OUTPUT=$'7,number,\n8,number,important=yes\n9,timeline,\n10,number,\n' run_helper "$laptop_helper" create
assert_file_equals $'snapper -c root --csvout --no-headers list --type single --columns number,cleanup,userdata\nsnapper -c root create -c number -d pre-update 2026-08-16T12:34:56-04:00\nsnapper -c root delete 7\nsnapper -c root delete 10' "$sudo_log"

: >"$sudo_log"
SNAPPER_LIST_OUTPUT=$'8,number,important=yes\n' run_helper "$laptop_helper" create
assert_file_equals $'snapper -c root --csvout --no-headers list --type single --columns number,cleanup,userdata\nsnapper -c root create -c number -d pre-update 2026-08-16T12:34:56-04:00' "$sudo_log"

: >"$sudo_log"
if SNAPPER_LIST_OUTPUT=$'7,number,\n' SNAPPER_LIST_STATUS=42 run_helper "$laptop_helper" create; then
  fail 'failed snapshot inventory unexpectedly succeeded'
else
  status=$?
fi
[[ $status -ne 0 ]] || fail 'failed snapshot inventory returned success'
assert_file_equals 'snapper -c root --csvout --no-headers list --type single --columns number,cleanup,userdata' "$sudo_log"

: >"$sudo_log"
if SNAPPER_LIST_OUTPUT=$'7,number,\n' SNAPPER_LIST_STATUS=127 run_helper "$laptop_helper" create; then
  fail 'post-preflight inventory status 127 unexpectedly succeeded'
else
  status=$?
fi
[[ $status -eq 1 ]] || fail "post-preflight inventory returned $status instead of 1"
assert_file_equals 'snapper -c root --csvout --no-headers list --type single --columns number,cleanup,userdata' "$sudo_log"

: >"$sudo_log"
if SNAPPER_LIST_OUTPUT=$'7,number,\n' SNAPPER_CREATE_STATUS=42 run_helper "$laptop_helper" create; then
  fail 'failed snapshot creation unexpectedly succeeded'
else
  status=$?
fi
[[ $status -eq 42 ]] || fail "failed create returned $status instead of 42"
assert_file_equals $'snapper -c root --csvout --no-headers list --type single --columns number,cleanup,userdata\nsnapper -c root create -c number -d pre-update 2026-08-16T12:34:56-04:00' "$sudo_log"

: >"$sudo_log"
deletion_state="$test_root/deletion-state"
mkdir -- "$deletion_state"
printf '7\n10\n' >"$deletion_state/snapshots"
if SNAPPER_CONCURRENCY_STATE="$deletion_state" SNAPPER_DELETE_FAILURE_ID=7 SNAPPER_DELETE_STATUS=43 \
  run_helper "$laptop_helper" create; then
  fail 'failed snapshot deletion unexpectedly succeeded'
else
  status=$?
fi
[[ $status -eq 43 ]] || fail "failed delete returned $status instead of 43"
assert_file_equals $'snapper -c root --csvout --no-headers list --type single --columns number,cleanup,userdata\nsnapper -c root create -c number -d pre-update 2026-08-16T12:34:56-04:00\nsnapper -c root delete 7' "$sudo_log"
mapfile -t retained_snapshots <"$deletion_state/snapshots"
[[ ${#retained_snapshots[@]} -eq 3 ]] || fail "expected three retained snapshots, found ${#retained_snapshots[@]}"
[[ ${retained_snapshots[0]} == 7 && ${retained_snapshots[1]} == 10 ]] ||
  fail 'failed delete did not retain the prior ordinary snapshots'

: >"$sudo_log"
SNAPPER_CONFIGS_OUTPUT=$'Config,Subvolume\nroot,/\nhome,/home\n' run_helper "$desktop_helper" create
assert_file_equals $'snapper --csvout list-configs\nsnapper -c root create -c number -d pre-update 2026-08-16T12:34:56-04:00\nsnapper -c home create -c number -d pre-update 2026-08-16T12:34:56-04:00' "$sudo_log"

: >"$sudo_log"
mkdir -p -- "$missing_config_dir"
cp -- "$wrapper_source" "$missing_config_dir/snapshot"
if RUN_HELPER_PATH="$no_snapper_path" run_helper "$missing_config_dir/snapshot" create \
  2>"$test_root/missing-config-missing-snapper.err"; then
  fail 'missing config plus missing Snapper unexpectedly succeeded'
else
  status=$?
fi
[[ $status -eq 127 ]] || fail "missing config plus missing Snapper returned $status instead of 127"
assert_file_equals '' "$sudo_log"

: >"$sudo_log"
prepare_custom_config_helper __EMPTY__ "$empty_config_dir"
if RUN_HELPER_PATH="$bin:$PATH" run_helper "$empty_config_dir/snapshot" create \
  2>"$test_root/empty-config.err"; then
  fail 'empty rendered host selector unexpectedly succeeded'
else
  status=$?
fi
[[ $status -ne 0 ]] || fail 'empty rendered host selector returned success'
assert_file_equals '' "$sudo_log"

: >"$sudo_log"
prepare_custom_config_helper 'SNAPSHOT_HOST=invalid' "$invalid_config_dir"
if RUN_HELPER_PATH="$bin:$PATH" run_helper "$invalid_config_dir/snapshot" create \
  2>"$test_root/invalid-config.err"; then
  fail 'invalid rendered host selector unexpectedly succeeded'
else
  status=$?
fi
[[ $status -ne 0 ]] || fail 'invalid rendered host selector returned success'
assert_file_equals '' "$sudo_log"

: >"$sudo_log"
: >"$update_log"
if PATH="$no_snapper_path" command -v snapper &>/dev/null; then
  fail 'missing-Snapper test path unexpectedly contains snapper'
fi
if run_update "$no_snapper_path" "$test_root/missing-snapper-update.err" "$test_root/missing-snapper-update.out"; then
  status=0
else
  status=$?
fi
[[ $status -eq 0 ]] || fail "missing-Snapper update returned $status"
assert_file_equals $'snapshot create\nupdate-time \nupdate-perform ' "$update_log"
assert_file_equals '' "$sudo_log"

: >"$sudo_log"
: >"$update_log"
if PATH="$no_flock_path" command -v flock &>/dev/null; then
  fail 'missing-flock test path unexpectedly contains flock'
fi
if run_update "$no_flock_path" "$test_root/missing-flock-update.err" "$test_root/missing-flock-update.out"; then
  fail 'update silently accepted missing flock failure'
else
  status=$?
fi
[[ $status -ne 0 && $status -ne 127 ]] || fail "missing flock update returned reserved status $status"
[[ $(<"$test_root/missing-flock-update.err") == *'snapshot: flock is required for serialized snapshots'* ]] ||
  fail 'missing flock diagnostic was not reported through update'
assert_file_equals 'snapshot create' "$update_log"
assert_file_equals '' "$sudo_log"
[[ $(<"$test_root/missing-flock-update.out") == *'Something went wrong during the update!'* ]] ||
  fail 'update ERR diagnostic was not visible for missing flock'

: >"$sudo_log"
if RUN_HELPER_PATH="$no_flock_path" run_helper "$laptop_helper" create 2>"$test_root/missing-flock-direct.err"; then
  fail 'direct missing-flock helper unexpectedly succeeded'
else
  status=$?
fi
[[ $status -eq 1 ]] || fail "direct missing flock returned $status instead of 1"
assert_file_equals 'snapshot: flock is required for serialized snapshots' "$test_root/missing-flock-direct.err"
assert_file_equals '' "$sudo_log"

: >"$sudo_log"
: >"$update_log"
if run_update "$no_date_path" "$test_root/missing-date-update.err" "$test_root/missing-date-update.out"; then
  fail 'update silently accepted missing date failure'
else
  status=$?
fi
[[ $status -ne 0 ]] || fail 'missing date update returned success'
missing_date_error=$(<"$test_root/missing-date-update.err")
[[ $missing_date_error == *'date: command not found'* ]] ||
  fail "missing date failure was not reported: $missing_date_error"
assert_file_equals 'snapshot create' "$update_log"
assert_file_equals '' "$sudo_log"
[[ $(<"$test_root/missing-date-update.out") == *'Something went wrong during the update!'* ]] ||
  fail 'update ERR diagnostic was not visible for missing date'

: >"$sudo_log"
: >"$update_log"
if run_update "$no_dirname_path" "$test_root/missing-dirname-update.err" "$test_root/missing-dirname-update.out"; then
  fail 'update silently accepted missing dirname failure'
else
  status=$?
fi
[[ $status -ne 0 && $status -ne 127 ]] || fail "missing dirname update returned reserved status $status"
assert_file_equals 'snapshot create' "$update_log"
assert_file_equals '' "$sudo_log"
[[ $(<"$test_root/missing-dirname-update.err") == *'snapshot: failed to resolve helper directory'* ]] ||
  fail 'missing dirname diagnostic was not reported through update'
[[ $(<"$test_root/missing-dirname-update.out") == *'Something went wrong during the update!'* ]] ||
  fail 'update ERR diagnostic was not visible for missing dirname'

: >"$sudo_log"
concurrency_state="$test_root/concurrency"
mkdir -- "$concurrency_state"
# The supported helper scope is one configured user's HOME; both invocations share it.
SNAPPER_CONCURRENCY_STATE="$concurrency_state" RUN_HELPER_TIMEOUT=5 \
  run_helper "$laptop_helper" create >"$test_root/concurrency-first.log" 2>&1 &
first_pid=$!

for ((attempt = 0; attempt < 100; attempt++)); do
  [[ -f $concurrency_state/list-started ]] && break
  sleep 0.01
done
[[ -f $concurrency_state/list-started ]] || fail 'first concurrent inventory did not start'

SNAPPER_CONCURRENCY_STATE="$concurrency_state" RUN_HELPER_TIMEOUT=5 \
  run_helper "$laptop_helper" create >"$test_root/concurrency-second.log" 2>&1 &
second_pid=$!

first_status=0
second_status=0
wait "$first_pid" || first_status=$?
wait "$second_pid" || second_status=$?
[[ $first_status -eq 0 ]] || fail "first concurrent create returned $first_status"
[[ $second_status -eq 0 ]] || fail "second concurrent create returned $second_status"
[[ ! -e $concurrency_state/list-overlap ]] || fail 'concurrent inventories overlapped'

snapshot_count=$(wc -l <"$concurrency_state/snapshots")
[[ $snapshot_count -eq 1 ]] || fail "expected one snapshot after concurrent creates, found $snapshot_count"

: >"$sudo_log"
run_helper "$laptop_helper" restore
assert_file_equals 'limine-snapper-restore' "$sudo_log"

if RUN_HELPER_PATH="$no_snapper_path" run_helper "$laptop_helper" create; then
  fail 'missing snapper unexpectedly succeeded'
else
  status=$?
fi
[[ $status -eq 127 ]] || fail "missing snapper returned $status instead of 127"

printf 'PASS: snapshot helper\n'
