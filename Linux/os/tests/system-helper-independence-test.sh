#!/usr/bin/env bash
# shellcheck disable=SC2016
set -Eeuo pipefail

ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../../.." && pwd -P)"

modified_helpers=(
  update
  update-perform
  snapshot
  hibernation-available
  hibernation-remove
  hibernation-setup
  launch-floating-terminal-with-presentation
  launch-tui
  config-direct-boot
  state
  windows-vm
  voxtype-install
  cmd-tzupdate
  voxtype-model
  tzupdate-and-restart-waybar
  voxtype-model-setup
  cmd-screenrecord
  cmd-screenshot
  font-set
)

deleted_helpers=(
  hook
  install-terminal
  refresh-applications
  refresh-chromium
  refresh-config
  refresh-fastfetch
  refresh-hypridle
  refresh-hyprland
  refresh-hyprlock
  refresh-hyprsunset
  refresh-limine
  refresh-pacman
  refresh-plymouth
  refresh-sddm
  refresh-swayosd
  refresh-tmux
  refresh-waybar
  show-logo
  toggle-hybrid-gpu
  toggle-suspend
  update-available-reset
  update-branch
  update-git
  update-restart
  update-without-idle
)

for helper in "${modified_helpers[@]}"; do
  helper_path="$ROOT/Linux/os/helpers/$helper"
  test -x "$helper_path"
  bash -n "$helper_path"
done

for helper in "${deleted_helpers[@]}"; do
  helper_path="$ROOT/Linux/os/helpers/$helper"
  if [[ -e $helper_path || -L $helper_path ]]; then
    printf 'obsolete helper still exists: %s\n' "$helper_path" >&2
    exit 1
  fi
done

for helper in "${modified_helpers[@]}"; do
  helper_path="$ROOT/Linux/os/helpers/$helper"
  if grep -Eiq 'omarchy|OMARCHY_PATH|OMARCHY_|org\.omarchy|show-logo|show-done|update-git|update-available-reset|update-restart|hook post-update' "$helper_path"; then
    printf 'retained helper still contains obsolete runtime branding or lifecycle code: %s\n' "$helper_path" >&2
    exit 1
  fi
done

HIBERNATION_FILES=(
  "$ROOT/Linux/os/helpers/hibernation-available"
  "$ROOT/Linux/os/helpers/hibernation-remove"
  "$ROOT/Linux/os/helpers/hibernation-setup"
)
for helper_path in "${HIBERNATION_FILES[@]}"; do
  grep -Fq '/etc/mkinitcpio.conf.d/resume.conf' "$helper_path"
done

grep -Fq 'SCREENRECORD_DIR' "$ROOT/Linux/os/helpers/cmd-screenrecord"
grep -Fq 'SCREENSHOT_DIR' "$ROOT/Linux/os/helpers/cmd-screenshot"
grep -Fq 'SCREENSHOT_EDITOR' "$ROOT/Linux/os/helpers/cmd-screenshot"
grep -Fq 'SCREENRECORD_DIR' "$ROOT/Linux/os/tests/cmd-screenrecord-test.sh"
if grep -Fq 'OMARCHY_SCREENRECORD_DIR' "$ROOT/Linux/os/tests/cmd-screenrecord-test.sh"; then
  printf '%s\n' 'screenrecord test still uses the Omarchy output variable' >&2
  exit 1
fi

grep -Fq "DESC=\"pre-update \$(date --iso-8601=seconds)\"" "$ROOT/Linux/os/helpers/snapshot"
grep -Fq 'snapshot create' "$ROOT/Linux/os/helpers/update"
grep -Fq 'update-perform' "$ROOT/Linux/os/helpers/update"
grep -Fq 'update-keyring' "$ROOT/Linux/os/helpers/update-perform"
grep -Fq 'update-system-pkgs' "$ROOT/Linux/os/helpers/update-perform"
grep -Fq 'update-aur-pkgs' "$ROOT/Linux/os/helpers/update-perform"
grep -Fq 'update-orphan-pkgs' "$ROOT/Linux/os/helpers/update-perform"
grep -Fq 'update-analyze-logs' "$ROOT/Linux/os/helpers/update-perform"
grep -Fq 'noidle' "$ROOT/Linux/os/helpers/update-perform"

for helper_path in \
  "$ROOT/Linux/os/helpers/launch-floating-terminal-with-presentation" \
  "$ROOT/Linux/os/helpers/launch-tui"; do
  grep -Fq -- '--app-id=org.local.terminal' "$helper_path"
  grep -Fq -- '--title=System' "$helper_path"
  grep -Fq 'set -Eeuo pipefail' "$helper_path"
  grep -Fq 'if (( $# == 0 )); then' "$helper_path"
  grep -Fq -- '-e "$@"' "$helper_path"
