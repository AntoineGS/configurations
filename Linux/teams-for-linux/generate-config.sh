#!/usr/bin/env bash
# Generate config.json from template with environment variables

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TEMPLATE="${SCRIPT_DIR}/config.json.template"
OUTPUT="${SCRIPT_DIR}/config.json"

# Check if template exists
if [[ ! -f "$TEMPLATE" ]]; then
  echo "Error: Template file not found: $TEMPLATE" >&2
  exit 1
fi

# Check if required environment variables are set
if [[ -z "${TEAMS_MQTT_PASSWORD:-}" ]]; then
  echo "Error: TEAMS_MQTT_PASSWORD environment variable is not set" >&2
  echo "Please add it to your ~/.zshenv or set it before running this script" >&2
  exit 1
fi

# Generate config.json using envsubst
envsubst < "$TEMPLATE" > "$OUTPUT"

echo "✓ Generated $OUTPUT from template"
