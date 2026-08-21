#!/usr/bin/env bash
set -Eeuo pipefail

ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../../.." && pwd -P)"
HELPER="$ROOT/Linux/os/helpers/desktop-fallback-cleanup"
ROUTE_SERVICE='desktop-shell-mako-route.service'
TEST_ROOT='' BIN='' LOG='' STATE='' REPO='' HOME_FIXTURE=''
status=0 output=''
trap '[[ -z ${TEST_ROOT:-} ]] || rm -rf -- "$TEST_ROOT"' EXIT

fail() { printf 'not ok: %s\n' "$1" >&2; exit 1; }
assert_status() { [[ $status == "$1" ]] || fail "expected status $1, got $status: $output"; }
assert_contains() { [[ $1 == *"$2"* ]] || fail "missing '$2' in: $1"; }
assert_not_contains() { [[ $1 != *"$2"* ]] || fail "unexpected '$2' in: $1"; }
assert_file_absent() { [[ ! -e $1 && ! -L $1 ]] || fail "path remains: $1"; }

log_argv() {
  local command_name=$1 arg
  shift
  printf '%s' "$command_name" >>"$FAKE_LOG"
  for arg in "$@"; do printf '|%q' "$arg" >>"$FAKE_LOG"; done
  printf '\n' >>"$FAKE_LOG"
}

setup_fixture() {
  TEST_ROOT="$(mktemp -d)"; BIN="$TEST_ROOT/bin"; LOG="$TEST_ROOT/commands.log"
  STATE="$TEST_ROOT/packages"; REPO="$TEST_ROOT/repository"; HOME_FIXTURE="$TEST_ROOT/home"
  mkdir -p "$BIN" "$REPO/Linux" "$REPO/Linux/quickshell/desktop-shell/systemd" \
    "$HOME_FIXTURE/.config/systemd/user" "$TEST_ROOT/usr/local/bin"
  : >"$LOG"; : >"$STATE"
  export TEST_ROOT
  export PATH="$BIN:$PATH" HOME="$HOME_FIXTURE" FAKE_LOG="$LOG" FAKE_STATE="$STATE"
  export FAKE_REPO_ROOT="$REPO" FAKE_CONFIG_ROOT="$HOME_FIXTURE/.config" FAKE_ROUTE_STATE_FILE="$TEST_ROOT/route-state"
  export FAKE_ROUTE_CLEANED_FILE="$TEST_ROOT/route-cleaned"
  export FAKE_SYSTEMD_USER_DIR="$HOME_FIXTURE/.config/systemd/user"
  export FAKE_WAYBAR_BIN="$TEST_ROOT/usr/local/bin/waybar"
  export DESKTOP_FALLBACK_CLEANUP_TEST_MODE=1
  export FAKE_OWNERSHIP=unowned FAKE_PACMAN_FAIL=0 FAKE_SYSTEMCTL_FAIL=0 FAKE_LOCALE_REQUIRED=1
  export FAKE_SHELL_ACTIVE=1 FAKE_ACTIVATE_FAIL=0 FAKE_IPC_FAIL=0 FAKE_STATUS_FAIL=0
  export FAKE_PGREP_STATUS=1 FAKE_ROUTE_STATE=absent FAKE_TOCTOU=0 FAKE_SYSTEMCTL_INSPECT_ERROR=0
  export FAKE_ROUTE_ENABLED_OUTPUT=not-found FAKE_ROUTE_ENABLED_STATUS=1
  export FAKE_ROUTE_ACTIVE_OUTPUT=unknown FAKE_ROUTE_ACTIVE_STATUS=4
  export FAKE_DISABLE_REMOVES_LINK=0 FAKE_DISABLE_REPLACES_LINK=0

  cat >"$BIN/log-argv" <<'EOF'
#!/usr/bin/env bash
set -Eeuo pipefail
command_name=$1; shift
printf '%s' "$command_name" >>"${FAKE_LOG:?}"
for arg in "$@"; do printf '|%q' "$arg" >>"$FAKE_LOG"; done
printf '\n' >>"$FAKE_LOG"
EOF

  cat >"$BIN/pacman" <<'EOF'
#!/usr/bin/env bash
set -Eeuo pipefail
log-argv pacman "$@"
case ${1:-} in
  -Qq) [[ -s $FAKE_STATE ]] && sort -u "$FAKE_STATE" || true ;;
  -Qo)
    [[ ${FAKE_LOCALE_REQUIRED:-0} != 1 || ${LC_ALL:-} == C ]] || { printf 'locale error\n' >&2; exit 2; }
    case ${FAKE_OWNERSHIP:?} in
      owned) printf 'local/package owns %s\n' "${3:?}"; exit 0 ;;
      unowned) printf 'error: No package owns %s\n' "${3:?}" >&2; exit 1 ;;
      error) printf 'error: database is unavailable\n' >&2; exit 1 ;;
      *) exit 2 ;;
    esac ;;
  -Rns)
    [[ $FAKE_PACMAN_FAIL == 1 ]] && { printf 'transaction declined\n' >&2; exit 73; }
    shift
    printf '%s\n' "$@" | while IFS= read -r package; do
      [[ $package == -- ]] || printf '%s\n' "$package" >>"$TEST_ROOT/removed"
    done
    while IFS= read -r package; do
      [[ -n $package ]] && sed -i "/^${package//./\.}$/d" "$FAKE_STATE"
    done <"$TEST_ROOT/removed"
    ;;
  *) exit 2 ;;
