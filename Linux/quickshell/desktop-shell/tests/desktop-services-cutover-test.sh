#!/usr/bin/env bash
set -Eeuo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
ROOT="$(cd -- "$SCRIPT_DIR/../../../../" && pwd -P)"
CONFIG_FILE="$ROOT/tidydots.yaml"
AUTOSTART="$ROOT/Linux/hypr/autostart.lua"
SHELL_ROOT="$ROOT/Linux/quickshell/desktop-shell"
SHELL_UNIT="$SHELL_ROOT/systemd/desktop-shell.service"
ROLLBACK_UNIT="$SHELL_ROOT/systemd/desktop-shell-mako-route.service"
TIDYDOTS_BIN="$(command -v tidydots || true)"
DOCKER_BIN="$(command -v docker || true)"

fail() {
  printf 'FAIL: %s\n' "$*" >&2
  exit 1
}

assert_file() {
  local path="$1"
  local label="$2"

  [[ -r "$path" ]] || fail "$label is missing: $path"
}

assert_executable() {
  local path="$1"
  local label="$2"

  [[ -x "$path" ]] || fail "$label is not executable: $path"
}

extract_application() {
  local application="$1"

  awk -v wanted="$application" '
    function flush() {
      if (application_name == wanted) {
        printf "%s", block
      }
    }

    /^  - / {
      if (length(block) > 0) {
        flush()
      }
      block = $0 ORS
      application_name = ""
      next
    }

    {
      block = block $0 ORS
      if ($0 ~ /^    name: /) {
        application_name = $0
        sub(/^    name: /, "", application_name)
      }
    }

    END {
      if (length(block) > 0) {
        flush()
      }
    }
  ' "$CONFIG_FILE"
}

assert_application_line() {
  local application="$1"
  local expected_line="$2"
  local block

  block="$(extract_application "$application")"
  [[ -n "$block" ]] || fail "application $application is not declared"
  grep -Fqx -- "$expected_line" <<< "$block" ||
    fail "$application does not contain expected declaration: $expected_line"
}

