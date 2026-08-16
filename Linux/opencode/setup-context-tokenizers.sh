#!/usr/bin/env bash
set -Eeuo pipefail

usage() {
  printf 'Usage: %s --check|--apply|--help\n' "${0##*/}"
}

prefix="${OPENCODE_TOKENIZER_PREFIX:-$HOME/.config/opencode/plugins/vendor}"

check_tokenizers() {
  [[ -f "$prefix/node_modules/js-tiktoken/package.json" ]] &&
    [[ -f "$prefix/node_modules/@huggingface/transformers/package.json" ]]
}

case "${1:-}" in
  --check)
    check_tokenizers
    ;;
  --apply)
    npm install js-tiktoken@latest '@huggingface/transformers@^3.3.3' \
      --omit=dev --no-audit --loglevel=error --prefix "$prefix"
    ;;
  --help)
    usage
    ;;
  *)
    usage >&2
    exit 2
    ;;
esac
