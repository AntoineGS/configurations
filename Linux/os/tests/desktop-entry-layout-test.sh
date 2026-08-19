#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../../.." && pwd -P)"

test -f "$ROOT/Linux/os/applications/common/Docker.desktop"
test -f "$ROOT/Linux/os/applications/common/Disk Usage.desktop"
test -f "$ROOT/Linux/os/applications/common/GitHub.desktop"
test -f "$ROOT/Linux/os/applications/common/nvim-open.desktop"
test -f "$ROOT/Linux/os/applications/common/pkg-install.desktop"
test -f "$ROOT/Linux/os/applications/antoinews-linux/mdexplorer.desktop"
test -f "$ROOT/Linux/os/applications/desktop-e07vtrn/.gitkeep"
test -f "$ROOT/Linux/os/applications/omarchbook/.gitkeep"
test -f "$ROOT/Linux/os/application-overrides/fcitx5-wayland-launcher.desktop"

if ! command -v yq >/dev/null 2>&1; then
  printf '%s\n' 'yq is required to validate desktop tidydots tuples' >&2
  exit 1
fi

expected_desktop_tuples=$(
  printf '%s\n' \
    $'common .desktop files\t~/.local/share/applications/common\t./Linux/os/applications/common\t' \
    $'fcitx desktop override\t~/.local/share/applications\t./Linux/os/application-overrides\t' \
    $'antoinews-linux .desktop files\t~/.local/share/applications/antoinews-linux\t./Linux/os/applications/antoinews-linux\t{{ eq .Hostname "antoinews-linux" }}' \
    $'desktop-e07vtrn .desktop files\t~/.local/share/applications/desktop-e07vtrn\t./Linux/os/applications/desktop-e07vtrn\t{{ eq .Hostname "DESKTOP-E07VTRN" }}' \
    $'omarchbook .desktop files\t~/.local/share/applications/omarchbook\t./Linux/os/applications/omarchbook\t{{ eq .Hostname "omarchbook" }}'
)
actual_desktop_tuples=$(
  yq -r '
    [.applications[] | (.entries // [])[]
      | select(
          .name == "common .desktop files" or
          .name == "fcitx desktop override" or
          .name == "antoinews-linux .desktop files" or
          .name == "desktop-e07vtrn .desktop files" or
          .name == "omarchbook .desktop files"
        )
      | [.name, .targets.linux, .backup, (.when // "")]
      | @tsv
    ] | .[]
  ' "$ROOT/tidydots.yaml"
)
if [[ $actual_desktop_tuples != "$expected_desktop_tuples" ]]; then
  printf 'desktop tidydots tuples mismatch:\nexpected:\n%s\nactual:\n%s\n' \
    "$expected_desktop_tuples" "$actual_desktop_tuples" >&2
  exit 1
fi

while IFS= read -r -d '' application_file; do
  application_name="${application_file##*/}"
  case "$application_name" in
    mimeinfo_target_20260404.cache|*_target_20260404*)
      printf 'dated desktop application artifact remains: %s\n' "$application_file" >&2
      exit 1
      ;;
  esac
done < <(find "$ROOT/Linux/os/applications" \( -type f -o -type l \) -print0)

python3 - "$ROOT/Linux/os/mimeapps.list" <<'PY'
import configparser
import sys

path = sys.argv[1]
parser = configparser.ConfigParser(interpolation=None)
parser.read(path, encoding="utf-8")

section = "Default Applications"
key = "x-scheme-handler/nvim"
expected = "common-nvim-open.desktop"
actual = parser[section][key]
if actual != expected:
    raise SystemExit(
        f"{path}: [{section}] {key} expected {expected!r}, got {actual!r}"
    )
PY

list_output=$(cd "$ROOT" && tidydots list)
grep -Fq 'common .desktop files' <<<"$list_output"
grep -Fq 'fcitx desktop override' <<<"$list_output"

case $(hostnamectl --static) in
  antoinews-linux)
    grep -Fq 'antoinews-linux .desktop files' <<<"$list_output"
    ! grep -Fq 'desktop-e07vtrn .desktop files' <<<"$list_output"
    ! grep -Fq 'omarchbook .desktop files' <<<"$list_output"
    ;;
  DESKTOP-E07VTRN)
    grep -Fq 'desktop-e07vtrn .desktop files' <<<"$list_output"
    ! grep -Fq 'antoinews-linux .desktop files' <<<"$list_output"
    ! grep -Fq 'omarchbook .desktop files' <<<"$list_output"
    ;;
  omarchbook)
    grep -Fq 'omarchbook .desktop files' <<<"$list_output"
    ! grep -Fq 'antoinews-linux .desktop files' <<<"$list_output"
    ! grep -Fq 'desktop-e07vtrn .desktop files' <<<"$list_output"
    ;;
esac
