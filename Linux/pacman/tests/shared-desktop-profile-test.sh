#!/usr/bin/env bash
set -Eeuo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
REPO_DIR="$(cd -- "$SCRIPT_DIR/../../.." && pwd -P)"
CONFIG_FILE="$REPO_DIR/tidydots.yaml"
PYTHON_BIN="${PYTHON_BIN:-python3}"
RUNTIME_AUDIT="$SCRIPT_DIR/hyprland_runtime_audit.py"

fail() {
  printf 'FAIL: %s\n' "$*" >&2
  exit 1
}

[[ -r "$CONFIG_FILE" ]] || fail "cannot read $CONFIG_FILE"
command -v tidydots >/dev/null 2>&1 || fail "tidydots is not installed"
command -v "$PYTHON_BIN" >/dev/null 2>&1 || fail "$PYTHON_BIN is not installed"
[[ -r "$RUNTIME_AUDIT" ]] || fail "cannot read $RUNTIME_AUDIT"

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

extract_direct_manager_packages() {
  local manager="$1"

  awk -v wanted="$manager" '
    /^      managers:$/ {
      in_managers = 1
      next
    }

    in_managers && /^    [^[:space:]]/ {
      in_managers = 0
      next
    }

    in_managers && $0 ~ "^        " wanted ":[[:space:]]+[^[:space:]]" {
      package_name = $0
      sub("^        " wanted ":[[:space:]]+", "", package_name)
      print package_name
      next
    }
  '
}

