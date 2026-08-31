#!/usr/bin/env bash
set -Eeuo pipefail

repo_root=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../../../.." && pwd)
shell_dir="$repo_root/Linux/quickshell/desktop-shell"
if ! command -v quickshell >/dev/null 2>&1; then
  printf 'SKIP: quickshell unavailable\n'
  exit 0
fi
[[ $(stat -c '%a' "$0") == 755 ]] || { printf 'notification runtime test must be executable\n' >&2; exit 1; }

tmp_dir=$(mktemp -d)
runtime_dir="$tmp_dir/runtime"
route_dir="$runtime_dir/desktop-shell"
wrapper_dir="$tmp_dir/bin"
mkdir -p -- "$route_dir" "$wrapper_dir"
stat_block="$tmp_dir/stat-block"
stat_blocked="$tmp_dir/stat-blocked"
cat >"$wrapper_dir/stat" <<'EOF'
#!/usr/bin/env bash
if [[ -e ${STAT_BLOCK:-} ]]; then
  : >"$STAT_BLOCKED"
  while [[ -e $STAT_BLOCK ]]; do sleep 0.01; done
fi
exec /usr/bin/stat "$@"
EOF
chmod 755 -- "$wrapper_dir/stat"
chmod 700 -- "$route_dir"
host_runtime_dir=${XDG_RUNTIME_DIR:-}
if [[ -n ${WAYLAND_DISPLAY:-} && -S "$host_runtime_dir/$WAYLAND_DISPLAY" ]]; then
  ln -s -- "$host_runtime_dir/$WAYLAND_DISPLAY" "$runtime_dir/$WAYLAND_DISPLAY"
fi
export XDG_RUNTIME_DIR="$runtime_dir"
route_file="$route_dir/notification-route.json"
lease_file="$route_dir/notification-route-lease.json"

atomic_write() {
  local path=$1 content=$2 temporary
  temporary=$(mktemp "$path.XXXXXX")
  chmod 600 -- "$temporary"
  printf '%s\n' "$content" >"$temporary"
  mv -f -- "$temporary" "$path"
}

route_json() {
  local output=$1 updated=$2
  jq -cn --arg output "$output" --argjson updated "$updated" \
    '{version:1,visible:true,output:$output,cueOutput:$output,direction:"left",updatedAt:$updated}'
}

lease_json() {
  local route_updated=$1 refreshed=$2 expires=$3
  jq -cn --argjson route_updated "$route_updated" --argjson refreshed "$refreshed" \
    --argjson expires "$expires" \
    '{version:2,refreshedAtMs:$refreshed,expiresAtMs:$expires,routeUpdatedAt:$route_updated}'
}

now_ms() { date +%s%3N; }
write_valid_state() {
  local output=$1 updated=$2 lifetime=${3:-15000} now
  now=$(now_ms)
  atomic_write "$route_file" "$(route_json "$output" "$updated")"
  atomic_write "$lease_file" "$(lease_json "$updated" "$now" "$((now + lifetime))")"
}

initial_generation=$(date +%s)
shell_pid=""
trap '[[ -z $shell_pid ]] || kill "$shell_pid" 2>/dev/null || true; rm -rf -- "$tmp_dir"' EXIT
isolated_shell_dir="$tmp_dir/desktop-shell"
cp -a -- "$shell_dir" "$isolated_shell_dir"

env HOME="$tmp_dir/home" XDG_CONFIG_HOME="$tmp_dir/home/.config" \
  XDG_STATE_HOME="$tmp_dir/home/.local/state" XDG_RUNTIME_DIR="$runtime_dir" \
  PATH="$wrapper_dir:$PATH" STAT_BLOCK="$stat_block" STAT_BLOCKED="$stat_blocked" \
  DESKTOP_SHELL_TEST_NO_SURFACES=1 DESKTOP_SHELL_NOTIFICATIONS_REGISTER=0 \
  quickshell -n -p "$isolated_shell_dir" >"$tmp_dir/quickshell.log" 2>&1 &
shell_pid=$!

sleep 0.3
write_valid_state DVI-D-1 "$initial_generation"

response=""
for _ in {1..100}; do
  response=$(quickshell ipc --pid "$shell_pid" call -- desktop.notifications ping 2>/dev/null || true)
  [[ $response == pong ]] && break
  kill -0 "$shell_pid" 2>/dev/null || break
  sleep 0.1