is_allowed_zone() {
  case "$1" in
    Linux/mako/*|Linux/swayosd/*|Linux/*/tests/*|Linux/os/helpers/desktop-shell-rollback|Linux/os/helpers/desktop-shell-mako-route)
      return 0
      ;;
    *)
      return 1
      ;;
  esac
}

active_route_paths() {
  local path

  while IFS= read -r path; do
    case "$path" in
      Linux/hypr/*|Linux/autostart/*|Linux/vicinae/scripts/*|Linux/os/mimeapps.list|Linux/os/applications/*|Linux/quickshell/desktop-shell/*)
        if [[ -f "$ROOT/$path" ]] && ! is_allowed_zone "$path"; then
          printf '%s\n' "$path"
        fi
        ;;
    esac
  done < <(git -C "$ROOT" ls-files)
}

audit_active_routes() {
  local path forbidden_route match
  local -a forbidden_routes=(
    'uwsm-app -- mako'
    'uwsm-app -- swayosd-server'
    'polkit-gnome-authentication-agent-1'
    'makoctl'
    'swayosd-client'
    'swayosd-brightness'
    'swayosd-kbd-brightness'
  )
  local -a forbidden_hits=()

  while IFS= read -r path; do
    for forbidden_route in "${forbidden_routes[@]}"; do
      while IFS= read -r match; do
        [[ -n "$match" ]] || continue
        forbidden_hits+=("$path:$match")
      done < <(grep -nF -- "$forbidden_route" "$ROOT/$path" || true)
    done
  done < <(active_route_paths)

  if ((${#forbidden_hits[@]} > 0)); then
    printf 'FAIL: forbidden active desktop-service routes (%d):\n' "${#forbidden_hits[@]}" >&2
    printf '  %s\n' "${forbidden_hits[@]}" >&2
    exit 1
  fi
}

assert_autostart_order() {
  local marker line previous=0
  local -a markers=(
    'hl.exec_cmd("uwsm-app -- hypridle")'
    'hl.exec_cmd("uwsm-app -- fcitx5 --disable notificationitem")'
    'hl.exec_cmd("uwsm-app -- swaybg -c '\''#1e1e2e'\''")'
    'systemctl --user import-environment'
    'dbus-update-activation-environment --systemd --all'
    'hyprpm reload -n'
    'signal-desktop'
    'teams-for-linux'
  )

  for marker in "${markers[@]}"; do
    line="$(awk -v marker="$marker" 'index($0, marker) { print NR; exit }' "$AUTOSTART")"
    [[ -n "$line" ]] || fail "autostart marker is missing: $marker"
    ((line > previous)) || fail "autostart marker order changed at: $marker"
    previous=$line
  done
}

assert_manifests_and_helpers() {
  local manifest id
  local -a manifests=(
    'plugins/notifications/manifest.json|desktop.notifications'
    'plugins/osd/manifest.json|desktop.osd'
    'plugins/polkit/manifest.json|desktop.polkit'
  )

  for manifest in "${manifests[@]}"; do
    IFS='|' read -r manifest_path id <<< "$manifest"
    assert_file "$SHELL_ROOT/$manifest_path" "${id} manifest"
    grep -Fqx -- "  \"id\": \"$id\"," "$SHELL_ROOT/$manifest_path" ||
      fail "${id} manifest id is missing"
  done

  assert_executable "$ROOT/Linux/os/helpers/desktop-shell-activate" 'desktop-shell activation helper'
  assert_executable "$ROOT/Linux/os/helpers/desktop-shell-rollback" 'desktop-shell rollback helper'
  assert_executable "$ROOT/Linux/os/helpers/desktop-shell-mako-route" 'desktop-shell Mako rollback helper'
  assert_file "$SHELL_UNIT" 'desktop-shell service unit'
  assert_file "$ROLLBACK_UNIT" 'desktop-shell Mako rollback unit'
  grep -Fqx 'Conflicts=desktop-shell-mako-route.service' "$SHELL_UNIT" ||
    fail 'desktop-shell service unit does not isolate the rollback unit'
  grep -Fqx 'Conflicts=desktop-shell.service' "$ROLLBACK_UNIT" ||
    fail 'rollback unit does not isolate desktop-shell.service'
}

assert_legacy_declarations() {
  assert_application_line mako '        pacman: mako'
  assert_application_line mako '        backup: ./Linux/mako'
  assert_application_line swayosd '        pacman: swayosd'
  assert_application_line swayosd '        backup: ./Linux/swayosd'
  assert_application_line polkit-gnome '        pacman: polkit-gnome'
  assert_file "$ROOT/Linux/mako" 'Mako rollback configuration'
  assert_file "$ROOT/Linux/swayosd" 'SwayOSD rollback configuration'
}

assert_service_repair() {
  local block

  block="$(extract_application desktop-shell)"
  [[ -n "$block" ]] || fail 'desktop-shell application is not declared'
  grep -Fqx -- '          - desktop-shell.service' <<< "$block" ||
    fail 'desktop-shell service is not mapped'
  grep -Fqx -- '          - desktop-shell-mako-route.service' <<< "$block" ||
    fail 'rollback unit is not mapped'
  grep -Fq 'systemctl --user is-enabled --quiet desktop-shell.service &&' <<< "$block" ||
    fail 'desktop-shell repair does not require enabled state'
  grep -Fq 'systemctl --user is-active --quiet desktop-shell.service &&' <<< "$block" ||
    fail 'desktop-shell repair does not require active state'
  grep -Fq 'systemctl --user show desktop-shell.service --property=NeedDaemonReload --value' <<< "$block" ||
    fail 'desktop-shell repair does not check daemon reload state'
  grep -Fq 'systemctl --user daemon-reload && systemctl --user enable --now desktop-shell.service' <<< "$block" ||
    fail 'desktop-shell repair command changed'
  if grep -Fq 'is-enabled --quiet desktop-shell-mako-route.service' <<< "$block" ||
    grep -Fq 'enable --now desktop-shell-mako-route.service' <<< "$block"; then
    fail 'rollback unit is enabled by default'
  fi
  if grep -Fq 'WantedBy=' "$ROLLBACK_UNIT"; then
    fail 'rollback unit has an install target and may be enabled by default'
  fi
}

assert_rendered_graphical_profile() {
  local label="$1"
  local hostname="$2"
  local output

  if ! output="$("$DOCKER_BIN" run --rm --network none --hostname "$hostname" \
    --env DISPLAY=:99 --env WAYLAND_DISPLAY=wayland-test \
    --volume "$ROOT:/src:ro" \
    --volume "$TIDYDOTS_BIN:/usr/local/bin/tidydots:ro" \
    --workdir /src ubuntu:24.04 \
    bash -c 'exec /usr/local/bin/tidydots --dir /src --os linux list' 2>&1)"; then
    printf '%s\n' "$output" >&2
    fail "rendered graphical profile failed: $label"
  fi

  for application in desktop-shell hyprland mako swayosd polkit-gnome; do
    grep -Fqx -- "Application: $application" <<< "$output" ||
      fail "$application is missing from rendered graphical profile: $label"
  done
}

[[ -r "$CONFIG_FILE" ]] || fail "cannot read $CONFIG_FILE"
[[ -r "$AUTOSTART" ]] || fail "cannot read $AUTOSTART"
[[ -x "$TIDYDOTS_BIN" ]] || fail 'tidydots is required for rendered profile audits'
[[ -x "$DOCKER_BIN" ]] || fail 'docker is required for rendered graphical profile audits'

audit_active_routes
assert_autostart_order
assert_manifests_and_helpers
assert_legacy_declarations
assert_service_repair
assert_rendered_graphical_profile 'DESKTOP-E07VTRN graphical' DESKTOP-E07VTRN
assert_rendered_graphical_profile 'antoinews-linux graphical' antoinews-linux
assert_rendered_graphical_profile 'omarchbook graphical' omarchbook

printf 'PASS: desktop service cutover and graphical profile audit passed\n'
