#!/usr/bin/env bash
set -Eeuo pipefail

script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
script="$script_dir/../helpers/setup-remmina-hostkey"
tmp_dir="$(mktemp -d)"
pref_file="$tmp_dir/config/remmina/remmina.pref"

trap 'rm -rf -- "$tmp_dir"' EXIT

fail() {
  printf 'FAIL: %s\n' "$*" >&2
  exit 1
}

[[ -x "$script" ]] || fail "$script must exist and be executable"

run_script() {
  REMMINA_PREF_FILE="$pref_file" "$script" "$@"
}

assert_content() {
  local expected="$1"
  local description="$2"
  local actual

  actual="$(<"$pref_file")"
  [[ "$actual" == "$expected" ]] || {
    printf 'Expected %s:\n%s\nActual:\n%s\n' "$description" "$expected" "$actual" >&2
    fail "$description differs"
  }
}

assert_bytes() {
  local expected="$1"
  local description="$2"
  local expected_file="$tmp_dir/expected-bytes"

  printf '%s' "$expected" > "$expected_file"
  cmp -s -- "$expected_file" "$pref_file" || fail "$description differs at the byte level"
}

if run_script --check; then
  fail "--check succeeded without a preference file"
fi
[[ ! -e "$pref_file" ]] || fail "--check created the preference file"

run_script --apply || fail "--apply failed without a preference file"
assert_content $'[remmina_pref]\nhostkey=0' "minimal preference"
run_script --check || fail "--check failed after creating the minimal preference"

incorrect_pref=$'[remmina_pref]\nsecret=keep-this-secret\nremmina_file_name=%G_%P_%N_%h\nhostkey=65508\n\n[other]\nhostkey=42'
corrected_pref=$'[remmina_pref]\nsecret=keep-this-secret\nremmina_file_name=%G_%P_%N_%h\nhostkey=0\n\n[other]\nhostkey=42'
printf '%s\n' "$incorrect_pref" > "$pref_file"
chmod 640 -- "$pref_file"

if run_script --check; then
  fail "--check succeeded with the incorrect host key"
fi
assert_content "$incorrect_pref" "preference after read-only check"
run_script --apply || fail "--apply failed with the incorrect host key"
assert_content "$corrected_pref" "corrected preference"
[[ "$(stat -c %a "$pref_file")" == 640 ]] || fail "--apply did not preserve the preference mode"
run_script --check || fail "--check failed with the corrected host key"

missing_key_pref=$'[remmina_pref]\nsecret=another-secret\n\n[remmina_info]\ndisable_tip=true'
injected_key_pref=$'[remmina_pref]\nsecret=another-secret\nhostkey=0\n\n[remmina_info]\ndisable_tip=true'
printf '%s\n' "$missing_key_pref" > "$pref_file"

if run_script --check; then
  fail "--check succeeded without a host key"
fi
run_script --apply || fail "--apply failed without a host key"
assert_content "$injected_key_pref" "preference with injected host key"
run_script --check || fail "--check failed after injecting the host key"

missing_section_pref=$'[remmina_info]\ninfo_uid_prefix=keep-this-id\ndisable_tip=true'
appended_section_pref=$'[remmina_info]\ninfo_uid_prefix=keep-this-id\ndisable_tip=true\n\n[remmina_pref]\nhostkey=0'
printf '%s\n' "$missing_section_pref" > "$pref_file"

if run_script --check; then
  fail "--check succeeded without the preference section"
fi
run_script --apply || fail "--apply failed without the preference section"
assert_content "$appended_section_pref" "preference with appended section"
run_script --check || fail "--check failed after appending the preference section"

duplicate_key_pref=$'[remmina_pref]\nsecret=duplicate-test\nhostkey=0\nhostkey=65508'
normalized_key_pref=$'[remmina_pref]\nsecret=duplicate-test\nhostkey=0'
printf '%s\n' "$duplicate_key_pref" > "$pref_file"

if run_script --check; then
  fail "--check succeeded with a conflicting duplicate host key"
fi
run_script --apply || fail "--apply failed with duplicate host keys"
assert_content "$normalized_key_pref" "preference with normalized host key"
run_script --check || fail "--check failed after normalizing host keys"

duplicate_section_pref=$'[remmina_pref]\nsecret=section-test\nhostkey=65508\n\n[remmina_info]\ndisable_tip=true\n\n[remmina_pref]\nexpanded_group=work\nhostkey=123'
normalized_section_pref=$'[remmina_pref]\nsecret=section-test\nhostkey=0\n\n[remmina_info]\ndisable_tip=true\n\n[remmina_pref]\nexpanded_group=work'
printf '%s\n' "$duplicate_section_pref" > "$pref_file"

