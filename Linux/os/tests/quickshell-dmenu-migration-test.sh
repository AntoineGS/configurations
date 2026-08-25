#!/usr/bin/env bash
set -Eeuo pipefail

repo_root=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../../.." && pwd)
helpers=$repo_root/Linux/os/helpers
rename_helper=$helpers/hyprland-workspace-rename
keybindings_helper=$helpers/menu-keybindings
test_root=$(mktemp -d)
bin=$test_root/bin
menu_input_log=$test_root/menu-input.log
menu_select_prompt=$test_root/menu-select.prompt
menu_select_input=$test_root/menu-select.input
hypr_log=$test_root/hypr.log
vicinae_log=$test_root/vicinae.log

trap 'rm -rf "$test_root"' EXIT

fail() {
  printf 'FAIL: %s\n' "$1" >&2
  exit 1
}

install -d -m 700 "$bin"

cat >"$bin/menu-input" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "$*" >"$MENU_INPUT_LOG"
printf 'renamed workspace\n'
EOF
cat >"$bin/menu-select" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "$1" >"$MENU_SELECT_PROMPT"
cat >"$MENU_SELECT_INPUT"
printf 'selected\n'
EOF
cat >"$bin/vicinae" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "$*" >"$VICINAE_LOG"
exit 99
EOF
cat >"$bin/xkbcli" <<'EOF'
#!/usr/bin/env bash
exit 0
EOF
cat >"$bin/hyprctl" <<'EOF'
#!/usr/bin/env bash
set -Eeuo pipefail
case "$*" in
  "activeworkspace -j") printf '{"id":7,"name":"current"}\n' ;;
  "binds")
    printf 'bind\n\tmodmask: 64\n\tkey: Q\n\tdescription: Quit\n\tdispatcher: __lua\n\targ: 1\n'
    ;;
  eval*) printf '%s\n' "$*" >"$HYPR_LOG" ;;
  *) exit 2 ;;
esac
EOF
chmod +x "$bin"/*

run_env=(
  PATH="$bin:$PATH"
  MENU_INPUT_LOG="$menu_input_log"
  MENU_SELECT_PROMPT="$menu_select_prompt"
  MENU_SELECT_INPUT="$menu_select_input"
  HYPR_LOG="$hypr_log"
  VICINAE_LOG="$vicinae_log"
)

env "${run_env[@]}" "$rename_helper"
[[ $(<"$menu_input_log") == 'Rename Workspace --initial current' ]] || fail "workspace rename did not use Quickshell input"
grep -F 'workspace=7' "$hypr_log" >/dev/null || fail "workspace rename lost the workspace ID"
grep -F 'name="renamed workspace"' "$hypr_log" >/dev/null || fail "workspace rename did not JSON-encode the new name"

env "${run_env[@]}" "$keybindings_helper"
[[ $(<"$menu_select_prompt") == Keybindings ]] || fail "keybindings viewer did not use Quickshell selection"
grep -F 'SUPER + Q' "$menu_select_input" >/dev/null || fail "keybindings viewer lost the key combination"
grep -F 'Quit' "$menu_select_input" >/dev/null || fail "keybindings viewer lost the description"
[[ ! -e $vicinae_log ]] || fail "a migrated dmenu helper still invoked Vicinae"

printf 'PASS: Quickshell dmenu helper migration\n'
