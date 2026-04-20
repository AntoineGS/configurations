# Zellij plugins

Plugins vendored into this repo and deployed by tidydots to
`~/.config/zellij/plugins/` (Linux) or `~/AppData/Roaming/Zellij/config/plugins/`
(Windows).

## `zellij-attention.wasm`

Upstream: https://github.com/KiryuuLight/zellij-attention
Release:  v0.3.1
sha256:   4209337ab61a731448ec733362f3ef699a905bbb5c0112a93a6d616360fd722f

Adds waiting/completed status icons to zellij tab names via the `zellij pipe`
protocol. Wired up from `Both/ClaudeCode/settings.json` hooks — see
`Both/Zellij/config.kdl` for icon configuration.

### Refresh

```bash
curl -L -o Both/Zellij/plugins/zellij-attention.wasm \
  https://github.com/KiryuuLight/zellij-attention/releases/download/<tag>/zellij-attention.wasm
sha256sum Both/Zellij/plugins/zellij-attention.wasm
```

Update the `Release` and `sha256` lines above with the new values.
