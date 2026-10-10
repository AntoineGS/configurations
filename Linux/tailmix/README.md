# Tailmix: work proxy alongside personal Tailscale

Managed by the `tailmix` application in `tidydots.yaml`, only on
`DESKTOP-E07VTRN` and `omarchbook`.

- `tailscaled` keeps the existing personal device identity, IP, DNS, routes,
  inbound connections, and desktop widget.
- `tailmixd` runs in **SOCKS mode** on `127.0.0.1:1080`, with a `work`
  profile. This mode provides outbound TCP through the proxy and does not
  install host routes or DNS configuration. Work authentication state lives
  in `/var/lib/tailmix`, outside this repository.

The initial TUN-mode experiment registered a second personal identity.
Restore disables that Tailmix `personal` profile if present and removes its
saved DNS search suffix. The original identity stays managed by `tailscaled`.

## Install and activate on each machine

```sh
REPO_DIR="$HOME/gits/configurations"
tidydots --dir "$REPO_DIR" install tailmix -n
tidydots --dir "$REPO_DIR" restore tailmix -n
```

Review the previews, then apply:

```sh
tidydots --dir "$REPO_DIR" install tailmix
tidydots --dir "$REPO_DIR" restore tailmix
sudo tailmix ts -p work up --hostname="$(hostname)-tailmix"
```

Complete the browser login with the work account/tailnet. The hostname flag
repeats the non-default setting established when creating the work profile.

Package installation bootstraps upstream v0.1.15 with `--no-start` and installs
Ncat (Arch's `nmap` package), Git, and Go. Restore then builds and installs
**v0.1.15-socksfix.1**, a local patch for the upstream SOCKS-mode nil-TUN crash.
The source revision is pinned to `5b94b5754fe081f7dfc34e2e0b9dbf7a51029152`;
`socks-nil-tun.patch` includes the fix and its regression test. Go automatically
fetches the upstream-required 1.27.2 toolchain when needed.

Builds run as the normal user and are cached, with checksums, under
`~/.cache/tailmix/v0.1.15-socksfix.1/<architecture>`. Only the upstream binary
installer runs through sudo. Both binaries switch together and existing
profile state is retained. Automatic updates are disabled with a daemon flag
to keep the patch pinned until a tested upstream release includes the fix.

To build or preview installation separately, run from this repository:

```sh
Linux/tailmix/install-patched-tailmix --dry-run
Linux/tailmix/install-patched-tailmix --build
```

The upstream contribution checkout is `~/gits/tailmix`, branch
`fix/socks-nil-tun`. The regression test was observed failing before the fix;
the patched checkout passed upstream's `make check`.

Restore replaces the old conflict drop-in with SOCKS settings, reloads
systemd, ensures personal Tailscale is running, and starts/restarts Tailmix
when its service configuration needs applying. Its start command waits up to
30 seconds for the control API before profile setup proceeds. Both services
run together.
The existing `tailscaled.conf` filename is retained to replace already
deployed symlinks.

## SSH and databases

Use the installed `work-ssh` helper with a **fully qualified work MagicDNS
name**, as shown in `tailmix ts -p work status --json`:

```sh
work-ssh USER@HOST.WORK-TAILNET.ts.net
```

The helper uses Ncat's SOCKS5 transport with remote DNS resolution. Tailmix
SOCKS mode rejects short MagicDNS names and raw canonical `100.x` peer IPs.
Use the full work hostname so Tailmix can select the correct profile.

For database clients, configure SOCKS5 at `127.0.0.1:1080` with proxy-side DNS
if supported, or forward the database through a work SSH host. For example,
for PostgreSQL listening on that SSH host's loopback interface:

```sh
work-ssh -N -o ExitOnForwardFailure=yes \
  -L 127.0.0.1:15432:127.0.0.1:5432 USER@HOST.WORK-TAILNET.ts.net
```

Connect the database client to `127.0.0.1:15432`; replace the destination
address/port when the database lives elsewhere on the SSH host's network.

For direct proxy access to advertised work subnets or corporate split DNS,
inspect and bind the required routes with `tailmix routes list --available`,
`tailmix dns routes list --available`, and the corresponding `bind -p work`
commands. These policies apply inside the proxy, not to host networking.

## RustDesk

The Office PC is now `antoinews-linux.tail0b6859.ts.net` on the work tailnet.
The **Office PC** desktop launcher owns an on-demand SSH tunnel and opens
RustDesk at `127.0.0.1:21120`. It is available on `DESKTOP-E07VTRN` and
`omarchbook` through the `rustdesk-office` tidydots application.

With the current Hyprland configuration checked out on both the client and
Office PC, preview the client setup:

```sh
tidydots restore rustdesk-focus-handoff -n
tidydots restore rustdesk-office -n
```

After reviewing, run those restores without `-n`. The first retires the old
always-on personal-tailnet handoff listener; the second installs the wrapper
and desktop entry. The handoff script itself is part of the existing
`hyprland` configuration. Close any manual tunnel on port 21120 before using
the launcher.

The wrapper requires key-based SSH authentication for
`a.simard@multidev.local`, an unlocked SSH key, and the host key already trusted.
It connects through Tailmix directly, using a dedicated SSH process independent
of Herdr's connections. RustDesk direct IP access must be enabled on the Office
PC; its permanent RustDesk password is separate from SSH authentication.

Closing the **Office PC remote window** removes the tunnels and handoff
listener, even if RustDesk's main window or other sessions remain open.
Launching again focuses the existing Office PC window. If SSH disconnects,
the launcher cleans up and displays a notification; launch Office PC again
to reconnect. Diagnostics are in
`~/.local/state/rustdesk-office/session.log`.

### Focus-handoff return path

The launcher forwards Office PC loopback port `45973` back through SSH to a
private Unix socket on the client. At the remote desktop's left edge,
`Super+H` sends `focus-left` to that loopback port. The client handles it only
while the `127.0.0.1:21120` RustDesk window is active, moving focus to the left
monitor or, when focus cannot move there, the previous workspace.

The shared remote callback port permits **one active Office PC launcher at a
time across the desktop and laptop**. Close that window before switching
clients. SSH rejects a conflicting return forward rather than sending focus
events to the wrong client. No additional tailnet ACL port is needed.

## Verify and manage

```sh
tailscale status
tailmix status
tailmix ts -p work status
systemctl is-active tailscaled.service tailmixd.service
```

Verify an existing inbound client and the Office PC RustDesk connection,
then an actual work SSH/database connection through the proxy.
The desktop Tailscale widget controls personal connectivity; use
`sudo tailmix down` / `sudo tailmix up` to pause/resume work proxy access.

To stop the work proxy, use `sudo systemctl disable --now tailmixd.service`.
For a permanent opt-out, remove the host from the `tailmix` application
condition before restoring again.
