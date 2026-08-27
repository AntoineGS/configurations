#!/usr/bin/env bash
set -Eeuo pipefail

repo_root=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../../.." && pwd)
edit_helper=$repo_root/Linux/os/helpers/desktop-shell-edit
test_root=$(mktemp -d)
bin=$test_root/bin
home=$test_root/home
shell_root=$home/.config/quickshell/desktop-shell
log=$test_root/editor.log

trap 'rm -rf "$test_root"' EXIT

fail() {
  printf 'FAIL: %s\n' "$1" >&2
  exit 1
}

[[ -x $edit_helper ]] || fail "desktop-shell-edit is missing or not executable"
mkdir -p -- \
  "$bin" \
  "$home/.local/share/applications" \
  "$test_root/common-applications" \
  "$shell_root/config" \
  "$shell_root/plugins/panels/audio"
touch -- \
  "$shell_root/config/menu.jsonc" \
  "$shell_root/config/shell.json" \
  "$shell_root/plugins/panels/audio/Panel.qml" \
  "$home/.local/share/applications/org.example.Editor.desktop" \
  "$home/.local/share/applications/ARC Raiders.desktop" \
  "$test_root/common-applications/Docker.desktop"
ln -s -- "$test_root/common-applications" "$home/.local/share/applications/common"

cat >"$bin/launch-editor" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "$1" >"$EDITOR_LOG"
EOF

cat >"$bin/cmd-screenshot" <<'EOF'
#!/usr/bin/env bash
exit 0
EOF

cat >"$bin/desktop-shell-action" <<'EOF'
#!/usr/bin/env bash
exit 0
EOF

cat >"$bin/desktop-shell" <<'EOF'
#!/usr/bin/env bash
exit 0
EOF

chmod +x \
  "$bin/launch-editor" \
  "$bin/cmd-screenshot" \
  "$bin/desktop-shell-action" \
  "$bin/desktop-shell"

assert_edit() {
  local expected=$1
  shift
  rm -f -- "$log"
  EDITOR_LOG=$log \
    HOME=$home \
    XDG_DATA_HOME=$home/.local/share \
    XDG_DATA_DIRS=$test_root/system-share \
    DESKTOP_SHELL_ROOT=$shell_root \
    PATH="$bin:/usr/bin:/bin" \
    "$edit_helper" "$@"
  [[ -f $log ]] || fail "$* did not launch the editor"
  [[ $(<"$log") == "$expected" ]] \
    || fail "$* opened '$(<"$log")' instead of '$expected'"
}

assert_edit "$shell_root/config/menu.jsonc" menu trigger
assert_edit "$shell_root/config/shell.json" action setup.shell-config
assert_edit "$shell_root/plugins/panels/audio/Panel.qml" action setup.audio
assert_edit "$bin/cmd-screenshot" action trigger.screenshot
assert_edit "$bin/desktop-shell" action update.shell-reload
assert_edit "$bin/desktop-shell-action" action system.suspend
assert_edit "$home/.local/share/applications/org.example.Editor.desktop" \
  application org.example.Editor
assert_edit "$home/.local/share/applications/ARC Raiders.desktop" \
  application 'ARC Raiders'
assert_edit "$home/.local/share/applications/common/Docker.desktop" \
  application common-Docker

for invalid in \
  'unknown trigger' \
  'action ../../etc/passwd' \
  'application ../../etc/passwd'; do
  read -r kind id <<<"$invalid"
  rm -f -- "$log"
  if EDITOR_LOG=$log \
    HOME=$home \
    DESKTOP_SHELL_ROOT=$shell_root \
    PATH="$bin:/usr/bin:/bin" \
    "$edit_helper" "$kind" "$id" >/dev/null 2>&1; then
    fail "$invalid unexpectedly succeeded"
  fi
  [[ ! -e $log ]] || fail "$invalid launched the editor"
done

printf 'PASS: desktop shell edit target dispatch\n'
