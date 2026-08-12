#!/usr/bin/env bash
set -Eeuo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
REPO_DIR="$(cd -- "$SCRIPT_DIR/../../.." && pwd -P)"
CONFIG_FILE="$REPO_DIR/tidydots.yaml"
LIMINE_CONFIG="$REPO_DIR/Linux/limine/limine"
SNAPPER_ROOT_CONFIG="$REPO_DIR/Linux/Snapper/configs/root"
SNAPPER_HOME_CONFIG="$REPO_DIR/Linux/Snapper/configs/home"
SNAPPER_REGISTRATION="$REPO_DIR/Linux/Snapper/conf.d/snapper"
SNAPPER_INITIALIZER="$REPO_DIR/Linux/Snapper/snapper-initialize"
BOOTSTRAP="$REPO_DIR/Linux/install/bootstrap"

fail() {
  printf 'FAIL: %s\n' "$*" >&2
  exit 1
}

[[ -r "$CONFIG_FILE" ]] || fail "cannot read $CONFIG_FILE"
[[ -r "$LIMINE_CONFIG" ]] || fail "cannot read $LIMINE_CONFIG"
[[ -r "$SNAPPER_ROOT_CONFIG" ]] || fail "cannot read $SNAPPER_ROOT_CONFIG"
[[ -r "$SNAPPER_HOME_CONFIG" ]] || fail "cannot read $SNAPPER_HOME_CONFIG"
[[ -r "$SNAPPER_REGISTRATION" ]] || fail "cannot read $SNAPPER_REGISTRATION"
[[ -x "$SNAPPER_INITIALIZER" ]] || fail "cannot execute $SNAPPER_INITIALIZER"
[[ -r "$BOOTSTRAP" ]] || fail "cannot read $BOOTSTRAP"
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

assert_when() {
  local application="$1"
  local expected_when="$2"
  local actual_when

  actual_when="$(extract_application_field "$application" when)" || fail "application $application has no when predicate"
  [[ "$actual_when" == "$expected_when" ]] || fail "application $application does not use the expected predicate"
}

assert_package() {
  local application="$1"
  local manager="$2"
  local package="$3"
  local block

  block="$(extract_application "$application")"
  [[ -n "$block" ]] || fail "application $application is not declared"
  grep -Fqx -- "        $manager: $package" <<< "$block" ||
    fail "$application does not declare $package through $manager"
}

assert_entry() {
  local application="$1"
  local expected_line="$2"
  local block

  block="$(extract_application "$application")"
  grep -Fqx -- "$expected_line" <<< "$block" ||
    fail "$application does not contain expected entry data: $expected_line"
}

