#!/usr/bin/env bash
set -Eeuo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
REPO_DIR="$(cd -- "$SCRIPT_DIR/../../.." && pwd -P)"
CONFIG_FILE="$REPO_DIR/tidydots.yaml"
TIDYDOTS_BIN="$(command -v tidydots || true)"

fail() {
  printf 'FAIL: %s\n' "$*" >&2
  exit 1
}

[[ -r "$CONFIG_FILE" ]] || fail "cannot read $CONFIG_FILE"
[[ -x "$TIDYDOTS_BIN" ]] || fail "tidydots is not installed"
command -v docker >/dev/null 2>&1 || fail "docker is required for controlled profile previews"

extract_manifest_arch_declarations() {
  awk '
    function reset( i) {
      application = ""
      in_managers = 0
      has_non_arch_method = 0
      declaration_count = 0
      for (i in manager_names) {
        delete manager_names[i]
        delete package_names[i]
      }
    }

    function flush( i) {
      if (application == "") {
        return
      }

      for (i = 1; i <= declaration_count; i++) {
        print application "\t" manager_names[i] "\t" package_names[i] "\t" has_non_arch_method
      }
    }

    /^  - / {
      if (seen_application) {
        flush()
      }
      reset()
      seen_application = 1
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

    in_managers && /^        (git|installer):/ {
      has_non_arch_method = 1
      next
    }

    in_managers && /^        (pacman|yay):[[:space:]]+[^[:space:]]/ {
      declaration = $0
      sub(/^        /, "", declaration)
      manager = declaration
      sub(/:.*/, "", manager)
      package_name = declaration
      sub(/^[^:]+:[[:space:]]+/, "", package_name)
      declaration_count++
      manager_names[declaration_count] = manager
      package_names[declaration_count] = package_name
      next
    }

    in_managers && /^        [^[:space:]]/ {
      next
    }

    /^      (custom|url):/ {
      has_non_arch_method = 1
      next
    }

    END {
      if (seen_application) {
        flush()
      }
    }
  ' "$CONFIG_FILE"
}

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

assert_yazi_windows_dependencies() {
  local yazi_block package_name

  yazi_block="$(awk '
    /^  - / {
      if (length(block) > 0 && application == "yazi") {
        printf "%s", block
        exit
      }
      block = $0 ORS
      application = ""
      next
    }

    {
      block = block $0 ORS
      if ($0 == "    name: yazi") {
        application = "yazi"
      }
    }

    END {
      if (application == "yazi") {
        printf "%s", block
      }
    }
  ' "$CONFIG_FILE")"
  [[ -n "$yazi_block" ]] || fail 'yazi application is not declared'
  grep -Fqx -- '          name: sxyazi.yazi' <<< "$yazi_block" || fail 'Yazi Windows package name changed'

  for package_name in 7zip.7zip jqlang.jq sharkdp.fd burntsushi.ripgrep.msvc junegunn.fzf ajeetdsouza.zoxide imagemagick.imagemagick GnuWin32.File; do
    grep -Fqx -- "            - $package_name" <<< "$yazi_block" || fail "Yazi Windows dependency changed: $package_name"
  done
}

load_manifest() {
  local application manager package_name has_non_arch_method key declaration
  local -a declarations=()
  declare -A seen_manager_packages=()

  declare -gA MANIFEST_PACKAGE_BY_KEY=()
  declare -gA MANIFEST_NON_ARCH_BY_APP=()
  mapfile -t declarations < <(extract_manifest_arch_declarations)

  for declaration in "${declarations[@]}"; do
    IFS=$'\t' read -r application manager package_name has_non_arch_method <<< "$declaration"
    key="$application|$manager"
    [[ -z "${MANIFEST_PACKAGE_BY_KEY[$key]+set}" ]] || fail "duplicate direct $manager declaration for $application"
    MANIFEST_PACKAGE_BY_KEY["$key"]="$package_name"

    if [[ "$has_non_arch_method" == 1 ]]; then
      MANIFEST_NON_ARCH_BY_APP["$application"]=1
    fi

    key="$manager|$package_name"
    [[ -z "${seen_manager_packages[$key]+set}" ]] || fail "duplicate real Arch installation for $key"
    seen_manager_packages["$key"]="$application"
  done
}

extract_selected_arch_applications() {
  awk '
    / \((pacman|yay)\)$/ {
      line = $0
      sub(/^[^[:alnum:]]+/, "", line)

      manager = line
      sub(/^.* \(/, "", manager)
      sub(/\)$/, "", manager)

      application = line
      sub(/[[:space:]]+\((pacman|yay)\)$/, "", application)
      print application "\t" manager
    }
  '
}

extract_actual_arch_operations() {
  awk '
    /^\[ok\] / {
      line = $0
      sub(/^\[ok\] /, "", line)

      application = line
      sub(/: Would run: .*/, "", application)

      command = line
      sub(/^.*: Would run: /, "", command)

      if (command ~ /^sudo pacman -S --noconfirm [^[:space:]]+$/) {
        package_name = command
        sub(/^sudo pacman -S --noconfirm /, "", package_name)
        print application "\tpacman\t" package_name
      } else if (command ~ /^yay -S --noconfirm [^[:space:]]+$/) {
        package_name = command
        sub(/^yay -S --noconfirm /, "", package_name)
        print application "\tyay\t" package_name
      }
    }
  '
}

expected_arch_operations() {
  local list_output="$1"
  local application manager key package_name

  while IFS=$'\t' read -r application manager; do
    [[ -n "$application" ]] || continue
    key="$application|$manager"
    package_name="${MANIFEST_PACKAGE_BY_KEY[$key]-}"
    [[ -n "$package_name" ]] || fail "selected $manager application $application has no direct manifest declaration"

    [[ -z "${MANIFEST_NON_ARCH_BY_APP[$application]+set}" ]] || continue
    printf '%s\t%s\t%s\n' "$application" "$manager" "$package_name"
  done < <(printf '%s\n' "$list_output" | extract_selected_arch_applications)
}

extract_section() {
  local output="$1"
  local start_marker="$2"
  local end_marker="$3"

  awk -v start="$start_marker" -v end="$end_marker" '
    $0 == start {
      in_section = 1
      next
    }

    index($0, end) == 1 {
      exit
    }

    in_section {
      print
    }
  ' <<< "$output"
}

assert_operation_multiset() {
  local label="$1"
  local expected="$2"
  local actual="$3"
  local temporary_directory

  temporary_directory="$(mktemp -d)"
  printf '%s\n' "$expected" | LC_ALL=C sort >"$temporary_directory/expected"
  printf '%s\n' "$actual" | LC_ALL=C sort >"$temporary_directory/actual"

  if ! cmp -s "$temporary_directory/expected" "$temporary_directory/actual"; then
    printf 'FAIL: %s package operation multiset differs\n' "$label" >&2
    printf '%s\n' 'Missing operations:' >&2
    comm -23 "$temporary_directory/expected" "$temporary_directory/actual" >&2 || true
    printf '%s\n' 'Extra operations:' >&2
    comm -13 "$temporary_directory/expected" "$temporary_directory/actual" >&2 || true
    rm -rf -- "$temporary_directory"
    exit 1
  fi

  rm -rf -- "$temporary_directory"
}

assert_preview() {
  local label="$1"
  local list_output="$2"
  local install_output="$3"
  local install_status="$4"
  local expected actual

  [[ "$install_status" == 0 ]] || {
    printf 'install preview for %s exited %s:\n%s\n' "$label" "$install_status" "$install_output" >&2
    fail "canonical unscoped preview failed for $label"
  }

  expected="$(expected_arch_operations "$list_output")"
  actual="$(printf '%s\n' "$install_output" | extract_actual_arch_operations)"
  [[ -n "$expected" ]] || fail "manifest produced no Arch operations for $label"
  [[ -n "$actual" ]] || fail "preview produced no Arch operations for $label"
  assert_operation_multiset "$label" "$expected" "$actual"
}

assert_windows_installer() {
  local application="$1"
  local command="$2"
  local output expected

  if output="$(tidydots --dir "$REPO_DIR" --os windows install "$application" -n 2>&1)"; then
    :
  else
    printf '%s\n' "$output" >&2
    fail "Windows preview failed for $application"
  fi

  expected="[ok] $application: Would run: $command"
  grep -Fqx -- "$expected" <<< "$output" || {
    printf 'Windows preview for %s:\n%s\n' "$application" "$output" >&2
    fail "Windows installer command changed for $application"
  }
}

run_native_profile() {
  local label="$1"
  local list_output install_output install_status

  if ! list_output="$(tidydots --dir "$REPO_DIR" --os linux list-packages 2>&1)"; then
    printf '%s\n' "$list_output" >&2
    fail "list-packages failed for $label"
  fi

  if install_output="$(tidydots --dir "$REPO_DIR" --os linux install -n 2>&1)"; then
    install_status=0
  else
    install_status=$?
  fi

  assert_preview "$label" "$list_output" "$install_output" "$install_status"
}

run_container_profile() {
  local label="$1"
  local hostname="$2"
  local display_mode="$3"
  local output list_output install_output install_status
  local -a display_arguments=()

  case "$display_mode" in
    graphical)
      display_arguments=(--env DISPLAY=:99 --env WAYLAND_DISPLAY=wayland-test)
      ;;
    headless)
      display_arguments=(--env DISPLAY= --env WAYLAND_DISPLAY= --env XDG_RUNTIME_DIR=/nonexistent)
      ;;
    *)
      fail "unsupported display mode $display_mode"
      ;;
  esac

  if output="$(docker run --rm --network none --hostname "$hostname" \
    "${display_arguments[@]}" \
    --volume "$REPO_DIR:/src:ro" \
    --volume "$TIDYDOTS_BIN:/usr/local/bin/tidydots:ro" \
    --workdir /src \
    ubuntu:24.04 \
    bash -c '
      set -Eeuo pipefail
      mkdir -p /tmp/tidydots-bin
      for command_name in brew git pacman yay; do
        printf "%s\\n" "#!/bin/sh" "exit 0" >"/tmp/tidydots-bin/$command_name"
        chmod +x -- "/tmp/tidydots-bin/$command_name"
      done
      export PATH="/tmp/tidydots-bin:/usr/local/bin:/usr/bin:/bin"
      printf "%s\\n" "__LIST__"
      tidydots --dir /src --os linux list-packages
      printf "%s\\n" "__INSTALL__"
      set +e
      tidydots --dir /src --os linux install -n
      install_status=$?
      set -e
      printf "__INSTALL_STATUS__%s\\n" "$install_status"
    ' 2>&1)"; then
    :
  else
    printf '%s\n' "$output" >&2
    fail "controlled preview runner failed for $label"
  fi

  list_output="$(extract_section "$output" __LIST__ __INSTALL__)"
  install_output="$(extract_section "$output" __INSTALL__ '__INSTALL_STATUS__')"
  install_status="$(awk '/^__INSTALL_STATUS__/ { sub(/^__INSTALL_STATUS__/, ""); print; exit }' <<< "$output")"
  [[ -n "$install_status" ]] || fail "controlled preview did not report install status for $label"
  assert_preview "$label" "$list_output" "$install_output" "$install_status"
}

assert_no_arch_dependency_arrays
assert_yazi_windows_dependencies
load_manifest
run_native_profile 'canonical native Linux host'
run_container_profile 'DESKTOP-E07VTRN graphical' DESKTOP-E07VTRN graphical
run_container_profile 'antoinews-linux graphical' antoinews-linux graphical
run_container_profile 'antoinews-linux headless' antoinews-linux headless
run_container_profile 'omarchbook headless' omarchbook headless
run_container_profile 'server headless' server headless
assert_windows_installer posting-windows 'uv tool install --python 3.13 posting'
assert_windows_installer eza-windows 'cargo install eza'
assert_windows_installer sd-windows 'cargo install sd'

printf 'PASS: manifest-derived Arch package previews are complete for supported profiles\n'
