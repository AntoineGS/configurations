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
      if ($0 == "    name: " wanted) {
        application_name = wanted
      }
    }

    END {
      if (length(block) > 0) {
        flush()
      }
    }
  ' "$CONFIG_FILE"
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
  local block

  block="$(extract_application "$application")"
  [[ -n "$block" ]] || fail "application $application is not declared"
  if ! grep -Fq -- "$expected_when" <<< "$block"; then
    fail "application $application does not use the expected Linux profile gate"
  fi
}

assert_packages() {
  local application="$1"
  shift
  local block packages package

  block="$(extract_application "$application")"
  [[ -n "$block" ]] || fail "application $application is not declared"
  packages="$(printf '%s\n' "$block" | extract_pacman_packages)"

  for package in "$@"; do
    if ! grep -Fxq -- "$package" <<< "$packages"; then
      fail "package $package is missing from the pacman declaration for $application"
    fi
  done
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

GRAPHICAL_WHEN="when: '{{ and .HasDisplay (eq .OS \"linux\") (not .IsWSL) }}'"
REAL_LINUX_WHEN="when: '{{ and (eq .OS \"linux\") (not .IsWSL) }}'"

assert_when hyprland "$GRAPHICAL_WHEN"
assert_when pipewire-audio "$GRAPHICAL_WHEN"
assert_when linux-services-packages "$REAL_LINUX_WHEN"

assert_packages hyprland \
  hyprland \
  hypridle \
  hyprlock \
  hyprshot \
  hyprsunset \
  polkit-gnome \
  sddm \
  swaybg \
  uwsm \
  wl-clipboard \
  wl-clip-persist \
  wtype \
  xdg-desktop-portal-gtk \
  xdg-desktop-portal-hyprland

assert_packages pipewire-audio \
  pipewire \
  pipewire-alsa \
  pipewire-pulse \
  wireplumber \
  pamixer

assert_packages linux-services-packages \
  ufw \
  avahi \
  bluez \
  bluez-utils \
  cups \
  cups-browsed \
  docker \
  tailscale

shared_packages=""
for application in hyprland pipewire-audio linux-services-packages; do
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

printf 'PASS: shared graphical Arch package profile is complete\n'
