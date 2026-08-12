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

extract_pacman_primary() {
  awk '
    /^        pacman:/ {
      package_name = $0
      sub(/^        pacman:[[:space:]]*/, "", package_name)
      if (length(package_name) > 0) {
        print package_name
        exit
      }
      in_pacman = 1
      next
    }

    in_pacman && /^          name: / {
      package_name = $0
      sub(/^          name: /, "", package_name)
      print package_name
      exit
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

assert_exact_packages() {
  local application="$1"
  local primary="$2"
  shift 2
  local block actual expected actual_count expected_count

  block="$(extract_application "$application")"
  [[ -n "$block" ]] || fail "application $application is not declared"
  [[ "$(extract_application_field "$application" name)" == "$application" ]] || fail "application $application was not matched at application level"
  [[ "$(printf '%s\n' "$block" | extract_pacman_primary)" == "$primary" ]] || fail "pacman primary for $application is not $primary"

  actual_count="$(printf '%s\n' "$block" | extract_pacman_packages | wc -l)"
  expected_count="$#"
  [[ "$actual_count" -eq "$expected_count" ]] || fail "pacman declaration for $application has $actual_count packages, expected $expected_count"

  actual="$(printf '%s\n' "$block" | extract_pacman_packages | sort)"
  expected="$(printf '%s\n' "$@" | sort)"
  [[ "$actual" == "$expected" ]] || {
    printf 'actual packages for %s:\n%s\nexpected packages:\n%s\n' "$application" "$actual" "$expected" >&2
    fail "pacman declaration for $application does not match the exact package expansion"
  }
}

HYPRLAND_PACKAGES=(
  hyprland
  hypridle
  hyprlock
  hyprshot
  hyprsunset
  polkit-gnome
  sddm
  swaybg
  uwsm
  wl-clipboard
  wl-clip-persist
  wtype
  xdg-desktop-portal-gtk
  xdg-desktop-portal-hyprland
)

PIPEWIRE_AUDIO_PACKAGES=(
  pipewire
  pipewire-alsa
  pipewire-pulse
  wireplumber
  pamixer
)

LINUX_SERVICES_PACKAGE_SET=(
  ufw
  avahi
  bluez
  bluez-utils
  cups
  cups-browsed
  docker
  tailscale
)

PROFILE_ANCHORS=(
  hyprland
  pipewire-audio
  linux-services-packages
)

GRAPHICAL_SHARED_APPLICATIONS=(
  hyprland
  pipewire-audio
)

REAL_LINUX_SHARED_APPLICATIONS=(
  linux-services-packages
)

assert_grouped_package_declarations() {
  assert_exact_packages hyprland hyprland "${HYPRLAND_PACKAGES[@]}"
  assert_exact_packages pipewire-audio pipewire "${PIPEWIRE_AUDIO_PACKAGES[@]}"
  assert_exact_packages linux-services-packages ufw "${LINUX_SERVICES_PACKAGE_SET[@]}"
}

assert_focused_dry_run() {
  local application="$1"
  local package="$2"
  local output expected actual

  expected="[ok] $application: Would run: sudo pacman -S --noconfirm $package"
  if ! output="$(tidydots --dir "$REPO_DIR" install "$application" -n 2>&1)"; then
    printf '%s\n' "$output" >&2
    fail "focused dry-run for $application failed"
  fi

  actual="$(printf '%s\n' "$output" | grep -F 'Would run: sudo pacman -S --noconfirm ' || true)"
  [[ "$actual" == "$expected" ]] || {
    printf 'dry-run output for %s:\n%s\n' "$application" "$output" >&2
    fail "focused dry-run for $application does not prove primary package $package"
  }
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

assert_grouped_package_declarations
assert_focused_dry_run hyprland hyprland
assert_focused_dry_run pipewire-audio pipewire
assert_focused_dry_run linux-services-packages ufw

GRAPHICAL_WHEN="'{{ and (eq .OS \"linux\") (or .HasDisplay (eq .Hostname \"antoinews-linux\")) (not .IsWSL) }}'"
REAL_LINUX_WHEN="'{{ and (eq .OS \"linux\") (not .IsWSL) }}'"

for application in "${GRAPHICAL_SHARED_APPLICATIONS[@]}"; do
  assert_when "$application" "$GRAPHICAL_WHEN"
done

for application in "${REAL_LINUX_SHARED_APPLICATIONS[@]}"; do
  assert_when "$application" "$REAL_LINUX_WHEN"
done

shared_packages=""
for application in "${PROFILE_ANCHORS[@]}"; do
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
