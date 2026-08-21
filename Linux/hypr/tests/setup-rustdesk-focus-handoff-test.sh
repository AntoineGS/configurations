#!/usr/bin/env bash
set -Eeuo pipefail

SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
SETUP="$SCRIPT_DIR/../setup-rustdesk-focus-handoff"
UNIT_SOURCE="$SCRIPT_DIR/../rustdesk-focus-handoff.service"

fail() {
  printf 'FAIL: %s\n' "$1" >&2
  exit 1
}

TEST_ROOT=$(mktemp -d)
trap 'rm -rf -- "$TEST_ROOT"' EXIT
TEST_BIN="$TEST_ROOT/bin"
TEST_HOME="$TEST_ROOT/home"
SYSTEMCTL_LOG="$TEST_ROOT/systemctl.log"
SERVICE_STATE="$TEST_ROOT/service-state"
mkdir -p -- "$TEST_BIN" "$TEST_HOME"
export SYSTEMCTL_LOG SERVICE_STATE TEST_HOSTNAME=DESKTOP-E07VTRN

cat >"$TEST_BIN/hostname" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "$TEST_HOSTNAME"
EOF

cat >"$TEST_BIN/systemctl" <<'EOF'
#!/usr/bin/env bash
set -Eeuo pipefail

printf '%s\n' "$*" >>"$SYSTEMCTL_LOG"
[[ ${1:-} == --user ]] || exit 125
shift

case ${1:-} in
  is-enabled)
    [[ ${2:-} == --quiet && ${3:-} == rustdesk-focus-handoff.service && $# == 3 ]] || exit 125
    [[ -f $SERVICE_STATE && $(<"$SERVICE_STATE") == enabled-active ]]
    ;;
  is-active)
    [[ ${2:-} == --quiet && ${3:-} == rustdesk-focus-handoff.service && $# == 3 ]] || exit 125
    [[ -f $SERVICE_STATE && $(<"$SERVICE_STATE") == enabled-active ]]
    ;;
  show)
    [[ ${2:-} == rustdesk-focus-handoff.service &&
      ${3:-} == --property=NeedDaemonReload && ${4:-} == --value && $# == 4 ]] || exit 125
    printf 'no\n'
    ;;
  daemon-reload)
    [[ $# == 1 ]] || exit 125
    ;;
  enable)
    [[ ${2:-} == --now && ${3:-} == rustdesk-focus-handoff.service && $# == 3 ]] || exit 125
    printf 'enabled-active\n' >"$SERVICE_STATE"
    ;;
  *) exit 125 ;;
esac
EOF

chmod 0700 "$TEST_BIN/hostname" "$TEST_BIN/systemctl"
export PATH="$TEST_BIN:/usr/bin:/bin"

[[ -x $SETUP ]] || fail "$SETUP must exist and be executable"

run_setup() {
  HOME="$TEST_HOME" "$SETUP" "$@"
}

if run_setup --check; then
  fail '--check succeeded before the service was installed'
fi
[[ ! -e $TEST_HOME/.config/systemd/user/rustdesk-focus-handoff.service ]] ||
  fail '--check modified the service installation'

run_setup --apply || fail '--apply failed on the desktop client'
UNIT_TARGET="$TEST_HOME/.config/systemd/user/rustdesk-focus-handoff.service"
[[ -L $UNIT_TARGET ]] || fail '--apply did not create the service symlink'
[[ $(readlink -f -- "$UNIT_TARGET") == $(readlink -f -- "$UNIT_SOURCE") ]] ||
  fail '--apply linked the wrong service unit'
run_setup --check || fail '--check failed after installation'
if run_setup --check unexpected >/dev/null 2>&1; then
  fail '--check accepted unexpected arguments'
fi

expected_log=$'--user daemon-reload\n--user enable --now rustdesk-focus-handoff.service\n--user is-enabled --quiet rustdesk-focus-handoff.service\n--user is-active --quiet rustdesk-focus-handoff.service\n--user show rustdesk-focus-handoff.service --property=NeedDaemonReload --value\n--user is-enabled --quiet rustdesk-focus-handoff.service\n--user is-active --quiet rustdesk-focus-handoff.service\n--user show rustdesk-focus-handoff.service --property=NeedDaemonReload --value'
[[ $(<"$SYSTEMCTL_LOG") == "$expected_log" ]] ||
  fail "unexpected systemctl calls: $(<"$SYSTEMCTL_LOG")"

override_home="$TEST_ROOT/override-home"
override_target="$TEST_ROOT/redirected/rustdesk-focus-handoff.service"
mkdir -p -- "$override_home"
RUSTDESK_FOCUS_HANDOFF_UNIT_TARGET="$override_target" \
  HOME="$override_home" "$SETUP" --apply || fail '--apply rejected the desktop client with an override present'
fixed_target="$override_home/.config/systemd/user/rustdesk-focus-handoff.service"
[[ -L $fixed_target ]] || fail 'unit-target override redirected the service installation'
[[ ! -e $override_target && ! -L $override_target ]] || fail 'unit-target override was honored'

missing_source_dir="$TEST_ROOT/missing-source"
missing_source_home="$TEST_ROOT/missing-source-home"
mkdir -p -- "$missing_source_dir" "$missing_source_home/.config/systemd/user"
cp -- "$SETUP" "$missing_source_dir/setup-rustdesk-focus-handoff"
chmod 0700 "$missing_source_dir/setup-rustdesk-focus-handoff"
ln -s -- "$missing_source_dir/rustdesk-focus-handoff.service" \
  "$missing_source_home/.config/systemd/user/rustdesk-focus-handoff.service"
if HOME="$missing_source_home" "$missing_source_dir/setup-rustdesk-focus-handoff" --check; then
  fail '--check accepted an installation with a missing source unit'
fi

regular_home="$TEST_ROOT/regular-target-home"
regular_target="$regular_home/.config/systemd/user/rustdesk-focus-handoff.service"
mkdir -p -- "$(dirname -- "$regular_target")"
printf 'preserve me\n' >"$regular_target"
if HOME="$regular_home" "$SETUP" --apply >/dev/null 2>&1; then
  fail '--apply replaced an existing non-symlink unit'
fi
[[ ! -L $regular_target && $(<"$regular_target") == 'preserve me' ]] ||
  fail '--apply modified an existing non-symlink unit'

TEST_HOSTNAME=antoinews-linux
wrong_host_home="$TEST_ROOT/wrong-host-home"
mkdir -p -- "$wrong_host_home"
if RUSTDESK_FOCUS_HANDOFF_HOSTNAME=antoinews-linux \
  HOME="$wrong_host_home" "$SETUP" --apply >/dev/null 2>&1; then
  fail '--apply installed the listener on the controlled host'
fi
if HOME="$wrong_host_home" "$SETUP" --check >/dev/null 2>&1; then
  fail '--check accepted the controlled host'
fi
[[ ! -e $wrong_host_home/.config/systemd/user/rustdesk-focus-handoff.service ]] ||
  fail 'wrong-host refusal modified the service installation'

printf 'PASS: RustDesk focus handoff setup tests\n'
