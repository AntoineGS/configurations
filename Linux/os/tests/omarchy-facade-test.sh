#!/usr/bin/env bash
set -Eeuo pipefail

test_root=$(mktemp -d)
trap 'rm -rf -- "$test_root"' EXIT
repo_root=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../../.." && pwd -P)
facade="$repo_root/Linux/os/helpers/omarchy"
[[ -x $facade ]] || { printf 'FAIL: facade is missing or not executable\n' >&2; exit 1; }

bin="$test_root/bin"
mkdir -p -- "$bin" "$test_root/native" "$test_root/omarchy-path/bin"
cat >"$bin/desktop-shell-plugin" <<'EOF'
#!/usr/bin/env bash
set -Eeuo pipefail
printf 'plugin:%s\n' "$*"
EOF
cat >"$test_root/native/omarchy" <<'EOF'
#!/usr/bin/env bash
set -Eeuo pipefail
printf 'native:%s\n' "$*"
EOF
cat >"$test_root/omarchy-path/bin/omarchy" <<'EOF'
#!/usr/bin/env bash
set -Eeuo pipefail
printf 'omarchy-path:%s\n' "$*"
EOF
chmod +x -- "$bin/desktop-shell-plugin" "$test_root/native/omarchy" "$test_root/omarchy-path/bin/omarchy"
cp -- "$facade" "$bin/omarchy"
chmod +x -- "$bin/omarchy"
cp -- "$facade" "$test_root/omarchy-copy"
chmod +x -- "$test_root/omarchy-copy"
ln -- "$bin/omarchy" "$test_root/omarchy-hardlink"

plugin_output=$(PATH="$bin:$PATH" "$bin/omarchy" plugin list --json)
[[ $plugin_output == 'plugin:list --json' ]] || { printf 'FAIL: plugin delegation\n' >&2; exit 1; }

native_output=$(DESKTOP_SHELL_NATIVE_OMARCHY="$test_root/native/omarchy" PATH="$bin:$PATH" "$bin/omarchy" update)
[[ $native_output == 'native:update' ]] || { printf 'FAIL: override delegation\n' >&2; exit 1; }

path_output=$(OMARCHY_PATH="$test_root/omarchy-path" PATH="$bin:$PATH" "$bin/omarchy" update)
[[ $path_output == 'omarchy-path:update' ]] || { printf 'FAIL: OMARCHY_PATH delegation\n' >&2; exit 1; }

path_native="$test_root/path-native"
mkdir -- "$path_native"
cat >"$path_native/omarchy" <<'EOF'
#!/usr/bin/env bash
set -Eeuo pipefail
printf 'path-native:%s\n' "$*"
EOF
chmod +x -- "$path_native/omarchy"
path_fallback_output=$(env -u OMARCHY_PATH -u DESKTOP_SHELL_NATIVE_OMARCHY -u OMARCHY_FACADE_DEPTH PATH="$bin:$path_native:/usr/bin:/bin" "$bin/omarchy" update)
[[ $path_fallback_output == 'path-native:update' ]] || { printf 'FAIL: PATH fallback delegation\n' >&2; exit 1; }

if env -u OMARCHY_PATH -u DESKTOP_SHELL_NATIVE_OMARCHY PATH="$bin:/usr/bin:/bin" "$bin/omarchy" update >/dev/null 2>"$test_root/self.err"; then
  printf 'FAIL: self-only PATH unexpectedly delegated\n' >&2
  exit 1
fi
grep -Fq 'unsupported without a native Omarchy installation' "$test_root/self.err" || { printf 'FAIL: unsupported error\n' >&2; exit 1; }

if env -u OMARCHY_PATH DESKTOP_SHELL_NATIVE_OMARCHY="$bin/omarchy" "$bin/omarchy" update >/dev/null 2>"$test_root/recursion.err"; then
  printf 'FAIL: facade recursion unexpectedly succeeded\n' >&2
  exit 1
fi
grep -Fq 'unsupported without a native Omarchy installation' "$test_root/recursion.err" || { printf 'FAIL: recursion error\n' >&2; exit 1; }

ln -s -- "$bin/omarchy" "$test_root/facade-link"
if env -u OMARCHY_PATH DESKTOP_SHELL_NATIVE_OMARCHY="$test_root/facade-link" "$bin/omarchy" update >/dev/null 2>"$test_root/symlink-recursion.err"; then
  printf 'FAIL: symlink recursion unexpectedly succeeded\n' >&2
  exit 1
fi
grep -Fq 'unsupported without a native Omarchy installation' "$test_root/symlink-recursion.err" || { printf 'FAIL: symlink recursion error\n' >&2; exit 1; }

if env -u OMARCHY_PATH DESKTOP_SHELL_NATIVE_OMARCHY="$test_root/omarchy-copy" "$bin/omarchy" update >/dev/null 2>"$test_root/copy-recursion.err"; then
  printf 'FAIL: copied facade recursion unexpectedly succeeded\n' >&2
  exit 1
fi
grep -Fq 'unsupported without a native Omarchy installation' "$test_root/copy-recursion.err" || { printf 'FAIL: copied facade recursion error\n' >&2; exit 1; }

if env -u OMARCHY_PATH DESKTOP_SHELL_NATIVE_OMARCHY="$test_root/omarchy-hardlink" "$bin/omarchy" update >/dev/null 2>"$test_root/hardlink-recursion.err"; then
  printf 'FAIL: hard-linked facade recursion unexpectedly succeeded\n' >&2
  exit 1
fi
grep -Fq 'unsupported without a native Omarchy installation' "$test_root/hardlink-recursion.err" || { printf 'FAIL: hard-linked facade recursion error\n' >&2; exit 1; }

printf 'PASS: omarchy facade\n'
