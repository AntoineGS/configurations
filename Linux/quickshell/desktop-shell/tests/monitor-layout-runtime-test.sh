#!/usr/bin/env bash
set -Eeuo pipefail

if ! command -v quickshell >/dev/null 2>&1; then
  printf 'SKIP: quickshell unavailable\n'
  exit 0
fi

repo_root=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../../../.." && pwd)
shell_dir="$repo_root/Linux/quickshell/desktop-shell"
tmp_dir=$(mktemp -d)
log_file="$tmp_dir/quickshell.log"

cleanup() { rm -rf -- "$tmp_dir"; }
trap cleanup EXIT

mkdir -p -- "$tmp_dir/bin" "$tmp_dir/home/.config" "$tmp_dir/home/.local/state" "$tmp_dir/runtime"
chmod 0700 -- "$tmp_dir/runtime"
host_runtime_dir=${XDG_RUNTIME_DIR:-}
if [[ -n ${WAYLAND_DISPLAY:-} && -S "$host_runtime_dir/$WAYLAND_DISPLAY" ]]; then
  ln -s -- "$host_runtime_dir/$WAYLAND_DISPLAY" "$tmp_dir/runtime/$WAYLAND_DISPLAY"
else
  printf 'SKIP: a Wayland socket is required to instantiate Monitor.Panel\n'
  exit 0
fi

cat >"$tmp_dir/bin/fake-monitor-state" <<'EOF'
#!/usr/bin/env bash
set -Eeuo pipefail
mode=$(<"$MONITOR_RUNTIME_STATE_MODE")
if [[ $mode == hold-old ]]; then
  : >"$MONITOR_RUNTIME_STATE_ENTERED"
  while [[ $(<"$MONITOR_RUNTIME_STATE_RELEASE") != release ]]; do sleep 0.01; done
  cat -- "$MONITOR_RUNTIME_OLD_STATE"
else
  cat -- "$MONITOR_RUNTIME_NEW_STATE"
fi
EOF
cat >"$tmp_dir/bin/fake-monitor-action" <<'EOF'
#!/usr/bin/env bash
set -Eeuo pipefail
printf '%s\n' "$*" >>"$MONITOR_RUNTIME_ACTION_LOG"
mode=$(<"$MONITOR_RUNTIME_ACTION_MODE")
if [[ $mode == hold ]]; then
  : >"$MONITOR_RUNTIME_ACTION_ENTERED"
  while [[ $(<"$MONITOR_RUNTIME_ACTION_RELEASE") != release ]]; do sleep 0.01; done
elif [[ $mode == fail ]]; then
  printf 'fixture failure %0250d\n' 0 >&2
  exit 7
fi
EOF
cat >"$tmp_dir/bin/fake-hostname" <<'EOF'
#!/usr/bin/env bash
printf 'runtime-fixture\n'
EOF
chmod 0755 -- "$tmp_dir/bin/fake-monitor-state" "$tmp_dir/bin/fake-monitor-action" "$tmp_dir/bin/fake-hostname"

printf '%s\n' ready >"$tmp_dir/state-mode"
printf '%s\n' wait >"$tmp_dir/state-release"
printf '%s\n' ready >"$tmp_dir/action-mode"
printf '%s\n' wait >"$tmp_dir/action-release"
cat >"$tmp_dir/old-state.json" <<'EOF'
{"available":true,"stale":false,"data":{"monitors":[{"name":"eDP-1","enabled":true},{"name":"HDMI-A-1","enabled":false}]}}
EOF
cat >"$tmp_dir/new-state.json" <<'EOF'
{"available":true,"stale":false,"data":{"monitors":[{"name":"eDP-1","enabled":true},{"name":"HDMI-A-1","enabled":false}]}}
EOF

if timeout --foreground --kill-after=2s 15s env \
  HOME="$tmp_dir/home" XDG_CONFIG_HOME="$tmp_dir/home/.config" \
  XDG_STATE_HOME="$tmp_dir/home/.local/state" XDG_RUNTIME_DIR="$tmp_dir/runtime" \
  QT_QPA_PLATFORM=wayland DESKTOP_SHELL_TEST_NO_SURFACES=1 \
  MONITOR_RUNTIME_STATE="$tmp_dir/bin/fake-monitor-state" \
  MONITOR_RUNTIME_ACTION="$tmp_dir/bin/fake-monitor-action" \
  MONITOR_RUNTIME_HOSTNAME="$tmp_dir/bin/fake-hostname" \
  MONITOR_RUNTIME_STATE_MODE="$tmp_dir/state-mode" \
  MONITOR_RUNTIME_STATE_RELEASE="$tmp_dir/state-release" \
  MONITOR_RUNTIME_STATE_ENTERED="$tmp_dir/state-entered" \
  MONITOR_RUNTIME_OLD_STATE="$tmp_dir/old-state.json" \
  MONITOR_RUNTIME_NEW_STATE="$tmp_dir/new-state.json" \
  MONITOR_RUNTIME_ACTION_MODE="$tmp_dir/action-mode" \
  MONITOR_RUNTIME_ACTION_RELEASE="$tmp_dir/action-release" \
  MONITOR_RUNTIME_ACTION_ENTERED="$tmp_dir/action-entered" \
  MONITOR_RUNTIME_ACTION_LOG="$tmp_dir/actions.log" \
  quickshell -n -p "$shell_dir/monitor-layout-runtime-test.qml" >"$log_file" 2>&1; then
  exit_code=0
else
  exit_code=$?
fi

log_text=$(<"$log_file")
if (( exit_code != 0 )) || [[ $log_text != *'Monitor layout runtime fixture passed'* ]]; then
  printf 'FAIL: monitor layout runtime fixture failed (exit %s)\n' "$exit_code" >&2
  cat -- "$log_file" >&2
  exit 1
fi
printf '%s\n' 'Monitor layout runtime fixture passed'
