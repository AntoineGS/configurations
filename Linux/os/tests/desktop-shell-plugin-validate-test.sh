#!/usr/bin/env bash
# shellcheck disable=SC2016
set -Eeuo pipefail

repo_root=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../../.." && pwd -P)
validator="$repo_root/Linux/os/helpers/desktop-shell-plugin-validate"
test_root=$(mktemp -d)
trap 'rm -rf -- "$test_root"' EXIT

fail() { printf 'FAIL: %s\n' "$1" >&2; exit 1; }
[[ -x "$validator" ]] || fail "validator is missing or not executable: $validator"
command -v jq >/dev/null 2>&1 || fail "jq is required"
command -v realpath >/dev/null 2>&1 || fail "realpath is required"

write_manifest() {
  local directory=$1 id=${2:-acme.plugin}
  local kinds=${3:-'["bar","bar-widget","menu","overlay","panel","service"]'}
  local entry_points=${4:-'{"bar":"Bar.qml","barWidget":"BarWidget.qml","menu":"Menu.qml","overlay":"Overlay.qml","panel":"Panel.qml","service":"Service.qml"}'}
  jq -n --arg id "$id" --argjson kinds "$kinds" --argjson entryPoints "$entry_points" \
    '{schemaVersion:1,id:$id,name:"Acme Plugin",version:"1.0.0",kinds:$kinds,entryPoints:$entryPoints}' >"$directory/manifest.json"
}

make_fixture() {
  local directory=$1
  mkdir -p "$directory/.git/hooks" "$directory/src"
  for file in Bar BarWidget Menu Overlay Panel Service; do printf 'source\n' >"$directory/$file.qml"; done
  printf '#!/bin/sh\nprintf hook-ran >%s\n' "$test_root/hook-ran" >"$directory/.git/hooks/pre-commit"
  chmod +x "$directory/.git/hooks/pre-commit"
  ln -s /tmp "$directory/.git/objects-link"
  write_manifest "$directory"
}

expect_accept() {
  local name=$1 kinds=${2:-} entries=${3:-} directory="$test_root/$1"
  make_fixture "$directory"
  [[ -z "$kinds" ]] || write_manifest "$directory" acme.plugin "$kinds" "$entries"
  "$validator" "$directory" >"$test_root/$name.stdout" 2>"$test_root/$name.stderr" || fail "$name was rejected: $(<"$test_root/$name.stderr")"
  [[ ! -s "$test_root/$name.stdout" ]] || fail "$name produced stdout"
  [[ ! -s "$test_root/$name.stderr" ]] || fail "$name produced stderr"
}

expect_reject() {
  local name=$1 expected=$2 directory="$test_root/$1" status=0
  shift 2
  make_fixture "$directory"
  TEST_DIRECTORY="$directory" FIELD="${FIELD:-}" "$@"
  if "$validator" "$directory" >"$test_root/$name.stdout" 2>"$test_root/$name.stderr"; then fail "$name was accepted"; else status=$?; fi
  [[ "$status" -ne 0 ]] || fail "$name returned success"
  grep -Fq -- "$expected" "$test_root/$name.stderr" || fail "$name did not report '$expected': $(<"$test_root/$name.stderr")"
}

mutate_wrong_type() {
  local filter
  case "$FIELD" in
    kinds) filter='.kinds = "bar"' ;;
    entryPoints) filter='.entryPoints = []' ;;
    schemaVersion) filter='.schemaVersion = "one"' ;;
    *) filter='.[ $field ] = 1' ;;
  esac
  jq --arg field "$FIELD" "$filter" "$TEST_DIRECTORY/manifest.json" >"$TEST_DIRECTORY/manifest.tmp"
  mv "$TEST_DIRECTORY/manifest.tmp" "$TEST_DIRECTORY/manifest.json"
}

expect_accept accepted-all-kinds
for kind in bar bar-widget menu overlay panel service; do
  key=$kind; [[ "$kind" == bar-widget ]] && key=barWidget
  expect_accept "accepted-$kind" "[\"$kind\"]" "{\"$key\":\"${key^}.qml\"}"
done

