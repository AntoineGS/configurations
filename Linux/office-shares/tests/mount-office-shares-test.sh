#!/usr/bin/env bash
set -Eeuo pipefail
shopt -s inherit_errexit

script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
helper="$script_dir/../mount-office-shares"
tmp_dir="$(mktemp -d)"
bin_dir="$tmp_dir/bin"
cache_dir="$tmp_dir/caches"
gvfs_root="$tmp_dir/runtime/gvfs"
test_state="$tmp_dir/state"
test_shares="$tmp_dir/Shares"
test_fail_share=''

cleanup() {
  rm -rf -- "$tmp_dir"
}
trap cleanup EXIT

fail() {
  printf 'FAIL: %s\n' "$*" >&2
  exit 1
}

mkdir -p -- "$bin_dir" "$cache_dir" "$gvfs_root" "$test_state"

unix_user="$(id -un)"
unix_user="${unix_user%@*}"
expected_principal="${unix_user}@MULTIDEV.LOCAL"

cat >"$bin_dir/klist" <<'STUB'
#!/usr/bin/env bash
set -eu

cache="${KRB5CCNAME#FILE:}"
case "${cache##*/}" in
  *_foreign)
    principal='a.simard@OTHER.REALM'
    ;;
  *_same_realm_wrong)
    principal='other.user@MULTIDEV.LOCAL'
    ;;
  *_case_variant)
    principal="${OFFICE_TEST_CASE_VARIANT_PRINCIPAL:?}"
    ;;
  *_valid_old|*_valid_new)
    principal="${OFFICE_TEST_EXPECTED_PRINCIPAL:?}"
    ;;
  *)
    exit 1
    ;;
esac

if [[ "${1:-}" == '-s' ]]; then
  exit 0
fi

printf 'Ticket cache: FILE:%s\nDefault principal: %s\n' "$cache" "$principal"
STUB

cat >"$bin_dir/mountpoint" <<'STUB'
#!/usr/bin/env bash
set -eu

