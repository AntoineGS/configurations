# Snapper Review Fix Report

## Commit

`abc2949 fix(snapper): serialize bootstrap lifecycle`

## Findings Addressed

- Added the shared root-owned `/run/lock/antoinews-linux-snapper.lock` lifecycle lock to bootstrap recovery, deployment, cleanup, initial snapshot creation, and final validation.
- Added the same lock to direct `--apply` and `--create-initial-snapshots` initializer modes, with a clear non-blocking failure and an explicit internal-call bypass to avoid nested deadlock.
- Added lock ordering, contention, release-after-validation, and bootstrap-before-recovery regression coverage.
- Merged the duplicate `/etc/snapper/configs` and `/etc/conf.d` test-stub `-e` conditions so existing directories and managed legacy links are modeled distinctly.
- Preserved the prior rollback-assisted deployment, root-path integrity checks, environment isolation, cleanup wording, and deferred initial-snapshot behavior.

## Verification

- `bash Linux/install/tests/bootstrap-test.sh`: passed.
- `bash Linux/install/tests/snapper-bootstrap-test.sh`: passed.
- `bash Linux/Snapper/tests/snapper-initialize-test.sh`: passed.
- `bash Linux/Snapper/tests/btrfs-loop-fixture-test.sh`: skipped because root privileges are unavailable for disposable mounts.
- `bash Linux/install/tests/all-tests.sh`: passed on committed `abc2949`.
- Aggregate ShellCheck ran in `koalaman/shellcheck:stable` with `--network none` and passed.
- Aggregate `tidydots --dir ... list` passed.
- Aggregate `git diff --check` passed.

## Safety Boundaries

No live mounts, loop devices, tidydots mutation, or host system path writes were performed. The deployment remains rollback-assisted per-file rather than fully transactional, and Btrfs snapshot creation remains an external non-transactional operation.

## Follow-up Review Fix

- Production bootstrap now always starts with the fixed root-owned `/run/lock/antoinews-linux-snapper.lock`; caller-provided `SNAPPER_BOOTSTRAP_TEST_MODE` and `SNAPPER_BOOTSTRAP_LIFECYCLE_LOCK` cannot select another lock.
- Direct command-stub tests use the explicit hidden `--test-only-lifecycle-lock` argument and adversarially poison both legacy caller variables while asserting the caller-selected lock is never created or used.
- The shared lock remains held through deployment, cleanup, initial snapshot creation, validation, broad restore, and EXIT cleanup; release is no longer performed after initializer validation.
- Removed the duplicate unreachable `touch` handler from `Linux/install/tests/snapper-bootstrap-test.sh`.
- Local-user denial at the root-owned lock boundary remains fail-closed. Without non-interactive sudo authorization, bootstrap stops before recovery or deployment, which is an intentional availability tradeoff for lifecycle serialization and root-owned lock integrity.

## Follow-up Verification

- `bash Linux/install/tests/bootstrap-test.sh`: passed.
- `bash Linux/install/tests/snapper-bootstrap-test.sh`: passed.
- `bash Linux/install/tests/all-tests.sh`: passed.
- Aggregate ShellCheck passed in `koalaman/shellcheck:stable` with `--network none`.
- `bash -n Linux/install/bootstrap Linux/install/tests/bootstrap-test.sh Linux/install/tests/snapper-bootstrap-test.sh`: passed.
- `git diff --check`: passed.
- `Linux/Snapper/tests/btrfs-loop-fixture-test.sh`: skipped because root privileges are unavailable for disposable mounts.

No live mounts, loop devices, tidydots mutation, or host system path writes were performed for this follow-up.
