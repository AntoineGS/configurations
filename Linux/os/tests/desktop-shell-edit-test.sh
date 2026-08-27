#!/usr/bin/env bash
set -Eeuo pipefail

repo_root=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../../.." && pwd)
edit_helper=$repo_root/Linux/os/helpers/desktop-shell-edit
test_root=$(mktemp -d)
bin=$test_root/bin
home=$test_root/home
shell_root=$home/.config/quickshell/desktop-shell
log=$test_root/open.log

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
  "$test_root/plugins/io.yasino55.omarchy-plugin-marketplace" \
  "$shell_root/config" \
  "$shell_root/plugins/menu" \
  "$shell_root/plugins/panels/audio"
touch -- \
  "$shell_root/config/menu.jsonc" \
  "$shell_root/config/shell.json" \
  "$shell_root/plugins/menu/Menu.qml" \
  "$shell_root/plugins/panels/audio/Panel.qml"
printf '%s\n' '{"entryPoints":{"barWidget":"Panel.qml"}}' \
  >"$shell_root/plugins/panels/audio/manifest.json"
printf '%s\n' '{"entryPoints":{"service":"Marketplace.qml"}}' \
  >"$test_root/plugins/io.yasino55.omarchy-plugin-marketplace/manifest.json"
touch -- "$test_root/plugins/io.yasino55.omarchy-plugin-marketplace/Marketplace.qml"
ln -s -- "$test_root/common-applications" "$home/.local/share/applications/common"

cat >"$home/.local/share/applications/ARC Raiders.desktop" <<'EOF'
[Desktop Entry]
Name=ARC Raiders
Exec=env DESKTOP_LAUNCH=1 xdg-terminal-exec --app-id=TUI.tile -e pkg-install
EOF

cat >"$home/.local/share/applications/Screenshot.desktop" <<'EOF'
[Desktop Entry]
Name=Screenshot Tool
Exec=cmd-screenshot
EOF

cat >"$home/.local/share/applications/Argument.desktop" <<'EOF'
[Desktop Entry]
Name=Executable Argument
Exec=cmd-screenshot pkg-install
EOF

cat >"$home/.local/share/applications/Quoted.desktop" <<EOF
[Desktop Entry]
Name=Quoted Executable
Exec="$bin/App Runner" --mode edit
EOF

cat >"$home/.local/share/applications/EnvUnset.desktop" <<'EOF'
[Desktop Entry]
Name=Environment Wrapper
Exec=env -u UNUSED cmd-screenshot
EOF

cat >"$home/.local/share/applications/EnvSeparator.desktop" <<'EOF'
[Desktop Entry]
Name=Environment Separator
Exec=env -- SCREENSHOT_MODE=menu cmd-screenshot
EOF

printf '%s\n' \
  '[Desktop Entry]' \
  'Name=Escaped Executable' \
  "Exec=$bin/Escaped\\sRunner" \
  >"$home/.local/share/applications/Escaped.desktop"

cat >"$test_root/common-applications/Docker.desktop" <<'EOF'
[Desktop Entry]
Name=Docker
Exec=docker
EOF

cat >"$bin/launch-editor" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "${0##*/}" "$@" >"$OPEN_LOG"
EOF

cat >"$bin/launch-tui-large" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "${0##*/}" "$@" >"$OPEN_LOG"
EOF

for command in cmd-screenshot desktop-shell desktop-shell-action pkg-install 'App Runner' 'Escaped Runner'; do
  cat >"$bin/$command" <<'EOF'
#!/usr/bin/env bash
exit 0
EOF
done

chmod +x \
  "$bin/launch-editor" \
  "$bin/launch-tui-large" \
  "$bin/cmd-screenshot" \
  "$bin/desktop-shell" \
  "$bin/desktop-shell-action" \
  "$bin/pkg-install" \
  "$bin/App Runner" \
  "$bin/Escaped Runner"

run_helper() {
  OPEN_LOG=$log \
    HOME=$home \
    XDG_DATA_HOME=$home/.local/share \
    XDG_DATA_DIRS=$test_root/system-share \
    DESKTOP_SHELL_ROOT=$shell_root \
    DESKTOP_SHELL_PLUGINS_DIR=$test_root/plugins \
    PATH="$bin:/usr/bin:/bin" \
    "$edit_helper" "$@"
}

list_contexts() {
  run_helper list "$1" "$2" | jq -s .
}

assert_context() {
  local contexts=$1
  local key=$2
  local label=$3
  jq -e --arg key "$key" --arg label "$label" \
    'any(.[]; .key == $key and .label == $label)' <<<"$contexts" >/dev/null \
    || fail "missing context '$key' with label '$label'"
}

assert_context_count() {
  local contexts=$1
  local expected=$2
  jq -e --argjson expected "$expected" 'length == $expected' <<<"$contexts" >/dev/null \
    || fail "context list did not contain exactly $expected distinct targets"
}

assert_open() {
  local expected=$1
  shift
  rm -f -- "$log"
  run_helper open "$@"
  [[ -f $log ]] || fail "$* did not launch a context target"
  [[ $(<"$log") == "$expected" ]] \
    || fail "$* launched '$(<"$log")' instead of '$expected'"
}