[[ "${1:-}" == '-q' && $# -eq 2 ]] || exit 2
mountpoint_path="$2"
printf 'mountpoint -q %s\n' "$mountpoint_path" >>"$OFFICE_TEST_STATE/mountpoint.log"

if [[ -f "$OFFICE_TEST_MOUNTED" ]]; then
  while IFS= read -r mounted_path; do
    if [[ "$mounted_path" == "$mountpoint_path" ]]; then
      exit 0
    fi
  done <"$OFFICE_TEST_MOUNTED"
fi

exit 1
STUB

cat >"$bin_dir/timeout" <<'STUB'
#!/usr/bin/env bash
set -eu

[[ "${1:-}" == '15s' && "${2:-}" == 'mount' && $# -eq 3 ]] || exit 2
printf '%s\n' "$*" >>"$OFFICE_TEST_STATE/timeout.log"
shift 1
"$@"
STUB

cat >"$bin_dir/mount" <<'STUB'
#!/usr/bin/env bash
set -eu

[[ $# -eq 1 ]] || exit 2
mountpoint_path="$1"
printf 'KRB5CCNAME=%s path=%s\n' "${KRB5CCNAME-}" "$mountpoint_path" >>"$OFFICE_TEST_STATE/attempt.log"

if [[ ! -t 0 ]]; then
  printf '%s\n' closed >>"$OFFICE_TEST_STATE/stdin.log"
else
  printf '%s\n' open >>"$OFFICE_TEST_STATE/stdin.log"
fi

if [[ "${OFFICE_TEST_FAIL_SHARE:-}" == "${mountpoint_path##*/}" ]]; then
  exit 1
fi

printf '%s\n' "$mountpoint_path" >>"$OFFICE_TEST_MOUNTED"
printf 'KRB5CCNAME=%s path=%s\n' "${KRB5CCNAME-}" "$mountpoint_path" >>"$OFFICE_TEST_STATE/mount.log"
STUB

chmod +x -- "$bin_dir/klist" "$bin_dir/mountpoint" "$bin_dir/timeout" "$bin_dir/mount"

run_helper() {
  mkdir -p -- "$test_state"

  env \
    PATH="$bin_dir:$PATH" \
    OFFICE_TEST_EXPECTED_PRINCIPAL="$expected_principal" \
    OFFICE_TEST_CASE_VARIANT_PRINCIPAL="$unix_user@multidev.local" \
    OFFICE_TEST_MOUNTED="$test_state/mounted" \
    OFFICE_TEST_STATE="$test_state" \
    OFFICE_TEST_FAIL_SHARE="$test_fail_share" \
    OFFICE_SHARES_CACHE_DIR="$cache_dir" \
    OFFICE_SHARES_DIR="$test_shares" \
    OFFICE_SHARES_GVFS_ROOT="$gvfs_root" \
    "$helper"
}

expected_mounts_for() {
  local directory="$1"
  printf '%s\n' \
    "$directory/G-serveurgdb" \
    "$directory/J-fichierscommuns" \
    "$directory/O-applications" \
    "$directory/Z-QA"
}

old_gvfs_target() {
  local share="$1"
  printf '%s/smb-share:server=md-fs01.multidev.local,share=%s' "$gvfs_root" "$share"
}

for prohibited in gio systemctl keyring guest ntlm password credentials username; do
  if grep -Eiq -- "$prohibited" "$helper"; then
    fail "prohibited mechanism reference remains: $prohibited"
  fi
done
grep -Fq -- 'OFFICE_SHARES_GVFS_ROOT' "$helper" || fail 'legacy path root is not configurable'
grep -Fq -- 'mountpoint -q' "$helper" || fail 'mountpoint idempotency check is missing'
grep -Fq -- 'timeout 15s mount' "$helper" || fail 'bounded mount command is missing'
if grep -Fq -- 'office-shares-gvfs-cache' "$helper"; then
  fail 'runtime cache marker remains'
fi

touch -- "$cache_dir/krb5cc_${UID}_invalid"
run_helper 2>"$tmp_dir/invalid-ticket.err" || fail 'missing-ticket run failed'
[[ ! -e "$test_state/mount.log" ]] || fail 'mounted without a matching ticket'
[[ ! -e "$test_shares" ]] || fail 'created paths without a matching ticket'

touch -- "$cache_dir/krb5cc_${UID}_foreign"
run_helper 2>"$tmp_dir/foreign-ticket.err" || fail 'foreign-realm run failed'
[[ ! -e "$test_shares" ]] || fail 'created paths with only a foreign ticket'

touch -- "$cache_dir/krb5cc_${UID}_same_realm_wrong"
run_helper 2>"$tmp_dir/wrong-principal.err" || fail 'same-realm wrong-principal run failed'
[[ ! -e "$test_shares" ]] || fail 'created paths with a wrong principal'

touch -- "$cache_dir/krb5cc_${UID}_case_variant"
run_helper 2>"$tmp_dir/case-variant.err" || fail 'case-variant principal run failed'
[[ ! -e "$test_shares" ]] || fail 'created paths with a case-variant principal'

touch -d '2 minutes ago' -- "$cache_dir/krb5cc_${UID}_valid_old"
touch -d '1 minute ago' -- "$cache_dir/krb5cc_${UID}_valid_new"
run_helper || fail 'valid-ticket run failed'

selected_cache="FILE:$cache_dir/krb5cc_${UID}_valid_new"
first_mountpoint="$test_shares/G-serveurgdb"
first_mount_line="KRB5CCNAME=$selected_cache path=$first_mountpoint"
first_mount="$(awk 'NR == 1 { print; exit }' "$test_state/mount.log")"
[[ "$first_mount" == "$first_mount_line" ]] || fail 'selected cache was not exported before the first mount'

expected_mounts="$(expected_mounts_for "$test_shares")"
actual_mounts="$(awk -F ' path=' '{ print $2 }' "$test_state/mount.log")"
[[ "$actual_mounts" == "$expected_mounts" ]] || fail 'mountpoint set or order differs'

expected_timeouts="$expected_mounts"
expected_timeouts="${expected_timeouts//$'\n'/$'\n15s mount '}"
expected_timeouts="15s mount $expected_timeouts"
[[ "$(<"$test_state/timeout.log")" == "$expected_timeouts" ]] || fail 'mount timeout invocations differ'
[[ "$(<"$test_state/stdin.log")" == $'closed\nclosed\nclosed\nclosed' ]] || fail 'mount stdin was not closed'

mount_count="$(wc -l <"$test_state/mount.log")"
run_helper || fail 'already-mounted run failed'
[[ "$(wc -l <"$test_state/mount.log")" == "$mount_count" ]] || fail 'already-mounted paths were mounted again'

symlink_state="$tmp_dir/symlink-root-state"
symlink_root="$tmp_dir/Shares-symlink"
symlink_target="$tmp_dir/symlink-target"
mkdir -p -- "$symlink_state" "$symlink_target"
ln -s -- "$symlink_target" "$symlink_root"
test_state="$symlink_state"
test_shares="$symlink_root"
if run_helper 2>"$tmp_dir/symlink-root.err"; then
  fail 'symlinked Shares root did not fail'
fi
[[ -L "$symlink_root" ]] || fail 'symlinked Shares root was replaced'
[[ ! -e "$symlink_target/G-serveurgdb" ]] || fail 'mountpoint was created through Shares symlink'
[[ ! -e "$symlink_state/mountpoint.log" ]] || fail 'mountpoint was queried through Shares symlink'
[[ ! -e "$symlink_state/mount.log" ]] || fail 'mount was invoked through Shares symlink'

file_root_state="$tmp_dir/file-root-state"
file_root="$tmp_dir/Shares-file"
mkdir -p -- "$file_root_state"
printf '%s\n' protected >"$file_root"
test_state="$file_root_state"
test_shares="$file_root"
if run_helper 2>"$tmp_dir/file-root.err"; then
  fail 'non-directory Shares root did not fail'
fi
[[ -f "$file_root" && "$(<"$file_root")" == protected ]] || fail 'non-directory Shares root changed'
[[ ! -e "$file_root_state/mountpoint.log" ]] || fail 'mountpoint was queried through file Shares root'
[[ ! -e "$file_root_state/mount.log" ]] || fail 'mount was invoked through file Shares root'

migration_state="$tmp_dir/migration-state"
migration_shares="$tmp_dir/migration-Shares"
mkdir -p -- "$migration_state" "$migration_shares"
test_state="$migration_state"
test_shares="$migration_shares"
for mapping in \
  'G-serveurgdb:serveurgdb' \
  'J-fichierscommuns:fichierscommuns' \
  'O-applications:applications' \
  'Z-QA:qa'; do
  link_name="${mapping%%:*}"
  share_name="${mapping#*:}"
  ln -s -- "$(old_gvfs_target "$share_name")" "$migration_shares/$link_name"
done
run_helper || fail 'legacy path migration failed'
for link_name in G-serveurgdb J-fichierscommuns O-applications Z-QA; do
  [[ -d "$migration_shares/$link_name" && ! -L "$migration_shares/$link_name" ]] || \
    fail "legacy path was not replaced with a directory: $link_name"
done

conflict_state="$tmp_dir/conflict-state"
conflict_shares="$tmp_dir/conflict-Shares"
mkdir -p -- "$conflict_state" "$conflict_shares"
test_state="$conflict_state"
test_shares="$conflict_shares"
wrong_target="$(old_gvfs_target serveurgdb)-stale"
ln -s -- "$wrong_target" "$conflict_shares/G-serveurgdb"
if run_helper 2>"$tmp_dir/symlink-conflict.err"; then
  fail 'unrelated legacy symlink did not fail'
fi
[[ -L "$conflict_shares/G-serveurgdb" ]] || fail 'unrelated legacy symlink was removed'
[[ "$(readlink -- "$conflict_shares/G-serveurgdb")" == "$wrong_target" ]] || \
  fail 'unrelated legacy symlink target changed'

rm -- "$conflict_shares/G-serveurgdb"
printf '%s\n' untouched >"$conflict_shares/G-serveurgdb"
if run_helper 2>"$tmp_dir/file-conflict.err"; then
  fail 'file conflict did not fail'
fi
[[ -f "$conflict_shares/G-serveurgdb" && "$(<"$conflict_shares/G-serveurgdb")" == untouched ]] || \
  fail 'file conflict was changed'

failure_state="$tmp_dir/failure-state"
failure_shares="$tmp_dir/failure-Shares"
mkdir -p -- "$failure_state" "$failure_shares"
test_state="$failure_state"
test_shares="$failure_shares"
test_fail_share=O-applications
if run_helper 2>"$tmp_dir/mount-failure.err"; then
  fail 'one-share mount failure returned success'
fi
expected_failure_mounts="$(printf '%s\n' \
  "$failure_shares/G-serveurgdb" \
  "$failure_shares/J-fichierscommuns" \
  "$failure_shares/Z-QA")"
actual_failure_mounts="$(awk -F ' path=' '{ print $2 }' "$failure_state/mount.log")"
[[ "$actual_failure_mounts" == "$expected_failure_mounts" ]] || \
  fail 'one-share failure prevented independent mounts'
if grep -Fq -- "$failure_shares/O-applications" "$failure_state/mount.log"; then
  fail 'failed mount was recorded as successful'
fi
grep -Fq -- "path=$failure_shares/O-applications" "$failure_state/attempt.log" || \
  fail 'failed mount was not attempted'
for link_name in G-serveurgdb J-fichierscommuns O-applications Z-QA; do
  [[ -d "$failure_shares/$link_name" ]] || fail "mountpoint directory missing after isolated failure: $link_name"
done

printf 'PASS: office share mount helper\n'