expect_reject invalid-json "manifest validation failed" bash -c 'printf "{" >"$TEST_DIRECTORY/manifest.json"'
expect_reject wrong-schema "schemaVersion must be 1" bash -c 'jq ".schemaVersion=2" "$TEST_DIRECTORY/manifest.json" >"$TEST_DIRECTORY/manifest.tmp" && mv "$TEST_DIRECTORY/manifest.tmp" "$TEST_DIRECTORY/manifest.json"'
for field in id name version kinds entryPoints; do
  FIELD="$field" expect_reject "missing-$field" "missing required field '$field'" bash -c 'jq "del(.[\$FIELD])" --arg FIELD "$FIELD" "$TEST_DIRECTORY/manifest.json" >"$TEST_DIRECTORY/manifest.tmp" && mv "$TEST_DIRECTORY/manifest.tmp" "$TEST_DIRECTORY/manifest.json"'
  FIELD="$field" expect_reject "wrong-type-$field" "must" mutate_wrong_type
done
expect_reject empty-kinds "kinds must be a non-empty array" bash -c 'jq ".kinds=[]" "$TEST_DIRECTORY/manifest.json" >"$TEST_DIRECTORY/manifest.tmp" && mv "$TEST_DIRECTORY/manifest.tmp" "$TEST_DIRECTORY/manifest.json"'
expect_reject duplicate-kinds "kinds must contain unique strings" bash -c 'jq ".kinds=[\"bar\",\"bar\"]" "$TEST_DIRECTORY/manifest.json" >"$TEST_DIRECTORY/manifest.tmp" && mv "$TEST_DIRECTORY/manifest.tmp" "$TEST_DIRECTORY/manifest.json"'
expect_reject unsupported-kind "unsupported kind" bash -c 'jq ".kinds=[\"nope\"]|.entryPoints={}" "$TEST_DIRECTORY/manifest.json" >"$TEST_DIRECTORY/manifest.tmp" && mv "$TEST_DIRECTORY/manifest.tmp" "$TEST_DIRECTORY/manifest.json"'
for id in desktop.clock omarchy.clock; do expect_reject "unsafe-${id//./-}" "plugin id" env ID="$id" bash -c 'jq --arg id "$ID" ".id=\$id" "$TEST_DIRECTORY/manifest.json" >"$TEST_DIRECTORY/manifest.tmp" && mv "$TEST_DIRECTORY/manifest.tmp" "$TEST_DIRECTORY/manifest.json"'; done
expect_reject absolute-entry "entry point escapes plugin directory" bash -c 'jq ".entryPoints.bar=\"/tmp/Bar.qml\"" "$TEST_DIRECTORY/manifest.json" >"$TEST_DIRECTORY/manifest.tmp" && mv "$TEST_DIRECTORY/manifest.tmp" "$TEST_DIRECTORY/manifest.json"'
expect_reject parent-entry "entry point escapes plugin directory" bash -c 'jq ".entryPoints.bar=\"../Bar.qml\"" "$TEST_DIRECTORY/manifest.json" >"$TEST_DIRECTORY/manifest.tmp" && mv "$TEST_DIRECTORY/manifest.tmp" "$TEST_DIRECTORY/manifest.json"'
expect_reject missing-kind-entry "requires entryPoints.barWidget" bash -c 'jq "del(.entryPoints.barWidget)" "$TEST_DIRECTORY/manifest.json" >"$TEST_DIRECTORY/manifest.tmp" && mv "$TEST_DIRECTORY/manifest.tmp" "$TEST_DIRECTORY/manifest.json"'
expect_reject missing-file "entry point file not found" bash -c 'rm -f "$TEST_DIRECTORY/Bar.qml"'
expect_reject directory-entry "entry point" bash -c 'rm -f "$TEST_DIRECTORY/Menu.qml" && mkdir "$TEST_DIRECTORY/Menu.qml"'
expect_reject undeclared-key "has no declared kind" bash -c 'jq ".kinds=[\"bar\"]" "$TEST_DIRECTORY/manifest.json" >"$TEST_DIRECTORY/manifest.tmp" && mv "$TEST_DIRECTORY/manifest.tmp" "$TEST_DIRECTORY/manifest.json"'
expect_reject unsupported-key "unsupported entry point key" bash -c 'jq ".entryPoints.nope=\"Nope.qml\"" "$TEST_DIRECTORY/manifest.json" >"$TEST_DIRECTORY/manifest.tmp" && mv "$TEST_DIRECTORY/manifest.tmp" "$TEST_DIRECTORY/manifest.json"'
expect_reject invalid-section "barWidget.defaultSection must be left, center, or right" bash -c 'jq ".barWidget={defaultSection:\"top\"}" "$TEST_DIRECTORY/manifest.json" >"$TEST_DIRECTORY/manifest.tmp" && mv "$TEST_DIRECTORY/manifest.tmp" "$TEST_DIRECTORY/manifest.json"'
expect_reject null-widget "barWidget must be an object" bash -c 'jq ".barWidget=null" "$TEST_DIRECTORY/manifest.json" >"$TEST_DIRECTORY/manifest.tmp" && mv "$TEST_DIRECTORY/manifest.tmp" "$TEST_DIRECTORY/manifest.json"'
expect_reject null-section "barWidget.defaultSection must be left, center, or right" bash -c 'jq ".barWidget={defaultSection:null}" "$TEST_DIRECTORY/manifest.json" >"$TEST_DIRECTORY/manifest.tmp" && mv "$TEST_DIRECTORY/manifest.tmp" "$TEST_DIRECTORY/manifest.json"'
expect_reject newline-kind "unsupported kind" bash -c 'jq ".kinds=[\"bar\\nmenu\"]|.entryPoints={bar:\"Bar.qml\",menu:\"Menu.qml\"}" "$TEST_DIRECTORY/manifest.json" >"$TEST_DIRECTORY/manifest.tmp" && mv "$TEST_DIRECTORY/manifest.tmp" "$TEST_DIRECTORY/manifest.json"'
expect_reject newline-entry "entry point file not found" bash -c 'jq ".kinds=[\"bar\"]|.entryPoints={bar:(\"Bar.qml\" + \"\\u000a\")}" "$TEST_DIRECTORY/manifest.json" >"$TEST_DIRECTORY/manifest.tmp" && mv "$TEST_DIRECTORY/manifest.tmp" "$TEST_DIRECTORY/manifest.json"'
expect_reject nul-entry "NUL" bash -c 'jq ".entryPoints.bar=\"Bar.qml\\u0000\"" "$TEST_DIRECTORY/manifest.json" >"$TEST_DIRECTORY/manifest.tmp" && mv "$TEST_DIRECTORY/manifest.tmp" "$TEST_DIRECTORY/manifest.json"'
expect_reject newline-key "unsupported entry point key" bash -c 'jq ".kinds=[\"bar\"]|.entryPoints={\"bar\\nmenu\":\"Bar.qml\"}" "$TEST_DIRECTORY/manifest.json" >"$TEST_DIRECTORY/manifest.tmp" && mv "$TEST_DIRECTORY/manifest.tmp" "$TEST_DIRECTORY/manifest.json"'
expect_reject outside-link "symbolic links are not allowed" bash -c 'printf outside >"$TEST_DIRECTORY/../outside.qml" && ln -s "$TEST_DIRECTORY/../outside.qml" "$TEST_DIRECTORY/outside-link"'
expect_reject outside-dir-link "symbolic links are not allowed" bash -c 'ln -s /tmp "$TEST_DIRECTORY/src/outside-link"'

safe_sibling="$test_root/trailing-sibling"
unsafe_sibling="$test_root/trailing-sibling"$'\n'
make_fixture "$safe_sibling"
mkdir -p "$unsafe_sibling"
unsafe_status=0
if "$validator" "$unsafe_sibling" >"$test_root/trailing-sibling.stdout" 2>"$test_root/trailing-sibling.stderr"; then
  fail "trailing-newline sibling was accepted through the safe sibling"
else
  unsafe_status=$?
fi
[[ "$unsafe_status" -ne 0 ]] || fail "trailing-newline sibling returned success"
grep -Fq -- "root manifest.json is required" "$test_root/trailing-sibling.stderr" ||
  fail "trailing-newline sibling reported the wrong error: $(<"$test_root/trailing-sibling.stderr")"

[[ ! -e "$test_root/hook-ran" ]] || fail "validator executed a Git hook"
printf 'PASS: desktop-shell plugin validator\n'
