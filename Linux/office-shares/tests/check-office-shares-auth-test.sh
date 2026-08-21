#!/usr/bin/env bash
set -Eeuo pipefail
shopt -s inherit_errexit

script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
helper="$script_dir/../check-office-shares-auth"
tmp_dir="$(mktemp -d)"
bin_dir="$tmp_dir/bin"
cache_dir="$tmp_dir/caches"
state_dir="$tmp_dir/state"

cleanup() {
  rm -rf -- "$tmp_dir"
}
trap cleanup EXIT

fail() {
  printf 'FAIL: %s\n' "$*" >&2
  exit 1
}

assert_file_equals() {
  local expected="$1"
  local path="$2"
  local description="$3"
  local actual=''

  [[ ! -e "$path" ]] || actual="$(<"$path")"
  [[ "$actual" == "$expected" ]] || {
    printf 'FAIL: %s\nexpected:\n%s\nactual:\n%s\n' "$description" "$expected" "$actual" >&2
    exit 1
  }
}

mkdir -p -- "$bin_dir" "$cache_dir" "$state_dir"

cat >"$bin_dir/klist" <<'STUB'
#!/usr/bin/env bash
set -eu

[[ "${LC_ALL:-}" == C ]] || exit 3
cache="${KRB5CCNAME#FILE:}"
case "${cache##*/}" in
  *_valid)
    principal="${AUTH_TEST_EXPECTED_PRINCIPAL:?}"
    ;;
  *_wrong)
    principal='other.user@MULTIDEV.LOCAL'
    ;;
  *)
    exit 1
    ;;
esac

[[ "${1:-}" != '-s' ]] || exit 0
printf 'Ticket cache: FILE:%s\nDefault principal: %s\n' "$cache" "$principal"
STUB

cat >"$bin_dir/notify-send" <<'STUB'
#!/usr/bin/env bash
set -eu
printf '%s\n' "$@" >"$AUTH_TEST_STATE/notify.log"
printf '%s\n' "${AUTH_TEST_ACTION:-}"
STUB

cat >"$bin_dir/systemd-run" <<'STUB'
#!/usr/bin/env bash
set -eu
printf '%s\n' "$@" >"$AUTH_TEST_STATE/systemd-run.log"
STUB

cat >"$bin_dir/kinit" <<'STUB'
#!/usr/bin/env bash
set -eu
printf 'KRB5CCNAME=%s principal=%s\n' "${KRB5CCNAME-}" "$*" >"$AUTH_TEST_STATE/kinit.log"
exit "${AUTH_TEST_KINIT_STATUS:-0}"
STUB

cat >"$bin_dir/systemctl" <<'STUB'
#!/usr/bin/env bash
set -eu
printf '%s\n' "$@" >"$AUTH_TEST_STATE/systemctl.log"
STUB

cat >"$bin_dir/uwsm" <<'STUB'
#!/usr/bin/env bash
exit 0
STUB

cat >"$bin_dir/ghostty" <<'STUB'
#!/usr/bin/env bash
exit 0
STUB

chmod +x -- "$bin_dir"/*

unix_user="$(id -un)"
unix_user="${unix_user%@*}"
expected_principal="$unix_user@MULTIDEV.LOCAL"

run_helper() {
  env \
    PATH="$bin_dir:$PATH" \
    AUTH_TEST_EXPECTED_PRINCIPAL="$expected_principal" \
    AUTH_TEST_STATE="$state_dir" \
    AUTH_TEST_ACTION="${AUTH_TEST_ACTION:-}" \
    AUTH_TEST_KINIT_STATUS="${AUTH_TEST_KINIT_STATUS:-0}" \
    OFFICE_SHARES_CACHE_DIR="$cache_dir" \
    "$helper" "$@"
}

[[ -x "$helper" ]] || fail 'authentication check helper is missing or not executable'

touch -- "$cache_dir/krb5cc_${UID}_valid"
run_helper || fail 'valid-ticket check failed'
[[ ! -e "$state_dir/notify.log" ]] || fail 'valid ticket produced a notification'

rm -- "$cache_dir/krb5cc_${UID}_valid"
touch -- "$cache_dir/krb5cc_${UID}_wrong"
run_helper || fail 'missing-ticket notification failed'
expected_notification=$'--app-name=Office Shares\n--icon=dialog-password\n--urgency=critical\n--expire-time=0\n--action=authenticate=Authenticate\n--wait\n--\nDomain authentication required\nNetwork shares need a fresh Kerberos ticket.'
assert_file_equals "$expected_notification" "$state_dir/notify.log" 'persistent notification arguments differ'
[[ ! -e "$state_dir/systemd-run.log" ]] || fail 'dismissed notification launched authentication'

AUTH_TEST_ACTION=authenticate run_helper || fail 'authentication action failed'
expected_launch="--user
--unit=office-shares-authenticate
--collect
--
uwsm
app
--
ghostty
--class=office-shares-auth
-e
$helper
--authenticate"
assert_file_equals "$expected_launch" "$state_dir/systemd-run.log" 'authentication terminal launch differs'

rm -f -- "$state_dir/kinit.log" "$state_dir/systemctl.log"
run_helper --authenticate || fail 'interactive authentication mode failed'
expected_kinit="KRB5CCNAME=FILE:$cache_dir/krb5cc_${UID} principal=$expected_principal"
assert_file_equals "$expected_kinit" "$state_dir/kinit.log" 'Kerberos cache or principal differs'
assert_file_equals $'--user\nstart\noffice-shares-mount.service' "$state_dir/systemctl.log" \
  'successful authentication did not retry share mounts'

rm -f -- "$state_dir/kinit.log" "$state_dir/systemctl.log"
if AUTH_TEST_KINIT_STATUS=1 run_helper --authenticate 2>/dev/null; then
  fail 'failed authentication returned success'
fi
[[ ! -e "$state_dir/systemctl.log" ]] || fail 'failed authentication retried share mounts'

printf 'PASS: office share authentication check\n'