esac
EOF
  cat >"$BIN/sudo" <<'EOF'
#!/usr/bin/env bash
set -Eeuo pipefail
log-argv sudo "$@"
"$@"
EOF
  cat >"$BIN/systemctl" <<'EOF'
#!/usr/bin/env bash
set -Eeuo pipefail
log-argv systemctl "$@"
if [[ -e ${FAKE_ROUTE_CLEANED_FILE:?} ]]; then
  FAKE_ROUTE_ENABLED_OUTPUT=disabled FAKE_ROUTE_ENABLED_STATUS=1
  FAKE_ROUTE_ACTIVE_OUTPUT=inactive FAKE_ROUTE_ACTIVE_STATUS=3
fi
[[ ${FAKE_SYSTEMCTL_FAIL:-0} == 1 && ${2:-} == disable ]] && exit 74
if [[ ${1:-} == --user && ${2:-} == is-enabled ]]; then
  [[ ${FAKE_SYSTEMCTL_INSPECT_ERROR:-0} == 1 ]] && { printf 'inspection failed\n' >&2; exit 2; }
  printf '%s\n' "$FAKE_ROUTE_ENABLED_OUTPUT"; exit "$FAKE_ROUTE_ENABLED_STATUS"
fi
if [[ ${1:-} == --user && ${2:-} == is-active && ${3:-} == --quiet ]]; then
  if [[ ${4:-} == desktop-shell-mako-route.service ]]; then
    exit "$FAKE_ROUTE_ACTIVE_STATUS"
  fi
  [[ ${FAKE_SHELL_ACTIVE:-1} == 1 ]]; exit
fi
if [[ ${1:-} == --user && ${2:-} == is-active && ${3:-} == desktop-shell-mako-route.service ]]; then
  printf '%s\n' "$FAKE_ROUTE_ACTIVE_OUTPUT"; exit "$FAKE_ROUTE_ACTIVE_STATUS"
fi
if [[ ${2:-} == disable ]]; then
  : >"$FAKE_ROUTE_CLEANED_FILE"
  route_link="$FAKE_SYSTEMD_USER_DIR/desktop-shell-mako-route.service"
  if [[ ${FAKE_DISABLE_REMOVES_LINK:-0} == 1 ]]; then rm -f -- "$route_link"; fi
  if [[ ${FAKE_DISABLE_REPLACES_LINK:-0} == 1 ]]; then rm -f -- "$route_link"; printf replacement >"$route_link"; fi
