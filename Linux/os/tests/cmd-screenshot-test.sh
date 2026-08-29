#!/usr/bin/env bash

set -Eeuo pipefail

repo_root=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../../.." && pwd)
screenshot="$repo_root/Linux/os/helpers/cmd-screenshot"
test_root=$(mktemp -d)
trap 'rm -rf "$test_root"' EXIT

bin_dir="$test_root/bin"
pictures_dir="$test_root/pictures"
editor_args="$test_root/editor-args"
notify_args="$test_root/notify-args"
mkdir -p "$bin_dir" "$pictures_dir"

cat >"$bin_dir/satty" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "$@" >"$TEST_EDITOR_ARGS"
EOF

cat >"$bin_dir/pkill" <<'EOF'
#!/usr/bin/env bash
exit 1
EOF

cat >"$bin_dir/hyprctl" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' '[]'
EOF

cat >"$bin_dir/jq" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' '0,0 100x100'
EOF

cat >"$bin_dir/grim" <<'EOF'
#!/usr/bin/env bash
output=${!#}
: >"$output"
EOF

cat >"$bin_dir/wl-copy" <<'EOF'
#!/usr/bin/env bash
cat >/dev/null
EOF

cat >"$bin_dir/notify-send" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "$@" >"$TEST_NOTIFY_ARGS"
EOF

cat >"$bin_dir/date" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' '2026-08-29_12-34-56'
EOF

chmod +x "$bin_dir"/*

existing="$pictures_dir/existing.png"
: >"$existing"
PATH="$bin_dir:$PATH" \
  TEST_EDITOR_ARGS="$editor_args" \
  SCREENSHOT_EDITOR=satty \
  "$screenshot" --edit-existing "$existing"

expected_editor_args=$'--filename\n'"$existing"$'\n--output-filename\n'"$existing"$'\n--actions-on-enter\nsave-to-clipboard\n--save-after-copy\n--copy-command\nwl-copy'
[[ $(<"$editor_args") == "$expected_editor_args" ]] || {
  printf '%s\n' 'edit-existing did not invoke Satty with the saved screenshot' >&2
  exit 1
}

status=0
PATH="$bin_dir:$PATH" TEST_EDITOR_ARGS="$editor_args" \
  "$screenshot" --edit-existing "$pictures_dir/missing.png" >/dev/null 2>&1 || status=$?
((status != 0)) || {
  printf '%s\n' 'edit-existing accepted a missing screenshot' >&2
  exit 1
}

rm -f "$editor_args"
PATH="$bin_dir:$PATH" \
  SCREENSHOT_DIR="$pictures_dir" \
  TEST_EDITOR_ARGS="$editor_args" \
  TEST_NOTIFY_ARGS="$notify_args" \
  "$screenshot" fullscreen

for ((attempt = 0; attempt < 50; attempt++)); do
  [[ -e $notify_args ]] && break
  sleep 0.01
done
[[ -e $notify_args ]] || {
  printf '%s\n' 'screenshot notification was not sent' >&2
  exit 1
}

captured="$pictures_dir/screenshot-2026-08-29_12-34-56.png"
expected_action_hint="--hint=string:x-desktop-shell-history-action:edit-screenshot"
expected_target_hint="--hint=string:x-desktop-shell-history-action-target:$captured"
mapfile -t notification <"$notify_args"
[[ " ${notification[*]} " == *" $expected_action_hint "* ]] || {
  printf '%s\n' 'screenshot notification omitted its durable action kind' >&2
  exit 1
}
[[ " ${notification[*]} " == *" $expected_target_hint "* ]] || {
  printf '%s\n' 'screenshot notification omitted its durable absolute target' >&2
  exit 1
}

printf '%s\n' 'cmd-screenshot-test: durable screenshot history action verified'
