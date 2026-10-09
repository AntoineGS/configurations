# Tailmix: personal + work

Managed by the `tailmix` application in `tidydots.yaml`, only on
`DESKTOP-E07VTRN` and `omarchbook`. Each machine has its own `personal` and
`work` profiles. Authentication state lives in `/var/lib/tailmix`, outside
this repository.

## Install on each machine

Run from a local terminal: switching services interrupts existing Tailscale
connections, including remote desktop or SSH sessions using that connection.

```sh
REPO_DIR="$HOME/gits/configurations"
tidydots --dir "$REPO_DIR" install tailmix -n
tidydots --dir "$REPO_DIR" restore tailmix -n
```

Review the previews, then apply:

```sh
tidydots --dir "$REPO_DIR" install tailmix
tidydots --dir "$REPO_DIR" restore tailmix
```

Installation uses the upstream v0.1.15 installer with `--no-start`; the
installer verifies the release archive checksum. Repeated installs skip the
installer when both binaries and the service unit already exist, preserving
versions installed by Tailmix's updater. Restore disables/stops
`tailscaled`, enables/starts `tailmixd`, creates both profiles, and adds the
personal MagicDNS search suffix. The service conflict prevents both daemons
from running together. Ordinary service restores skip `tailscaled` on these
two hosts.

Tailmix's upstream automatic updates are enabled by default. Inspect them
with `tailmix update status`; use `sudo tailmix update disable` to opt out.

## Log in

```sh
sudo tailmix ts -p personal up --hostname="$(hostname)-tailmix"
sudo tailmix ts -p work up --hostname="$(hostname)-tailmix"
```

The hostname repeats the non-default setting established by profile creation;
the embedded Tailscale CLI requires it when using `up`.

Complete each browser login with the matching account/tailnet. These are new
devices named `<hostname>-tailmix`, with new Tailscale IPs. Reapply the old
personal device's tags in the admin console (`tag:admin` on both hosts,
plus `tag:ssh-server` on `DESKTOP-E07VTRN`) and any required work approval.
The original client's identity remains available for rollback.

MagicDNS fully qualified names work for both connected tailnets. Personal
short names use `tail0fcf84.ts.net`. For work short names, add the work suffix
shown by `tailmix ts -p work status --json`:

```sh
sudo tailmix dns search add YOUR_WORK_TAILNET.ts.net
```

If work resources sit behind a subnet router or use corporate split DNS,
inspect the available routes and bind the required subnet/domain:

```sh
tailmix routes list --available
tailmix dns routes list --available
# Examples: replace with the actual advertised subnet and domain.
sudo tailmix routes bind -p work 10.20.0.0/16
sudo tailmix dns routes bind -p work corp.example.com
```

## Check and use

```sh
tailmix status
tailmix ts -p personal status
tailmix ts -p work status
tailmix ts -p personal ping antoinews-linux
# Check a known work peer too, and connect to real services on both networks.
getent hosts antoinews-linux.tail0fcf84.ts.net
```

Use `sudo tailmix down` / `sudo tailmix up` to pause/resume both networks.
Use `sudo tailmix profiles disable work` / `enable work` for just work.

The current desktop Tailscale widget and scripts invoking plain `tailscale`
still target the original daemon. Use the Tailmix CLI to inspect and control
these connections; the widget needs separate Tailmix integration.

## Roll back locally

```sh
sudo systemctl disable --now tailmixd.service
sudo systemctl enable --now tailscaled.service
tailscale status
```

For a permanent rollback, remove the host from the `tailmix` application
condition and from the `enable-tailscaled` exclusion in `tidydots.yaml`.
Restoring `tailmix` again otherwise switches the machine back to Tailmix.