done
[[ $response == pong ]] || { printf 'notification service IPC target failed: %q\n' "$response" >&2; sed -n '1,260p' "$tmp_dir/quickshell.log" >&2; exit 1; }

status_json() { quickshell ipc --pid "$shell_pid" call -- desktop.notifications status; }
wait_for() {
  local condition=$1 status
  for _ in {1..100}; do
    status=$(status_json 2>/dev/null || true)
    if STATUS="$status" python3 -c "import json, os; s=json.loads(os.environ['STATUS']); raise SystemExit(0 if $condition else 1)"; then
      return 0
    fi
    kill -0 "$shell_pid" 2>/dev/null || return 1
    sleep 0.1
  done
  printf 'last notification status: %s\n' "$status" >&2
  sed -n '1,260p' "$tmp_dir/quickshell.log" >&2
  return 1
}

wait_for "s.get('routeValid') is True" || { sed -n '1,240p' "$tmp_dir/quickshell.log" >&2; exit 1; }

rm -f -- "$lease_file"
wait_for "s.get('routeValid') is False and s.get('routeInvalidationCount', 0) >= 1" || exit 1

recovery_generation=$(date +%s)
write_valid_state HDMI-A-1 "$recovery_generation"
wait_for "s.get('routeValid') is True and s.get('routeCueOutput') == 'HDMI-A-1'" || exit 1

now=$(now_ms)
expected_deadline=$((now + 1500))
atomic_write "$lease_file" "$(lease_json "$recovery_generation" "$now" "$expected_deadline")"
wait_for "s.get('routeValid') is True and s.get('routeAcceptedExpiresAtMs') == $expected_deadline" || exit 1
while (( $(now_ms) < expected_deadline )); do sleep 0.05; done
wait_for "s.get('routeValid') is False and s.get('routeAcceptedExpiresAtMs') == -1" || exit 1

touch -- "$stat_block"
write_valid_state DP-1 "$(date +%s)"
for _ in {1..100}; do
  [[ -e $stat_blocked ]] && break
  sleep 0.05
done
[[ -e $stat_blocked ]] || exit 1
blocked_status=$(status_json)
blocked_attempt=$(STATUS="$blocked_status" python3 -c 'import json, os; print(json.loads(os.environ["STATUS"])["routeMetadataAttemptCount"])')
blocked_revision=$(STATUS="$blocked_status" python3 -c 'import json, os; print(json.loads(os.environ["STATUS"])["routeCandidateRevision"])')
write_valid_state DP-2 "$(date +%s)"
write_valid_state eDP-1 "$(date +%s)"
stable_revision=-1
stable_samples=0
for _ in {1..100}; do
  status=$(status_json 2>/dev/null || true)
  revision=$(STATUS="$status" python3 -c 'import json, os; print(json.loads(os.environ["STATUS"]).get("routeCandidateRevision", -1))' 2>/dev/null || printf '%s' -1)
  if [[ $revision == "$stable_revision" && $revision -gt $blocked_revision ]]; then
    stable_samples=$((stable_samples + 1))
    ((stable_samples >= 3)) && break
  else
    stable_revision=$revision
    stable_samples=0
  fi
  sleep 0.05
done
[[ $stable_samples -ge 3 ]] || exit 1
rm -f -- "$stat_block"
wait_for "s.get('routeValid') is True and s.get('routeCueOutput') == 'eDP-1' and s.get('routeAcceptedGeneration', -1) >= 0" || exit 1
final_status=$(status_json)
FINAL_STATUS="$final_status" BLOCKED_ATTEMPT="$blocked_attempt" python3 - <<'PY'
import json
import os
status = json.loads(os.environ["FINAL_STATUS"])
if status["routeMetadataAttemptCount"] != int(os.environ["BLOCKED_ATTEMPT"]) + 1:
    raise SystemExit("generation mismatch did not produce exactly one follow-up validation")
PY

before_status=$(status_json)
sleep 2
after_status=$(status_json)
BEFORE_STATUS="$before_status" AFTER_STATUS="$after_status" python3 - <<'PY'
import json
import os
before = json.loads(os.environ["BEFORE_STATUS"])
after = json.loads(os.environ["AFTER_STATUS"])
if after["routeMetadataAttemptCount"] != before["routeMetadataAttemptCount"]:
    raise SystemExit("metadata validation was not stable after final route promotion")
PY

printf 'PASS: notification metadata promotion, fail-close, expiry, recovery, and generation follow-up verified\n'
