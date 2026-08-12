#!/usr/bin/env bash
set -Eeuo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
REPO_DIR="$(cd -- "$SCRIPT_DIR/../../.." && pwd -P)"
TIDYDOTS_BIN="$(command -v tidydots || true)"

fail() {
  printf 'FAIL: %s\n' "$*" >&2
  exit 1
}

[[ -r "$REPO_DIR/tidydots.yaml" ]] || fail "cannot read $REPO_DIR/tidydots.yaml"
command -v docker >/dev/null 2>&1 || fail "docker is required for the headless profile test"
[[ -x "$TIDYDOTS_BIN" ]] || fail "tidydots is not installed"

list_headless_application() {
  local application="$1"

  docker run --rm --network none --hostname antoinews-linux \
    --env DISPLAY= \
    --env WAYLAND_DISPLAY= \
    --env XDG_RUNTIME_DIR=/nonexistent \
    --tmpfs /tmp \
    --volume "$REPO_DIR:/src:ro" \
    --volume "$TIDYDOTS_BIN:/usr/local/bin/tidydots:ro" \
    --workdir /src \
    ubuntu:24.04 \
    bash -c 'test -z "${DISPLAY:-}" && test -z "${WAYLAND_DISPLAY:-}" && test ! -e /tmp/.X11-unix && exec /usr/local/bin/tidydots --dir /src list "$1"' _ "$application"
}

for application in hyprland pipewire-audio waybar ghostty sddm os-files enable-desktop-services; do
  if ! output="$(list_headless_application "$application" 2>&1)"; then
    printf '%s\n' "$output" >&2
    fail "$application was not selected for headless antoinews-linux"
  fi

  grep -Fqx -- "Application: $application" <<< "$output" ||
    fail "headless list did not include application $application"
done

printf 'PASS: headless antoinews-linux selects the complete graphical profile\n'
