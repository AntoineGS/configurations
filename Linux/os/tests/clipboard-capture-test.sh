#!/usr/bin/env bash
set -Eeuo pipefail

repo_root=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../../.." && pwd)
capture=$repo_root/Linux/quickshell/desktop-shell/plugins/clipboard/capture.sh
test_root=$(mktemp -d)
bin=$test_root/bin
state=$test_root/state

trap 'rm -rf "$test_root"' EXIT

fail() {
  printf 'FAIL: %s\n' "$1" >&2
  exit 1
}

[[ -x $capture ]] || fail "clipboard capture helper is missing or not executable: $capture"

install -d -m 700 "$bin"
cat >"$bin/wl-paste" <<'EOF'
#!/usr/bin/env bash
set -Eeuo pipefail

if [[ ${1-} == --list-types ]]; then
  printf '%b' "${WL_PASTE_TYPES:-text/plain\n}"
elif [[ ${1-} == --type && ${2-} == text ]]; then
  printf '%s' "${WL_PASTE_TEXT:-current text}"
fi
EOF
chmod +x "$bin/wl-paste"

install -d -m 700 "$state/desktop-shell" "$state/desktop-shell/clipboard-images"
printf '[]\n' >"$state/desktop-shell/clipboard-history.json"
chmod 644 "$state/desktop-shell/clipboard-history.json"
PATH="$bin:$PATH" XDG_STATE_HOME="$state" "$capture" --init
[[ $(stat -c '%a' "$state/desktop-shell/clipboard-history.json") == 600 ]] || fail "state initialization did not repair history permissions"

symlink_state=$test_root/symlink-state
install -d -m 700 "$symlink_state" "$test_root/state-target"
ln -s "$test_root/state-target" "$symlink_state/desktop-shell"
if PATH="$bin:$PATH" XDG_STATE_HOME="$symlink_state" "$capture" --init >/dev/null 2>&1; then
  fail "state initialization accepted a symlinked state root"
fi

capture_output=$(printf 'normal text' | PATH="$bin:$PATH" XDG_STATE_HOME="$state" "$capture" text)
[[ $capture_output == '{"type":"text","text":"normal text"}' ]] || fail "watched text was not captured"

capture_output=$(PATH="$bin:$PATH" XDG_STATE_HOME="$state" WL_PASTE_TEXT='current clipboard' "$capture")
[[ $capture_output == '{"type":"text","text":"current clipboard"}' ]] || fail "current text clipboard was not captured"

capture_output=$(printf '%s' 'Little endian 日本 😀' | iconv -f UTF-8 -t UTF-16LE | PATH="$bin:$PATH" XDG_STATE_HOME="$state" "$capture" text)
[[ $capture_output == '{"type":"text","text":"Little endian 日本 😀"}' ]] || fail "UTF-16LE text was not decoded"

capture_output=$(printf '%s' 'Big endian 日本 😀' | iconv -f UTF-8 -t UTF-16BE | PATH="$bin:$PATH" XDG_STATE_HOME="$state" "$capture" text)
[[ $capture_output == '{"type":"text","text":"Big endian 日本 😀"}' ]] || fail "UTF-16BE text was not decoded"

capture_output=$({ printf '\377\376'; printf '%s' 'BOM text' | iconv -f UTF-8 -t UTF-16LE; } | PATH="$bin:$PATH" XDG_STATE_HOME="$state" "$capture" text)
[[ $capture_output == '{"type":"text","text":"BOM text"}' ]] || fail "BOM-tagged UTF-16 text was not decoded"

capture_output=$(printf 'secret' | CLIPBOARD_STATE=sensitive PATH="$bin:$PATH" XDG_STATE_HOME="$state" "$capture" text)
[[ -z $capture_output ]] || fail "sensitive watched text was captured"

capture_output=$(CLIPBOARD_STATE=sensitive PATH="$bin:$PATH" XDG_STATE_HOME="$state" "$capture")
[[ -z $capture_output ]] || fail "sensitive current clipboard was captured"

capture_output=$(WL_PASTE_TYPES=$'text/plain\nx-kde-passwordManagerHint\n' PATH="$bin:$PATH" XDG_STATE_HOME="$state" "$capture")
[[ -z $capture_output ]] || fail "password-manager clipboard was captured"

capture_output=$(printf 'png-data' | PATH="$bin:$PATH" XDG_STATE_HOME="$state" "$capture" image/png)
image_path=$(jq -er '.path' <<<"$capture_output")
jq -e '.type == "image" and .mime == "image/png" and (.capturedAt | type == "string")' <<<"$capture_output" >/dev/null || fail "PNG metadata is invalid"
[[ -f $image_path && ! -L $image_path && $(<"$image_path") == png-data ]] || fail "PNG bytes were not stored"
[[ $(stat -c '%a' "$state/desktop-shell") == 700 ]] || fail "clipboard state directory is not private"
[[ $(stat -c '%a' "$state/desktop-shell/clipboard-images") == 700 ]] || fail "clipboard image directory is not private"
[[ $(stat -c '%a' "$image_path") == 600 ]] || fail "clipboard image is not private"

duplicate_output=$(printf 'png-data' | PATH="$bin:$PATH" XDG_STATE_HOME="$state" "$capture" image/png)
[[ $(jq -er '.path' <<<"$duplicate_output") == "$image_path" ]] || fail "equal images were not deduplicated"

generic_output=$(printf 'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAusB9Y9Zl1sAAAAASUVORK5CYII=' \
  | base64 -d \
  | PATH="$bin:$PATH" XDG_STATE_HOME="$state" "$capture" image)
jq -e '.type == "image" and .mime == "image/png" and (.path | endswith(".png"))' <<<"$generic_output" >/dev/null \
  || fail "generic image capture did not detect PNG content"

jpeg_output=$(printf 'jpeg-data' | PATH="$bin:$PATH" XDG_STATE_HOME="$state" "$capture" image/jpeg)
[[ $(jq -er '.path' <<<"$jpeg_output") == *.jpg ]] || fail "JPEG extension was not normalized"

before_count=$(find "$state/desktop-shell/clipboard-images" -type f | wc -l)
empty_output=$(printf '' | PATH="$bin:$PATH" XDG_STATE_HOME="$state" "$capture" image/png)
after_count=$(find "$state/desktop-shell/clipboard-images" -type f | wc -l)
[[ -z $empty_output && $before_count -eq $after_count ]] || fail "empty image created state"

unsupported_output=$(printf 'data' | PATH="$bin:$PATH" XDG_STATE_HOME="$state" "$capture" application/octet-stream)
[[ -z $unsupported_output ]] || fail "unsupported MIME type was captured"

printf 'PASS: secure clipboard capture\n'