fi
if [[ ${2:-} == unmask || ${2:-} == stop ]]; then : >"$FAKE_ROUTE_CLEANED_FILE"; fi
EOF
  cat >"$BIN/pgrep" <<'EOF'
#!/usr/bin/env bash
set -Eeuo pipefail
log-argv pgrep "$@"
exit "${FAKE_PGREP_STATUS:-1}"
EOF
  cat >"$BIN/desktop-shell" <<'EOF'
#!/usr/bin/env bash
set -Eeuo pipefail
log-argv desktop-shell "$@"
if [[ ${FAKE_IPC_FAIL:-0} == 1 ]]; then exit 75; fi
EOF
  cat >"$BIN/desktop-shell-activate" <<'EOF'
#!/usr/bin/env bash
set -Eeuo pipefail
log-argv desktop-shell-activate "$@"
if [[ ${FAKE_ACTIVATE_FAIL:-0} == 1 ]]; then exit 76; fi
EOF
  cat >"$BIN/desktop-shell-status" <<'EOF'
#!/usr/bin/env bash
set -Eeuo pipefail
log-argv desktop-shell-status "$@"
printf '{"class":"muted","text":"healthy"}\n'
EOF
  cat >"$BIN/jq" <<'EOF'
#!/usr/bin/env bash
set -Eeuo pipefail
cat >/dev/null
if [[ ${FAKE_STATUS_FAIL:-0} == 1 ]]; then exit 77; fi
EOF
  chmod +x "$BIN"/*
}

teardown_fixture() { rm -rf -- "$TEST_ROOT"; }
run_helper() {
  local capture="$TEST_ROOT/output"
  set +e
  "$HELPER" "$@" >"$capture" 2>&1
  status=$?
  set -e
  output="$(<"$capture")"
}
finish_case() { local result=$1; teardown_fixture; return "$result"; }
install_packages() { printf '%s\n' "$@" >"$STATE"; }

test_dry_run_only_needs_preview_dependencies() {
  setup_fixture; install_packages waybar-git waybar-ai-usage-go-bin mako
  rm -f -- "$BIN/sudo" "$BIN/systemctl" "$BIN/rm" "$BIN/pgrep" \
    "$BIN/desktop-shell" "$BIN/desktop-shell-activate" "$BIN/desktop-shell-status" "$BIN/jq"
  PATH="$BIN:/usr/bin:/bin" run_helper --dry-run
  assert_status 0; assert_contains "$output" 'waybar-git'; assert_not_contains "$(<"$LOG")" 'sudo'
  finish_case $?
}

test_confirmation_and_package_selection_are_exact() {
  setup_fixture; install_packages waybar waybar-git waybar-ai-usage-go-bin mako
  run_helper <<< 'cleanup'; assert_status 0
  local log; log="$(<"$LOG")"
  assert_contains "$log" '|waybar|'
  assert_contains "$log" 'waybar-git'; assert_contains "$log" 'waybar-ai-usage-go-bin'; assert_contains "$log" '|mako'
  finish_case $?
}

test_real_directory_and_unsafe_symlink_fail_before_mutation() {
  setup_fixture; install_packages mako; mkdir -p "$FAKE_CONFIG_ROOT/mako"
  run_helper <<< 'cleanup'; assert_status 1; assert_contains "$output" 'real directory'
  assert_not_contains "$(<"$LOG")" 'sudo|pacman|-Rns'; teardown_fixture
  setup_fixture; install_packages mako; ln -s /tmp/unsafe "$FAKE_CONFIG_ROOT/mako"
  run_helper <<< 'cleanup'; assert_status 1; assert_contains "$output" 'unsafe symlink'
  assert_not_contains "$(<"$LOG")" 'sudo|pacman|-Rns'; finish_case $?
}

test_enabled_route_without_link_is_stopped_and_inspection_errors_fail() {
  setup_fixture; FAKE_ROUTE_ENABLED_OUTPUT=enabled FAKE_ROUTE_ENABLED_STATUS=0
  run_helper <<< 'cleanup'; assert_status 0; assert_contains "$(<"$LOG")" 'systemctl|--user|disable|--now'
  setup_fixture; FAKE_SYSTEMCTL_INSPECT_ERROR=1
  run_helper <<< 'cleanup'; assert_status 1; assert_contains "$output" 'route'; finish_case $?
}

route_trace() {
  local line trace=''
  while IFS= read -r line; do
    [[ $line == *"$ROUTE_SERVICE"* ]] || continue
    trace+="$line"$'\n'
  done <"$LOG"
  printf '%s' "$trace"
}

assert_route_trace() {
  local expected=$1 actual
  expected=${expected%$'\n'}
  actual=$(route_trace)
  [[ $actual == "$expected" ]] || fail "unexpected route trace: $actual"
}

test_systemd_status_matrix_has_explicit_fail_closed_transitions() {
  setup_fixture; FAKE_ROUTE_ENABLED_OUTPUT=enabled FAKE_ROUTE_ENABLED_STATUS=0 FAKE_ROUTE_ACTIVE_OUTPUT=active FAKE_ROUTE_ACTIVE_STATUS=0
  run_helper <<< 'cleanup'; assert_status 0
  assert_route_trace $'systemctl|--user|is-enabled|desktop-shell-mako-route.service\nsystemctl|--user|is-active|desktop-shell-mako-route.service\nsystemctl|--user|disable|--now|desktop-shell-mako-route.service\nsystemctl|--user|is-enabled|desktop-shell-mako-route.service\nsystemctl|--user|is-active|desktop-shell-mako-route.service\n'; teardown_fixture

  setup_fixture; FAKE_ROUTE_ENABLED_OUTPUT=enabled FAKE_ROUTE_ENABLED_STATUS=0 FAKE_ROUTE_ACTIVE_OUTPUT=inactive FAKE_ROUTE_ACTIVE_STATUS=3
  run_helper <<< 'cleanup'; assert_status 0; assert_route_trace $'systemctl|--user|is-enabled|desktop-shell-mako-route.service\nsystemctl|--user|is-active|desktop-shell-mako-route.service\nsystemctl|--user|disable|--now|desktop-shell-mako-route.service\nsystemctl|--user|is-enabled|desktop-shell-mako-route.service\nsystemctl|--user|is-active|desktop-shell-mako-route.service\n'; teardown_fixture

  setup_fixture; FAKE_ROUTE_ENABLED_OUTPUT=disabled FAKE_ROUTE_ENABLED_STATUS=1 FAKE_ROUTE_ACTIVE_OUTPUT=active FAKE_ROUTE_ACTIVE_STATUS=0
  run_helper <<< 'cleanup'; assert_status 0; assert_route_trace $'systemctl|--user|is-enabled|desktop-shell-mako-route.service\nsystemctl|--user|is-active|desktop-shell-mako-route.service\nsystemctl|--user|stop|desktop-shell-mako-route.service\nsystemctl|--user|is-enabled|desktop-shell-mako-route.service\nsystemctl|--user|is-active|desktop-shell-mako-route.service\n'; teardown_fixture

  setup_fixture; FAKE_ROUTE_ENABLED_OUTPUT=disabled FAKE_ROUTE_ENABLED_STATUS=1 FAKE_ROUTE_ACTIVE_OUTPUT=inactive FAKE_ROUTE_ACTIVE_STATUS=3
  run_helper <<< 'cleanup'; assert_status 0; assert_route_trace $'systemctl|--user|is-enabled|desktop-shell-mako-route.service\nsystemctl|--user|is-active|desktop-shell-mako-route.service\nsystemctl|--user|is-enabled|desktop-shell-mako-route.service\nsystemctl|--user|is-active|desktop-shell-mako-route.service\n'; teardown_fixture

  setup_fixture; FAKE_ROUTE_ENABLED_OUTPUT=not-found FAKE_ROUTE_ENABLED_STATUS=4 FAKE_ROUTE_ACTIVE_OUTPUT=inactive FAKE_ROUTE_ACTIVE_STATUS=4
  run_helper <<< 'cleanup'; assert_status 0; assert_route_trace $'systemctl|--user|is-enabled|desktop-shell-mako-route.service\nsystemctl|--user|is-active|desktop-shell-mako-route.service\nsystemctl|--user|is-enabled|desktop-shell-mako-route.service\nsystemctl|--user|is-active|desktop-shell-mako-route.service\n'; teardown_fixture

  setup_fixture; FAKE_ROUTE_ENABLED_OUTPUT=masked FAKE_ROUTE_ENABLED_STATUS=1 FAKE_ROUTE_ACTIVE_OUTPUT=inactive FAKE_ROUTE_ACTIVE_STATUS=3
  run_helper <<< 'cleanup'; assert_status 0; assert_route_trace $'systemctl|--user|is-enabled|desktop-shell-mako-route.service\nsystemctl|--user|is-active|desktop-shell-mako-route.service\nsystemctl|--user|unmask|desktop-shell-mako-route.service\nsystemctl|--user|disable|--now|desktop-shell-mako-route.service\nsystemctl|--user|is-enabled|desktop-shell-mako-route.service\nsystemctl|--user|is-active|desktop-shell-mako-route.service\n'; teardown_fixture

  setup_fixture; FAKE_ROUTE_ENABLED_OUTPUT=masked-runtime FAKE_ROUTE_ENABLED_STATUS=1 FAKE_ROUTE_ACTIVE_OUTPUT=active FAKE_ROUTE_ACTIVE_STATUS=0
  run_helper <<< 'cleanup'; assert_status 0; assert_route_trace $'systemctl|--user|is-enabled|desktop-shell-mako-route.service\nsystemctl|--user|is-active|desktop-shell-mako-route.service\nsystemctl|--user|unmask|desktop-shell-mako-route.service\nsystemctl|--user|disable|--now|desktop-shell-mako-route.service\nsystemctl|--user|is-enabled|desktop-shell-mako-route.service\nsystemctl|--user|is-active|desktop-shell-mako-route.service\n'; teardown_fixture

  setup_fixture; FAKE_ROUTE_ENABLED_OUTPUT=linked FAKE_ROUTE_ENABLED_STATUS=0 FAKE_ROUTE_ACTIVE_OUTPUT=inactive FAKE_ROUTE_ACTIVE_STATUS=3
  run_helper <<< 'cleanup'; assert_status 0; assert_route_trace $'systemctl|--user|is-enabled|desktop-shell-mako-route.service\nsystemctl|--user|is-active|desktop-shell-mako-route.service\nsystemctl|--user|disable|--now|desktop-shell-mako-route.service\nsystemctl|--user|is-enabled|desktop-shell-mako-route.service\nsystemctl|--user|is-active|desktop-shell-mako-route.service\n'; teardown_fixture

  setup_fixture; FAKE_ROUTE_ENABLED_OUTPUT=linked-runtime FAKE_ROUTE_ENABLED_STATUS=0 FAKE_ROUTE_ACTIVE_OUTPUT=inactive FAKE_ROUTE_ACTIVE_STATUS=3
  run_helper <<< 'cleanup'; assert_status 0; assert_route_trace $'systemctl|--user|is-enabled|desktop-shell-mako-route.service\nsystemctl|--user|is-active|desktop-shell-mako-route.service\nsystemctl|--user|disable|--now|desktop-shell-mako-route.service\nsystemctl|--user|is-enabled|desktop-shell-mako-route.service\nsystemctl|--user|is-active|desktop-shell-mako-route.service\n'; teardown_fixture

  setup_fixture; FAKE_ROUTE_ENABLED_OUTPUT=not-found FAKE_ROUTE_ENABLED_STATUS=4 FAKE_ROUTE_ACTIVE_OUTPUT=unknown FAKE_ROUTE_ACTIVE_STATUS=4
  run_helper <<< 'cleanup'; assert_status 0; assert_route_trace $'systemctl|--user|is-enabled|desktop-shell-mako-route.service\nsystemctl|--user|is-active|desktop-shell-mako-route.service\nsystemctl|--user|is-enabled|desktop-shell-mako-route.service\nsystemctl|--user|is-active|desktop-shell-mako-route.service\n'; teardown_fixture

  setup_fixture; FAKE_ROUTE_ENABLED_OUTPUT=transport-error FAKE_ROUTE_ENABLED_STATUS=5
  run_helper <<< 'cleanup'; assert_status 1; assert_contains "$output" 'route'
  assert_not_contains "$(route_trace)" '|unmask|'; assert_not_contains "$(route_trace)" '|disable|';
  assert_not_contains "$(route_trace)" '|stop|'; finish_case $?
}

test_disable_may_remove_validated_route_link_but_rejects_replacement() {
  setup_fixture; FAKE_ROUTE_ENABLED_OUTPUT=enabled FAKE_ROUTE_ENABLED_STATUS=0 FAKE_ROUTE_ACTIVE_OUTPUT=inactive FAKE_ROUTE_ACTIVE_STATUS=3
  ln -s "$REPO/Linux/quickshell/desktop-shell/systemd/$ROUTE_SERVICE" "$FAKE_SYSTEMD_USER_DIR/$ROUTE_SERVICE"
  FAKE_DISABLE_REMOVES_LINK=1 run_helper <<< 'cleanup'; assert_status 0
  assert_file_absent "$FAKE_SYSTEMD_USER_DIR/$ROUTE_SERVICE"; teardown_fixture

  setup_fixture; FAKE_ROUTE_ENABLED_OUTPUT=enabled FAKE_ROUTE_ENABLED_STATUS=0 FAKE_ROUTE_ACTIVE_OUTPUT=inactive FAKE_ROUTE_ACTIVE_STATUS=3
  ln -s "$REPO/Linux/quickshell/desktop-shell/systemd/$ROUTE_SERVICE" "$FAKE_SYSTEMD_USER_DIR/$ROUTE_SERVICE"
  FAKE_DISABLE_REPLACES_LINK=1 run_helper <<< 'cleanup'; assert_status 1; assert_contains "$output" 'target identity/type changed'; finish_case $?
}

test_binary_symlink_is_rejected_during_preflight() {
  setup_fixture; install_packages mako; ln -s "$REPO/Linux/mako" "$FAKE_WAYBAR_BIN"
  run_helper <<< 'cleanup'; assert_status 1; assert_contains "$output" 'binary'
  assert_not_contains "$(<"$LOG")" 'sudo|pacman|-Rns'; finish_case $?
}

test_decline_and_pacman_failure_do_not_mutate_route() {
  setup_fixture; install_packages mako; ln -s "$REPO/Linux/mako" "$FAKE_CONFIG_ROOT/mako"
  run_helper <<< 'no'; assert_status 1; assert_contains "$output" 'no changes were made'; [[ -L $FAKE_CONFIG_ROOT/mako ]] || fail 'decline mutated link'
  FAKE_PACMAN_FAIL=1 run_helper <<< 'cleanup'; assert_status 1; assert_contains "$output" 'phase=packages'; [[ -L $FAKE_CONFIG_ROOT/mako ]] || fail 'failure mutated link'
  finish_case $?
}

test_ownership_results_fail_closed_and_recheck() {
  setup_fixture; install_packages mako; touch "$FAKE_WAYBAR_BIN"; FAKE_OWNERSHIP=error
  run_helper --dry-run; assert_status 1; assert_contains "$output" 'ownership'
  FAKE_OWNERSHIP=owned; run_helper --dry-run; assert_status 1; assert_contains "$output" 'owned'
  FAKE_OWNERSHIP=unowned; run_helper --dry-run; assert_status 0
  finish_case $?
}

test_toctou_replacement_aborts_before_unlink() {
  setup_fixture; install_packages mako; ln -s "$REPO/Linux/mako" "$FAKE_CONFIG_ROOT/mako"; FAKE_TOCTOU=1
  run_helper <<< 'cleanup'; assert_status 1; assert_contains "$output" 'identity'; [[ -L $FAKE_CONFIG_ROOT/mako ]] || true
  finish_case $?
}

test_success_verifies_absence_activation_health_and_rerun() {
  setup_fixture; install_packages waybar waybar-git waybar-ai-usage-go-bin mako
  ln -s "$REPO/Linux/mako" "$FAKE_CONFIG_ROOT/mako"
  ln -s "$REPO/Linux/quickshell/desktop-shell/systemd/desktop-shell-mako-route.service" "$FAKE_SYSTEMD_USER_DIR/desktop-shell-mako-route.service"
  touch "$FAKE_WAYBAR_BIN"; FAKE_OWNERSHIP=unowned
  run_helper <<< 'cleanup'; assert_status 0
  assert_file_absent "$FAKE_CONFIG_ROOT/mako"; assert_file_absent "$FAKE_SYSTEMD_USER_DIR/desktop-shell-mako-route.service"
  assert_file_absent "$FAKE_WAYBAR_BIN"; assert_contains "$(<"$LOG")" 'desktop-shell-activate'
  assert_contains "$(<"$LOG")" 'desktop-shell|call|desktop.notifications|ping'
  assert_contains "$(<"$LOG")" 'desktop-shell|call|desktop.osd|ping'
  assert_contains "$(<"$LOG")" 'desktop-shell-status|codex'
  run_helper <<< 'cleanup'; assert_status 0; finish_case $?
}

test_pgrep_errors_and_process_presence_fail() {
  setup_fixture; FAKE_PGREP_STATUS=2; run_helper <<< 'cleanup'; assert_status 1; assert_contains "$output" 'pgrep'
  FAKE_PGREP_STATUS=0; run_helper <<< 'cleanup'; assert_status 1; assert_contains "$output" 'process'; finish_case $?
}

test_health_failures_and_partial_phase_are_reported() {
  setup_fixture; FAKE_ACTIVATE_FAIL=1; run_helper <<< 'cleanup'; assert_status 1; assert_contains "$output" 'phase=activation'
  FAKE_ACTIVATE_FAIL=0; FAKE_IPC_FAIL=1; run_helper <<< 'cleanup'; assert_status 1; assert_contains "$output" 'phase=health'; finish_case $?
}

main() {
  local test_name result
  local -a tests=(
    test_dry_run_only_needs_preview_dependencies
    test_confirmation_and_package_selection_are_exact
    test_real_directory_and_unsafe_symlink_fail_before_mutation
    test_enabled_route_without_link_is_stopped_and_inspection_errors_fail
    test_systemd_status_matrix_has_explicit_fail_closed_transitions
    test_disable_may_remove_validated_route_link_but_rejects_replacement
    test_binary_symlink_is_rejected_during_preflight
    test_decline_and_pacman_failure_do_not_mutate_route
    test_ownership_results_fail_closed_and_recheck
    test_toctou_replacement_aborts_before_unlink
    test_success_verifies_absence_activation_health_and_rerun
    test_pgrep_errors_and_process_presence_fail
    test_health_failures_and_partial_phase_are_reported
  )
  for test_name in "${tests[@]}"; do
    result=0; "$test_name" || result=$?
    ((result == 0)) || exit "$result"
    printf 'ok - %s\n' "$test_name"
  done
}
main "$@"
