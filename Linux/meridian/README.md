# Meridian

Standalone Claude Max proxy on `antoinews-linux`, installed from the AUR with
`yay`. OpenCode loads Meridian's bundled V2 plugin directly from
`/usr/lib/meridian/dist/meridian-v2`; updating the `meridian` package updates both
the proxy and its OpenCode integration.

The tidydots application installs `meridian`, `claude-code`, and `npm`, deploys
the prompt-scrubber manifest and systemd user service, installs the scrubber,
and enables the service with user lingering. Claude authentication is local:
run `claude auth login` on a new machine before starting the service.

The existing `opencode-with-claude.conf` filename is retained for the upstream
idle setting so previously deployed environment.d symlinks remain valid. The
standalone service reads it explicitly and uses `/usr/bin/claude`.

## First migration from opencode-with-claude

Preview from the repository root:

```sh
tidydots --dir "$PWD" install meridian -n
tidydots --dir "$PWD" restore opencode config -n
tidydots --dir "$PWD" restore meridian -n
```

After reviewing the previews, finish active OpenCode work and run the following
from a separate terminal. Stopping OpenCode releases the embedded proxy's port
3456 before the standalone service starts.

```sh
tidydots --dir "$PWD" install meridian
opencode service stop
tidydots --dir "$PWD" restore opencode config
tidydots --dir "$PWD" restore meridian
opencode service start
```

The OpenCode template selects the bundled Meridian plugin on `antoinews-linux`.
The Windows host retains its existing wrapper configuration.

## Updates and diagnostics

Update Meridian through normal yay upgrades, then restart the service when
active requests have finished. Restart OpenCode as well to load any updated
integration code:

```sh
yay -S meridian
systemctl --user restart meridian.service
opencode service restart
```

The scrubber is a separate npm package, pinned in the `opencode-scrub` setup
entry. To update it, change the version in both its check and install command,
preview `tidydots restore meridian -n`, then restore after reviewing the result.

```sh
systemctl --user status meridian.service
journalctl --user -u meridian.service -n 100
curl -fsS http://127.0.0.1:3456/health
```

Dashboard: <http://127.0.0.1:3456/telemetry>.
