#!/usr/bin/env bash
set -Eeuo pipefail
shopt -s inherit_errexit

script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
component_dir="$(cd -- "$script_dir/.." && pwd -P)"
repo_dir="$(cd -- "$component_dir/../.." && pwd -P)"
service="$component_dir/office-shares-mount.service"
timer="$component_dir/office-shares-mount.timer"
config="$repo_dir/tidydots.yaml"
legacy_helpers_target='~'/.local/share/helpers
legacy_helpers_source='Linux/os/helpers'
legacy_helpers_service_target='%h/.local/share/helpers'

fail() {
  printf 'FAIL: %s\n' "$*" >&2
  exit 1
}

[[ -x "$component_dir/mount-office-shares" ]] || fail 'user helper is not executable'
[[ -x "$component_dir/setup-office-shares-fstab" ]] || fail 'root helper is not executable'
[[ -r "$service" ]] || fail 'service is missing'
[[ -r "$timer" ]] || fail 'timer is missing'

grep -Fqx 'Type=oneshot' "$service" || fail 'service is not oneshot'
exec_start_count="$(awk '/^[[:space:]]*ExecStart=/ { count++ } END { print count + 0 }' "$service")"
[[ "$exec_start_count" == 1 ]] || fail 'service must contain exactly one ExecStart line'
canonical_exec_start_count="$(awk '
  /^[[:space:]]*ExecStart=/ {
    line = $0
    sub(/^[[:space:]]*/, "", line)
    if (line == "ExecStart=%h/.local/libexec/office-shares/mount-office-shares") count++
  }
  END { print count + 0 }
' "$service")"
[[ "$canonical_exec_start_count" == 1 ]] || \
  fail 'service helper path differs'
grep -Fqx 'TimeoutStartSec=90' "$service" || fail 'service timeout differs'
grep -Fqx 'OnStartupSec=30s' "$timer" || fail 'initial timer delay differs'
grep -Fqx 'OnUnitActiveSec=60s' "$timer" || fail 'timer cadence differs'
grep -Fqx 'WantedBy=timers.target' "$timer" || fail 'timer install target differs'

block="$(awk '
  /^  - / && found { exit }
  /^  - / { candidate = $0 ORS; found = 0; next }
  { candidate = candidate $0 ORS }
  /^    name: office-shares$/ { found = 1 }
  END { if (found) printf "%s", candidate }
' "$config")"

