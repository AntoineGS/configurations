#!/usr/bin/env bash
# shellcheck disable=SC2016
set -Eeuo pipefail

repo_root=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../../.." && pwd -P)
validator="$repo_root/Linux/os/helpers/desktop-shell-plugin-validate"
test_root=$(mktemp -d)

trap 'rm -rf -- "$test_root"' EXIT

fail() {
  printf 'FAIL: %s\n' "$1" >&2
  exit 1
}

[[ -x "$validator" ]] || fail "validator is missing or not executable: $validator"
command -v jq >/dev/null 2>&1 || fail "jq is required"
command -v realpath >/dev/null 2>&1 || fail "realpath is required"

write_manifest() {
  local directory=$1
  local id=${2:-acme.plugin}
  local kinds=${3:-'["bar","bar-widget","menu","overlay","panel","service"]'}
  local entry_points=${4:-'{"bar":"Bar.qml","barWidget":"BarWidget.qml","menu":"Menu.qml","overlay":"Overlay.qml","panel":"Panel.qml","service":"Service.qml"}'}
  local schema=${5:-1}

  jq -n \
    --arg id "$id" \
    --argjson kinds "$kinds" \
    --argjson entryPoints "$entry_points" \
    --argjson schemaVersion "$schema" \
    '{schemaVersion:$schemaVersion,id:$id,name:"Acme Plugin",version:"1.0.0",kinds:$kinds,entryPoints:$entryPoints}' \
    >"$directory/manifest.json"
}

make_fixture() {
  local directory=$1
  mkdir -p "$directory/.git/hooks" "$directory/src"
  printf 'plugin source\n' >"$directory/Bar.qml"
  printf 'plugin source\n' >"$directory/BarWidget.qml"
  printf 'plugin source\n' >"$directory/Menu.qml"
  printf 'plugin source\n' >"$directory/Overlay.qml"
  printf 'plugin source\n' >"$directory/Panel.qml"
  printf 'plugin source\n' >"$directory/Service.qml"
  printf '#!/bin/sh\nprintf hook-ran >%s\n' "$test_root/hook-ran" >"$directory/.git/hooks/pre-commit"
  chmod +x "$directory/.git/hooks/pre-commit"
  ln -s /tmp "$directory/.git/objects-link"
  write_manifest "$directory"
}

expect_accept() {
  local name=$1
  local kinds=${2:-'["bar","bar-widget","menu","overlay","panel","service"]'}
  local entry_points=${3:-'{"bar":"Bar.qml","barWidget":"BarWidget.qml","menu":"Menu.qml","overlay":"Overlay.qml","panel":"Panel.qml","service":"Service.qml"}'}
  local directory="$test_root/$name"
  make_fixture "$directory"
  write_manifest "$directory" acme.plugin "$kinds" "$entry_points"
  "$validator" "$directory" >"$test_root/$name.stdout" 2>"$test_root/$name.stderr" ||
    fail "$name was rejected: $(<"$test_root/$name.stderr")"
  [[ ! -s "$test_root/$name.stdout" ]] || fail "$name produced stdout"
}

expect_reject() {
  local name=$1
  local expected=$2
  shift 2
  local directory="$test_root/$name"
  make_fixture "$directory"
  TEST_DIRECTORY="$directory" "$@"
  local status=0
  if "$validator" "$directory" >"$test_root/$name.stdout" 2>"$test_root/$name.stderr"; then
    fail "$name was accepted"
  else
    status=$?
  fi
  [[ "$status" -ne 0 ]] || fail "$name returned success"
  grep -Fq -- "$expected" "$test_root/$name.stderr" ||
    fail "$name did not report '$expected': $(<"$test_root/$name.stderr")"
}

expect_accept "accepted-all-kinds"

for kind in bar bar-widget menu overlay panel service; do
  key=$kind
  [[ "$kind" == bar-widget ]] && key=barWidget
  expect_accept "accepted-$kind" "[\"$kind\"]" "{\"$key\":\"${key^}.qml\"}"
done

expect_reject "invalid-json" "invalid JSON" bash -c 'printf "{" >"$TEST_DIRECTORY/manifest.json"'
expect_reject "wrong-schema" "schemaVersion must be 1" bash -c 'jq ".schemaVersion = 2" "$TEST_DIRECTORY/manifest.json" >"$TEST_DIRECTORY/manifest.tmp" && mv "$TEST_DIRECTORY/manifest.tmp" "$TEST_DIRECTORY/manifest.json"'

