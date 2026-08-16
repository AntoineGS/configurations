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

list_headless_host() {
  local hostname="$1"

  docker run --rm --network none --hostname "$hostname" \
    --env DISPLAY= \
    --env WAYLAND_DISPLAY= \
    --env XDG_RUNTIME_DIR=/nonexistent \
    --tmpfs /tmp \
    --volume "$REPO_DIR:/src:ro" \
    --volume "$TIDYDOTS_BIN:/usr/local/bin/tidydots:ro" \
    --workdir /src \
    ubuntu:24.04 \
    bash -c 'test -z "${DISPLAY:-}" && test -z "${WAYLAND_DISPLAY:-}" && test ! -e /tmp/.X11-unix && exec /usr/local/bin/tidydots --dir /src list'
}

list_wsl_host() {
  local hostname="$1"

  docker run --rm --cap-add SYS_ADMIN --security-opt seccomp=unconfined --network none --hostname "$hostname" \
    --env DISPLAY= \
    --env WAYLAND_DISPLAY= \
    --env XDG_RUNTIME_DIR=/nonexistent \
    --tmpfs /tmp \
    --volume "$REPO_DIR:/src:ro" \
    --volume "$TIDYDOTS_BIN:/usr/local/bin/tidydots:ro" \
    --workdir /src \
    ubuntu:24.04 \
    bash -c '
      set -Eeuo pipefail
      mkdir -p /tmp/fake-proc
      printf "%s\n" "Linux version 6.6.0-microsoft-standard-WSL2" > /tmp/fake-proc/version
      exec unshare --mount -- bash -c "
        mount --make-rprivate /
        mount --bind /tmp/fake-proc /proc
        grep -Fq microsoft /proc/version
        exec /usr/local/bin/tidydots --dir /src list
      "
    '
}

assert_selected() {
  local hostname="$1"
  local output="$2"
  local application="$3"

  grep -Fqx -- "Application: $application" <<< "$output" ||
    fail "$application was not selected for headless $hostname"
}

assert_excluded() {
  local hostname="$1"
  local output="$2"
  local application="$3"

  if grep -Fqx -- "Application: $application" <<< "$output"; then
    fail "$application was selected for excluded headless $hostname"
  fi
}

GRAPHICAL_APPLICATIONS=(
  1password
  brave
  xcompose
  desktop-shell
  hyprland
  pipewire-audio
  waybar
  uwsm
  sddm
  teams-for-linux
  ghostty
  fcitx5
  fontconfig
  hyprland-preview-share-picker
  imv
  insync
  mako
  obsidian
  signal
  swayosd
  typora
  wiremix
  vicinae
  autostart
  browser-flags
  enable-desktop-services
)

if ! antoinews_output="$(list_headless_host antoinews-linux 2>&1)"; then
  printf '%s\n' "$antoinews_output" >&2
  fail "headless antoinews-linux profile listing failed"
fi

for application in "${GRAPHICAL_APPLICATIONS[@]}"; do
  assert_selected antoinews-linux "$antoinews_output" "$application"
done

if ! server_output="$(list_headless_host server 2>&1)"; then
  printf '%s\n' "$server_output" >&2
  fail "headless server profile listing failed"
fi

for application in "${GRAPHICAL_APPLICATIONS[@]}"; do
  assert_excluded server "$server_output" "$application"
done

if ! other_headless_output="$(list_headless_host other-headless 2>&1)"; then
  printf '%s\n' "$other_headless_output" >&2
  fail "other headless profile listing failed"
fi

for application in "${GRAPHICAL_APPLICATIONS[@]}"; do
  assert_excluded other-headless "$other_headless_output" "$application"
done

if ! wsl_output="$(list_wsl_host antoinews-linux 2>&1)"; then
  printf '%s\n' "$wsl_output" >&2
  fail "WSL profile listing failed"
fi

for application in "${GRAPHICAL_APPLICATIONS[@]}"; do
  assert_excluded WSL "$wsl_output" "$application"
done

printf 'PASS: graphical profile host selection preserves headless and WSL exclusions\n'
