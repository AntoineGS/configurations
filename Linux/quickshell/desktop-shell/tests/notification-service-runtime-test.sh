#!/usr/bin/env bash
set -Eeuo pipefail

if ! command -v quickshell >/dev/null 2>&1; then
  printf 'SKIP: quickshell unavailable\n'
  exit 0
fi

repo_root=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../../../.." && pwd)
shell_dir="$repo_root/Linux/quickshell/desktop-shell"
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

printf 'PASS: notification service runtime loads\n'
