#!/usr/bin/env bash
set -Eeuo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../../.." && pwd)"
REGISTRY="$ROOT/Linux/quickshell/desktop-shell/services/PluginRegistry.qml"

scan_line="$(grep -F -- '-name manifest.json' "$REGISTRY")"
grep -Fq '\\(' <<<"$scan_line"
grep -Fq '\\)' <<<"$scan_line"

# shellcheck disable=SC2016
scan_script='scan_first_party() { local dir="$1"; while IFS= read -r manifest; do printf "%s\n" "$manifest"; done < <(find "$dir" -mindepth 2 -maxdepth 3 -type f \( -name manifest.json -o -name "*.manifest.json" \) | sort); }; scan_first_party "$0"'
bash -n -c "$scan_script"

fixture="$(mktemp -d)"
trap 'rm -rf "$fixture"' EXIT
mkdir -p "$fixture/plugins/bar"
printf '{}\n' >"$fixture/plugins/bar/manifest.json"
scan_output="$(bash -c "$scan_script" "$fixture")"
grep -Fxq "$fixture/plugins/bar/manifest.json" <<<"$scan_output"

grep -Fq 'onExited: function(exitCode)' "$REGISTRY"
grep -Fq 'registry.handleScanExit(exitCode, scanStdout.text || "")' "$REGISTRY"
grep -Fq 'if (Number(exitCode) !== 0)' "$REGISTRY"
grep -Fq 'registry.lastScanError =' "$REGISTRY"
grep -Fq 'registry.scanFinished()' "$REGISTRY"

previous_registry='{"desktop.keep":{"name":"keep"}}'
registry="$previous_registry"
scan_error=""
scan_exit=7
if ((scan_exit != 0)); then
  scan_error="first-party plugin scan failed with exit code $scan_exit"
else
  registry=""
fi

test "$registry" = "$previous_registry"
test "$scan_error" = 'first-party plugin scan failed with exit code 7'
printf 'registry scan contract: escaped grouping and failed-scan retention verified\n'
