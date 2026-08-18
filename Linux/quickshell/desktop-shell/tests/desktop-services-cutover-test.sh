#!/usr/bin/env bash
set -Eeuo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
ROOT="$(cd -- "$SCRIPT_DIR/../../../../" && pwd -P)"
CONFIG_FILE="$ROOT/tidydots.yaml"
AUTOSTART="$ROOT/Linux/hypr/autostart.lua"
SHELL_ROOT="$ROOT/Linux/quickshell/desktop-shell"
SHELL_UNIT="$SHELL_ROOT/systemd/desktop-shell.service"
ROLLBACK_UNIT="$SHELL_ROOT/systemd/desktop-shell-mako-route.service"
PROFILE_FIXTURE="$ROOT/Linux/pacman/tests/graphical-profile-fixtures.tsv"
TIDYDOTS_BIN="$(command -v tidydots || true)"
DOCKER_BIN="$(command -v docker || true)"
TEST_ROOT="$(mktemp -d)"
trap 'rm -rf -- "$TEST_ROOT"' EXIT HUP INT TERM

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
  local config_file="${2:-$CONFIG_FILE}"

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
  ' "$config_file"
}

extract_application_entry() {
  local application="$1"
  local entry="$2"
  local config_file="${3:-$CONFIG_FILE}"
  local application_block

  application_block="$(extract_application "$application" "$config_file")"
  awk -v wanted="$entry" '
    function flush() {
      if (entry_name == wanted) {
        printf "%s", entry_block
        found = 1
      }
    }

    /^      - / {
      if (length(entry_block) > 0) {
        flush()
      }
      if (found) {
        exit
      }
      entry_block = $0 ORS
      entry_name = ""
      next
    }

    {
      if (length(entry_block) > 0) {
        entry_block = entry_block $0 ORS
        if ($0 ~ /^        name: /) {
          entry_name = $0
          sub(/^        name: /, "", entry_name)
        }
      }
    }

    END {
      if (!found && length(entry_block) > 0) {
        flush()
      }
    }
  ' <<< "$application_block"
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

write_fixture_file() {
  local fixture_root="$1"
  local relative_path="$2"
  local content="$3"

  mkdir -p -- "$fixture_root/$(dirname -- "$relative_path")"
  printf '%s\n' "$content" >"$fixture_root/$relative_path"
}

assert_rejects_fixture() {
  local label="$1"
  local expected="$2"
  shift 2
  local output

  if output="$("$@" 2>&1)"; then
    fail "$label mutation was accepted"
  fi
  grep -Fq -- "$expected" <<< "$output" ||
    fail "$label mutation failed for an unexpected reason: $output"
}

assert_route_mutation_detected() {
  local label="$1"
  local relative_path="$2"
  local content="$3"
  local fixture="$TEST_ROOT/route-$label"
  local hits

  mkdir -p -- "$fixture"
  write_fixture_file "$fixture" "$relative_path" "$content"
  git -C "$fixture" init -q
  git -C "$fixture" add --all
  hits="$(collect_forbidden_hits "$fixture")"
  grep -Fq -- "$relative_path:" <<< "$hits" ||
    fail "route mutation was not rejected: $label ($relative_path)"
}

assert_round2_route_mutations() {
  assert_route_mutation_detected post--wrapper Linux/hypr/route-variants.lua \
    'uwsm-app -- env -- /usr/bin/mako'
  assert_route_mutation_detected continuation Linux/hypr/route-continuation.lua \
    $'uwsm-app -- \\\n+  /usr/bin/mako'
  assert_route_mutation_detected quoted-hash Linux/hypr/route-quoted-hash.lua \
    "printf '# payload' && uwsm-app -- /usr/bin/mako"
  assert_route_mutation_detected dynamic-helper Linux/os/helpers/dynamic-route \
    'makoctl dismiss'
  assert_route_mutation_detected test-like-file Linux/os/helpers/route-test.sh \
    'swayosd-client --monitor DP-1'
}

assert_round3_route_mutations() {
  assert_route_mutation_detected shell-parameter-expansion Linux/os/helpers/source-route \
    "\${source#*/}; makoctl dismiss"
  assert_route_mutation_detected lua-length-operator Linux/hypr/route-length.lua \
    'if #items > 0 then uwsm-app -- mako end'
}

assert_round4_route_mutations() {
  assert_route_mutation_detected lua-comment-continuation Linux/hypr/route-comment-continuation.lua \
    $'-- note \\\nuwsm-app -- mako'
}

assert_adapter_reference_mutation_detected() {
  local label="$1"
  local relative_path="$2"
  local content="$3"
  local fixture="$TEST_ROOT/round2-adapter-$label"

  mkdir -p -- "$fixture"
  write_fixture_file "$fixture" "$relative_path" "$content"
  git -C "$fixture" init -q
  git -C "$fixture" add --all
  assert_rejects_fixture "adapter $label" 'adapter activation or dependency reference' \
    assert_no_adapter_enrollment "$fixture"
}

assert_round2_adapter_mutations() {
  assert_adapter_reference_mutation_detected yaml-setup tidydots.yaml \
    '        linux: systemctl --user enable --now desktop-shell-mako-route.service'
  assert_adapter_reference_mutation_detected graphical-target Linux/systemd/graphical-session.target \
    'Wants=desktop-shell-mako-route.service'
  assert_adapter_reference_mutation_detected lua-startup Linux/hypr/autostart.lua \
    'hl.exec_cmd("systemctl --user start desktop-shell-mako-route.service")'
  assert_adapter_reference_mutation_detected shell-startup Linux/os/helpers/active-runtime \
    'systemctl --user start desktop-shell-mako-route.service'
  assert_adapter_reference_mutation_detected desktop-startup Linux/os/applications/route.desktop \
    'Exec=systemctl --user start desktop-shell-mako-route.service'
}

assert_adapter_file_mutation_detected() {
  local label="$1"
  local relative_path="$2"
  local content="$3"
  local fixture="$TEST_ROOT/round3-adapter-$label"

  mkdir -p -- "$fixture"
  write_fixture_file "$fixture" "$relative_path" "$content"
  git -C "$fixture" init -q
  git -C "$fixture" add --all
  assert_rejects_fixture "adapter $label" 'adapter activation or dependency reference' \
    assert_no_adapter_enrollment "$fixture"
}

assert_round3_adapter_mutations() {
  assert_adapter_file_mutation_detected route-allow-zone Linux/mako/config \
    'desktop-shell-mako-route.service'
  assert_adapter_file_mutation_detected activation-enable Linux/os/helpers/desktop-shell-activate \
    'systemctl --user enable --now desktop-shell-mako-route.service'
  assert_adapter_file_mutation_detected rollback-enable Linux/os/helpers/desktop-shell-rollback \
    'systemctl --user enable --now desktop-shell-mako-route.service'
  assert_adapter_file_mutation_detected unit-enable Linux/quickshell/desktop-shell/systemd/desktop-shell-mako-route.service \
    'ExecStart=systemctl --user enable --now desktop-shell-mako-route.service'
  assert_adapter_file_mutation_detected unit-start Linux/quickshell/desktop-shell/systemd/desktop-shell-mako-route.service \
    'ExecStart=systemctl --user start desktop-shell-mako-route.service'
}

assert_round4_adapter_mutations() {
  assert_adapter_reference_mutation_detected yaml-comment-continuation Linux/systemd/adapter-comment.yaml \
    $'# note \\\nWants=desktop-shell-mako-route.service'
  assert_adapter_file_mutation_detected activation-status-suffix Linux/os/helpers/desktop-shell-activate \
    "printf '%s\\n' 'desktop-shell activation status' 'desktop-shell.service: active' 'desktop-shell-mako-route.service: inactive' ; systemctl --user enable --now desktop-shell-mako-route.service"
  assert_adapter_file_mutation_detected rollback-status-suffix Linux/os/helpers/desktop-shell-rollback \
    "printf '%s\\n' 'desktop-shell rollback status' 'desktop-shell.service: inactive' 'desktop-shell-mako-route.service: active' ; systemctl --user enable --now desktop-shell-mako-route.service"
}

assert_mutation_fixtures() {
  local fixture="$TEST_ROOT/mutation-repository"
  local hits expected_path allowed_path

  assert_round2_route_mutations
  assert_round3_route_mutations
  assert_round4_route_mutations
  assert_round2_adapter_mutations
  assert_round3_adapter_mutations
  assert_round4_adapter_mutations
  assert_graphical_profile_fixture_consumption

  mkdir -p -- "$fixture"
  write_fixture_file "$fixture" Linux/hypr/autostart.lua \
    'active-uwsm-mako active-uwsm-swayosd active-polkit active-command-routes'
  write_fixture_file "$fixture" Linux/os/helpers/active-uwsm-mako \
    'exec env -- /usr/bin/uwsm-app -- /usr/bin/mako'
  write_fixture_file "$fixture" Linux/os/helpers/active-uwsm-swayosd \
    "setsid /usr/bin/uwsm-app -- 'swayosd-server'"
  write_fixture_file "$fixture" Linux/os/helpers/active-polkit \
    'exec /usr/lib/polkit-gnome/polkit-gnome-authentication-agent-1'
  write_fixture_file "$fixture" Linux/os/helpers/active-command-routes \
    $'/usr/bin/makoctl dismiss\n/usr/bin/swayosd-client --monitor DP-1\n/usr/bin/swayosd-brightness 40\n/usr/bin/swayosd-kbd-brightness 50\nnotmakoctl makoctl-wrapper not-swayosd-client'
  write_fixture_file "$fixture" Linux/vicinae/scripts/route-variants.sh \
    $'/usr/bin/uwsm-app -- /opt/bin/mako\nsetsid uwsm-app -- swayosd-server\nexec /usr/bin/makoctl; /usr/bin/swayosd-client'
  write_fixture_file "$fixture" Linux/vicinae/scripts/negative-routes.sh \
    $'notmakoctl makoctl-wrapper not-swayosd-client swayosd-client-wrapper\n# makoctl\n# uwsm-app -- mako'
  write_fixture_file "$fixture" Linux/mako/config \
    $'makoctl reload\nuwsm-app -- mako\nswayosd-client'
  write_fixture_file "$fixture" Linux/swayosd/style.css '/* swayosd-client makoctl */'
  write_fixture_file "$fixture" Linux/example/tests/route-test.sh \
    $'makoctl\nswayosd-client\nuwsm-app -- mako'
  write_fixture_file "$fixture" Linux/os/helpers/desktop-shell-rollback \
    $'makoctl\nuwsm-app -- mako\n/usr/lib/polkit-gnome/polkit-gnome-authentication-agent-1'
  write_fixture_file "$fixture" Linux/os/helpers/desktop-shell-mako-route \
    'makoctl mode'
  write_fixture_file "$fixture" Linux/os/helpers/desktop-shell-activate \
    $'makoctl\n/usr/lib/polkit-gnome/polkit-gnome-authentication-agent-1'
  write_fixture_file "$fixture" tidydots.yaml \
    $'        pacman: makoctl\n        pacman: swayosd-client\n        pacman: swayosd-brightness'
  git -C "$fixture" init -q
  git -C "$fixture" add --all

  hits="$(collect_forbidden_hits "$fixture")"
  for expected_path in \
    Linux/os/helpers/active-uwsm-mako \
    Linux/os/helpers/active-uwsm-swayosd \
    Linux/os/helpers/active-polkit \
    Linux/os/helpers/active-command-routes \
    Linux/vicinae/scripts/route-variants.sh; do
    grep -Fq -- "$expected_path:" <<< "$hits" ||
      fail "mutation fixture route was not detected: $expected_path"
  done
  if grep -Fq -- 'Linux/vicinae/scripts/negative-routes.sh:' <<< "$hits"; then
    fail 'bounded command token mutation fixture produced a false positive'
  fi
  for allowed_path in \
    Linux/mako/config \
    Linux/swayosd/style.css \
    Linux/example/tests/route-test.sh \
    Linux/os/helpers/desktop-shell-rollback \
    Linux/os/helpers/desktop-shell-mako-route \
    Linux/os/helpers/desktop-shell-activate \
    tidydots.yaml; do
    if grep -Fq -- "$allowed_path:" <<< "$hits"; then
      fail "allowed mutation fixture was incorrectly detected: $allowed_path"
    fi
  done

  write_fixture_file "$fixture" setup.yaml \
    $'applications:\n  - name: fixture\n    entries:\n      - check:\n          linux: systemctl --user enable --now desktop-shell-mako-route.service'
  git -C "$fixture" add --all
  assert_rejects_fixture 'adapter setup' 'adapter activation or dependency reference' \
    assert_no_adapter_enrollment "$fixture"

  write_fixture_file "$fixture" Linux/systemd/graphical-session.target \
    $'[Unit]\nWants=desktop-shell-mako-route.service'
  git -C "$fixture" add --all
  assert_rejects_fixture 'adapter dependency' 'adapter activation or dependency reference' \
    assert_no_adapter_enrollment "$fixture"

  write_fixture_file "$fixture" mapping.yaml \
    $'applications:\n  - name: desktop-shell\n    entries:\n      - targets:\n          linux: ~/.config/systemd/user\n        name: systemd-service\n        backup: ./Linux/quickshell/desktop-shell/systemd\n        files:\n          - desktop-shell.service'
  assert_rejects_fixture 'systemd mapping' 'desktop-shell systemd-service entry is missing' \
    assert_systemd_mapping "$fixture/mapping.yaml"

  cp -- "$AUTOSTART" "$TEST_ROOT/autostart-mutated.lua"
  sed -i '/teams-for-linux/d' "$TEST_ROOT/autostart-mutated.lua"
  assert_rejects_fixture 'autostart content' 'autostart content or order changed' \
    assert_autostart_fixture "$TEST_ROOT/autostart-mutated.lua"
}

is_route_allowed_zone() {
  case "$1" in
    Linux/mako/*|Linux/swayosd/*|*/tests/*|Linux/os/helpers/desktop-shell-activate|Linux/os/helpers/desktop-shell-rollback|Linux/os/helpers/desktop-shell-mako-route|Linux/os/helpers/notification-dismiss|Linux/os/helpers/restart-mako|Linux/os/helpers/swayosd-brightness|Linux/os/helpers/swayosd-kbd-brightness)
      return 0
      ;;
    *)
      return 1
      ;;
  esac
}

is_adapter_non_runtime_file() {
  case "$1" in
    Linux/quickshell/desktop-shell/tests/desktop-services-cutover-test.sh|Linux/quickshell/desktop-shell/tests/desktop-services-lifecycle-test.sh|Linux/quickshell/desktop-shell/tests/mako-route-adapter-test.sh)
      return 0
      ;;
    *)
      return 1
      ;;
  esac
}

is_non_runtime_file() {
  case "$1" in
    *.md|*.markdown|*.rst|*.diff|*.patch|*.gif|*.ico|*.jpeg|*.jpg|*.png|*.ttf|*.otf|*.wasm)
      return 0
      ;;
    *)
      return 1
      ;;
  esac
}

readonly UWSM_ROUTE_RE="(^|[^[:alnum:]_.-])([^[:space:];|&()\"']+/)?uwsm-app[[:space:]]+--([^;&|]*[[:space:]/\"'])(mako|swayosd-server)([^[:alnum:]_.-]|$)"
readonly DIRECT_ROUTE_RE="(^|[^[:alnum:]_.-])([^[:space:];|&()\"']+/)?(polkit-gnome-authentication-agent-1|makoctl|swayosd-client|swayosd-brightness|swayosd-kbd-brightness)([^[:alnum:]_.-]|$)"

collect_tracked_text_paths() {
  local root="$1"
  local path
  local -a tracked_paths=()
  TRACKED_TEXT_PATHS=()

  mapfile -d '' tracked_paths < <(git -C "$root" grep -zIl -e . -- . 2>/dev/null || true)
  for path in "${tracked_paths[@]}"; do
    [[ -f "$root/$path" ]] || continue
    is_non_runtime_file "$path" && continue
    TRACKED_TEXT_PATHS+=("$path")
  done
}

collect_route_paths() {
  local path

  collect_tracked_text_paths "$1"
  ACTIVE_ROUTE_PATHS=()
  for path in "${TRACKED_TEXT_PATHS[@]}"; do
    is_route_allowed_zone "$path" && continue
    ACTIVE_ROUTE_PATHS+=("$path")
  done
}

collect_inventory_hits() {
  local root="$1"
  local mode="$2"
  local -a files=()

  if [[ "$mode" == route ]]; then
    collect_route_paths "$root"
    for path in "${ACTIVE_ROUTE_PATHS[@]}"; do
      files+=("$root/$path")
    done
  else
    collect_tracked_text_paths "$root"
    for path in "${TRACKED_TEXT_PATHS[@]}"; do
      is_adapter_non_runtime_file "$path" && continue
      files+=("$root/$path")
    done
  fi

  awk -v root="$root" -v mode="$mode" -v uwsm="$UWSM_ROUTE_RE" -v direct="$DIRECT_ROUTE_RE" '
    function is_whole_line_comment(path, value) {
      if (value ~ /^[[:space:]]*$/) {
        return 1
      }
      if (path ~ /\.lua$/) {
        return value ~ /^[[:space:]]*--/
      }
      if (path ~ /\.qml$/) {
        return value ~ /^[[:space:]]*\/\//
      }
      if (path ~ /\.(bash|conf|fish|ini|mount|nu|service|sh|socket|target|timer|toml|yaml|yml|zsh)$/ ||
          path ~ /^Linux\/os\/helpers\/[^/]+$/) {
        return value ~ /^[[:space:]]*#/
      }
      return 0
    }

    function relative_path(value, prefix) {
      prefix = root "/"
      if (index(value, prefix) == 1) {
        return substr(value, length(prefix) + 1)
      }
      return value
    }

    function package_declaration(path, value) {
      if (path == "tidydots.yaml" && value ~ /^[[:space:]]+(apt|brew|pacman|yay|winget):[[:space:]]+[[:alnum:]_.+:-]+$/) {
        return 1
      }
      if (path ~ /^Linux\/pacman\/pkglist-/ && value ~ /^[[:alnum:]_.+:-]+$/) {
        return 1
      }
      return 0
    }

    function normalize_logical(value) {
      gsub(/[[:space:]]+/, " ", value)
      sub(/^ /, "", value)
      sub(/ $/, "", value)
      return value
    }

    function activation_status_line(quote, double_quote, value) {
      quote = sprintf("%c", 39)
      double_quote = sprintf("%c", 34)
      value = "printf " quote "%s\\n" quote
      value = value " " quote "desktop-shell activation status" quote
      value = value " " quote "desktop-shell.service: active" quote
      value = value " " quote "desktop-shell-mako-route.service: inactive" quote
      value = value " " double_quote "desktop-shell.pid: $shell_pid" double_quote
      value = value " " quote "mako.pid: absent" quote
      value = value " " quote "swayosd-server.pid: absent" quote
      value = value " " quote "polkit.pid: absent" quote
      value = value " " quote "notification-owner: desktop-shell" quote
      value = value " " double_quote "polkit-registered: $polkit_registered" double_quote
      return value
    }

    function rollback_status_line(quote, double_quote, value) {
      quote = sprintf("%c", 39)
      double_quote = sprintf("%c", 34)
      value = "printf " quote "%s\\n" quote
      value = value " " quote "desktop-shell rollback status" quote
      value = value " " quote "desktop-shell.service: inactive" quote
      value = value " " quote "desktop-shell-mako-route.service: active" quote
      value = value " " double_quote "mako.pid: $mako_pid" double_quote
      value = value " " double_quote "swayosd-server.pid: $swaysod_pid" double_quote
      value = value " " double_quote "polkit.pid: $polkit_pid" double_quote
      value = value " " quote "notification-owner: mako" quote
      value = value " " quote "polkit-process: present" quote
      return value
    }

    function adapter_reference_allowed(path, value) {
      value = normalize_logical(value)
      quote = sprintf("%c", 39)
      if (path == "tidydots.yaml" && value == "- desktop-shell-mako-route.service") {
        return 1
      }
      if (path == "Linux/os/helpers/desktop-shell-activate" &&
          value == "stop_units=(systemctl --user stop desktop-shell.service desktop-shell-mako-route.service)") {
        return 1
      }
      if (path == "Linux/os/helpers/desktop-shell-rollback" &&
          (value == "adapter_active=(systemctl --user is-active --quiet desktop-shell-mako-route.service)" ||
           value == "stop_adapter=(systemctl --user stop desktop-shell-mako-route.service)" ||
           value == "start_adapter=(systemctl --user start desktop-shell-mako-route.service)" ||
           value == ("wait_for_unit_active desktop-shell-mako-route.service || die " quote "rollback adapter is not active" quote) ||
           value == ("\"${stop_adapter[@]}\" || die " quote "could not isolate desktop-shell-mako-route.service" quote) ||
           value == ("\"${start_adapter[@]}\" || die " quote "could not start desktop-shell-mako-route.service" quote))) {
        return 1
      }
      if (path == "Linux/quickshell/desktop-shell/systemd/desktop-shell.service" &&
          value == "Conflicts=desktop-shell-mako-route.service") {
        return 1
      }
      if (path == "Linux/quickshell/desktop-shell/systemd/desktop-shell-mako-route.service" &&
          (value == "Conflicts=desktop-shell.service" ||
           value == "ExecStart=%h/.local/share/helpers/desktop-shell-mako-route")) {
        return 1
      }
      if (path == "Linux/os/helpers/desktop-shell-activate" &&
          value == activation_status_line()) {
        return 1
      }
      if (path == "Linux/os/helpers/desktop-shell-rollback" &&
          value == rollback_status_line()) {
        return 1
      }
      return 0
    }

    function scan_logical(value, start, path) {
      if (is_whole_line_comment(path, value) || package_declaration(path, value)) {
        return
      }
      if (mode == "route" && (value ~ uwsm || value ~ direct)) {
        print path ":" start ":" value
      }
      if (mode == "adapter" && index(value, "desktop-shell-mako-route") &&
          !adapter_reference_allowed(path, value)) {
        print path ":" start ":" value
      }
    }

    FNR == 1 {
      if (seen_file && logical != "") {
        scan_logical(logical, logical_start, previous_path)
      }
      logical = ""
      logical_start = 0
      previous_path = relative_path(FILENAME)
      seen_file = 1
    }

    {
      if (logical == "") {
        logical_start = FNR
      }
      line = $0
      if (is_whole_line_comment(relative_path(FILENAME), line)) {
        if (logical != "") {
          scan_logical(logical, logical_start, relative_path(FILENAME))
        }
        logical = ""
        logical_start = 0
        next
      }
      if (line ~ /\\[[:space:]]*$/) {
        sub(/\\[[:space:]]*$/, " ", line)
        logical = logical line
        next
      }
      logical = logical line
      scan_logical(logical, logical_start, relative_path(FILENAME))
      logical = ""
      logical_start = 0
    }

    END {
      if (logical != "") {
        scan_logical(logical, logical_start, previous_path)
      }
    }
  ' "${files[@]}"
}

collect_forbidden_hits() {
  collect_inventory_hits "$1" route
}

audit_active_routes() {
  local hits

  hits="$(collect_forbidden_hits "$ROOT")"
  if [[ -n "$hits" ]]; then
    printf 'FAIL: forbidden active desktop-service routes:\n%s\n' "$hits" >&2
    exit 1
  fi
}

assert_autostart_fixture() {
  local path="$1"
  local expected="$TEST_ROOT/expected-autostart.lua"

  cat >"$expected" <<'EOF'
-- Autostart processes. Order matches the original autostart.conf exec-once chain.

local hostname_pipe = io.popen("hostname")
local hostname = hostname_pipe and hostname_pipe:read("*l") or ""
if hostname_pipe then
	hostname_pipe:close()
end

hl.on("hyprland.start", function()
	hl.exec_cmd("uwsm-app -- hypridle")
	hl.exec_cmd("uwsm-app -- fcitx5 --disable notificationitem")
	hl.exec_cmd("uwsm-app -- swaybg -c '#1e1e2e'")

	-- Slow app launch fix -- set systemd vars
	hl.exec_cmd("systemctl --user import-environment $(env | cut -d'=' -f 1)")
	hl.exec_cmd("dbus-update-activation-environment --systemd --all")

	-- Extra autostart processes
	hl.exec_cmd("hyprpm reload -n")
	hl.exec_cmd("signal-desktop")
	hl.exec_cmd("teams-for-linux")

	-- Ensure all persistent workspaces are on the correct host-specific monitors.
	-- Legacy `hyprctl dispatch <name> <args>` strings are rejected by the Lua parser; route through `hyprctl eval`.
	-- `hl.dsp.*` calls return dispatcher closures -- they only fire when wrapped in `hl.dispatch(...)`.
	if hostname == "antoinews-linux" then
		hl.exec_cmd(
			[[sleep 1 && hyprctl eval 'hl.dispatch(hl.dsp.workspace.move({workspace=2, monitor="DP-2"})); hl.dispatch(hl.dsp.workspace.move({workspace=5, monitor="DP-2"})); hl.dispatch(hl.dsp.workspace.move({workspace=8, monitor="DP-2"})); hl.dispatch(hl.dsp.workspace.move({workspace=3, monitor="DP-1"})); hl.dispatch(hl.dsp.workspace.move({workspace=6, monitor="DP-1"})); hl.dispatch(hl.dsp.workspace.move({workspace=9, monitor="DP-1"})); hl.dispatch(hl.dsp.workspace.move({workspace=10, monitor="DP-1"})); hl.dispatch(hl.dsp.focus({workspace=2}))']]
		)
	elseif hostname == "DESKTOP-E07VTRN" then
		hl.exec_cmd(
			[[sleep 1 && hyprctl eval 'hl.dispatch(hl.dsp.workspace.move({workspace=1, monitor="DVI-D-1"})); hl.dispatch(hl.dsp.workspace.move({workspace=4, monitor="DVI-D-1"})); hl.dispatch(hl.dsp.workspace.move({workspace=7, monitor="DVI-D-1"})); hl.dispatch(hl.dsp.workspace.move({workspace=2, monitor="HDMI-A-1"})); hl.dispatch(hl.dsp.workspace.move({workspace=5, monitor="HDMI-A-1"})); hl.dispatch(hl.dsp.workspace.move({workspace=8, monitor="HDMI-A-1"})); hl.dispatch(hl.dsp.workspace.move({workspace=3, monitor="DP-2"})); hl.dispatch(hl.dsp.workspace.move({workspace=6, monitor="DP-2"})); hl.dispatch(hl.dsp.workspace.move({workspace=9, monitor="DP-2"})); hl.dispatch(hl.dsp.workspace.move({workspace=10, monitor="DP-2"})); hl.dispatch(hl.dsp.focus({workspace=2}))']]
		)
	end

	-- Hyprland 0.55 regression: cursor cannot enter DP-2's region until the monitor is re-applied.
	-- `hyprctl keyword` is disabled under the Lua parser, so route the nudge through `hyprctl eval` instead.
	if hostname == "antoinews-linux" then
		hl.exec_cmd(
			[[sleep 2 && hyprctl eval 'hl.monitor({ output = "DP-2", mode = "1920x1080@60", position = "1x0", scale = 1 })' && hyprctl eval 'hl.monitor({ output = "DP-2", mode = "1920x1080@60", position = "0x0", scale = 1 })']]
		)
	elseif hostname == "DESKTOP-E07VTRN" then
		hl.exec_cmd(
			[[sleep 2 && hyprctl eval 'hl.monitor({ output = "DP-2", mode = "1920x1080@60", position = "3601x0", scale = 1 })' && hyprctl eval 'hl.monitor({ output = "DP-2", mode = "1920x1080@60", position = "3600x0", scale = 1 })']]
		)
	end
end)
EOF

  cmp -s -- "$expected" "$path" || fail "autostart content or order changed: $path"
}

assert_systemd_mapping() {
  local config_file="$1"
  local entry

  entry="$(extract_application_entry desktop-shell systemd-service "$config_file")"
  [[ -n "$entry" ]] || fail "desktop-shell systemd-service entry is missing"
  grep -Fqx -- '          linux: ~/.config/systemd/user' <<< "$entry" ||
    fail 'desktop-shell systemd service target changed'
  grep -Fqx -- '        backup: ./Linux/quickshell/desktop-shell/systemd' <<< "$entry" ||
    fail 'desktop-shell systemd service backup changed'
  grep -Fqx -- '          - desktop-shell.service' <<< "$entry" ||
    fail 'desktop-shell service is not in the systemd mapping'
  grep -Fqx -- '          - desktop-shell-mako-route.service' <<< "$entry" ||
    fail 'rollback adapter is not in the desktop-shell systemd mapping'
}

collect_adapter_hits() {
  collect_inventory_hits "$1" adapter
}

assert_no_adapter_enrollment() {
  local root="$1"
  local hits

  hits="$(collect_adapter_hits "$root")"
  [[ -z "$hits" ]] || fail "adapter activation or dependency reference:\n$hits"
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
  assert_file "$ROOT/Linux/mako/config" 'Mako configuration'
  assert_executable "$ROOT/Linux/mako/rustdesk-notification-cue" 'Mako RustDesk cue helper'
  assert_file "$ROOT/Linux/swayosd/config.toml" 'SwayOSD configuration'
  assert_file "$ROOT/Linux/swayosd/style.css" 'SwayOSD style'
  [[ -s "$ROOT/Linux/mako/config" ]] || fail 'Mako configuration is empty'
  [[ -s "$ROOT/Linux/swayosd/config.toml" ]] || fail 'SwayOSD configuration is empty'
  [[ -s "$ROOT/Linux/swayosd/style.css" ]] || fail 'SwayOSD style is empty'
  grep -Fqx 'Conflicts=desktop-shell-mako-route.service' "$SHELL_UNIT" ||
    fail 'desktop-shell service unit does not isolate the rollback unit'
  grep -Fqx 'Conflicts=desktop-shell.service' "$ROLLBACK_UNIT" ||
    fail 'rollback unit does not isolate desktop-shell.service'
  grep -Fqx 'PartOf=graphical-session.target' "$ROLLBACK_UNIT" ||
    fail 'rollback unit lost its graphical-session lifecycle relationship'
  for forbidden_install_key in '[Install]' 'WantedBy=' 'RequiredBy=' 'Also=' 'Alias='; do
    if grep -Fq -- "$forbidden_install_key" "$ROLLBACK_UNIT"; then
      fail "rollback unit contains an install enrollment key: $forbidden_install_key"
    fi
  done
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
  assert_systemd_mapping "$CONFIG_FILE"
  grep -Fqx -- '          - desktop-shell.service' <<< "$block" ||
    fail 'desktop-shell service is not mapped'
  grep -Fqx -- '          - desktop-shell-mako-route.service' <<< "$block" ||
    fail 'rollback unit is not mapped'
  grep -Fq 'systemctl --user is-enabled --quiet desktop-shell.service &&' <<< "$block" ||
    fail 'desktop-shell repair does not require enabled state'
  grep -Fq 'systemctl --user show desktop-shell.service --property=NeedDaemonReload --value' <<< "$block" ||
    fail 'desktop-shell repair does not check daemon reload state'
  grep -Fq 'systemctl --user daemon-reload && systemctl --user enable desktop-shell.service' <<< "$block" ||
    fail 'desktop-shell repair is not enable-only'
  if grep -Eq 'systemctl --user (start|restart|try-restart) desktop-shell\.service|--now desktop-shell\.service' <<< "$block"; then
    fail 'desktop-shell repair starts or restarts the service'
  fi
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

assert_graphical_profile_fixture_consumption() {
  local fixture="$TEST_ROOT/round2-graphical-profile-mutation.tsv"
  local fake_docker="$TEST_ROOT/round2-profile-docker"
  local docker_log="$TEST_ROOT/round2-profile-docker.log"
  local original_fixture="$PROFILE_FIXTURE"
  local original_docker="$DOCKER_BIN"

  cp -- "$PROFILE_FIXTURE" "$fixture"
  printf '%s\tgraphical\n' round2-fixture-host >>"$fixture"
  cat >"$fake_docker" <<'EOF'
#!/usr/bin/env bash
set -Eeuo pipefail

hostname=''
while (($# > 0)); do
  if [[ "$1" == --hostname ]]; then
    hostname="$2"
    shift 2
  else
    shift
  fi
done

printf '%s\n' "$hostname" >>"${PROFILE_DOCKER_LOG:?}"
printf '%s\n' \
  'Application: desktop-shell' \
  'Application: hyprland' \
  'Application: mako' \
  'Application: swayosd' \
  'Application: polkit-gnome'
EOF
  chmod +x -- "$fake_docker"

  PROFILE_FIXTURE="$fixture"
  DOCKER_BIN="$fake_docker"
  PROFILE_DOCKER_LOG="$docker_log" assert_rendered_graphical_profiles
  grep -Fqx -- round2-fixture-host "$docker_log" ||
    fail 'graphical profile fixture mutation was not consumed'

  PROFILE_FIXTURE="$original_fixture"
  DOCKER_BIN="$original_docker"
}

load_profile_matrix() {
  local rows row hostname display_mode key
  declare -A seen_rows=()

  if ! rows="$(awk -F '\t' '
    /^[[:space:]]*#/ || /^[[:space:]]*$/ {
      next
    }

    NF != 2 {
      printf "invalid profile fixture row %d\n", NR > "/dev/stderr"
      invalid = 1
      next
    }

    $2 != "graphical" && $2 != "headless" {
      printf "unsupported display mode on profile fixture row %d\n", NR > "/dev/stderr"
      invalid = 1
      next
    }

    { print $1 "\t" $2 }

    END {
      exit invalid
    }
  ' "$PROFILE_FIXTURE")"; then
    fail 'graphical profile fixture is malformed'
  fi

  [[ -n "$rows" ]] || fail 'graphical profile fixture has no profiles'
  mapfile -t PROFILE_ROWS <<< "$rows"
  for row in "${PROFILE_ROWS[@]}"; do
    IFS=$'\t' read -r hostname display_mode <<< "$row"
    [[ -n "$hostname" && -n "$display_mode" ]] || fail 'graphical profile fixture contains an empty field'
    key="$hostname|$display_mode"
    [[ -z "${seen_rows[$key]+set}" ]] || fail "graphical profile fixture repeats $key"
    seen_rows["$key"]=1
  done
}

assert_rendered_graphical_profiles() {
  local row hostname display_mode
  local -a graphical_hosts=()
  declare -A seen_hosts=()

  load_profile_matrix
  for row in "${PROFILE_ROWS[@]}"; do
    IFS=$'\t' read -r hostname display_mode <<< "$row"
    [[ "$display_mode" == graphical ]] || continue
    graphical_hosts+=("$hostname")
  done
  ((${#graphical_hosts[@]} > 0)) || fail 'graphical profile fixture has no graphical profiles'

  for hostname in "${graphical_hosts[@]}"; do
    [[ -n "$hostname" ]] || fail 'graphical profile fixture contains an empty graphical hostname'
    [[ -z "${seen_hosts[$hostname]+set}" ]] || fail "graphical profile fixture repeats graphical profile: $hostname"
    seen_hosts["$hostname"]=1
    assert_rendered_graphical_profile "$hostname graphical" "$hostname"
  done
}

[[ -r "$CONFIG_FILE" ]] || fail "cannot read $CONFIG_FILE"
[[ -r "$AUTOSTART" ]] || fail "cannot read $AUTOSTART"
[[ -x "$TIDYDOTS_BIN" ]] || fail 'tidydots is required for rendered profile audits'
[[ -x "$DOCKER_BIN" ]] || fail 'docker is required for rendered graphical profile audits'

assert_mutation_fixtures
assert_no_adapter_enrollment "$ROOT"
audit_active_routes
assert_autostart_fixture "$AUTOSTART"
assert_autostart_order
assert_manifests_and_helpers
assert_legacy_declarations
assert_service_repair
assert_rendered_graphical_profiles

printf 'PASS: desktop service cutover and graphical profile audit passed\n'