extract_application_entry() {
  local application="$1"
  local entry="$2"
  local application_block

  application_block="$(extract_application "$application")"
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

assert_entry_field() {
  local application="$1"
  local entry="$2"
  local expected_line="$3"
  local entry_block

  entry_block="$(extract_application_entry "$application" "$entry")"
  [[ -n "$entry_block" ]] || fail "$application entry $entry is not declared"
  grep -Fqx -- "$expected_line" <<< "$entry_block" ||
    fail "$application entry $entry does not contain expected data: $expected_line"
}

assert_snapshot_policy() {
  local application="$1"
  local expected_when="$2"
  local expected_line="$3"
  local block

  assert_when "$application" "$expected_when"
  block="$(extract_application "$application")"
  grep -Fq -- "$expected_line" <<< "$block" ||
    fail "$application does not preserve expected snapshot policy: $expected_line"
}

tidydots --dir "$REPO_DIR" list >/dev/null || fail "tidydots list could not parse the configuration"

LINUX_WHEN="'{{ eq .OS \"linux\" }}'"
CURRENT_DESKTOP_WHEN="'{{ eq .Hostname \"DESKTOP-E07VTRN\" }}'"
SNAPSHOTS_ENABLED_WHEN="'{{ and (eq .OS \"linux\") (ne .Hostname \"omarchbook\") }}'"
SNAPSHOTS_DISABLED_WHEN="'{{ eq .Hostname \"omarchbook\" }}'"

assert_when limine "$LINUX_WHEN"
assert_package limine pacman limine
limine_block="$(extract_application limine)"
grep -Fqx '    entries: []' <<< "$limine_block" || fail "shared limine application deploys configuration entries"

assert_when snapper "$LINUX_WHEN"
assert_package snapper pacman snapper
assert_entry snapper '        name: configs'
assert_entry snapper '        name: registered-configs'
assert_entry_field snapper snapper-initialize '          linux: /usr/local/libexec/antoinews-linux'
assert_entry_field snapper snapper-initialize '        method: copy'
assert_entry_field snapper snapper-initialize '        backup: ./Linux/Snapper'
assert_entry_field snapper snapper-initialize '          - snapper-initialize'
assert_entry_field snapper snapper-initialize '        sudo: true'
assert_entry_field snapper configs '        method: copy'
assert_entry_field snapper configs '          - root'
assert_entry_field snapper configs '          - home'
assert_entry_field snapper configs '        sudo: true'
assert_entry_field snapper registered-configs '        method: copy'
assert_entry_field snapper registered-configs '          - snapper'
assert_entry_field snapper registered-configs '        sudo: true'
if grep -Fq 'initialize-btrfs-layout' <<<"$(extract_application snapper)"; then
  fail 'Snapper initializer must not be a tidydots setup entry'
fi

assert_when limine-snapper-sync "$LINUX_WHEN"
assert_package limine-snapper-sync yay limine-snapper-sync

assert_when limine-current-desktop-config "$CURRENT_DESKTOP_WHEN"
assert_entry limine-current-desktop-config '          - limine-snapper-sync.conf'
assert_entry limine-current-desktop-config '          - limine'

limine_mapping_owners="$(awk '
  function flush() {
    if (application_name != "" && block ~ /backup: \.\/Linux\/limine\//) {
      print application_name
    }
  }

  /^  - / {
    if (length(block) > 0) {
      flush()
    }
    block = $0 ORS
    application_name = ""
    if ($0 ~ /^  - name: /) {
      application_name = $0
      sub(/^  - name: /, "", application_name)
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
' "$CONFIG_FILE")"
[[ "$limine_mapping_owners" == "limine-current-desktop-config" ]] ||
  fail "Linux/limine mappings are owned by unexpected applications: $limine_mapping_owners"

grep -Fq 'PARTUUID=' "$LIMINE_CONFIG" || fail "current-desktop Limine configuration lost PARTUUID data"
grep -Fq 'resume_offset=' "$LIMINE_CONFIG" || fail "current-desktop Limine configuration lost resume_offset data"

antoinews_machine_data_owners="$(awk '
  function flush() {
    if (block ~ /Hostname "antoinews-linux"/ &&
      (block ~ /PARTUUID=|resume_offset=/ || block ~ /Linux\/limine\//)) {
      print application_name
    }
  }

  /^  - / {
    if (length(block) > 0) {
      flush()
    }
    block = $0 ORS
    application_name = ""
    if ($0 ~ /^  - name: /) {
      application_name = $0
      sub(/^  - name: /, "", application_name)
    }
    next
  }

  {
    block = block $0 ORS
  }

  END {
    if (length(block) > 0) {
      flush()
    }
  }
' "$CONFIG_FILE")"
[[ -z "$antoinews_machine_data_owners" ]] ||
  fail "antoinews-linux applications expose current-desktop Limine data: $antoinews_machine_data_owners"

for application in antoinews-linux-intel antoinews-linux-network; do
  application_block="$(extract_application "$application")"
  if grep -Eq 'PARTUUID=|resume_offset=|Linux/limine/' <<< "$application_block"; then
    fail "$application exposes current-desktop Limine data"
  fi
done

assert_snapshot_policy snapshots-enabled "$SNAPSHOTS_ENABLED_WHEN" \
  'linux: systemctl is-enabled --quiet snapper-timeline.timer && systemctl is-enabled --quiet snapper-cleanup.timer'
assert_snapshot_policy snapshots-enabled "$SNAPSHOTS_ENABLED_WHEN" \
  'linux: systemctl is-enabled --quiet limine-snapper-sync.service'
assert_snapshot_policy snapshots-disabled "$SNAPSHOTS_DISABLED_WHEN" \
  'linux: "! systemctl is-enabled --quiet snapper-timeline.timer && ! systemctl is-enabled --quiet snapper-cleanup.timer"'
assert_snapshot_policy snapshots-disabled "$SNAPSHOTS_DISABLED_WHEN" \
  'linux: "! systemctl is-enabled --quiet limine-snapper-sync.service"'

grep -Fxq 'SUBVOLUME="/"' "$SNAPPER_ROOT_CONFIG" || fail "root Snapper policy changed"
grep -Fxq 'SUBVOLUME="/home"' "$SNAPPER_HOME_CONFIG" || fail "home Snapper policy changed"
grep -Fxq 'ROOT_SUBVOLUME_PATH="/@"' "$REPO_DIR/Linux/limine/limine-snapper-sync.conf" ||
  fail "Limine Snapper sync root subvolume path changed"
grep -Fxq 'ROOT_SNAPSHOTS_PATH="/@/.snapshots"' "$REPO_DIR/Linux/limine/limine-snapper-sync.conf" ||
  fail "Limine Snapper sync snapshot path changed"
for config in "$SNAPPER_ROOT_CONFIG" "$SNAPPER_HOME_CONFIG"; do
  grep -Fxq 'TIMELINE_CREATE="yes"' "$config" || fail "$config does not enable timeline creation"
  grep -Fxq 'TIMELINE_CLEANUP="yes"' "$config" || fail "$config does not enable timeline cleanup"
  for limit in HOURLY DAILY WEEKLY MONTHLY QUARTERLY YEARLY; do
    grep -Eq "^TIMELINE_LIMIT_${limit}=\"[1-9][0-9]*\"$" "$config" ||
      fail "$config does not define a positive ${limit,,} retention limit"
  done
done
grep -Fxq 'SNAPPER_CONFIGS="root home"' "$SNAPPER_REGISTRATION" || fail "shared Snapper registration changed"
grep -Fq "[[ \"\$EUID\" -eq 0 ]]" "$SNAPPER_INITIALIZER" || fail "Snapper initializer is not root-only"
grep -Fq -- '--check|--apply' "$SNAPPER_INITIALIZER" || fail "Snapper initializer lacks explicit modes"
if grep -Fq 'sudo' "$SNAPPER_INITIALIZER"; then
  fail "Snapper initializer invokes sudo internally"
fi

snapper_mapping_owners="$(awk '
  function flush() {
    if (application_name != "" && block ~ /backup: \.\/Linux\/Snapper/) {
      print application_name
    }
  }

  /^  - / {
    if (length(block) > 0) {
      flush()
    }
    block = $0 ORS
    application_name = ""
    if ($0 ~ /^  - name: /) {
      application_name = $0
      sub(/^  - name: /, "", application_name)
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
' "$CONFIG_FILE")"
[[ "$snapper_mapping_owners" == "snapper" ]] ||
  fail "Linux/Snapper mappings are owned by unexpected applications: $snapper_mapping_owners"

bootstrap_snapper_restore_line="$(awk '/run_tidydots_phase restore snapper/ { print NR; exit }' "$BOOTSTRAP")"
bootstrap_broad_restore_line="$(awk '/run_tidydots_phase restore$/ && !/function/ { print NR; exit }' "$BOOTSTRAP")"
bootstrap_initializer_line="$(awk '/^[[:space:]]*run_snapper_initializer$/ { print NR; exit }' "$BOOTSTRAP")"
[[ -n "$bootstrap_snapper_restore_line" ]] || fail "bootstrap does not restore Snapper before the environment"
[[ -n "$bootstrap_broad_restore_line" ]] || fail "bootstrap does not preserve a broad restore phase"
[[ -n "$bootstrap_initializer_line" ]] || fail "bootstrap does not invoke the root-only Snapper initializer"
(( bootstrap_snapper_restore_line < bootstrap_initializer_line && bootstrap_initializer_line < bootstrap_broad_restore_line )) ||
  fail "bootstrap restores the broad environment before Snapper initialization"

printf 'PASS: shared Limine/Snapper ownership and host-safe boot profile are complete\n'
