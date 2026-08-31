#!/usr/bin/env bash
set -Eeuo pipefail

test_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
readonly test_dir
installer=$test_dir/../install-outlook-preview
readonly installer
expected_package_name=outlook-for-linux
readonly expected_package_name
expected_version=2.0.0_test.9-1
readonly expected_version
expected_url=https://github.com/AntoineGS/outlook-for-linux/releases/download/temp-build-9/outlook-for-linux-2.0.0-test.9-x86_64.pkg.tar.zst
readonly expected_url
expected_sha256=f14bab7563b8234a947e921b2e1f1bbf36d5b4e5c5843a2d4a005fe00fee8155
readonly expected_sha256
tmpdir=$(mktemp -d)
readonly tmpdir
download_dir=$tmpdir/packages
readonly download_dir
mkdir -p "$tmpdir/bin" "$download_dir"
trap 'rm -rf -- "$tmpdir"' EXIT

fail() { printf 'FAIL: %s\n' "$*" >&2; exit 1; }

state=$tmpdir/state
printf '%s\n' "$expected_version" >"$state"

cat >"$tmpdir/bin/pacman" <<'EOF'
#!/usr/bin/env bash
set -Eeuo pipefail
printf '%s\n' "$*" >>"$FAKE_PACMAN_CALLS"
if [[ $# == 2 && $1 == -Q && $2 == "$EXPECTED_PACKAGE_NAME" ]]; then
  [[ -s $FAKE_STATE ]] || exit 1
  printf '%s %s\n' "$EXPECTED_PACKAGE_NAME" "$(<"$FAKE_STATE")"
elif [[ $# == 4 && $1 == --noconfirm && $2 == -U && $3 == -- ]]; then
  [[ -f ${4:-} ]] || exit 2
  [[ ${4:-} == "$(<"$FAKE_CURL_OUTPUT")" ]] || exit 2
  printf '%s\n' "$FAKE_INSTALL_VERSION" >"$FAKE_STATE"
  printf '%s\n' "$4" >"$FAKE_INSTALL_CALL"
else
  exit 2
fi
EOF

cat >"$tmpdir/bin/uname" <<'EOF'
#!/usr/bin/env bash
set -Eeuo pipefail
printf '%s\n' "$*" >"$FAKE_UNAME_CALL"
[[ $# == 1 && $1 == -m ]] || exit 2
printf '%s\n' "${FAKE_ARCH:-x86_64}"
EOF

cat >"$tmpdir/bin/id" <<'EOF'
#!/usr/bin/env bash
set -Eeuo pipefail
printf '%s\n' "$*" >"$FAKE_ID_CALL"
[[ $# == 1 && $1 == -u ]] || exit 2
printf '%s\n' "${FAKE_UID:-0}"
EOF

cat >"$tmpdir/bin/curl" <<'EOF'
#!/usr/bin/env bash
set -Eeuo pipefail
printf '%s\n' "$*" >"$FAKE_CURL_CALL"
[[ $# == 12 ]] || exit 2
[[ $1 == --proto && $2 == '=https' && $3 == --tlsv1.2 && $4 == --fail ]] || exit 2
[[ $5 == --location && $6 == --silent && $7 == --show-error ]] || exit 2
[[ $8 == --retry && $9 == 3 && ${10} == --output ]] || exit 2
[[ -n ${11:-} && ${12:-} == "$EXPECTED_URL" ]] || exit 2
[[ ${11:-} == "$TMPDIR"/* ]] || exit 2
printf '%s\n' "$*" >"$FAKE_CURL_CALL"
printf '%s\n' "${11}" >"$FAKE_CURL_OUTPUT"
printf 'test package\n' >"${11}"
EOF

cat >"$tmpdir/bin/sha256sum" <<'EOF'
#!/usr/bin/env bash
set -Eeuo pipefail
printf '%s\n' "$*" >"$FAKE_SHA_ARGS"
[[ $# == 3 && $1 == --check && $2 == --status && $3 == - ]] || exit 2
actual=$(cat)
printf '%s\n' "$actual" >"$FAKE_SHA_INPUT"
expected="$EXPECTED_SHA256  $(<"$FAKE_CURL_OUTPUT")"
[[ $actual == "$expected" ]] || exit 1
[[ ${FAKE_SHA_RESULT:-success} == success ]]
EOF

chmod +x "$tmpdir/bin/"*
export PATH="$tmpdir/bin:$PATH"
export TMPDIR="$download_dir"
export FAKE_STATE="$state"
export FAKE_PACMAN_CALLS="$tmpdir/pacman-calls"
export FAKE_INSTALL_CALL="$tmpdir/install-call"
export FAKE_CURL_CALL="$tmpdir/curl-call"
export FAKE_CURL_OUTPUT="$tmpdir/curl-output"
export FAKE_SHA_INPUT="$tmpdir/sha-input"
export FAKE_SHA_ARGS="$tmpdir/sha-args"
export FAKE_UNAME_CALL="$tmpdir/uname-call"
export FAKE_ID_CALL="$tmpdir/id-call"
export EXPECTED_PACKAGE_NAME="$expected_package_name"
export EXPECTED_SHA256="$expected_sha256"
export EXPECTED_URL="$expected_url"
export FAKE_INSTALL_VERSION="$expected_version"

reset_state() {
  printf '%s\n' "$expected_version" >"$FAKE_STATE"
  rm -f -- "$FAKE_PACMAN_CALLS" "$FAKE_INSTALL_CALL" "$FAKE_CURL_CALL" \
    "$FAKE_CURL_OUTPUT" "$FAKE_SHA_INPUT" "$FAKE_SHA_ARGS" "$FAKE_UNAME_CALL" \
    "$FAKE_ID_CALL" "$TMPDIR"/outlook-for-linux.*.pkg.tar.zst
}

assert_no_download_or_install() {
  [[ ! -e $FAKE_CURL_CALL ]] || fail 'curl ran unexpectedly'
  [[ ! -e $FAKE_INSTALL_CALL ]] || fail 'pacman installation ran unexpectedly'
  if compgen -G "$TMPDIR/outlook-for-linux.*.pkg.tar.zst" >/dev/null; then
    fail 'temporary package remained'
  fi
}

assert_no_install_or_temp() {
  [[ ! -e $FAKE_INSTALL_CALL ]] || fail 'pacman installation ran unexpectedly'
  if compgen -G "$TMPDIR/outlook-for-linux.*.pkg.tar.zst" >/dev/null; then
    fail 'temporary package remained'
  fi
}

reset_state
"$installer" --check || fail '--check rejected the exact preview version'
[[ ! -e $FAKE_CURL_CALL ]] || fail '--check invoked curl'
[[ ! -e $FAKE_INSTALL_CALL ]] || fail '--check invoked pacman installation'
[[ $(<"$FAKE_PACMAN_CALLS") == "-Q $expected_package_name" ]] || fail '--check did not perform only the exact package query'
if compgen -G "$TMPDIR/outlook-for-linux.*.pkg.tar.zst" >/dev/null; then
  fail '--check created a temporary package'
fi

printf '2.0.0-1\n' >"$FAKE_STATE"
if "$installer" --check; then fail '--check accepted the stable version'; fi

reset_state
if FAKE_ARCH=aarch64 "$installer" --apply >"$tmpdir/architecture-output" 2>&1; then
  fail '--apply accepted aarch64'
fi
[[ $(<"$tmpdir/architecture-output") == 'Outlook preview installation requires x86_64' ]] || fail 'missing architecture error'
assert_no_download_or_install

reset_state
if FAKE_UID=1000 "$installer" --apply >"$tmpdir/root-output" 2>&1; then
  fail '--apply accepted non-root execution'
fi
[[ $(<"$tmpdir/root-output") == 'Outlook preview installation requires root' ]] || fail 'missing root error'
assert_no_download_or_install

reset_state
if "$installer" --check unexpected >"$tmpdir/check-arguments-output" 2>&1; then
  fail '--check accepted an unexpected argument'
fi
[[ $(<"$tmpdir/check-arguments-output") == 'Usage: install-outlook-preview --check|--apply' ]] || fail 'missing check usage error'
[[ ! -e $FAKE_PACMAN_CALLS ]] || fail '--check with unexpected argument queried pacman'
assert_no_download_or_install

reset_state
if "$installer" --apply unexpected >"$tmpdir/apply-arguments-output" 2>&1; then
  fail '--apply accepted an unexpected argument'
fi
[[ $(<"$tmpdir/apply-arguments-output") == 'Usage: install-outlook-preview --check|--apply' ]] || fail 'missing apply usage error'
[[ ! -e $FAKE_PACMAN_CALLS ]] || fail '--apply with unexpected argument queried pacman'
assert_no_download_or_install

reset_state
if FAKE_SHA_RESULT=failure "$installer" --apply >"$tmpdir/digest-output" 2>&1; then
  fail 'digest failure was accepted'
fi
[[ $(<"$tmpdir/digest-output") == 'Outlook preview package checksum verification failed' ]] || fail 'missing checksum error'
[[ -e $FAKE_CURL_CALL ]] || fail 'curl did not run before digest verification'
assert_no_install_or_temp

reset_state
if FAKE_INSTALL_VERSION=wrong-version "$installer" --apply >"$tmpdir/post-install-output" 2>&1; then
  fail 'wrong post-install state was accepted'
fi
[[ -e $FAKE_INSTALL_CALL ]] || fail 'pacman installation did not run'
[[ $(<"$FAKE_STATE") == wrong-version ]] || fail 'wrong post-install state was not recorded'
if compgen -G "$TMPDIR/outlook-for-linux.*.pkg.tar.zst" >/dev/null; then
  fail 'temporary package remained after post-install failure'
fi

reset_state
"$installer" --apply || fail 'successful apply failed'
[[ -e $FAKE_INSTALL_CALL ]] || fail 'pacman installation was not invoked'
[[ $(<"$FAKE_STATE") == "$expected_version" ]] || fail 'successful apply installed the wrong version'
[[ $(<"$FAKE_SHA_ARGS") == '--check --status -' ]] || fail 'sha256sum arguments differ'
[[ $(<"$FAKE_UNAME_CALL") == '-m' ]] || fail 'uname arguments differ'
[[ $(<"$FAKE_ID_CALL") == '-u' ]] || fail 'id arguments differ'
if compgen -G "$TMPDIR/outlook-for-linux.*.pkg.tar.zst" >/dev/null; then
  fail 'temporary package remained after successful apply'
fi
"$installer" --check || fail 'post-install check failed'

if "$installer" invalid >/dev/null 2>&1; then fail 'invalid operation was accepted'; fi
