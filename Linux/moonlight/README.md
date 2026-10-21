# Office PC streaming and clipboard

`moonlight-office` streams the office desktop using H.264, 1080p/60 FPS and
absolute mouse input. Hyprland's clean submap forwards remote Win shortcuts;
Win+Shift+Q restores local bindings. Moonlight's window rule retains that escape
even while system-key capture is enabled.

## Clipboard

Install `moonlight-clipboard` on the office host and each client. The launcher
starts a bidirectional clipboard channel and stops it when Moonlight exits.
Clipboard failures do not stop video streaming.

- New copies only: connecting/reconnecting does not send existing contents.
- UTF-8 plain text and PNG, up to 20 MiB per selection. PNG takes precedence
  when an application offers both an image and text.
- File-manager selections, rich text, other image encodings, primary selection,
  clipboard clears and history are not synchronized.
- Identical copies can be suppressed. Concurrent copies use client acceptance
  order; a newer unacknowledged local copy survives an older incoming update.
- Only one client may sync with the office host at a time. Other clients can
  still stream and will report clipboard unavailability.
- Transient failures retry with capped backoff and fresh baselines. Five
  consecutive short failed sessions stop retries; relaunch Moonlight to retry.
- The SSH channel reuses the remote bar's `~/.ssh/cm-%C` ControlMaster. Closing
  clipboard sync never deliberately terminates that shared master.

The helper reads the native Wayland data-control protocol and uses the real
`/usr/bin/wl-copy` for publishing. It bypasses Herdr clipboard redirection.
The agent resolves the office graphical environment from user systemd.

## Install

Requires Linux, a compositor supporting wlr-data-control v1 (Hyprland),
wl-clipboard, OpenSSH, and the existing working SSH host alias `antoinews-linux`.
Go 1.26+ is required only on the machine building the binary.

Preview before applying:

```sh
tidydots --dir /path/to/configurations restore moonlight-clipboard -n
tidydots --dir /path/to/configurations restore moonlight-office -n
```

After approval, restore `moonlight-clipboard` on the host first and clients next,
then restore the client launcher. A restore builds locally if Go is available.
Alternatively build once for a matching architecture:

```sh
Linux/moonlight/install-clipboard-sync --build
```

Copy the printed archive and its `.sha256` companion along with the matching
source checkout. On the destination, run:

```sh
Linux/moonlight/install-clipboard-sync --install-archive /path/to/package.tar.gz
```

Archive installation checks the checksum, source fingerprint and architecture,
then atomically replaces the user-local executable; no root privileges are used.
Never install an archive from an untrusted source: the checksum detects damage,
not publisher identity.

For diagnosis: `moonlight-clipboard client --host antoinews-linux` from the client
desktop terminal; stop it with Ctrl+C before launching Moonlight. Diagnostics
do not contain clipboard content. No clipboard payloads are written to disk.
