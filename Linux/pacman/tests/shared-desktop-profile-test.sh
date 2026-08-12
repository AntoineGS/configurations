#!/usr/bin/env bash
set -Eeuo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
REPO_DIR="$(cd -- "$SCRIPT_DIR/../../.." && pwd -P)"
CONFIG_FILE="$REPO_DIR/tidydots.yaml"

fail() {
  printf 'FAIL: %s\n' "$*" >&2
  exit 1
}

[[ -r "$CONFIG_FILE" ]] || fail "cannot read $CONFIG_FILE"
command -v tidydots >/dev/null 2>&1 || fail "tidydots is not installed"

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
      if ($0 == "  - name: " wanted) {
        application_name = wanted
      }
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

extract_application_field() {
  local application="$1"
  local field="$2"
  local block

  block="$(extract_application "$application")"
  [[ -n "$block" ]] || return 1

  awk -v wanted="$field" '
    $0 ~ "^    " wanted ": " {
      value = $0
      sub("^    " wanted ": ", "", value)
      print value
      exit
    }
  ' <<< "$block"
}

extract_pacman_packages() {
  awk '
    /^      managers:$/ {
      in_managers = 1
      in_pacman = 0
      in_deps = 0
      next
    }

    in_managers && /^    [^[:space:]]/ {
      in_managers = 0
      in_pacman = 0
      in_deps = 0
      next
    }

    in_managers && /^        pacman:/ {
      in_pacman = 1
      in_deps = 0
      package_name = $0
      sub(/^        pacman:[[:space:]]*/, "", package_name)
      if (length(package_name) > 0) {
        print package_name
      }
      next
    }

    in_managers && /^        [^[:space:]]/ {
      in_pacman = 0
      in_deps = 0
      next
    }

    in_pacman && /^          deps:$/ {
      in_deps = 1
      next
    }

    in_pacman && in_deps && /^            - / {
      package_name = $0
      sub(/^            - /, "", package_name)
      print package_name
      next
    }

    in_pacman && /^          name: / {
      package_name = $0
      sub(/^          name: /, "", package_name)
      print package_name
      next
    }
  '
}

extract_service_units() {
  awk '
    /systemctl (is-enabled|enable)/ {
      line = $0
      while (match(line, /[[:alnum:]_.@-]+[.](service|socket)/)) {
        print substr(line, RSTART, RLENGTH)
        line = substr(line, RSTART + RLENGTH)
      }
    }
  '
}

assert_when() {
  local application="$1"
  local expected_when="$2"
  local actual_name actual_when

  actual_name="$(extract_application_field "$application" name)" || fail "application $application is not declared"
  [[ "$actual_name" == "$application" ]] || fail "application $application was not matched at application level"

  actual_when="$(extract_application_field "$application" when)" || fail "application $application has no application-level when predicate"
  [[ "$actual_when" == "$expected_when" ]] || fail "application $application does not use the expected Linux profile gate"
}

assert_packages() {
  local application="$1"
  shift
  local block packages package

  block="$(extract_application "$application")"
  [[ -n "$block" ]] || fail "application $application is not declared"
  [[ "$(extract_application_field "$application" name)" == "$application" ]] || fail "application $application was not matched at application level"
  packages="$(printf '%s\n' "$block" | extract_pacman_packages)"

  for package in "$@"; do
    if ! grep -Fxq -- "$package" <<< "$packages"; then
      fail "package $package is missing from the pacman declaration for $application"
    fi
  done
}

SHARED_PACKAGE_APPLICATIONS=(
  'hyprland:hyprland'
  'hypridle:hypridle'
  'hyprlock:hyprlock'
  'hyprshot:hyprshot'
  'hyprsunset:hyprsunset'
  'polkit-gnome:polkit-gnome'
  'sddm-package:sddm'
  'swaybg:swaybg'
  'uwsm:uwsm'
  'wl-clipboard:wl-clipboard'
  'wl-clip-persist:wl-clip-persist'
  'wtype:wtype'
  'xdg-desktop-portal-gtk:xdg-desktop-portal-gtk'
  'xdg-desktop-portal-hyprland:xdg-desktop-portal-hyprland'
  'pipewire-audio:pipewire'
  'pipewire-alsa:pipewire-alsa'
  'pipewire-pulse:pipewire-pulse'
  'wireplumber:wireplumber'
  'pamixer:pamixer'
  'linux-services-packages:ufw'
  'avahi:avahi'
  'bluez:bluez'
  'bluez-utils:bluez-utils'
  'cups:cups'
  'cups-browsed:cups-browsed'
  'docker:docker'
  'tailscale:tailscale'
)

