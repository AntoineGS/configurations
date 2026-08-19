#!/usr/bin/env bash

set -Eeuo pipefail
shopt -s inherit_errexit

ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../../.." && pwd -P)"

helpers=(
  webapp-install
  webapp-remove
  webapp-remove-all
  tui-install
  tui-remove
  tui-remove-all
  windows-vm
)

for helper in "${helpers[@]}"; do
  helper_path="$ROOT/Linux/os/helpers/$helper"
  test -x "$helper_path"
  bash -n "$helper_path"
done

test_home="$(mktemp -d)"

cleanup() {
  rm -rf -- "$test_home"
}
trap cleanup EXIT

applications_root="$test_home/.local/share/applications"
common_dir="$applications_root/common"
common_icon_dir="$common_dir/icons"
mkdir -p -- "$common_icon_dir"

fake_bin="$test_home/fake-bin"
update_database_log="$test_home/update-desktop-database.log"
mkdir -p -- "$fake_bin"
cat >"$fake_bin/update-desktop-database" <<'EOF'
#!/usr/bin/env bash
set -Eeuo pipefail

if (( $# != 1 )); then
  exit 2
fi

printf '%s\n' "$1" >>"$UPDATE_DESKTOP_DATABASE_LOG"
: >"$1/mimeinfo.cache"
EOF
chmod +x -- "$fake_bin/update-desktop-database"

webapp_icon="$common_icon_dir/Test Web.png"
: >"$webapp_icon"
HOME="$test_home" "$ROOT/Linux/os/helpers/webapp-install" \
  'Test Web' 'https://example.com' 'Test Web.png'
test -f "$common_dir/Test Web.desktop"
grep -Fq "Icon=$webapp_icon" "$common_dir/Test Web.desktop"
test -f "$webapp_icon"
test ! -e "$test_home/.local/share/applications/Test Web.desktop"
test ! -e "$test_home/.local/share/applications/icons/Test Web.png"

HOME="$test_home" "$ROOT/Linux/os/helpers/webapp-remove" 'Test Web'
test ! -e "$common_dir/Test Web.desktop"
test ! -e "$webapp_icon"

tui_source_icon="$test_home/tui.png"
: >"$tui_source_icon"
tui_icon="$common_icon_dir/Test TUI.png"
HOME="$test_home" "$ROOT/Linux/os/helpers/tui-install" \
  'Test TUI' true tile "$tui_source_icon"
test -f "$common_dir/Test TUI.desktop"
grep -Fq "Icon=$tui_icon" "$common_dir/Test TUI.desktop"
test -f "$tui_icon"
test -f "$tui_source_icon"
test ! -e "$test_home/.local/share/applications/Test TUI.desktop"

HOME="$test_home" "$ROOT/Linux/os/helpers/tui-remove" 'Test TUI'
test ! -e "$common_dir/Test TUI.desktop"
test ! -e "$tui_icon"
test -f "$tui_source_icon"

webapp_all_name='Remove All Web'
webapp_all_icon="$common_icon_dir/$webapp_all_name.png"
: >"$webapp_all_icon"
cat >"$common_dir/$webapp_all_name.desktop" <<EOF
[Desktop Entry]
Name=$webapp_all_name
Exec=launch-webapp https://example.com
Type=Application
EOF

PATH="$fake_bin:$PATH" UPDATE_DESKTOP_DATABASE_LOG="$update_database_log" \
  HOME="$test_home" "$ROOT/Linux/os/helpers/webapp-remove-all"
test ! -e "$common_dir/$webapp_all_name.desktop"
test ! -e "$webapp_all_icon"

tui_all_name='Remove All TUI'
tui_all_icon="$common_icon_dir/$tui_all_name.png"
: >"$tui_all_icon"
cat >"$common_dir/$tui_all_name.desktop" <<EOF
[Desktop Entry]
Name=$tui_all_name
Exec=xdg-terminal-exec --app-id=TUI.tile -e true
Type=Application
EOF

PATH="$fake_bin:$PATH" UPDATE_DESKTOP_DATABASE_LOG="$update_database_log" \
  HOME="$test_home" "$ROOT/Linux/os/helpers/tui-remove-all"
test ! -e "$common_dir/$tui_all_name.desktop"
test ! -e "$tui_all_icon"

selected_app_dir="$test_home/selected applications"
selected_icon_dir="$selected_app_dir/icons"
mkdir -p -- "$selected_icon_dir"

selected_webapp_name='Selected Web'
selected_webapp_icon="$selected_icon_dir/$selected_webapp_name.png"
: >"$selected_webapp_icon"
cat >"$selected_app_dir/$selected_webapp_name.desktop" <<EOF
[Desktop Entry]
Name=$selected_webapp_name
Exec=launch-webapp https://example.com
Type=Application
EOF

PATH="$fake_bin:$PATH" UPDATE_DESKTOP_DATABASE_LOG="$update_database_log" \
  HOME="$test_home" "$ROOT/Linux/os/helpers/webapp-remove-all" "$selected_app_dir"
test ! -e "$selected_app_dir/$selected_webapp_name.desktop"
test ! -e "$selected_webapp_icon"

selected_tui_name='Selected TUI'
selected_tui_icon="$selected_icon_dir/$selected_tui_name.png"
: >"$selected_tui_icon"
cat >"$selected_app_dir/$selected_tui_name.desktop" <<EOF
[Desktop Entry]
Name=$selected_tui_name
Exec=xdg-terminal-exec --app-id=TUI.float -e true
Type=Application
EOF

PATH="$fake_bin:$PATH" UPDATE_DESKTOP_DATABASE_LOG="$update_database_log" \
  HOME="$test_home" "$ROOT/Linux/os/helpers/tui-remove-all" "$selected_app_dir"
test ! -e "$selected_app_dir/$selected_tui_name.desktop"
test ! -e "$selected_tui_icon"

expected_update_database_log=$(printf '%s\n' \
  "$applications_root" \
  "$applications_root" \
  "$applications_root" \
  "$applications_root")
actual_update_database_log=$(<"$update_database_log")
if [[ $actual_update_database_log != "$expected_update_database_log" ]]; then
  printf 'update-desktop-database arguments mismatch:\nexpected:\n%s\nactual:\n%s\n' \
    "$expected_update_database_log" "$actual_update_database_log" >&2
  exit 1
fi
test ! -e "$common_dir/mimeinfo.cache"

printf '%s\n' 'desktop helper path tests passed'
