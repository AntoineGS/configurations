#!/usr/bin/env bash
set -Eeuo pipefail
shopt -s inherit_errexit

script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
helper="$script_dir/../setup-office-shares-fstab"
tmp_dir="$(mktemp -d)"
bin_dir="$tmp_dir/bin"
fstab="$tmp_dir/fstab"
state_dir="$tmp_dir/state"
test_user='office-test-user'
test_home="$tmp_dir/home"
test_uid='4242'
test_gid='4343'

cleanup() {
  rm -rf -- "$tmp_dir"
}
trap cleanup EXIT

fail() {
  printf 'FAIL: %s\n' "$*" >&2
  exit 1
}

mkdir -p -- "$bin_dir" "$state_dir" "$test_home"
real_sync="$(command -v sync)"

cat >"$bin_dir/findmnt" <<'STUB'
#!/usr/bin/env bash
set -eu

[[ $# -eq 3 && "$1" == '--verify' && "$2" == '--tab-file' ]] || exit 2
candidate="$3"
printf '%s\n' "$*" >>"$OFFICE_TEST_STATE/findmnt.log"
[[ -r "$candidate" ]] || exit 2
if [[ "${OFFICE_TEST_FINDMNT_FAIL:-0}" == 1 ]]; then
  printf '%s\n' 'simulated findmnt validation failure' >&2
  exit 1
fi
if [[ "${OFFICE_TEST_MUTATE_FSTAB:-0}" == 1 ]]; then
  printf '%s\n' 'concurrent unrelated update' >"$OFFICE_SHARES_FSTAB"
fi
exit 0
STUB
chmod +x -- "$bin_dir/findmnt"

cat >"$bin_dir/sync" <<'STUB'
#!/usr/bin/env bash
set -eu

if [[ "${OFFICE_TEST_MUTATE_PRE_REVALIDATION:-0}" == 1 ]]; then
  printf '%s\n' 'latest unrelated update' >"$OFFICE_SHARES_FSTAB"
  chmod 600 -- "$OFFICE_SHARES_FSTAB"
elif [[ "${OFFICE_TEST_MUTATE_MODE_PRE_REVALIDATION:-0}" == 1 ]]; then
  chmod 600 -- "$OFFICE_SHARES_FSTAB"
fi
exec "$OFFICE_TEST_REAL_SYNC" "$@"
STUB
chmod +x -- "$bin_dir/sync"

common_env=(
  "PATH=$bin_dir:$PATH"
  "OFFICE_SHARES_FSTAB=$fstab"
  "OFFICE_SHARES_USER=$test_user"
  "OFFICE_SHARES_HOME=$test_home"
  "OFFICE_SHARES_UID=$test_uid"
  "OFFICE_SHARES_GID=$test_gid"
  "OFFICE_TEST_REAL_SYNC=$real_sync"
  "OFFICE_TEST_STATE=$state_dir"
)

run_helper() {
  env "${common_env[@]}" "$helper" "$@"
}

begin_marker='# BEGIN tidydots office-shares'
end_marker='# END tidydots office-shares'
block="//md-fs01.multidev.local/serveurgdb $test_home/Shares/G-serveurgdb cifs noauto,user,_netdev,sec=krb5,cruid=$test_uid,uid=$test_uid,gid=$test_gid,vers=3.1.1 0 0
//md-fs01.multidev.local/fichierscommuns $test_home/Shares/J-fichierscommuns cifs noauto,user,_netdev,sec=krb5,cruid=$test_uid,uid=$test_uid,gid=$test_gid,vers=3.1.1 0 0
//md-fs01.multidev.local/applications $test_home/Shares/O-applications cifs noauto,user,_netdev,sec=krb5,cruid=$test_uid,uid=$test_uid,gid=$test_gid,vers=3.1.1 0 0
//md-fs01.multidev.local/qa $test_home/Shares/Z-QA cifs noauto,user,_netdev,sec=krb5,cruid=$test_uid,uid=$test_uid,gid=$test_gid,vers=3.1.1 0 0"
expected_block="$begin_marker
$block
$end_marker"

if run_helper --help >"$tmp_dir/help.out" 2>"$tmp_dir/help.err"; then
  grep -Fq 'Usage:' "$tmp_dir/help.out" || fail 'help output has no usage text'
else
  fail '--help failed'
fi

unknown_status=0
run_helper --unknown >"$tmp_dir/unknown.out" 2>"$tmp_dir/unknown.err" || unknown_status=$?
[[ "$unknown_status" -eq 2 ]] || fail 'unknown argument did not return status 2'

if run_helper --check >"$tmp_dir/missing-check.out" 2>"$tmp_dir/missing-check.err"; then
  fail 'check accepted a missing fstab'
fi
[[ -s "$tmp_dir/missing-check.err" ]] || fail 'missing-fstab check did not report an error'

run_helper --apply || fail 'create apply failed'
[[ -f "$fstab" ]] || fail 'create apply did not create fstab'
[[ "$(<"$fstab")" == "$expected_block" ]] || fail 'created block differs from the exact block'
run_helper --check || fail 'exact check failed'

{
  printf 'unrelated-before\n%s\nunrelated-after\n' "$expected_block"
  printf '%s\n' "$begin_marker"
  printf '%s\n' 'stale duplicate entry'
  printf '%s\n' "$end_marker"
  printf '%s' 'tail-without-newline'
} >"$fstab"

if run_helper --check >"$tmp_dir/stale-check.out" 2>"$tmp_dir/stale-check.err"; then
  fail 'check accepted duplicate or stale marked blocks'
fi
[[ -s "$tmp_dir/stale-check.err" ]] || fail 'stale-block check did not report an error'
run_helper --apply || fail 'stale block replacement failed'
expected_replaced="unrelated-before
unrelated-after
tail-without-newline
$expected_block"
[[ "$(<"$fstab")" == "$expected_replaced" ]] || fail 'unrelated content or block replacement differs'
run_helper --check || fail 'check failed after stale block replacement'

printf 'metadata-before\n%s\nmetadata-after\n' \
  "$begin_marker" >"$fstab"
printf '%s\n' 'stale metadata block' >>"$fstab"
printf '%s\n' "$end_marker" >>"$fstab"
chmod 640 -- "$fstab"
owner_before="$(stat -c '%u:%g' -- "$fstab")"
mode_before="$(stat -c '%a' -- "$fstab")"
run_helper --apply || fail 'metadata-preserving apply failed'
[[ "$(stat -c '%u:%g' -- "$fstab")" == "$owner_before" ]] || fail 'apply changed ownership'
[[ "$(stat -c '%a' -- "$fstab")" == "$mode_before" ]] || fail 'apply changed mode'

chmod 640 -- "$fstab"
owner_before="$(stat -c '%u:%g' -- "$fstab")"
mode_before="$(stat -c '%a' -- "$fstab")"
inode_before="$(stat -c '%i' -- "$fstab")"
run_helper --apply || fail 'idempotent apply failed'
[[ "$(stat -c '%i' -- "$fstab")" == "$inode_before" ]] || fail 'idempotent apply replaced the inode'
[[ "$(stat -c '%u:%g' -- "$fstab")" == "$owner_before" ]] || fail 'idempotent apply changed ownership'
[[ "$(stat -c '%a' -- "$fstab")" == "$mode_before" ]] || fail 'idempotent apply changed mode'

printf 'unrelated-before\n%s\nstale duplicate entry\n%s\nunrelated-after\n' \
  "$begin_marker" "$end_marker" >"$fstab"
chmod 640 -- "$fstab"
owner_before="$(stat -c '%u:%g' -- "$fstab")"
mode_before="$(stat -c '%a' -- "$fstab")"
inode_before="$(stat -c '%i' -- "$fstab")"
cp -- "$fstab" "$tmp_dir/fstab.before-validation"
if env "${common_env[@]}" OFFICE_TEST_FINDMNT_FAIL=1 "$helper" --apply \
  >"$tmp_dir/validation.out" 2>"$tmp_dir/validation.err"; then
  fail 'validation failure returned success'
fi
grep -Fq 'simulated findmnt validation failure' "$tmp_dir/validation.err" || \
  fail 'validation failure did not report findmnt output'
cmp -- "$fstab" "$tmp_dir/fstab.before-validation" || fail 'validation failure changed fstab'
[[ "$(stat -c '%u:%g' -- "$fstab")" == "$owner_before" ]] || fail 'validation failure changed ownership'
[[ "$(stat -c '%a' -- "$fstab")" == "$mode_before" ]] || fail 'validation failure changed mode'
[[ "$(stat -c '%i' -- "$fstab")" == "$inode_before" ]] || fail 'validation failure replaced the inode'

printf 'before-concurrent\n' >"$fstab"
if env "${common_env[@]}" OFFICE_TEST_MUTATE_FSTAB=1 "$helper" --apply \
  >"$tmp_dir/concurrent.out" 2>"$tmp_dir/concurrent.err"; then
  fail 'concurrent fstab mutation did not fail apply'
fi
[[ "$(<"$fstab")" == 'concurrent unrelated update' ]] || \
  fail 'concurrent fstab update was overwritten'

printf 'before-latest-boundary\n' >"$fstab"
chmod 640 -- "$fstab"
if env "${common_env[@]}" OFFICE_TEST_MUTATE_PRE_REVALIDATION=1 "$helper" --apply \
  >"$tmp_dir/latest-boundary.out" 2>"$tmp_dir/latest-boundary.err"; then
  fail 'latest-boundary content mutation did not fail apply'
fi
[[ "$(<"$fstab")" == 'latest unrelated update' ]] || \
  fail 'latest-boundary content update was overwritten'
[[ "$(stat -c '%a' -- "$fstab")" == 600 ]] || \
  fail 'latest-boundary mode update was overwritten'

printf 'before-mode-boundary\n' >"$fstab"
chmod 640 -- "$fstab"
if env "${common_env[@]}" OFFICE_TEST_MUTATE_MODE_PRE_REVALIDATION=1 "$helper" --apply \
  >"$tmp_dir/mode-boundary.out" 2>"$tmp_dir/mode-boundary.err"; then
  fail 'latest-boundary mode mutation did not fail apply'
fi
[[ "$(<"$fstab")" == 'before-mode-boundary' ]] || \
  fail 'latest-boundary mode-only update was overwritten'
[[ "$(stat -c '%a' -- "$fstab")" == 600 ]] || \
  fail 'latest-boundary mode-only update was overwritten'

printf '%s' "$test_home/with whitespace" >"$tmp_dir/unsafe-home"
if env "${common_env[@]}" OFFICE_SHARES_HOME="$tmp_dir/unsafe home" "$helper" --check \
  >"$tmp_dir/unsafe-home.out" 2>"$tmp_dir/unsafe-home.err"; then
  fail 'unsafe home path was accepted'
fi
[[ -s "$tmp_dir/unsafe-home.err" ]] || fail 'unsafe home path did not report an error'

printf 'PASS: office share fstab setup helper\n'