extract_direct_arch_declarations() {
  awk '
    /^  - / {
      application = ""
      in_managers = 0
      next
    }

    /^    name: / {
      application = $0
      sub(/^    name: /, "", application)
      next
    }

    /^      managers:$/ {
      in_managers = 1
      next
    }

    in_managers && /^    [^[:space:]]/ {
      in_managers = 0
      next
    }

    in_managers && /^        (pacman|yay):[[:space:]]+[^[:space:]]/ {
      declaration = $0
      sub(/^        /, "", declaration)
      split(declaration, parts, /:[[:space:]]+/)
      print parts[1] "|" parts[2] "|" application
      next
    }
  ' "$CONFIG_FILE"
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

assert_application_absent() {
  local application="$1"

  [[ -z "$(extract_application "$application")" ]] || fail "legacy application $application remains declared"
  if grep -Fqx -- "Application: $application" <<< "$tidydots_list"; then
    fail "legacy application $application remains listed by tidydots"
  fi
}

assert_package_absent() {
  local package="$1"

  if extract_direct_manager_packages pacman | grep -Fxq -- "$package" ||
    extract_direct_manager_packages yay | grep -Fxq -- "$package"; then
    fail "legacy package $package remains declared"
  fi

  if grep -Eq -- "^(Package|Dependency): $package$" <<< "$tidydots_list"; then
    fail "legacy package $package remains listed by tidydots"
  fi
}

assert_source_requires_package() {
  local source_file="$1"
  local source_evidence="$2"
  local application="$3"
  local manager="$4"
  local package="$5"
  local source_path block

  source_path="$REPO_DIR/$source_file"
  [[ -r "$source_path" ]] || fail "runtime requirement source $source_file is not readable"
  grep -Fq -- "$source_evidence" "$source_path" ||
    fail "runtime requirement source $source_file no longer contains: $source_evidence"

  block="$(extract_application "$application")"
  [[ -n "$block" ]] || fail "application $application is not declared"
  if ! printf '%s\n' "$block" | extract_direct_manager_packages "$manager" | grep -Fxq -- "$package"; then
    fail "runtime source $source_file requires package $package in $application ($manager)"
  fi
}

GRAPHICAL_SHARED_APPLICATIONS=(
  1password
  brave
  desktop-shell
  hyprland
  bluetui
  brightnessctl
  evince
  ffmpeg
  gpu-screen-recorder
  grim
  hypridle
  hyprlock
  hyprpicker
  hyprshot
  hyprsunset
  impala
  imv
  lazydocker
  libnotify
  mpv
  nautilus
  playerctl
  satty
  sddm
  slurp
  socat
  swaybg
  uwsm
  v4l-utils
  waypipe
  wl-clipboard
  wl-clip-persist
  wtype
  xdg-desktop-portal-gtk
  xdg-desktop-portal-hyprland
  xdg-utils
  pipewire-audio
  pipewire-alsa
  pipewire-pulse
  wireplumber
  wiremix
  codexbar-cli
  hyprland-preview-share-picker
  insync
  obsidian
  signal
  xdg-terminal-exec
)

LEGACY_APPLICATIONS=(waybar mako swayosd polkit-gnome pamixer)
LEGACY_PACKAGES=(waybar waybar-git waybar-ai-usage-go-bin mako swayosd polkit-gnome pamixer)

OPTIONAL_GRAPHICAL_APPLICATIONS=(
  localsend
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

LINUX_SHARED_APPLICATIONS=(
  pacman-hooks
  rebuild-detector
)

assert_no_arch_dependency_arrays() {
  if awk '
    /^      managers:$/ {
      in_managers = 1
      in_arch_manager = 0
      next
    }

    in_managers && /^    [^[:space:]]/ {
      in_managers = 0
      in_arch_manager = 0
      next
    }

    in_managers && /^        (pacman|yay):$/ {
      in_arch_manager = 1
      next
    }

    in_managers && /^        [^[:space:]]/ {
      in_arch_manager = 0
      next
    }

    in_arch_manager && /^          deps:$/ {
      found = 1
    }

    END {
      exit found ? 0 : 1
    }
  ' "$CONFIG_FILE"; then
    fail 'pacman/yay dependency arrays remain hidden from previews'
  fi
}

assert_no_duplicate_arch_packages() {
  local declaration key manager package application
  local -a declarations=()
  declare -A seen=()

  mapfile -t declarations < <(extract_direct_arch_declarations)
  for declaration in "${declarations[@]}"; do
    IFS='|' read -r manager package application <<< "$declaration"
    key="$manager|$package"
    [[ -z "${seen[$key]+set}" ]] || fail "Arch package $key is declared more than once (application $application)"
    seen["$key"]="$application"
  done
}

assert_hyprland_runtime_ownership() {
  local -a command=("$PYTHON_BIN" "$RUNTIME_AUDIT" --manifest "$CONFIG_FILE")
  "${command[@]}"
}

assert_runtime_requirements() {
  assert_source_requires_package Linux/hypr/autostart.lua 'hl.exec_cmd("signal-desktop")' signal pacman signal-desktop
  assert_source_requires_package Linux/os/mimeapps.list image/png=imv.desktop imv pacman imv
  assert_source_requires_package Linux/hypr/bindings/apps.lua 'launch-tui-large lazydocker' lazydocker pacman lazydocker
  assert_source_requires_package Linux/os/applications/common/Docker.desktop '-e lazydocker' lazydocker pacman lazydocker
  assert_source_requires_package Linux/os/mimeapps.list application/pdf=org.gnome.Evince.desktop evince pacman evince
  assert_source_requires_package Linux/hypr/apps/system.lua org.gnome.Evince evince pacman evince
  assert_source_requires_package Linux/os/mimeapps.list inode/directory=org.gnome.Nautilus.desktop nautilus pacman nautilus
  assert_source_requires_package Linux/hypr/apps/system.lua org.gnome.Nautilus nautilus pacman nautilus
  assert_source_requires_package Linux/os/helpers/cmd-share 'localsend --headless send' localsend yay localsend
  assert_source_requires_package Linux/hypr/apps/localsend.lua 'class = "(Share|localsend)"' localsend yay localsend
  assert_hyprland_runtime_ownership
}

assert_focused_dry_run() {
  local application="$1"
  local manager="$2"
  local package="$3"
  local output expected actual

  case "$manager" in
    pacman)
      expected="[ok] $application: Would run: sudo pacman -S --noconfirm $package"
      ;;
    yay)
      expected="[ok] $application: Would run: yay -S --noconfirm $package"
      ;;
    *)
      fail "unsupported focused dry-run manager $manager"
      ;;
  esac

  if ! output="$(tidydots --dir "$REPO_DIR" install "$application" -n 2>&1)"; then
    printf '%s\n' "$output" >&2
    fail "focused dry-run for $application failed"
  fi

  actual="$(printf '%s\n' "$output" | grep -F "Would run: ${expected#*Would run: }" || true)"
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

assert_application_absent codexbar
assert_application_absent claudebar
for application in "${LEGACY_APPLICATIONS[@]}"; do
  assert_application_absent "$application"
done
for package in "${LEGACY_PACKAGES[@]}"; do
  assert_package_absent "$package"
done

assert_no_arch_dependency_arrays
assert_no_duplicate_arch_packages
assert_runtime_requirements
assert_focused_dry_run hyprland pacman hyprland
assert_focused_dry_run hyprland-preview-share-picker yay hyprland-preview-share-picker-git
assert_focused_dry_run localsend yay localsend
assert_focused_dry_run pipewire-audio pacman pipewire
assert_focused_dry_run linux-services-packages pacman ufw
assert_focused_dry_run brave yay brave-bin
assert_focused_dry_run signal pacman signal-desktop
assert_focused_dry_run insync yay insync
assert_focused_dry_run obsidian pacman obsidian
assert_focused_dry_run 1password yay 1password-beta
assert_focused_dry_run codexbar-cli yay codexbar-cli

GRAPHICAL_WHEN="'{{ and (eq .OS \"linux\") (or .HasDisplay (eq .Hostname \"antoinews-linux\")) (not .IsWSL) }}'"
POWER_PROFILE_WHEN="'{{ and (eq .OS \"linux\") .HasDisplay (not .IsWSL) (ne .Hostname \"antoinews-linux\") }}'"
REAL_LINUX_WHEN="'{{ and (eq .OS \"linux\") (not .IsWSL) }}'"
LINUX_WHEN="'{{ eq .OS \"linux\" }}'"

for application in "${GRAPHICAL_SHARED_APPLICATIONS[@]}"; do
  assert_when "$application" "$GRAPHICAL_WHEN"
done

for application in "${REAL_LINUX_SHARED_APPLICATIONS[@]}"; do
  assert_when "$application" "$REAL_LINUX_WHEN"
done

for application in "${LINUX_SHARED_APPLICATIONS[@]}"; do
  assert_when "$application" "$LINUX_WHEN"
done

for application in "${OPTIONAL_GRAPHICAL_APPLICATIONS[@]}"; do
  assert_when "$application" "$GRAPHICAL_WHEN"
done

assert_when power-profiles-daemon "$POWER_PROFILE_WHEN"

shared_packages=""
shared_packages="$(extract_direct_arch_declarations | awk -F'|' '$1 == "pacman" { print $2 }')"

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
