#!/usr/bin/env bash
set -Eeuo pipefail

script_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)
readonly ACTION_HELPER="${script_dir%/tests}/helpers/desktop-connectivity-action"
test_root=$(mktemp -d)
readonly BIN_DIR="$test_root/bin"
readonly CAPTURE_DIR="$test_root/capture"
trap 'rm -rf -- "$test_root"' EXIT

fail() {
  printf 'FAIL: %s\n' "$1" >&2
  exit 1
}

[[ -x $ACTION_HELPER ]] || fail 'desktop-connectivity-action is missing or not executable'
mkdir -p -- "$BIN_DIR" "$CAPTURE_DIR"

cat >"$BIN_DIR/iwctl" <<'EOF'
#!/usr/bin/env bash
set -Eeuo pipefail
printf '%s\n' "${0##*/}" >"$CAPTURE_DIR/executable"
printf '%s\n' "$@" >"$CAPTURE_DIR/argv"
if [[ ${1:-} == station && ${3:-} == connect ]]; then
  cat >"$CAPTURE_DIR/stdin"
fi
EOF

cat >"$BIN_DIR/resolvectl" <<'EOF'
#!/usr/bin/env bash
set -Eeuo pipefail
printf '%s\n' "${0##*/}" >"$CAPTURE_DIR/executable"
printf '%s\n' "$@" >"$CAPTURE_DIR/argv"
EOF
chmod 0755 -- "$BIN_DIR/iwctl" "$BIN_DIR/resolvectl"

run_action() {
  local capture_stdin=false
  if [[ ${1:-} == --capture-stdin ]]; then
    capture_stdin=true
    shift
  fi

  : >"$CAPTURE_DIR/argv"
  : >"$CAPTURE_DIR/executable"
  : >"$CAPTURE_DIR/stdin"
  if [[ $capture_stdin == true ]]; then
    env PATH="$BIN_DIR:$PATH" CAPTURE_DIR="$CAPTURE_DIR" "$@"
  else
    env PATH="$BIN_DIR:$PATH" CAPTURE_DIR="$CAPTURE_DIR" "$@" < /dev/null
  fi
}

assert_route() {
  local -n expected_args=$1
  local expected_executable=$2
  shift 2
  if ! run_action "$@"; then
    fail "command failed for $*"
  fi
  [[ $(<"$CAPTURE_DIR/executable") == "$expected_executable" ]] ||
    fail "wrong executable for $*: $(<"$CAPTURE_DIR/executable")"
  printf '%s\n' "${expected_args[@]}" >"$CAPTURE_DIR/expected"
  cmp -s "$CAPTURE_DIR/expected" "$CAPTURE_DIR/argv" || {
    printf 'unexpected argv:\n' >&2
    printf '%s' "$(<"$CAPTURE_DIR/argv")" >&2
    fail "argv mismatch for $*"
  }
}

expected=(station wlan0 scan)
assert_route expected iwctl "$ACTION_HELPER" network scan wlan0

expected=(station wlan0 connect Cafe)
printf 'correct horse battery staple\n' |
  run_action --capture-stdin "$ACTION_HELPER" network connect wlan0 Cafe || fail 'connect command failed'
[[ $(<"$CAPTURE_DIR/executable") == iwctl ]] || fail 'connect used the wrong executable'
[[ $(<"$CAPTURE_DIR/stdin") == 'correct horse battery staple' ]] || fail 'passphrase was not sent on stdin'
! grep -Fqx 'correct horse battery staple' "$CAPTURE_DIR/argv" || fail 'passphrase appeared in argv'
printf '%s\n' "${expected[@]}" >"$CAPTURE_DIR/expected"
cmp -s "$CAPTURE_DIR/expected" "$CAPTURE_DIR/argv" || fail 'connect argv mismatch'

expected=(station wlan0 disconnect)
assert_route expected iwctl "$ACTION_HELPER" network disconnect wlan0

expected=(known-networks Cafe forget)
assert_route expected iwctl "$ACTION_HELPER" network forget Cafe

expected=(revert wlan0)
assert_route expected resolvectl "$ACTION_HELPER" network set-dns wlan0 DHCP

expected=(dns wlan0 1.1.1.1 1.0.0.1 2606:4700:4700::1111 2606:4700:4700::1001)
assert_route expected resolvectl "$ACTION_HELPER" network set-dns wlan0 Cloudflare

expected=(dns wlan0 8.8.8.8 8.8.4.4 2001:4860:4860::8888 2001:4860:4860::8844)
assert_route expected resolvectl "$ACTION_HELPER" network set-dns wlan0 Google

if run_action "$ACTION_HELPER" network scan 'bad device' >/dev/null 2>&1; then
  fail 'invalid device was accepted'
elif (($? != 2)); then
  fail 'invalid device did not exit 2'
fi

if run_action "$ACTION_HELPER" network set-dns wlan0 Invalid >/dev/null 2>&1; then
  fail 'invalid provider was accepted'
elif (($? != 2)); then
  fail 'invalid provider did not exit 2'
fi

printf 'desktop connectivity network tests passed\n'
