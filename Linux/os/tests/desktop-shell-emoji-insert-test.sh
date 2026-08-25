#!/usr/bin/env bash
set -Eeuo pipefail

repo_root=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../../.." && pwd)
helper=$repo_root/Linux/os/helpers/desktop-shell-emoji-insert
test_root=$(mktemp -d)
bin=$test_root/bin
emoji_out=$test_root/emoji
paste_out=$test_root/pasted
primary_out=$test_root/primary
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
if [[ " $* " == *" --foreground "* ]]; then
  trap 'rm -f "$EMOJI_TEST_OUT"; exit 0' TERM
  while true; do :; done
fi
EOF
cat >"$bin/wtype" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "$*" >"$WTYPE_TEST_OUT"
case $* in
  '-M ctrl -M shift -k v -m shift -m ctrl') source=$EMOJI_TEST_OUT ;;
  '-M shift -k Insert -m shift') source=$EMOJI_TEST_PRIMARY ;;
  *) exit 0 ;;
esac
(
  /usr/bin/sleep 0.1
  [[ ! -f $source ]] || cat -- "$source" >"$EMOJI_TEST_PASTE_OUT"
) &
EOF
cat >"$bin/sleep" <<'EOF'
#!/usr/bin/env bash
exit 0
EOF
chmod +x "$bin"/*
printf 'https://github.com/ilyamiro/serpantinum' >"$primary_out"

EMOJI_TEST_OUT=$emoji_out EMOJI_TEST_PASTE_OUT=$paste_out EMOJI_TEST_PRIMARY=$primary_out \
  WTYPE_TEST_OUT=$wtype_out PATH="$bin:$PATH" "$helper" '👨‍💻'
/usr/bin/sleep 0.2
[[ -f $paste_out && $(<"$paste_out") == '👨‍💻' ]] \
  || fail "emoji was unavailable when the target requested clipboard data"
[[ $(<"$emoji_out.args") == '--type text/plain --sensitive' ]] || fail "clipboard flags are not sensitive"
[[ $(<"$wtype_out") == '-M ctrl -M shift -k v -m shift -m ctrl' ]] \
  || fail "emoji helper did not use the terminal-compatible clipboard shortcut"

rm -f "$emoji_out" "$emoji_out.args" "$paste_out" "$wtype_out"
EMOJI_TEST_OUT=$emoji_out EMOJI_TEST_PASTE_OUT=$paste_out EMOJI_TEST_PRIMARY=$primary_out \
  WTYPE_TEST_OUT=$wtype_out PATH="$bin:$PATH" "$helper" ''
[[ ! -e $emoji_out && ! -e $wtype_out ]] || fail "empty emoji triggered clipboard or typing"

if EMOJI_TEST_OUT=$emoji_out EMOJI_TEST_PASTE_OUT=$paste_out EMOJI_TEST_PRIMARY=$primary_out \
  WTYPE_TEST_OUT=$wtype_out PATH="$bin:$PATH" "$helper" one two >/dev/null 2>&1; then
  fail "extra emoji arguments were accepted"
fi

printf 'PASS: emoji insertion\n'