if run_script --check; then
  fail "--check succeeded with duplicate preference sections"
fi
run_script --apply || fail "--apply failed with duplicate preference sections"
assert_content "$normalized_section_pref" "preference with normalized duplicate sections"
run_script --check || fail "--check failed after normalizing duplicate sections"

keyless_duplicate_sections=$'[remmina_pref]\nsecret=keyless-section\n\n[remmina_info]\ndisable_tip=true\n\n[remmina_pref]\nexpanded_group=work'
normalized_keyless_sections=$'[remmina_pref]\nsecret=keyless-section\nhostkey=0\n\n[remmina_info]\ndisable_tip=true\n\n[remmina_pref]\nexpanded_group=work'
printf '%s\n' "$keyless_duplicate_sections" > "$pref_file"

run_script --apply || fail "--apply failed with keyless duplicate preference sections"
assert_content "$normalized_keyless_sections" "preference with normalized keyless duplicate sections"
run_script --check || fail "--check failed after normalizing keyless duplicate sections"

inode_before="$(stat -c %i "$pref_file")"
run_script --apply || fail "idempotent --apply failed"
assert_content "$normalized_keyless_sections" "preference after idempotent apply"
[[ "$(stat -c %i "$pref_file")" == "$inode_before" ]] || fail "idempotent --apply rewrote the preference"

linked_pref="$tmp_dir/linked/remmina.pref"
mkdir -p -- "$(dirname -- "$linked_pref")"
printf '%s\n' "$incorrect_pref" > "$linked_pref"
rm -- "$pref_file"
ln -s -- "$linked_pref" "$pref_file"

run_script --apply || fail "--apply failed for a symlinked preference"
[[ -L "$pref_file" ]] || fail "--apply replaced the preference symlink"
[[ "$(readlink -- "$pref_file")" == "$linked_pref" ]] || fail "--apply changed the preference symlink target"
assert_content "$corrected_pref" "corrected symlinked preference"
run_script --check || fail "--check failed for the corrected symlinked preference"

crlf_pref=$'  [remmina_pref]  \r\nsecret=crlf-secret\r\nhostkey = 65508\r\n\r\n[remmina_info]\r\ndisable_tip=true'
corrected_crlf_pref=$'  [remmina_pref]  \r\nsecret=crlf-secret\r\nhostkey=0\r\n\r\n[remmina_info]\r\ndisable_tip=true'
rm -- "$pref_file"
printf '%s' "$crlf_pref" > "$pref_file"

if run_script --check; then
  fail "--check succeeded with the incorrect CRLF host key"
fi
run_script --apply || fail "--apply failed for the CRLF preference"
assert_bytes "$corrected_crlf_pref" "corrected CRLF preference"
run_script --check || fail "--check failed for the corrected CRLF preference"

printf '%s\n' "$incorrect_pref" > "$pref_file"
if command -v setfacl >/dev/null 2>&1 && command -v getfacl >/dev/null 2>&1; then
  setfacl -m u:65534:r-- -- "$pref_file"
  acl_before="$(getfacl -cp -- "$pref_file")"
fi
if command -v setfattr >/dev/null 2>&1 && command -v getfattr >/dev/null 2>&1; then
  setfattr -n user.remmina-test -v preserve -- "$pref_file"
  xattr_before="$(getfattr -d -m - -- "$pref_file" 2>/dev/null)"
fi

run_script --apply || fail "--apply failed for a preference with metadata"
assert_content "$corrected_pref" "corrected preference with metadata"
if [[ -n "${acl_before:-}" ]]; then
  [[ "$(getfacl -cp -- "$pref_file")" == "$acl_before" ]] || fail "--apply did not preserve the preference ACL"
fi
if [[ -n "${xattr_before:-}" ]]; then
  [[ "$(getfattr -d -m - -- "$pref_file" 2>/dev/null)" == "$xattr_before" ]] || fail "--apply did not preserve preference xattrs"
fi

if command -v setfacl >/dev/null 2>&1 && command -v getfacl >/dev/null 2>&1; then
  printf '%s\n' "$incorrect_pref" > "$pref_file"
  setfacl -b -- "$pref_file"
  chmod 600 -- "$pref_file"
  setfacl -m d:u:65534:r-- -- "$(dirname -- "$pref_file")"
  basic_acl="$(getfacl -cp -- "$pref_file")"

  run_script --apply || fail "--apply failed under a parent default ACL"
  assert_content "$corrected_pref" "corrected preference under a parent default ACL"
  [[ "$(getfacl -cp -- "$pref_file")" == "$basic_acl" ]] || fail "--apply retained an ACL inherited by its temporary file"
fi

printf 'PASS: Remmina host key setup\n'
