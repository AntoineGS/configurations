#!/usr/bin/env bash
set -Eeuo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
CONFIG="$ROOT/Linux/install/archinstall/user_configuration.json"

jq -e '
  .bootloader_config.bootloader == "Limine" and
  .bootloader_config.uki == false and
  .bootloader_config.removable == false and
  .hostname == "antoinews-linux" and
  .kernels == ["linux"] and
  .locale_config.kb_layout == "us" and
  .locale_config.sys_enc == "UTF-8" and
  .locale_config.sys_lang == "en_US" and
  .timezone == "America/Toronto" and
  .ntp == true and
  (.packages | index("base-devel")) and
  (.packages | index("git")) and
  (.packages | index("iwd")) and
  (.services | index("iwd")) and
  (.services | index("systemd-networkd")) and
  (.services | index("systemd-resolved"))
' "$CONFIG" >/dev/null

for forbidden in disk_config disk_encryption users root_enc_password encryption_password password custom_commands; do
  ! jq -e --arg key "$forbidden" 'has($key)' "$CONFIG" >/dev/null
done

! grep -Eiq '(/dev/(sd|nvme|vd)|UUID=|PARTUUID=|PRIVATE KEY|ssh-|password)' "$CONFIG"

git -C "$ROOT" check-ignore -q Linux/install/archinstall/user_credentials.json
git -C "$ROOT" check-ignore -q Linux/install/archinstall/user_disk_layouts.json
git -C "$ROOT" check-ignore -q Linux/install/archinstall/example.local.json
