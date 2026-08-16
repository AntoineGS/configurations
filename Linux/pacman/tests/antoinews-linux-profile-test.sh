#!/usr/bin/env bash
set -Eeuo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
REPO_DIR="$(cd -- "$SCRIPT_DIR/../../.." && pwd -P)"
CONFIG_FILE="$REPO_DIR/tidydots.yaml"
SDDM_CONFIG="$REPO_DIR/Linux/sddm/autologin.conf"

fail() {
  printf 'FAIL: %s\n' "$*" >&2
  exit 1
}

[[ -r "$CONFIG_FILE" ]] || fail "cannot read $CONFIG_FILE"
[[ -r "$SDDM_CONFIG" ]] || fail "cannot read $SDDM_CONFIG"

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
    /^        pacman:/ {
      package_name = $0
      sub(/^        pacman:[[:space:]]*/, "", package_name)
      if (length(package_name) > 0) {
        print package_name
      }
      next
    }
  '
}

assert_exact_packages() {
  local application="$1"
  shift
  local block actual expected

  block="$(extract_application "$application")"
  [[ -n "$block" ]] || fail "application $application is not declared"

  actual="$(printf '%s\n' "$block" | extract_pacman_packages | sort)"
  expected="$(printf '%s\n' "$@" | sort)"
  [[ "$actual" == "$expected" ]] || {
    printf 'actual packages for %s:\n%s\nexpected packages:\n%s\n' "$application" "$actual" "$expected" >&2
    fail "pacman declaration for $application does not match the expected package set"
  }
}

assert_package_application() {
  local application="$1"
  local package="$2"
  local block actual

  block="$(extract_application "$application")"
  [[ -n "$block" ]] || fail "application $application is not declared"
  actual="$(printf '%s\n' "$block" | extract_pacman_packages)"
  [[ "$actual" == "$package" ]] || fail "pacman package for $application is $actual, expected $package"
}

assert_when() {
  local application="$1"
  local expected_when="$2"
  local actual_when

  actual_when="$(extract_application_field "$application" when)" || fail "application $application has no when predicate"
  [[ "$actual_when" == "$expected_when" ]] || fail "application $application does not use the expected predicate"
}

tidydots --dir "$REPO_DIR" list >/dev/null || fail "tidydots list could not parse the configuration"

INTEL_WHEN="'{{ eq .Hostname \"antoinews-linux\" }}'"
GRAPHICAL_WHEN="'{{ and (eq .OS \"linux\") (or .HasDisplay (eq .Hostname \"antoinews-linux\")) (not .IsWSL) }}'"

assert_when antoinews-linux-intel "$INTEL_WHEN"
assert_exact_packages antoinews-linux-intel \
  intel-ucode

for package in intel-media-driver libva-utils mesa mesa-utils vulkan-intel vulkan-tools; do
  assert_package_application "$package" "$package"
  assert_when "$package" "$INTEL_WHEN"
done

intel_block="$(extract_application antoinews-linux-intel)"
for forbidden in nvidia libva-nvidia thermald raydium qmk lnxlink tailscale-subnet-router; do
  if grep -Fq -- "$forbidden" <<< "$intel_block"; then
    fail "forbidden string $forbidden appears in the Intel profile"
  fi
done

assert_when sddm "$GRAPHICAL_WHEN"
sddm_block="$(extract_application sddm)"
if grep -Fq -- 'DESKTOP-E07VTRN' <<< "$sddm_block"; then
  fail "SDDM still uses the current-host-only predicate"
fi

grep -Fxq 'User=antoinegs' "$SDDM_CONFIG" || fail "SDDM autologin user changed"
grep -Fxq 'Session=hyprland-uwsm' "$SDDM_CONFIG" || fail "SDDM autologin session changed"

printf 'PASS: antoinews-linux Intel package profile and graphical SDDM gate are complete\n'
