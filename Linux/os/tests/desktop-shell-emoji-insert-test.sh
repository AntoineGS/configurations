#!/usr/bin/env bash
set -Eeuo pipefail

repo_root=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../../.." && pwd)
helper=$repo_root/Linux/os/helpers/desktop-shell-emoji-insert
test_root=$(mktemp -d)
bin=$test_root/bin
emoji_out=$test_root/emoji
wtype_out=$test_root/wtype

trap 'rm -rf "$test_root"' EXIT

fail() {
  printf 'FAIL: %s\n' "$1" >&2
  exit 1
}

[[ -x $helper ]] || fail "emoji insert helper is missing or not executable: $helper"

install -d -m 700 "$bin"
cat >"$bin/wl-copy" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "$*" >"$EMOJI_TEST_OUT.args"
cat >"$EMOJI_TEST_OUT"
EOF
cat >"$bin/wtype" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "$*" >"$WTYPE_TEST_OUT"
EOF
cat >"$bin/sleep" <<'EOF'
#!/usr/bin/env bash
exit 0
EOF
chmod +x "$bin"/*

EMOJI_TEST_OUT=$emoji_out WTYPE_TEST_OUT=$wtype_out PATH="$bin:$PATH" "$helper" '👨‍💻'
[[ $(<"$emoji_out") == '👨‍💻' ]] || fail "emoji payload changed"
[[ $(<"$emoji_out.args") == '--type text/plain --sensitive --foreground' ]] || fail "clipboard flags are not sensitive and transient"
[[ $(<"$wtype_out") == '-M shift -k Insert -m shift' ]] || fail "emoji helper did not use Shift+Insert"

rm -f "$emoji_out" "$emoji_out.args" "$wtype_out"
EMOJI_TEST_OUT=$emoji_out WTYPE_TEST_OUT=$wtype_out PATH="$bin:$PATH" "$helper" ''
[[ ! -e $emoji_out && ! -e $wtype_out ]] || fail "empty emoji triggered clipboard or typing"

if EMOJI_TEST_OUT=$emoji_out WTYPE_TEST_OUT=$wtype_out PATH="$bin:$PATH" "$helper" one two >/dev/null 2>&1; then
  fail "extra emoji arguments were accepted"
fi

printf 'PASS: transient emoji insertion\n'
