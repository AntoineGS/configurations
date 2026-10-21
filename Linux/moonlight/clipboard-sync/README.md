# Go clipboard helper

The protocol codec validates bounded frames before allocating payloads. The
coordinator orders updates and coalesces in-flight changes. The native Wayland
adapter binds data-control v1 and uses a display sync barrier to discard the
initial selection. Each offer's MIME types and capture FD belong to that same
offer; there is no separate, racy clipboard query.

```sh
go test -race ./...
go vet ./...
```

Tests normally use a private Unix-socket compositor fixture and in-memory
clipboard adapters. The real compositor test is explicitly opt-in and refuses
the user's normal Wayland socket. Start a separate nested Hyprland with an empty
configuration and runtime directory `/tmp/opencode/cb`, then run:

```sh
CLIPBOARD_TEST_SOCKET=/tmp/opencode/cb/wayland-1 go test -race -run TestClipboardIsolatedCompositor .
```

This test modifies only that isolated compositor's clipboard. See `../README.md`
for installation, user-facing behavior and supported formats.
