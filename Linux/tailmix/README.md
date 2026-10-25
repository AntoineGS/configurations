# Tailmix: personal and work tailnets

Managed by the `tailmix` application in `tidydots.yaml` on `omarchbook` and
`DESKTOP-E07VTRN`.

- `tailmixd` uses **TUN mode**, providing TCP and UDP for the `personal` and
  `work` profiles through `tailmix0`.
- Regular `tailscaled` is disabled on these clients to avoid competing routes
  and DNS. Its old identity remains on disk, but is not used by Tailmix.
- Authentication state lives in `/var/lib/tailmix`, outside this repository.
- Personal short names use `tail0fcf84.ts.net`. Work connections use full names
  such as `antoinews-linux.tail0b6859.ts.net`, avoiding the old offline personal
  device with the same short name.

Tailmix assigns stable synthetic addresses per client. Resolve peer names
instead of copying `100.127.x.x` addresses between machines. Logging in creates
a new personal identity: check device approvals and identity/tag-based grants.
Retain or rename the old device while validating the migration.

## Install and activate on each client

```sh
REPO_DIR="$HOME/gits/configurations"
tidydots --dir "$REPO_DIR" install tailmix -n
tidydots --dir "$REPO_DIR" restore tailmix -n
tidydots --dir "$REPO_DIR" restore ssh-agent ssh-config -n
```

Review the previews, then run those commands without `-n`. The daemon restart
interrupts existing connections. On a fresh installation the package bootstrap
installs v0.1.15 with `--no-start`; restore installs **v0.1.18** before enabling
TUN mode. Normal Tailscale is disabled; Tailmix is enabled at boot.

Existing profiles are retained. Inspect `tailmix profiles list --all` first.
Add only missing profiles, or enable an existing disabled profile, then log in:

```sh
sudo tailmix profiles add personal --hostname="$(hostname)"
sudo tailmix profiles add work --hostname="$(hostname)-tailmix"
sudo tailmix ts -p personal login
sudo tailmix ts -p work login
```

Choose the corresponding personal/work account in each browser login. No subnet
routes or exit nodes are accepted automatically. Use `tailmix routes list
--available` and `tailmix dns routes list --available` to inspect additional
routes, then bind only those needed.

## Pinned upstream build

`install-patched-tailmix` retains its historical filename but now builds
unmodified upstream **v0.1.18**, commit
`7161022fe10aaa77165d21078602bd43e5a49acf`. This includes the Linux IPv6 route
reconciliation and SOCKS nil-TUN fixes. The old `socks-nil-tun.patch` is no longer
applied. Go fetches the required 1.27.3 toolchain when needed.

Builds run as the normal user and are cached with checksums under
`~/.cache/tailmix/v0.1.18/<architecture>`. Only the pinned upstream installer
runs through sudo. Both binaries switch together; existing profiles are kept.
Automatic updates remain disabled to keep the version pinned.

```sh
Linux/tailmix/install-patched-tailmix --dry-run
Linux/tailmix/install-patched-tailmix --build
```

The service drop-in is copied into `/etc/systemd/system` so it is available
before `/home` mounts. Its historical `tailscaled.conf` name replaces the former
SOCKS configuration. Restore removes the runtime Sunshine trial override.

## SSH and Herdr

SSH connects directly through TUN; no SOCKS proxy is needed. `work-ssh` remains
as a compatibility alias for `ssh`. Restore `ssh-agent ssh-config` to remove the
old proxy setting. Herdr's Office PC target remains
`ssh://a.simard%40multidev.local@antoinews-linux.tail0b6859.ts.net`.

```sh
ssh antoinews-linux hostname
herdr machine status antoinews-linux --json
herdr machine reconnect antoinews-linux
```

Herdr retries failed connections automatically. Personal machines still require
SSH access rules for the new personal identity.

## Moonlight

```sh
tidydots install moonlight-office -n
tidydots restore moonlight-office -n
```

After reviewing, apply without `-n`. **Office PC (Moonlight)** launches the
Desktop app at 1080p/60 FPS, 10 Mbps, in a window, with H.264 and absolute mouse
input. H.264 avoids the observed Intel HEVC encoder crash on the host. Audio
remains disabled in Sunshine. Run `moonlight-office` from a terminal for logs.

The launcher resolves the work hostname to an IPv4 synthetic address on each
client. Sunshine listens on IPv4. Pair each client separately in Moonlight;
pairing credentials are local and are not stored in this repository.

For each client's **work-profile canonical IP**, allow these ports to the
Sunshine host (`100.75.1.123`) in the work tailnet's grants and host UFW rules:

- TCP: `47984`, `47989`, `47990`, `48010`
- UDP: `47998-48000`, `48002`, `48010`

On UFW, restrict these rules to `tailscale0` and that client IP. The laptop work
IP is `100.93.35.122`; inspect `tailmix ts -p work ip -4` on the desktop before
adding its grant and firewall rules.

For Sunshine's web UI, use a localhost SSH tunnel to avoid CSRF origin rejection
of Tailmix's synthetic address:

```sh
ssh -N -L 127.0.0.1:47990:127.0.0.1:47990 antoinews-linux
```

Open `https://localhost:47990/pin`, log in, and enter Moonlight's pairing PIN.

## RustDesk

The existing **Office PC** RustDesk launcher also connects directly through
Tailmix, retaining its window-scoped SSH tunnel and focus handoff. It needs
key-based SSH as `a.simard@multidev.local` and RustDesk direct-IP access on the
host. Its permanent RustDesk password is separate from SSH authentication.

Closing the Office PC remote window removes its tunnels and handoff listener.
Launching again focuses the existing window. Diagnostics are in
`~/.local/state/rustdesk-office/session.log`.

The launcher forwards remote loopback port `45973` back to a private Unix
socket. At the remote desktop's left edge, `Super+H` moves focus left locally.
Only one Office PC RustDesk launcher may run at a time across the two clients
because they share that remote callback port. The Moonlight launcher does the
same through its own SSH connection and remote port `45974`.

## Verify and manage

```sh
tailmix status
tailmix ts -p personal status
tailmix ts -p work status
systemctl is-active tailmixd.service
```

Use `sudo tailmix down` / `sudo tailmix up` to pause/resume both profiles.
Quickshell's network widget detects Tailmix and shows each profile's status,
addresses, peers, and enable/disable control. Its main toggle pauses/resumes
Tailmix; privileged actions prompt through Polkit. Copied peer addresses use
full DNS names so Tailmix can resolve the correct synthetic address. Exit-node
changes remain available through the Tailmix CLI.

On machines without an available Tailmix daemon, the widget retains the regular
Tailscale view and controls. Regular Tailscale must stay stopped while Tailmix
owns TUN routing and DNS.
