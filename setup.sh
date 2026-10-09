#!/usr/bin/env bash
# Bootstrap tidydots on Ubuntu. Run as your normal user, not through sudo.
set -Eeuo pipefail

die() {
  printf 'setup: %s\n' "$*" >&2
  exit 1
}

usage() {
  printf 'Usage: %s [--dry-run|--help]\n' "${0##*/}"
  printf 'Clone configurations and tidydots into ~/gits, ensure Go, build and initialize tidydots.\n'
}

dry_run=false
case "${1:-}" in
  --dry-run|-n) dry_run=true ;;
  --help|-h) usage; exit 0 ;;
  '') ;;
  *) usage >&2; exit 2 ;;
esac
[[ $# -le 1 ]] || { usage >&2; exit 2; }

[[ $EUID -ne 0 ]] || die 'run as your normal user; sudo is used only for apt prerequisites'
[[ -r /etc/os-release ]] || die 'cannot identify the operating system'
# shellcheck source=/dev/null
source /etc/os-release
[[ ${ID:-} == ubuntu ]] || die 'this bootstrap is for Ubuntu; use Linux/install/bootstrap on Arch'

readonly gits_dir="$HOME/gits"
readonly bin_dir="$HOME/.local/bin"
readonly configurations_dir="$gits_dir/configurations"
readonly tidydots_dir="$gits_dir/tidydots"
export PATH="$bin_dir:$PATH"

if [[ $dry_run == true ]]; then
  printf '%s\n' \
    'Ensure apt prerequisites: ca-certificates, curl, git, python3, build-essential, procps, file.' \
    "Clone https://github.com/AntoineGS/configurations.git into $configurations_dir if missing." \
    "Clone https://github.com/AntoineGS/tidydots.git into $tidydots_dir if missing." \
    'Reuse existing checkouts without pulling or resetting them.' \
    'Read the minimum Go version from tidydots/go.mod.' \
    "If Go is missing/too old, install a checksum-verified stable release under $HOME/.local/share/go." \
    "Expose the downloaded go and gofmt through $bin_dir." \
    "Build tidydots from $tidydots_dir into $bin_dir/tidydots." \
    "Run $bin_dir/tidydots init $configurations_dir." \
    'Package installation and dotfile restoration are separate tidydots commands.'
  exit 0
fi

missing_packages=()
for package in ca-certificates curl git python3 build-essential procps file; do
  if [[ $(dpkg-query -W -f='${Status}' "$package" 2>/dev/null || true) != 'install ok installed' ]]; then
    missing_packages+=("$package")
  fi
done
if (( ${#missing_packages[@]} )); then
  command -v sudo >/dev/null || die 'sudo is required to install apt prerequisites'
  sudo apt-get update
  sudo apt-get install -y -- "${missing_packages[@]}"
fi

ensure_checkout() {
  local name="$1" target="$gits_dir/$1" origin
  if [[ -e $target || -L $target ]]; then
    [[ $(git -C "$target" rev-parse --show-toplevel) == "$(realpath -- "$target")" ]] ||
      die "$target is not a repository root"
    origin=$(git -C "$target" remote get-url origin)
    case "$origin" in
      "https://github.com/AntoineGS/$name"|"https://github.com/AntoineGS/$name.git"|"git@github.com:AntoineGS/$name.git") ;;
      *) die "unexpected origin for $target: $origin" ;;
    esac
    printf 'Reusing %s (no pull/reset)\n' "$target"
  else
    git clone "https://github.com/AntoineGS/$name.git" "$target"
  fi
}

mkdir -p -- "$gits_dir" "$bin_dir"
ensure_checkout configurations
ensure_checkout tidydots
[[ -f $configurations_dir/tidydots.yaml ]] || die 'configurations checkout has no tidydots.yaml'

required_go=$(awk '$1 == "go" { print $2; exit }' "$tidydots_dir/go.mod")
[[ $required_go =~ ^[0-9]+\.[0-9]+(\.[0-9]+)?$ ]] || die 'cannot read the minimum Go version from go.mod'

version_at_least() {
  [[ $1 =~ ^[0-9]+\.[0-9]+(\.[0-9]+)?$ ]] &&
    [[ $(printf '%s\n' "$1" "$2" | sort -V | head -n 1) == "$2" ]]
}

temporary_dir=''
cleanup() {
  [[ -z $temporary_dir ]] || rm -rf -- "$temporary_dir"
}
trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM

installed_go=$(GOTOOLCHAIN=local go version 2>/dev/null | awk '{ sub(/^go/, "", $3); print $3 }' || true)
# Distribution builds may append experiment metadata (for example -X:nodwarf5).
installed_go=${installed_go%%-*}
if ! version_at_least "$installed_go" "$required_go"; then
  case "$(uname -m)" in
    x86_64) arch=amd64 ;;
    aarch64|arm64) arch=arm64 ;;
    *) die 'Go download supports Ubuntu amd64 and arm64' ;;
  esac
  mkdir -p -- "$HOME/.local/share/go"
  temporary_dir=$(mktemp -d "$HOME/.local/share/go/.setup-XXXXXX")
  curl --fail --silent --show-error --location --retry 3 \
    'https://go.dev/dl/?mode=json' -o "$temporary_dir/releases.json"
  release=$(python3 - "$temporary_dir/releases.json" "$arch" <<'PY'
import json
import re
import sys

with open(sys.argv[1]) as source:
    releases = json.load(source)
for release in releases:
    if not release.get("stable"):
        continue
    version = release["version"]
    if not re.fullmatch(r"go\d+\.\d+\.\d+", version):
        continue
    filename = f"{version}.linux-{sys.argv[2]}.tar.gz"
    for archive in release["files"]:
        if archive["filename"] == filename and re.fullmatch(r"[0-9a-f]{64}", archive["sha256"]):
            print(version, filename, archive["sha256"])
            sys.exit(0)
sys.exit("No stable Go archive found for this architecture")
PY
  )
  read -r version archive checksum <<< "$release"
  version_at_least "${version#go}" "$required_go" || die "latest stable Go is older than $required_go"
  go_dir="$HOME/.local/share/go/$version"
  [[ ! -e $go_dir && ! -L $go_dir ]] || die "existing Go directory is not active: $go_dir; inspect it before retrying"
  curl --fail --silent --show-error --location --retry 3 \
    "https://go.dev/dl/$archive" -o "$temporary_dir/$archive"
  (cd -- "$temporary_dir" && printf '%s  %s\n' "$checksum" "$archive" | sha256sum --check -)
  tar -xzf "$temporary_dir/$archive" -C "$temporary_dir"
  mv -- "$temporary_dir/go" "$go_dir"
  ln -sfnT -- "$go_dir/bin/go" "$bin_dir/go"
  ln -sfnT -- "$go_dir/bin/gofmt" "$bin_dir/gofmt"
  hash -r
fi

printf 'Building tidydots with %s\n' "$(go version)"
(
  cd -- "$tidydots_dir"
  GOBIN="$bin_dir" GOTOOLCHAIN=auto go install ./cmd/tidydots
)
"$bin_dir/tidydots" init "$configurations_dir"

# Print a command for the caller's shell, with variables left unexpanded.
# shellcheck disable=SC2016
printf '\nBootstrap complete. For this shell, run:\n  export PATH="$HOME/.local/bin:$PATH"\n'
printf '\nNext, preview Homebrew installation:\n  %q install homebrew -n\n' "$bin_dir/tidydots"
