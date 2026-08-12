#!/usr/bin/env bash
set -Eeuo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
CONFIG="$ROOT/Linux/install/archinstall/user_configuration.json"

fail() {
  printf 'FAIL: %s\n' "$1" >&2
  exit 1
}

jq -e '
  (keys | sort) == [
    "bootloader_config",
    "hostname",
    "kernels",
    "locale_config",
    "ntp",
    "packages",
    "services",
    "swap",
    "timezone"
  ] and
  .bootloader_config == {
    "bootloader": "Limine",
    "uki": false,
    "removable": false
  } and
  .hostname == "antoinews-linux" and
  .kernels == ["linux"] and
  .locale_config == {
    "kb_layout": "us",
    "sys_enc": "UTF-8",
    "sys_lang": "en_US"
  } and
  .ntp == true and
  .packages == ["base-devel", "git", "iwd", "linux-headers", "sudo"] and
  .services == ["iwd", "systemd-networkd", "systemd-resolved"] and
  .swap == true and
  .timezone == "America/Toronto"
' "$CONFIG" >/dev/null

for forbidden in disk_config disk_encryption users root_enc_password encryption_password password custom_commands; do
  if jq -e --arg key "$forbidden" 'has($key)' "$CONFIG" >/dev/null; then
    fail "forbidden key $forbidden found in $CONFIG"
  fi
done

if grep -Eiq '(/dev/(sd|nvme|vd)|UUID=|PARTUUID=|PRIVATE KEY|ssh-|password)' "$CONFIG"; then
  fail "sensitive data found in $CONFIG"
fi

for ignored in \
  "/Linux/install/archinstall/user_credentials.json" \
  "/Linux/install/archinstall/user_disk_layouts.json" \
  "/Linux/install/archinstall/*.local.json"
do
  grep -Fqx "$ignored" "$ROOT/.gitignore"
done

git -C "$ROOT" check-ignore -q Linux/install/archinstall/user_credentials.json
git -C "$ROOT" check-ignore -q Linux/install/archinstall/user_disk_layouts.json
git -C "$ROOT" check-ignore -q Linux/install/archinstall/example.local.json