[[ -n "$block" ]] || fail 'office-shares tidydots entry is missing'
hostname_gate_count="$(awk '$0 == "    when: '\''{{ eq .Hostname \"antoinews-linux\" }}'\''" { count++ } END { print count + 0 }' <<<"$block")"
[[ "$hostname_gate_count" == 1 ]] || fail 'hostname gate differs or is not unique'
grep -Fq 'pacman: cifs-utils' <<<"$block" || fail 'cifs-utils package is missing'
if grep -Fq 'gvfs-smb' <<<"$block"; then
  fail 'superseded gvfs-smb package remains'
fi

extract_entry() {
  local entry_name="$1"

  awk -v entry_name="$entry_name" '
    /^      - / {
      if (found) exit
      in_entry = 1
      candidate = $0 ORS
      next
    }
    in_entry { candidate = candidate $0 ORS }
    $0 == "        name: " entry_name { found = 1 }
    END { if (found) printf "%s", candidate }
  ' <<<"$block"
}

require_entry_line() {
  local entry_name="$1"
  local entry_content="$2"
  local expected_line="$3"
  local failure_message="$4"

  [[ -n "$entry_content" ]] || fail "$entry_name entry is missing"
  grep -Fqx -- "$expected_line" <<<"$entry_content" || fail "$failure_message"
}

root_helper_entry="$(extract_entry setup-fstab-helper)"
require_entry_line setup-fstab-helper "$root_helper_entry" \
  '          linux: /usr/local/libexec/antoinews-linux' 'root helper target differs'
require_entry_line setup-fstab-helper "$root_helper_entry" \
  '        method: copy' 'root helper is not copy mode'
require_entry_line setup-fstab-helper "$root_helper_entry" \
  '        backup: ./Linux/office-shares' 'root helper backup path differs'
require_entry_line setup-fstab-helper "$root_helper_entry" \
  '          - setup-office-shares-fstab' 'root helper file is not mapped'
require_entry_line setup-fstab-helper "$root_helper_entry" \
  '        sudo: true' 'root helper entry is not sudo'

root_setup_entry="$(extract_entry setup-fstab)"
require_entry_line setup-fstab "$root_setup_entry" \
  '          linux: /usr/local/libexec/antoinews-linux/setup-office-shares-fstab --check' \
  'root setup check differs'
require_entry_line setup-fstab "$root_setup_entry" \
  '          linux: /usr/local/libexec/antoinews-linux/setup-office-shares-fstab --apply' \
  'root setup apply differs'
require_entry_line setup-fstab "$root_setup_entry" \
  '        sudo: true' 'root setup action is not sudo'

user_helper_entry="$(extract_entry mount-helper)"
expected_mount_helper_entry="      - targets:
          linux: ~/.local/libexec/office-shares
        name: mount-helper
        backup: ./Linux/office-shares
        files:
          - mount-office-shares"
[[ "$user_helper_entry" == "$expected_mount_helper_entry" ]] || \
  fail 'mount-helper entry structure differs'
require_entry_line mount-helper "$user_helper_entry" \
  '          linux: ~/.local/libexec/office-shares' 'user helper target differs'
mount_helper_file_count="$(awk '{ count += gsub(/mount-office-shares/, "") } END { print count + 0 }' <<<"$block")"
[[ "$mount_helper_file_count" == 1 ]] || fail 'mount-office-shares is not mapped exactly once'
mount_helper_target_count="$(awk '/^          linux: / { count++ } END { print count + 0 }' <<<"$user_helper_entry")"
[[ "$mount_helper_target_count" == 1 ]] || fail 'mount-helper has more than one target'
require_entry_line mount-helper "$user_helper_entry" \
  '        backup: ./Linux/office-shares' 'user helper backup path differs'
require_entry_line mount-helper "$user_helper_entry" \
  '          - mount-office-shares' 'user helper file is not mapped'
if grep -Fq -- "$legacy_helpers_target" "$service" || grep -Fq -- "$legacy_helpers_target" <<<"$block"; then
  fail 'global helpers deployment path remains'
fi
if grep -Fq -- "$legacy_helpers_service_target" "$service"; then
  fail 'legacy service helper path remains'
fi
if grep -Fq -- "$legacy_helpers_source" "$service" || grep -Fq -- "$legacy_helpers_source" <<<"$block"; then
  fail 'global helpers source/reference remains'
fi

user_units_entry="$(extract_entry user-units)"
require_entry_line user-units "$user_units_entry" \
  '          linux: ~/.config/systemd/user' 'user unit target differs'
require_entry_line user-units "$user_units_entry" \
  '        backup: ./Linux/office-shares' 'user unit backup path differs'
require_entry_line user-units "$user_units_entry" \
  '          - office-shares-mount.service' 'service is not mapped'
require_entry_line user-units "$user_units_entry" \
  '          - office-shares-mount.timer' 'timer is not mapped'

timer_entry="$(extract_entry enable-timer)"
require_entry_line enable-timer "$timer_entry" \
  '            systemctl --user is-enabled --quiet office-shares-mount.timer &&' \
  'timer enabled-state check is missing'
require_entry_line enable-timer "$timer_entry" \
  '            systemctl --user is-active --quiet office-shares-mount.timer &&' \
  'timer active-state check is missing'
require_entry_line enable-timer "$timer_entry" \
  "            test \"\$(systemctl --user show office-shares-mount.timer --property=NeedDaemonReload --value)\" = no" \
  'NeedDaemonReload no-state assertion is missing'
require_entry_line enable-timer "$timer_entry" \
  '          linux: systemctl --user daemon-reload && systemctl --user enable --now office-shares-mount.timer' \
  'timer activation is missing'

tidydots --dir "$repo_dir" list >/dev/null || fail 'tidydots cannot parse the configuration'
printf 'PASS: office share units and tidydots configuration\n'
