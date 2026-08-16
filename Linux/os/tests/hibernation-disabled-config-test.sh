#!/bin/bash

set -euo pipefail

repo_root=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../../.." && pwd)
limine="$repo_root/Linux/limine/limine"
logind="$repo_root/Linux/systemd/logind.conf.d/screen-only-on-lid.conf"
sleep_conf="$repo_root/Linux/systemd/sleep.conf.d/no-hibernate.conf"
mkinitcpio="$repo_root/Linux/mkinitcpio/omarchy_hooks.conf"
hypr_input="$repo_root/Linux/hypr/input.lua"
packages="$repo_root/Linux/pacman/pkglist-pacman-omarchbook.txt"
tidydots="$repo_root/tidydots.yaml"

fail() {
  printf 'FAIL: %s\n' "$1" >&2
  exit 1
}

if grep -Eq 'resume=|resume_offset=' "$limine"; then
  fail "Limine still configures hibernation resume parameters"
fi

[[ ! -e $repo_root/Linux/systemd/logind.conf.d/hibernate-on-lid.conf ]] ||
  fail "obsolete hibernate-on-lid drop-in still exists"

grep -Fxq 'HandleLidSwitch=ignore' "$logind" || fail "battery lid action is not ignored"
grep -Fxq 'HandleLidSwitchExternalPower=ignore' "$logind" || fail "AC lid action is not ignored"

grep -Fxq 'AllowHibernation=no' "$sleep_conf" || fail "hibernation is not disabled"
grep -Fxq 'AllowSuspendThenHibernate=no' "$sleep_conf" || fail "suspend-then-hibernate is not disabled"
grep -Fxq 'AllowHybridSleep=no' "$sleep_conf" || fail "hybrid sleep is not disabled"
grep -Fxq 'AllowSuspend=yes' "$sleep_conf" || fail "normal suspend is not explicitly retained"

grep -Eq '^HOOKS=\(.*\)$' "$mkinitcpio" || fail "mkinitcpio hooks are not configured"
if grep -Eq '(^|[[:space:]])resume([[:space:]]|$)' "$mkinitcpio"; then
  fail "mkinitcpio still includes the resume hook"
fi

expected_lid_block=$(cat <<'EOF'
hl.bind("switch:on:Lid Switch", function()
    hl.config({ misc = { key_press_enables_dpms = false, mouse_move_enables_dpms = false } })
    hl.dispatch(hl.dsp.dpms({ action = "off", monitor = "eDP-1" }))
end, { locked = true })
hl.bind("switch:off:Lid Switch", function()
    hl.config({ misc = { key_press_enables_dpms = true, mouse_move_enables_dpms = true } })
    hl.dispatch(hl.dsp.dpms({ action = "on", monitor = "eDP-1" }))
end, { locked = true })
EOF
)
hypr_contents=$(<"$hypr_input")
[[ $hypr_contents == *"$expected_lid_block"* ]] || fail "lid bindings do not keep eDP-1 off while closed"

grep -Fxq 'zram-generator' "$packages" || fail "zram-generator is not retained in the host package list"

grep -Fq 'description: Keep running and turn off the internal display on lid close' "$tidydots" ||
  fail "tidydots logind description was not updated"
grep -Fq -- '- screen-only-on-lid.conf' "$tidydots" || fail "tidydots does not deploy the logind drop-in"
grep -Fq -- '- no-hibernate.conf' "$tidydots" || fail "tidydots does not deploy the systemd sleep drop-in"
grep -Fq -- '- omarchy_hooks.conf' "$tidydots" || fail "tidydots does not deploy the mkinitcpio hooks"
grep -Fq 'linux: rm -f /etc/systemd/logind.conf.d/hibernate-on-lid.conf' "$tidydots" ||
  fail "tidydots does not remove the obsolete lid drop-in"
if grep -Fq 'org.freedesktop.login1.Manager HandleLidSwitch' "$tidydots"; then
  fail "tidydots relies on the stale logind D-Bus lid property"
fi

expected_limine_rebuild=$(cat <<'EOF'
      - targets:
          linux: /etc/default/
        name: limine
        backup: ./Linux/limine/
        files:
          - limine
        sudo: true
      - check:
          linux: "test -r /boot/EFI/Linux/omarchy_linux.efi && test -r /boot/limine.conf && lsinitcpio -a /boot/EFI/Linux/omarchy_linux.efi >/dev/null && ! lsinitcpio -a /boot/EFI/Linux/omarchy_linux.efi | grep -qw resume && ! grep -Eq '^  cmdline:.*(resume=|resume_offset=)' /boot/limine.conf"
        run:
          linux: limine-update
        name: rebuild-boot-config
        sudo: true
EOF
)
tidydots_contents=$(<"$tidydots")
[[ $tidydots_contents == *"$expected_limine_rebuild"* ]] ||
  fail "tidydots does not rebuild Limine after deploying its source configuration"

printf 'PASS: hibernation-disabled configuration\n'
