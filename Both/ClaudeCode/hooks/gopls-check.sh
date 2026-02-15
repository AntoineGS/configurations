#!/bin/bash

# PostToolUse hook: run gopls check on edited/written Go files.
# Input is JSON on stdin with tool_input.file_path.

INPUT=$(cat)
FILE_PATH=$(echo "$INPUT" | jq -r '.tool_input.file_path')

# Only check .go files
if [[ "$FILE_PATH" != *.go ]]; then
  exit 0
fi

OUTPUT=$(gopls check "$FILE_PATH" 2>&1)

if [[ -n "$OUTPUT" ]]; then
  echo "$OUTPUT" >&2
  exit 2
fi
