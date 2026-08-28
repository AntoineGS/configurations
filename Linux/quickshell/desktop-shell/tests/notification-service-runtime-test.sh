#!/usr/bin/env bash
set -Eeuo pipefail

repo_root=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../../../.." && pwd)
shell_dir="$repo_root/Linux/quickshell/desktop-shell"
SERVICE_QML="$shell_dir/plugins/notifications/Service.qml" python3 - <<'PY'
import os
import re

source = open(os.environ["SERVICE_QML"], encoding="utf-8").read()
restore = re.search(r"function restorePopups\(raw\) \{(.*?)\n  \}", source, re.S)
if not restore or "NotificationLogic.restorePopupPlan" not in restore.group(1):
    raise SystemExit("restorePopups must consume NotificationLogic.restorePopupPlan")
if "restoration.expired" not in restore.group(1) or "restoration.migrated" not in restore.group(1):
    raise SystemExit("restorePopups must use the restoration plan for archive and migration")
PY

if ! command -v quickshell >/dev/null 2>&1; then
  printf 'SKIP: quickshell unavailable\n'
  exit 0
fi

tmp_dir=$(mktemp -d)
shell_pid=""
trap '[[ -z $shell_pid ]] || kill "$shell_pid" 2>/dev/null || true; rm -rf -- "$tmp_dir"' EXIT

isolated_shell_dir="$tmp_dir/desktop-shell"
cp -a -- "$shell_dir" "$isolated_shell_dir"

env \
  HOME="$tmp_dir/home" \
  XDG_CONFIG_HOME="$tmp_dir/home/.config" \
  DESKTOP_SHELL_TEST_NO_SURFACES=1 \
  DESKTOP_SHELL_NOTIFICATIONS_REGISTER=0 \
  quickshell -n -p "$isolated_shell_dir" >"$tmp_dir/quickshell.log" 2>&1 &
shell_pid=$!

response=""
for _ in {1..100}; do
  response=$(quickshell ipc --pid "$shell_pid" call -- desktop.notifications ping 2>/dev/null || true)
  [[ $response == pong ]] && break
  kill -0 "$shell_pid" 2>/dev/null || break
  sleep 0.1
done

if [[ $response != pong ]]; then
  printf 'notification service IPC target failed to load\n' >&2
  sed -n '1,220p' "$tmp_dir/quickshell.log" >&2
  exit 1
fi

status=$(quickshell ipc --pid "$shell_pid" call -- desktop.notifications status)
DESKTOP_SHELL_STATUS="$status" python3 - <<'PY'
import json
import os

status = json.loads(os.environ["DESKTOP_SHELL_STATUS"])
if status.get("snapshotDuration") != 15000 or status.get("snapshotRemainingLifetime") != 15000:
    raise SystemExit("service snapshot duration/lifetime propagation is not visible at runtime")
expected = {
    "phase": "closed",
    "activeIdentity": "",
    "visualOutgoingIdentity": "",
    "visualIncomingIdentity": "",
    "transitionToken": 0,
    "transitionKind": "",
    "countdownIdentity": "",
    "pendingCount": 0,
}
for key, value in expected.items():
    if status.get(key) != value:
        raise SystemExit(f"suppressed presenter field {key}={status.get(key)!r}, expected {value!r}")
PY

printf 'PASS: notification service runtime loads\n'
