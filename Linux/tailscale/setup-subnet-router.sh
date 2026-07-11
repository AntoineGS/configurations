#!/usr/bin/env bash
# Configure this host as a Tailscale subnet router for the standard LAN.
#
# The RustDesk relay (hbbr) and rendezvous server (hbbs) run on this box
# (192.168.1.15). Advertising 192.168.1.0/24 lets remote Tailscale clients
# reach that LAN IP, so RustDesk relayed sessions to the isolated work PC work
# from outside the network. IP forwarding is persisted via
# /etc/sysctl.d/99-tailscale.conf (deployed by tidydots) -- this script only
# applies it to the running kernel and advertises the route.
#
# Run once (re-running is safe/idempotent):
#   ~/.local/share/helpers/setup-subnet-router.sh
set -euo pipefail

LAN_ROUTE="192.168.1.0/24"

# Apply the persisted sysctl forwarding settings to the running kernel.
sudo sysctl --system

# Advertise the LAN subnet. `tailscale set` changes only this flag and leaves
# the rest of the tailscale config (login, hostname, etc.) untouched.
sudo tailscale set --advertise-routes="${LAN_ROUTE}"

cat <<EOF

Subnet route ${LAN_ROUTE} advertised from this host.

Final manual step (one time): approve the route in the Tailscale admin console
  https://login.tailscale.com/admin/machines
  -> this host -> "..." -> Edit route settings -> enable ${LAN_ROUTE}

Then, on the remote client, accept subnet routes:
  Linux:        sudo tailscale up --accept-routes
  Windows/Mac:  Tailscale tray -> "Use Tailscale subnet routes"
EOF
