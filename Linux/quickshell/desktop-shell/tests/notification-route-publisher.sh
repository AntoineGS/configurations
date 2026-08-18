#!/usr/bin/env bash

# Test helper: launch the real Hyprland route watcher against a private socket
# and deterministic monitor/client responses. Callers own process cleanup.

notification_publisher_process_start_time() {
  local pid=$1

  [[ $pid =~ ^[0-9]+$ && -r /proc/$pid/stat ]] || return 1
  awk '{print $22}' "/proc/$pid/stat"
}

notification_publisher_process_executable() {
  local pid=$1

  [[ $pid =~ ^[0-9]+$ && -L /proc/$pid/exe ]] || return 1
  readlink -f -- "/proc/$pid/exe"
}

notification_publisher_process_is_live() {
  local pid=$1
  local expected_start_time=$2
  local expected_executable=$3
  local state

  kill -0 "$pid" 2>/dev/null || return 1
  [[ $(notification_publisher_process_start_time "$pid") == "$expected_start_time" ]] || return 1
  [[ $(notification_publisher_process_executable "$pid") == "$expected_executable" ]] || return 1
  state=$(awk '/^State:/ {print $2; exit}' "/proc/$pid/status" 2>/dev/null) || return 1
  case $state in
    R|S|D|I|T|t|W) return 0 ;;
    *) return 1 ;;
  esac
}

notification_publisher_start() {
  local runtime_dir=$1
  local route_dir=$2
  local log_file=$3
  local publisher_pid_name=$4
  local publisher_start_name=$5
  local publisher_executable_name=$6
  local socket_pid_name=$7
  local socket_start_name=$8
  local socket_executable_name=$9
  local watcher
  local signature
  local hypr_dir
  local socket_path
  local publisher_bin
  local publisher_pid
  local socket_pid
  local start_time
  local executable
  local socket_start_time
  local socket_executable

  watcher="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../../../hypr" && pwd)/watch-rustdesk-submap.sh"
  signature="notification-publisher-${BASHPID:-$$}"
  hypr_dir="$runtime_dir/hypr/$signature"
  socket_path="$hypr_dir/.socket2.sock"
  publisher_bin="$runtime_dir/notification-publisher-bin"

  mkdir -p -- "$hypr_dir" "$publisher_bin"
  cat >"$publisher_bin/hyprctl" <<'EOF'
#!/usr/bin/env bash
set -Eeuo pipefail

case "${1:-} ${2:-}" in
  'monitors -j')
    printf '%s\n' '[{"id":1,"name":"DVI-D-1","x":0,"y":0,"width":1920,"height":1080,"focused":true,"disabled":false,"dpmsStatus":true}]'
    ;;
  'clients -j')
    printf '%s\n' '[]'
    ;;
  *)
    exit 125
    ;;
esac
EOF
  chmod 700 -- "$publisher_bin/hyprctl"

  /usr/bin/socat "UNIX-LISTEN:$socket_path,reuseaddr" \
    EXEC:'/usr/bin/sleep 2147483647' >/dev/null 2>&1 &
  socket_pid=$!
  for _ in {1..100}; do
    [[ -S $socket_path ]] && break
    /usr/bin/sleep 0.01
  done
  [[ -S $socket_path ]] || return 1

  XDG_RUNTIME_DIR="$runtime_dir" \
  HYPRLAND_INSTANCE_SIGNATURE="$signature" \
  NOTIFICATION_ROUTE_DIR="$route_dir" \
  NOTIFICATION_ROUTE_FILE="$route_dir/notification-route.json" \
  NOTIFICATION_LEASE_FILE="$route_dir/notification-route-lease.json" \
  NOTIFICATION_RECONCILE_INTERVAL=1 \
  SOCAT=/usr/bin/socat \
  PATH="$publisher_bin:$PATH" \
    bash "$watcher" >"$log_file" 2>&1 &
  publisher_pid=$!

  for _ in {1..100}; do
    start_time=$(notification_publisher_process_start_time "$publisher_pid" 2>/dev/null || true)
    executable=$(notification_publisher_process_executable "$publisher_pid" 2>/dev/null || true)
    [[ -n $start_time && -n $executable ]] && break
    /usr/bin/sleep 0.01
  done
  if [[ -z ${start_time:-} || -z ${executable:-} ]]; then
    kill -KILL "$publisher_pid" 2>/dev/null || true
    kill -TERM "$socket_pid" 2>/dev/null || true
    wait "$publisher_pid" "$socket_pid" 2>/dev/null || true
    return 1
  fi

  socket_start_time=$(notification_publisher_process_start_time "$socket_pid") || return 1
  socket_executable=$(notification_publisher_process_executable "$socket_pid") || return 1
  printf -v "$publisher_pid_name" '%s' "$publisher_pid"
  printf -v "$publisher_start_name" '%s' "$start_time"
  printf -v "$publisher_executable_name" '%s' "$executable"
  printf -v "$socket_pid_name" '%s' "$socket_pid"
  printf -v "$socket_start_name" '%s' "$socket_start_time"
  printf -v "$socket_executable_name" '%s' "$socket_executable"
}

notification_publisher_kill() {
  local pid=$1
  local start_time=$2
  local executable=$3
  local signal=$4

  notification_publisher_process_is_live "$pid" "$start_time" "$executable" || return 1
  kill -"$signal" "$pid"
  wait "$pid" 2>/dev/null || true
}

notification_publisher_cleanup() {
  local publisher_pid=$1
  local publisher_start_time=$2
  local publisher_executable=$3
  local socket_pid=$4
  local socket_start_time=$5
  local socket_executable=$6

  if notification_publisher_process_is_live "$publisher_pid" "$publisher_start_time" "$publisher_executable"; then
    kill -TERM "$publisher_pid" 2>/dev/null || true
    wait "$publisher_pid" 2>/dev/null || true
  fi
  if notification_publisher_process_is_live "$socket_pid" "$socket_start_time" "$socket_executable"; then
    kill -TERM "$socket_pid" 2>/dev/null || true
    wait "$socket_pid" 2>/dev/null || true
  fi
}
