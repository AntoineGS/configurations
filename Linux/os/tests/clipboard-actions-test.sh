#!/usr/bin/env bash
set -Eeuo pipefail

repo_root=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../../.." && pwd)
helpers=$repo_root/Linux/os/helpers
paste_text=$helpers/desktop-shell-clipboard-paste-text
paste_file=$helpers/desktop-shell-clipboard-paste-file
open_entry=$helpers/desktop-shell-clipboard-open
cleanup_images=$helpers/desktop-shell-clipboard-cleanup
test_root=$(mktemp -d)
bin=$test_root/bin
state=$test_root/state
state_root=$state/desktop-shell
image_dir=$state_root/clipboard-images
history_file=$state_root/clipboard-history.json
copy_out=$test_root/copied
copy_args=$test_root/copy.args
wtype_log=$test_root/wtype
open_log=$test_root/open
editor_path=$test_root/editor-path
editor_text=$test_root/editor-text
editor_mode=$test_root/editor-mode

trap 'rm -rf "$test_root"' EXIT

fail() {
  printf 'FAIL: %s\n' "$1" >&2
  exit 1
}

expect_failure() {
  if "$@" >/dev/null 2>&1; then
    fail "command unexpectedly succeeded: $*"
  fi
}

for helper in "$paste_text" "$paste_file" "$open_entry" "$cleanup_images"; do
  [[ -x $helper ]] || fail "clipboard helper is missing or not executable: $helper"
done

install -d -m 700 "$bin" "$state_root" "$image_dir"

cat >"$bin/wl-copy" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "$*" >"$CLIPBOARD_TEST_COPY_ARGS"
cat >"$CLIPBOARD_TEST_COPY_OUT"
EOF
cat >"$bin/wtype" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "$*" >"$CLIPBOARD_TEST_WTYPE_LOG"
EOF
cat >"$bin/xdg-open" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "$1" >"$CLIPBOARD_TEST_OPEN_LOG"
EOF
cat >"$bin/launch-editor" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "$1" >"$CLIPBOARD_TEST_EDITOR_PATH"
cat -- "$1" >"$CLIPBOARD_TEST_EDITOR_TEXT"
stat -c '%a' -- "$1" >"$CLIPBOARD_TEST_EDITOR_MODE"
EOF
cat >"$bin/sleep" <<'EOF'
#!/usr/bin/env bash
exit 0
EOF
chmod +x "$bin"/*

printf 'image-data' >"$image_dir/image.png"
chmod 600 "$image_dir/image.png"
jq -n --arg text $'line one\nline two\n' --arg image "$image_dir/image.png" '[
  {type:"text", text:"ignored"},
  {type:"text", text:$text},
  {type:"text", text:"https://example.com/docs"},
  {type:"image", mime:"image/png", path:$image}
]' >"$history_file"
chmod 600 "$history_file"

run_env=(
  XDG_STATE_HOME="$state"
  PATH="$bin:$PATH"
  CLIPBOARD_TEST_COPY_OUT="$copy_out"
  CLIPBOARD_TEST_COPY_ARGS="$copy_args"
  CLIPBOARD_TEST_WTYPE_LOG="$wtype_log"
  CLIPBOARD_TEST_OPEN_LOG="$open_log"
  CLIPBOARD_TEST_EDITOR_PATH="$editor_path"
  CLIPBOARD_TEST_EDITOR_TEXT="$editor_text"
  CLIPBOARD_TEST_EDITOR_MODE="$editor_mode"
)

env "${run_env[@]}" "$paste_text" --shift-insert --history-index 1
[[ $(<"$copy_out") == $'line one\nline two' ]] || fail "text paste changed multiline content"
[[ $(<"$wtype_log") == '-M shift -k Insert -m shift' ]] || fail "text paste did not use Shift+Insert"

rm -f "$wtype_log"
env "${run_env[@]}" "$paste_text" --copy-only --history-index 1
[[ ! -e $wtype_log ]] || fail "copy-only text triggered typing"

expect_failure env "${run_env[@]}" "$paste_text" --copy-only --history-index -1
expect_failure env "${run_env[@]}" "$paste_text" --copy-only --history-index 99
expect_failure env "${run_env[@]}" "$paste_text" --copy-only --history-index text

rm -f "$wtype_log"
env "${run_env[@]}" "$paste_file" --copy-only image/png "$image_dir/image.png"
[[ $(<"$copy_out") == image-data ]] || fail "image paste changed file bytes"
[[ $(<"$copy_args") == '--type image/png' ]] || fail "image paste lost MIME type"
[[ ! -e $wtype_log ]] || fail "copy-only image triggered typing"

outside=$test_root/outside.png
printf outside >"$outside"
symlink_image=$image_dir/symlink.png
ln -s "$outside" "$symlink_image"
expect_failure env "${run_env[@]}" "$paste_file" --copy-only image/png "$outside"
expect_failure env "${run_env[@]}" "$paste_file" --copy-only image/png "$symlink_image"

env "${run_env[@]}" "$open_entry" --history-index 2
[[ $(<"$open_log") == https://example.com/docs ]] || fail "URL entry was not opened"

env "${run_env[@]}" "$open_entry" --history-index 1
[[ $(<"$editor_text") == $'line one\nline two' ]] || fail "text entry was not opened with exact content"
[[ $(<"$editor_mode") == 600 ]] || fail "temporary editor file is not private"

env "${run_env[@]}" "$open_entry" --history-index 3
[[ $(<"$open_log") == "$image_dir/image.png" ]] || fail "image entry was not opened"

orphan=$image_dir/orphan.png
printf orphan >"$orphan"
chmod 600 "$orphan"
env "${run_env[@]}" "$cleanup_images" --remove "$image_dir/image.png"
[[ -e $image_dir/image.png ]] || fail "cleanup removed an image still referenced by history"
env "${run_env[@]}" "$cleanup_images" --remove "$orphan"
[[ ! -e $orphan ]] || fail "cleanup did not remove an orphan image"
expect_failure env "${run_env[@]}" "$cleanup_images" --remove "$outside"
expect_failure env "${run_env[@]}" "$cleanup_images" --remove "$symlink_image"

orphan=$image_dir/prune.png
printf prune >"$orphan"
chmod 600 "$orphan"
env "${run_env[@]}" "$cleanup_images" --prune
[[ ! -e $orphan && -e $image_dir/image.png ]] || fail "prune did not preserve only referenced images"

printf '{' >"$history_file"
protected=$image_dir/protected.png
printf protected >"$protected"
chmod 600 "$protected"
expect_failure env "${run_env[@]}" "$cleanup_images" --prune
[[ -e $protected ]] || fail "malformed history allowed image deletion"

printf 'PASS: clipboard actions and cleanup\n'
