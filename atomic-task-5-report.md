Status: implemented

Changes:
- Added explicit watcher `ready` handshake after dependency preflight.
- Reset watcher retry and error state only after readiness, not process spawn.
- Preserved global `watcher` errors during successful registry scans.
- Updated the registry fixture's readiness assertion to use the explicit ready handler.

Tests:
- `plugin-registry-contract-test.sh`: PASS
- `plugin-registry-watcher-fifo-test.sh`: PASS
- `plugin-ipc-contract-test.sh`: PASS
- `shellcheck ...`: PASS
- `git diff --check`: PASS

Concerns:
- Marketplace integration test was not present in this worktree.
- The focused Process callback-order harness was not retained because its Quickshell timing was environment-dependent; existing contract coverage is deterministic.
