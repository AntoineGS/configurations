#!/bin/sh
# Move /var/lib/docker and /var/lib/containerd onto top-level @docker/@containerd
# subvolumes so snapper's root snapshots no longer pin pruned images and build cache.
# The originals are kept as /var/lib/<name>.old until removed by hand.
set -eu

uuid=$(findmnt -no UUID /)
opts=rw,relatime,compress=zstd:3,ssd,space_cache=v2
top=$(mktemp -d)

pending=
for name in docker containerd; do
  [ "$(findmnt -no FSROOT "/var/lib/$name" || true)" = "/@$name" ] || pending="$pending $name"
done
[ -n "$pending" ] || exit 0

for name in $pending; do
  if [ -e "/var/lib/$name.old" ]; then
    echo "/var/lib/$name.old already exists, remove it before migrating" >&2
    exit 1
  fi
done

systemctl stop docker.socket docker.service containerd.service
mount -o subvolid=5 "UUID=$uuid" "$top"
trap 'umount "$top" && rmdir "$top"' EXIT

for name in $pending; do
  src=/var/lib/$name
  mkdir -p "$src"
  if [ -e "$top/@$name" ]; then
    echo "$top/@$name already exists, refusing to overwrite it" >&2
    exit 1
  fi
  btrfs subvolume create "$top/@$name"
  cp -a --reflink=always "$src/." "$top/@$name/"
  chown --reference="$src" "$top/@$name"
  chmod --reference="$src" "$top/@$name"
  mv "$src" "$src.old"
  mkdir "$src"
  chown --reference="$src.old" "$src"
  chmod --reference="$src.old" "$src"
  findmnt -s "$src" >/dev/null ||
    printf 'UUID=%s\t%s\tbtrfs     \t%s,subvol=/@%s\t0 0\n' "$uuid" "$src" "$opts" "$name" >>/etc/fstab
  systemctl daemon-reload
  mount "$src"
  echo "moved $src to @$name; delete $src.old once Docker looks right"
done

systemctl start containerd.service docker.service docker.socket
