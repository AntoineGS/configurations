#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd -- "$SCRIPT_DIR/../../.." && pwd)"
CONFIG="$ROOT/tidydots.yaml"

extract_check() {
  awk '
    $0 == "      - check:" { in_check = 1; in_linux = 0; command = ""; next }
    in_check && $0 == "        run:" { in_linux = 0; next }
    in_check && $0 == "        name: pi-herdr" { found = 1; exit }
    in_check && $0 ~ /^          linux: >-/ { in_linux = 1; next }
    in_linux && $0 !~ /^            / { in_linux = 0; next }
    in_linux {
      line = $0
      sub(/^            /, "", line)
      command = command (command ? " " : "") line
    }
    END { if (found) print command }
  ' "$CONFIG"
}

write_plugin_output() {
  case "$PLUGIN_STATE" in
    enabled)
      cat <<'JSON'
{
  "npm": [
    {
      "name": "other-plugin",
      "version": "1.0.0",
      "manifest": {
        "name": "@andrewjacop/pi-herdr",
        "enabled": true
      },
      "enabled": true
    },
    {
      "name": "@andrewjacop/pi-herdr",
      "version": "0.2.5",
      "manifest": {},
      "enabled": true
    }
  ],
  "marketplace": []
}
JSON
      ;;
    disabled)
      cat <<'JSON'
{
  "npm": [
    {
      "name": "@andrewjacop/pi-herdr",
      "version": "0.2.5",
      "manifest": {},
      "enabled": false
    }
  ],
  "marketplace": []
}
JSON
      ;;
    absent)
      cat <<'JSON'
{
  "npm": [
    {
      "name": "other-plugin",
      "version": "1.0.0",
      "manifest": {},
      "enabled": true
    }
  ],
  "marketplace": []
}
JSON
      ;;
    similar)
      cat <<'JSON'
{
  "npm": [
    {
      "name": "@andrewjacop/pi-herdr-extra",
      "version": "0.2.5",
      "manifest": {},
      "enabled": true
    }
  ],
  "marketplace": []
}
JSON
      ;;
    nested)
      cat <<'JSON'
{
  "npm": [
    {
      "name": "other-plugin",
      "version": "1.0.0",
      "manifest": {
        "name": "@andrewjacop/pi-herdr",
        "enabled": true
      },
      "enabled": true
    }
  ],
  "marketplace": [
    {
      "id": "@andrewjacop/pi-herdr",
      "enabled": true
    }
  ]
}
JSON
      ;;
    *)
      return 2
      ;;
  esac
}

run_fixture() {
  local state="$1"
  local expect_success="$2"
  local fixture_root fixture_bin fake_omp check_status

  fixture_root="$(mktemp -d)"
  fixture_bin="$fixture_root/bin"
  mkdir -p "$fixture_bin" "$fixture_root/home" "$fixture_root/xdg-data"
  PLUGIN_STATE="$state" write_plugin_output > "$fixture_root/plugin.json"

  fake_omp="$fixture_bin/omp"
  cat > "$fake_omp" <<'SH'
#!/bin/sh
if [ "$1 $2 $3" != "plugin list --json" ]; then
  exit 2
fi
if [ "${EXPECT_XDG_DATA_HOME:-}" != "${XDG_DATA_HOME:-}" ]; then
  exit 3
fi
/bin/cat "$PLUGIN_FIXTURE"
SH
  chmod +x "$fake_omp"
  ln -s "$(command -v awk)" "$fixture_bin/awk"

  check_status=0
  PATH="$fixture_bin" HOME="$fixture_root/home" XDG_DATA_HOME="$fixture_root/xdg-data" \
    PLUGIN_FIXTURE="$fixture_root/plugin.json" EXPECT_XDG_DATA_HOME="$fixture_root/xdg-data" \
    /bin/bash -c "$(extract_check)" || check_status=$?

  if [[ "$expect_success" == true ]]; then
    test "$check_status" -eq 0
  else
    test "$check_status" -ne 0
  fi

  rm -rf "$fixture_root"
}

check="$(extract_check)"
if [[ -z "$check" ]]; then
  printf 'pi-herdr check not found\n' >&2
  exit 1
fi
if printf '%s\n' "$check" | rg -q 'jq|\.omp/plugins|node_modules/pi-herdr'; then
  printf 'pi-herdr check uses a filesystem or jq dependency\n' >&2
  exit 1
fi

run_fixture enabled true
run_fixture disabled false
run_fixture absent false
run_fixture similar false
run_fixture nested false

printf 'pi-herdr check fixtures passed\n'
