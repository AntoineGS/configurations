#!/usr/bin/env bash
set -Eeuo pipefail

repo_root=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../../.." && pwd)
action_helper=$repo_root/Linux/os/helpers/desktop-shell-action
test_root=$(mktemp -d)
bin=$test_root/bin
log=$test_root/action.log

trap 'rm -rf "$test_root"' EXIT

fail() {
  printf 'FAIL: %s\n' "$1" >&2
  exit 1
}

[[ -x $action_helper ]] || fail "desktop-shell-action is missing or not executable"
install -d -m 700 "$bin"

cat >"$bin/action-stub" <<'EOF'
#!/usr/bin/env bash
printf '%s' "${0##*/}" >"$ACTION_LOG"
if (( $# > 0 )); then
  printf ' %s' "$@" >>"$ACTION_LOG"
fi
printf '\n' >>"$ACTION_LOG"
EOF
chmod +x "$bin/action-stub"

commands=(
  menu-keybindings
  toggle-desktop-shell-bar
  hyprland-window-gaps-toggle
  hyprland-window-single-square-aspect-toggle
  turn-off-screens
  hyprland-monitor-scaling-cycle
  hyprland-workspace-layout-toggle
  toggle-nightlight
  toggle-idle
  launch-audio
  launch-wifi
  launch-bluetooth
  desktop-shell-prompt-action
  desktop-shell
  start-all-terminals
)
for command in "${commands[@]}"; do
  ln -s action-stub "$bin/$command"
done

assert_action() {
  local action=$1
  local expected=$2
  rm -f "$log"
  ACTION_LOG=$log PATH="$bin:$PATH" "$action_helper" "$action"
  [[ -f $log ]] || fail "$action did not execute a command"
  [[ $(<"$log") == "$expected" ]] || fail "$action executed '$(<"$log")' instead of '$expected'"
}

assert_action setup.keybindings 'menu-keybindings'
assert_action trigger.toggle.top-bar 'toggle-desktop-shell-bar'
assert_action trigger.toggle.window-gaps 'hyprland-window-gaps-toggle'
assert_action trigger.toggle.window-ratio 'hyprland-window-single-square-aspect-toggle'
assert_action trigger.turn-off-screens 'turn-off-screens 2'
assert_action setup.cycle-display-scaling 'hyprland-monitor-scaling-cycle'
assert_action trigger.toggle.workspace-layout 'hyprland-workspace-layout-toggle'
assert_action trigger.toggle.nightlight 'toggle-nightlight'
assert_action trigger.toggle.idle-lock 'toggle-idle'
assert_action setup.audio-tui 'launch-audio'
assert_action setup.wifi-tui 'launch-wifi'
assert_action setup.bluetooth-tui 'launch-bluetooth'
assert_action system.suspend-in 'desktop-shell-prompt-action system.suspend-in'
assert_action system.close-rustdesk-in 'desktop-shell-prompt-action system.close-rustdesk-in'
assert_action trigger.start-all-terminals 'start-all-terminals'
assert_action install.plugin-marketplace \
  'desktop-shell summon io.yasino55.omarchy-plugin-marketplace {}'

rm -f "$log"
if ACTION_LOG=$log PATH="$bin:$PATH" "$action_helper" unknown.action >/dev/null 2>&1; then
  fail "unknown action succeeded"
fi
[[ ! -e $log ]] || fail "unknown action executed a command"

printf 'PASS: desktop shell fixed action dispatch\n'
