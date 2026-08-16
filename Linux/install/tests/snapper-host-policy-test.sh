#!/usr/bin/env bash
set -Eeuo pipefail

ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../../.." && pwd -P)"
TIDYDOTS_CONFIG="$ROOT/tidydots.yaml"

fail() {
  printf 'FAIL: %s\n' "$*" >&2
  exit 1
}

assert_contains() {
  local -r haystack="$1"
  local -r needle="$2"
  local -r context="$3"

  [[ "$haystack" == *"$needle"* ]] || fail "$context: missing '$needle'"
}

assert_not_contains() {
  local -r haystack="$1"
  local -r needle="$2"
  local -r context="$3"

  [[ "$haystack" != *"$needle"* ]] || fail "$context: found '$needle'"
}

application_block() {
  local -r wanted_name="$1"

  awk -v wanted_name="$wanted_name" '
    /^  - / {
      if (in_block && found) {
        printf "%s", block
        found = 0
        exit
      }
      block = $0 ORS
      in_block = 1
      found = 0
      if ($0 == "  - name: " wanted_name) found = 1
      next
    }
    in_block {
      block = block $0 ORS
      if ($0 == "  - name: " wanted_name || $0 == "    name: " wanted_name) {
        found = 1
      }
    }
    END {
      if (found) printf "%s", block
    }
  ' "$TIDYDOTS_CONFIG"
}

[[ -f "$TIDYDOTS_CONFIG" ]] || fail "missing tidydots config: $TIDYDOTS_CONFIG"

SNAPPER_BLOCK="$(application_block snapper)"
DESKTOP_BLOCK="$(application_block snapper-current-desktop-config)"

assert_contains "$SNAPPER_BLOCK" 'pacman: snapper' 'shared Snapper package ownership'
assert_contains "$SNAPPER_BLOCK" 'when: '\''{{ eq .OS "linux" }}'\''' 'shared Snapper package gate'
assert_contains "$SNAPPER_BLOCK" 'entries: []' 'shared Snapper package has no file entries'
assert_not_contains "$SNAPPER_BLOCK" 'targets:' 'shared Snapper package has no target mappings'
assert_not_contains "$SNAPPER_BLOCK" 'Linux/Snapper' 'shared Snapper package has no Snapper file ownership'

assert_contains "$DESKTOP_BLOCK" 'name: snapper-current-desktop-config' 'desktop Snapper application name'
assert_contains "$DESKTOP_BLOCK" 'when: '\''{{ eq .Hostname "DESKTOP-E07VTRN" }}'\''' 'desktop Snapper exact hostname gate'
assert_contains "$DESKTOP_BLOCK" 'linux: /etc/snapper/configs' 'desktop Snapper config target'
assert_contains "$DESKTOP_BLOCK" 'linux: /etc/conf.d' 'desktop Snapper registration target'
assert_contains "$DESKTOP_BLOCK" 'backup: ./Linux/Snapper/configs' 'desktop Snapper config source'
assert_contains "$DESKTOP_BLOCK" 'backup: ./Linux/Snapper/conf.d' 'desktop Snapper registration source'
assert_not_contains "$DESKTOP_BLOCK" 'snapper-initialize' 'desktop does not own Archinstall initializer'

[[ "$(awk '$0 == "  - name: snapper-current-desktop-config" { count++ } END { print count + 0 }' "$TIDYDOTS_CONFIG")" == 1 ]] ||
  fail 'desktop Snapper application is not declared exactly once'
[[ "$(awk '/backup: \.\/Linux\/Snapper\/configs$/ { count++ } END { print count + 0 }' "$TIDYDOTS_CONFIG")" == 1 ]] ||
  fail 'Snapper config mapping has more than one tidydots writer'
[[ "$(awk '/backup: \.\/Linux\/Snapper\/conf\.d$/ { count++ } END { print count + 0 }' "$TIDYDOTS_CONFIG")" == 1 ]] ||
  fail 'Snapper registration mapping has more than one tidydots writer'
[[ "$(awk '/snapper-initialize/ { count++ } END { print count + 0 }' "$TIDYDOTS_CONFIG")" == 0 ]] ||
  fail 'Archinstall initializer remains a tidydots mapping'

printf 'PASS: Snapper package and host policy ownership\n'