done

for helper in windows-vm cmd-screenrecord cmd-screenshot font-set cmd-tzupdate voxtype-model; do
  grep -Fq 'set -Eeuo pipefail' "$ROOT/Linux/os/helpers/$helper"
done

if grep -Eq '\$\*|bash -c' "$ROOT/Linux/os/helpers/launch-floating-terminal-with-presentation"; then
  printf '%s\n' 'floating terminal launcher reparses a shell command string' >&2
  exit 1
fi

grep -Fq 'launch-floating-terminal-with-presentation tzupdate-and-restart-waybar' \
  "$ROOT/Linux/os/helpers/cmd-tzupdate"
grep -Fq 'launch-floating-terminal-with-presentation voxtype-model-setup' \
  "$ROOT/Linux/os/helpers/voxtype-model"
grep -Fq 'sudo tzupdate' "$ROOT/Linux/os/helpers/tzupdate-and-restart-waybar"
grep -Fq 'voxtype setup model' "$ROOT/Linux/os/helpers/voxtype-model-setup"
if grep -Fq 'sudo tzupdate && restart-waybar' "$ROOT/Linux/os/helpers/cmd-tzupdate"; then
  printf '%s\n' 'timezone update still passes a compound shell command' >&2
  exit 1
fi

grep -Fq 'RESUME_DROP_IN="/etc/limine-entry-tool.d/resume.conf"' \
  "$ROOT/Linux/os/helpers/hibernation-remove"
grep -Fq 'RTC_ALARM_DROP_IN="/etc/limine-entry-tool.d/rtc-alarm.conf"' \
  "$ROOT/Linux/os/helpers/hibernation-remove"
grep -Fq 'LIMINE_UPDATE_REQUIRED=true' "$ROOT/Linux/os/helpers/hibernation-remove"
grep -Fq 'if [[ $HIBERNATION_CONFIGURED == false && $LIMINE_UPDATE_REQUIRED == false ]]; then' \
  "$ROOT/Linux/os/helpers/hibernation-remove"
grep -Fq 'sudo rm -f -- "$RESUME_DROP_IN" "$RTC_ALARM_DROP_IN"' \
  "$ROOT/Linux/os/helpers/hibernation-remove"
grep -Fq 'sudo limine-update' "$ROOT/Linux/os/helpers/hibernation-remove"

grep -Fq 'trap restore_noidle EXIT' "$ROOT/Linux/os/helpers/update-perform"
grep -Fq 'tag="-noidle"' "$ROOT/Linux/os/helpers/update-perform"

grep -Fq "STATE_DIR=\"\$HOME/.local/state/configurations\"" "$ROOT/Linux/os/helpers/state"
grep -Fq 'arch*.efi' "$ROOT/Linux/os/helpers/config-direct-boot"
grep -Fq -- '--label "Arch"' "$ROOT/Linux/os/helpers/config-direct-boot"
grep -Fq 'voxtype setup --download' "$ROOT/Linux/os/helpers/voxtype-install"
if grep -Fq -- '--no-post-install' "$ROOT/Linux/os/helpers/voxtype-install"; then
  exit 1
fi

if grep -Fq 'hook font-set' "$ROOT/Linux/os/helpers/font-set"; then
  printf '%s\n' 'font-set still invokes the deleted hook helper' >&2
  exit 1
fi

terminal_test_dir=$(mktemp -d)
terminal_argv_log="$terminal_test_dir/argv"
injection_marker="$terminal_test_dir/should-not-run"
printf '%s\n' \
  '#!/usr/bin/env bash' \
  'printf "<%s>\\n" "$@" >"$TERMINAL_ARGV_LOG"' \
  >"$terminal_test_dir/setsid"
chmod +x "$terminal_test_dir/setsid"

expected_terminal_argv=$(printf '%s\n' \
  '<uwsm-app>' \
  '<-->' \
  '<xdg-terminal-exec>' \
  '<--app-id=org.local.terminal>' \
  '<--title=System>' \
  '<-e>' \
  '<printf>' \
  '<argument with spaces>' \
  "<\$(touch $injection_marker)>" \
  '<>')
PATH="$terminal_test_dir:$PATH" TERMINAL_ARGV_LOG="$terminal_argv_log" \
  "$ROOT/Linux/os/helpers/launch-floating-terminal-with-presentation" \
  printf 'argument with spaces' "\$(touch $injection_marker)" ''