GRAPHICAL_SHARED_APPLICATIONS=(
  hyprland
  hypridle
  hyprlock
  hyprshot
  hyprsunset
  polkit-gnome
  sddm-package
  swaybg
  uwsm
  wl-clipboard
  wl-clip-persist
  wtype
  xdg-desktop-portal-gtk
  xdg-desktop-portal-hyprland
  pipewire-audio
  pipewire-alsa
  pipewire-pulse
  wireplumber
  pamixer
)

REAL_LINUX_SHARED_APPLICATIONS=(
  linux-services-packages
  avahi
  bluez
  bluez-utils
  cups
  cups-browsed
  docker
  tailscale
)

assert_shared_package_declarations() {
  local declaration application package

  for declaration in "${SHARED_PACKAGE_APPLICATIONS[@]}"; do
    application="${declaration%%:*}"
    package="${declaration#*:}"
    assert_packages "$application" "$package"
  done
}

assert_dry_run_packages() {
  local output application package expected actual_count declaration
  local -a applications=()
  local -a packages=()

  for declaration in "${SHARED_PACKAGE_APPLICATIONS[@]}"; do
    applications+=("${declaration%%:*}")
    packages+=("${declaration#*:}")
  done

  [[ "${#applications[@]}" -eq "${#packages[@]}" ]] || fail "dry-run package test has mismatched application and package lists"

  if ! output="$(DISPLAY=:99 WAYLAND_DISPLAY=wayland-test tidydots --dir "$REPO_DIR" --os linux install "${applications[@]}" -n 2>&1)"; then
    printf '%s\n' "$output" >&2
    fail "tidydots dry-run could not install the shared package applications"
  fi

  for application in "${applications[@]}"; do
    [[ -n "$application" ]] || fail "dry-run application name is empty"
  done

  for i in "${!applications[@]}"; do
    application="${applications[$i]}"
    package="${packages[$i]}"
    expected="[ok] $application: Would run: sudo pacman -S --noconfirm $package"
    if ! grep -Fqx -- "$expected" <<< "$output"; then
      fail "dry-run for $application does not prove package $package\n$output"
    fi
  done

  actual_count="$(grep -c '^\[ok\] ' <<< "$output" || true)"
  [[ "$actual_count" -eq "${#applications[@]}" ]] || fail "dry-run returned $actual_count package commands, expected ${#applications[@]}\n$output"
}

package_for_service_unit() {
  local service_unit="$1"
  local service_name="${service_unit%.*}"

  case "$service_name" in
    avahi-daemon)
      printf 'avahi\n'
      ;;
    bluetooth)
      printf 'bluez\n'
      ;;
    tailscaled)
      printf 'tailscale\n'
      ;;
    *)
      printf '%s\n' "$service_name"
      ;;
  esac
}

if ! tidydots_list="$(tidydots --dir "$REPO_DIR" list 2>&1)"; then
  printf '%s\n' "$tidydots_list" >&2
  fail "tidydots list could not parse the configuration"
fi

GRAPHICAL_WHEN="'{{ and .HasDisplay (eq .OS \"linux\") (not .IsWSL) }}'"
REAL_LINUX_WHEN="'{{ and (eq .OS \"linux\") (not .IsWSL) }}'"

for application in "${GRAPHICAL_SHARED_APPLICATIONS[@]}"; do
  assert_when "$application" "$GRAPHICAL_WHEN"
done

for application in "${REAL_LINUX_SHARED_APPLICATIONS[@]}"; do
  assert_when "$application" "$REAL_LINUX_WHEN"
done

shared_packages=""
for declaration in "${SHARED_PACKAGE_APPLICATIONS[@]}"; do
  application="${declaration%%:*}"
  application_block="$(extract_application "$application")"
  shared_packages+="$(printf '%s\n' "$application_block" | extract_pacman_packages)"
  shared_packages+=$'\n'
done

for service_application in enable-desktop-services enable-linux-services; do
  service_block="$(extract_application "$service_application")"
  [[ -n "$service_block" ]] || fail "application $service_application is not declared"

  service_units="$(printf '%s\n' "$service_block" | extract_service_units)"
  while IFS= read -r service_unit; do
    [[ -n "$service_unit" ]] || continue
    service_package="$(package_for_service_unit "$service_unit")"
    if ! grep -Fxq -- "$service_package" <<< "$shared_packages"; then
      fail "service $service_unit in $service_application has no declared package $service_package"
    fi
  done <<< "$service_units"
done

assert_shared_package_declarations
assert_dry_run_packages

printf 'PASS: shared graphical Arch package profile is complete\n'