menu_contexts=$(list_contexts menu trigger)
assert_context "$menu_contexts" menu-definition 'Edit menu definition'
assert_context "$menu_contexts" menu-implementation 'Edit menu implementation'
assert_context "$menu_contexts" menu-config-location 'Browse menu config location'
assert_context "$menu_contexts" menu-implementation-location 'Browse menu implementation location'
assert_context_count "$menu_contexts" 4

script_contexts=$(list_contexts action trigger.screenshot)
screenshot_hash=$(printf '%s' Screenshot | sha256sum)
screenshot_hash=${screenshot_hash%% *}
screenshot_entry_key=desktop-entry-$screenshot_hash
screenshot_location_key=desktop-entry-location-$screenshot_hash
assert_context "$script_contexts" source 'Edit script'
assert_context "$script_contexts" source-location 'Browse script location'
assert_context "$script_contexts" dispatcher 'Edit action dispatcher'
assert_context "$script_contexts" menu-definition 'Edit menu definition'
assert_context "$script_contexts" "$screenshot_entry_key" 'Edit desktop entry: Screenshot Tool'
assert_context "$script_contexts" "$screenshot_location_key" 'Browse desktop entry: Screenshot Tool'
assert_context_count "$script_contexts" 12

qml_contexts=$(list_contexts action setup.audio)
assert_context "$qml_contexts" source 'Edit Quickshell entry'
assert_context "$qml_contexts" source-location 'Browse Quickshell location'
assert_context "$qml_contexts" plugin-manifest 'Edit plugin manifest'
assert_context "$qml_contexts" dispatcher 'Edit action dispatcher'
assert_context "$qml_contexts" menu-definition 'Edit menu definition'
assert_context_count "$qml_contexts" 5

marketplace_contexts=$(list_contexts action install.plugin-marketplace)
assert_context "$marketplace_contexts" source 'Edit Quickshell entry'
assert_context "$marketplace_contexts" plugin-manifest 'Edit plugin manifest'
assert_context_count "$marketplace_contexts" 5

application_contexts=$(list_contexts application 'ARC Raiders')
assert_context "$application_contexts" desktop-entry 'Edit desktop entry'
assert_context "$application_contexts" desktop-entry-location 'Browse desktop entry location'
assert_context "$application_contexts" executable-location 'Browse executable location'
assert_context_count "$application_contexts" 3

argument_contexts=$(list_contexts application Argument)
assert_context "$argument_contexts" executable-location 'Browse executable location'
assert_context_count "$argument_contexts" 3

quoted_contexts=$(list_contexts application Quoted)
assert_context "$quoted_contexts" executable-location 'Browse executable location'
assert_context_count "$quoted_contexts" 3

env_contexts=$(list_contexts application EnvUnset)
assert_context "$env_contexts" executable-location 'Browse executable location'
assert_context_count "$env_contexts" 3

env_separator_contexts=$(list_contexts application EnvSeparator)
assert_context "$env_separator_contexts" executable-location 'Browse executable location'
assert_context_count "$env_separator_contexts" 3

escaped_contexts=$(list_contexts application Escaped)
assert_context "$escaped_contexts" executable-location 'Browse executable location'
assert_context_count "$escaped_contexts" 3

system_contexts=$(list_contexts action system.suspend)
assert_context "$system_contexts" source 'Edit action dispatcher'
assert_context "$system_contexts" menu-definition 'Edit menu definition'
assert_context_count "$system_contexts" 2

assert_open $'launch-editor\n'"$bin/cmd-screenshot" \
  action trigger.screenshot source
assert_open $'launch-tui-large\nyazi\n'"$bin/cmd-screenshot" \
  action trigger.screenshot source-location
assert_open $'launch-editor\n'"$home/.local/share/applications/Screenshot.desktop" \
  action trigger.screenshot "$screenshot_entry_key"
assert_open $'launch-tui-large\nyazi\n'"$bin/pkg-install" \
  application 'ARC Raiders' executable-location
assert_open $'launch-tui-large\nyazi\n'"$bin/cmd-screenshot" \
  application Argument executable-location
assert_open $'launch-tui-large\nyazi\n'"$bin/App Runner" \
  application Quoted executable-location
assert_open $'launch-tui-large\nyazi\n'"$bin/cmd-screenshot" \
  application EnvUnset executable-location
assert_open $'launch-tui-large\nyazi\n'"$bin/cmd-screenshot" \
  application EnvSeparator executable-location
assert_open $'launch-tui-large\nyazi\n'"$bin/Escaped Runner" \
  application Escaped executable-location
assert_open $'launch-editor\n'"$home/.local/share/applications/common/Docker.desktop" \
  application common-Docker desktop-entry

mv -- "$bin/desktop-shell-action" "$bin/desktop-shell-action.disabled"
assert_context_count "$(list_contexts menu trigger)" 4
assert_context_count "$(list_contexts application 'ARC Raiders')" 3
mv -- "$bin/desktop-shell-action.disabled" "$bin/desktop-shell-action"

for invalid in \
  'list unknown trigger' \
  'list action ../../etc/passwd' \
  'open action trigger.screenshot ../../etc/passwd' \
  'open application ../../etc/passwd desktop-entry'; do
  read -r -a args <<<"$invalid"
  rm -f -- "$log"
  if run_helper "${args[@]}" >/dev/null 2>&1; then
    fail "$invalid unexpectedly succeeded"
  fi
  [[ ! -e $log ]] || fail "$invalid launched a target"
done

printf 'PASS: desktop shell related-context dispatch\n'