actual_terminal_argv=$(<"$terminal_argv_log")
if [[ $actual_terminal_argv != "$expected_terminal_argv" ]]; then
  printf 'floating terminal argv mismatch:\nexpected:\n%s\nactual:\n%s\n' \
    "$expected_terminal_argv" "$actual_terminal_argv" >&2
  exit 1
fi
if [[ -e $injection_marker ]]; then
  printf '%s\n' 'floating terminal launcher evaluated an argument as shell code' >&2
  exit 1
fi

: >"$terminal_argv_log"
PATH="$terminal_test_dir:$PATH" TERMINAL_ARGV_LOG="$terminal_argv_log" \
  "$ROOT/Linux/os/helpers/launch-tui" \
  printf 'argument with spaces' "\$(touch $injection_marker)" ''
actual_terminal_argv=$(<"$terminal_argv_log")
if [[ $actual_terminal_argv != "$expected_terminal_argv" ]]; then
  printf 'TUI launcher argv mismatch:\nexpected:\n%s\nactual:\n%s\n' \
    "$expected_terminal_argv" "$actual_terminal_argv" >&2
  exit 1
fi
if PATH="$terminal_test_dir:$PATH" \
  "$ROOT/Linux/os/helpers/launch-floating-terminal-with-presentation" >/dev/null 2>&1; then
  printf '%s\n' 'floating terminal launcher accepts an empty command' >&2
  exit 1
fi
if PATH="$terminal_test_dir:$PATH" "$ROOT/Linux/os/helpers/launch-tui" >/dev/null 2>&1; then
  printf '%s\n' 'TUI launcher accepts an empty command' >&2
  exit 1
fi
rm -rf "$terminal_test_dir"

"$ROOT/Linux/os/helpers/windows-vm" >/dev/null
"$ROOT/Linux/os/helpers/font-set" >/dev/null

state_test_dir=$(mktemp -d)
state_home="$state_test_dir/home"
mkdir -p "$state_home"
HOME="$state_home" "$ROOT/Linux/os/helpers/state" set suspend-off
test -f "$state_home/.local/state/configurations/suspend-off"
HOME="$state_home" "$ROOT/Linux/os/helpers/state" clear 'suspend-*'
test ! -e "$state_home/.local/state/configurations/suspend-off"
if HOME="$state_home" "$ROOT/Linux/os/helpers/state" set '../escaped' >/dev/null 2>&1; then
  printf '%s\n' 'state accepts a path-traversing state name' >&2
  exit 1
fi
if [[ -e "$state_home/.local/state/escaped" ]]; then
  printf '%s\n' 'state wrote outside its state directory' >&2
  exit 1
fi
if HOME="$state_home" "$ROOT/Linux/os/helpers/state" clear '../*' >/dev/null 2>&1; then
  printf '%s\n' 'state accepts a path-traversing clear pattern' >&2
  exit 1
fi
rm -rf "$state_test_dir"

update_test_dir=$(mktemp -d)
update_events="$update_test_dir/events"
update_log="$update_test_dir/update.log"
printf '%s\n' \
  '#!/usr/bin/env bash' \
  'printf "%s\\n" "$*" >>"$UPDATE_EVENTS"' \
  >"$update_test_dir/hyprctl"
printf '%s\n' \
  '#!/usr/bin/env bash' \
  'if [[ ${1:-} == -o0 ]]; then shift; fi' \
  'exec "$@"' \
  >"$update_test_dir/stdbuf"
printf '%s\n' \
  '#!/usr/bin/env bash' \
  'cat >"$UPDATE_LOG"' \
  >"$update_test_dir/tee"
printf '%s\n' \
  '#!/usr/bin/env bash' \
  'exit 23' \
  >"$update_test_dir/update-keyring"
chmod +x "$update_test_dir/hyprctl" "$update_test_dir/stdbuf" "$update_test_dir/tee" \
  "$update_test_dir/update-keyring"
update_status=0
if PATH="$update_test_dir:$PATH" UPDATE_EVENTS="$update_events" UPDATE_LOG="$update_log" \
  "$ROOT/Linux/os/helpers/update-perform"; then
  update_status=0
else
  update_status=$?
fi
if (( update_status == 0 )); then
  printf '%s\n' 'update-perform hides an update failure' >&2
  exit 1
fi
grep -Fq 'tag="+noidle"' "$update_events"
grep -Fq 'tag="-noidle"' "$update_events"
rm -rf "$update_test_dir"

printf '%s\n' 'system helper independence tests passed'