for field in id name version kinds entryPoints; do
  FIELD="$field" expect_reject "missing-$field" "missing required field '$field'" \
    bash -c 'jq "del(.[\$field])" --arg field "$FIELD" "$TEST_DIRECTORY/manifest.json" >"$TEST_DIRECTORY/manifest.tmp" && mv "$TEST_DIRECTORY/manifest.tmp" "$TEST_DIRECTORY/manifest.json"'
done

expect_reject "empty-kinds" "kinds must be a non-empty array" \
  bash -c 'jq ".kinds = []" "$TEST_DIRECTORY/manifest.json" >"$TEST_DIRECTORY/manifest.tmp" && mv "$TEST_DIRECTORY/manifest.tmp" "$TEST_DIRECTORY/manifest.json"'
expect_reject "duplicate-kinds" "kinds must contain unique strings" \
  bash -c 'jq ".kinds = [\"bar\",\"bar\"]" "$TEST_DIRECTORY/manifest.json" >"$TEST_DIRECTORY/manifest.tmp" && mv "$TEST_DIRECTORY/manifest.tmp" "$TEST_DIRECTORY/manifest.json"'
expect_reject "unsupported-kind" "unsupported kind: nope" \
  bash -c 'jq ".kinds = [\"nope\"] | .entryPoints = {}" "$TEST_DIRECTORY/manifest.json" >"$TEST_DIRECTORY/manifest.tmp" && mv "$TEST_DIRECTORY/manifest.tmp" "$TEST_DIRECTORY/manifest.json"'

for id in unsafe 'desktop.clock' 'omarchy.clock'; do
  expect_reject "unsafe-id-${id//./-}" "plugin id" \
    env ID="$id" bash -c 'jq --arg id "$ID" ".id = \$id" "$TEST_DIRECTORY/manifest.json" >"$TEST_DIRECTORY/manifest.tmp" && mv "$TEST_DIRECTORY/manifest.tmp" "$TEST_DIRECTORY/manifest.json"'
done

expect_reject "absolute-entry-point" "entry point escapes plugin directory" \
  bash -c 'jq ".entryPoints.bar = \"/tmp/Bar.qml\"" "$TEST_DIRECTORY/manifest.json" >"$TEST_DIRECTORY/manifest.tmp" && mv "$TEST_DIRECTORY/manifest.tmp" "$TEST_DIRECTORY/manifest.json"'
expect_reject "parent-entry-point" "entry point escapes plugin directory" \
  bash -c 'jq ".entryPoints.bar = \"../Bar.qml\"" "$TEST_DIRECTORY/manifest.json" >"$TEST_DIRECTORY/manifest.tmp" && mv "$TEST_DIRECTORY/manifest.tmp" "$TEST_DIRECTORY/manifest.json"'
expect_reject "missing-declared-entry-point" "kind 'bar-widget' requires entryPoints.barWidget" \
  bash -c 'jq "del(.entryPoints.barWidget)" "$TEST_DIRECTORY/manifest.json" >"$TEST_DIRECTORY/manifest.tmp" && mv "$TEST_DIRECTORY/manifest.tmp" "$TEST_DIRECTORY/manifest.json"'
expect_reject "missing-entry-point-file" "entry point file not found: Bar.qml" bash -c 'rm -f "$TEST_DIRECTORY/Bar.qml"'
expect_reject "invalid-default-section" "barWidget.defaultSection must be left, center, or right" \
  bash -c 'jq ".barWidget = {defaultSection:\"top\"}" "$TEST_DIRECTORY/manifest.json" >"$TEST_DIRECTORY/manifest.tmp" && mv "$TEST_DIRECTORY/manifest.tmp" "$TEST_DIRECTORY/manifest.json"'
expect_reject "outside-file-symlink" "symbolic links are not allowed" \
  bash -c 'ln -s /tmp "$TEST_DIRECTORY/outside-link"'
expect_reject "outside-directory-symlink" "symbolic links are not allowed" \
  bash -c 'ln -s /tmp "$TEST_DIRECTORY/src/outside-link"'

[[ ! -e "$test_root/hook-ran" ]] || fail "validator executed a Git hook"

printf 'PASS: desktop-shell plugin validator\n'
