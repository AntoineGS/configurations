#!/usr/bin/env bash
set -Eeuo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../../.." && pwd)"
SHELL_ROOT="$ROOT/Linux/quickshell/desktop-shell"

if ! command -v quickshell >/dev/null 2>&1; then
  printf 'SKIP: quickshell is unavailable\n'
  exit 0
fi

if [[ -z ${WAYLAND_DISPLAY:-} ]]; then
  printf 'SKIP: no Wayland session is available\n'
  exit 0
fi

command -v jq >/dev/null 2>&1 || {
  printf 'FAIL: jq is required\n' >&2
  exit 1
}
command -v timeout >/dev/null 2>&1 || {
  printf 'FAIL: timeout is required\n' >&2
  exit 1
}

preview_log=$(mktemp)
preview_pid=''

cleanup() {
  local status=$?

  trap - EXIT HUP INT TERM
  if [[ -n $preview_pid ]] && kill -0 "$preview_pid" 2>/dev/null; then
    kill "$preview_pid" 2>/dev/null || true
    for _ in {1..20}; do
      kill -0 "$preview_pid" 2>/dev/null || break
      sleep 0.1
    done
    kill -KILL "$preview_pid" 2>/dev/null || true
  fi
  [[ -z $preview_pid ]] || wait "$preview_pid" 2>/dev/null || true

  if grep -Fq 'Loader.Error' "$preview_log"; then
    printf 'FAIL: Loader.Error found in the Quickshell preview log\n' >&2
    status=1
  fi
  if grep -Eq 'Plugin widget [^[:space:]]+ failed:' "$preview_log"; then
    printf 'FAIL: plugin widget failure found in the Quickshell preview log\n' >&2
    status=1
  fi
  if ((status != 0)) && [[ -s $preview_log ]]; then
    printf '%s\n' '--- quickshell preview log ---' >&2
    printf '%s\n' "$(<"$preview_log")" >&2
  fi

  rm -f "$preview_log"
  exit "$status"
}

trap cleanup EXIT
trap 'exit 129' HUP
trap 'exit 130' INT
trap 'exit 143' TERM

DESKTOP_SHELL_PREVIEW=1 quickshell -p "$SHELL_ROOT" >"$preview_log" 2>&1 &
preview_pid=$!

deadline=$((SECONDS + 15))
ping=''
while ((SECONDS < deadline)); do
  kill -0 "$preview_pid" 2>/dev/null || {
    printf 'FAIL: Quickshell preview exited before becoming ready\n' >&2
    exit 1
  }
  ping=$(timeout --kill-after=1s 1s quickshell ipc --pid "$preview_pid" \
    call desktop-shell ping 2>/dev/null) || true
  [[ $ping == pong ]] && break
  sleep 0.2
done

[[ $ping == pong ]] || {
  printf 'FAIL: desktop-shell ping did not return pong within 15 seconds\n' >&2
  exit 1
}

plugins=$(timeout --kill-after=1s 3s quickshell ipc --pid "$preview_pid" \
  call desktop-shell listPlugins 2>/dev/null) || {
  printf 'FAIL: desktop-shell listPlugins failed\n' >&2
  exit 1
}

jq -e -s '
  length == 1 and
  (.[0] | (if type == "string" then fromjson else . end) | has("desktop.bar"))
' <<<"$plugins" >/dev/null || {
  printf 'FAIL: listPlugins did not report desktop.bar\n' >&2
  exit 1
}

printf 'PASS: Quickshell preview runtime\n'
