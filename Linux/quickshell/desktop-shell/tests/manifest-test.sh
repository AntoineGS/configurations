#!/usr/bin/env bash
set -Eeuo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../../.." && pwd)"
SHELL_ROOT="$ROOT/Linux/quickshell/desktop-shell"
MANIFEST_ROOT="${DESKTOP_SHELL_MANIFEST_ROOT:-$SHELL_ROOT}"

command -v node >/dev/null 2>&1 || {
  printf 'manifest-test: node is required\n' >&2
  exit 1
}

node - "$MANIFEST_ROOT" <<'NODE'
const assert = require("node:assert/strict")
const fs = require("node:fs")
const path = require("node:path")

const root = path.resolve(process.argv[2])
const manifestFiles = []

function visit(directory) {
  for (const entry of fs.readdirSync(directory, { withFileTypes: true })) {
    const entryPath = path.join(directory, entry.name)
    if (entry.isDirectory()) {
      visit(entryPath)
      continue
    }
    if (entry.isFile() && (entry.name === "manifest.json" || entry.name.endsWith(".manifest.json"))) {
      manifestFiles.push(entryPath)
    }
  }
}

if (!fs.existsSync(root)) {
  console.error(`manifest-test: manifest root does not exist: ${root}`)
  process.exit(1)
}
visit(root)

if (manifestFiles.length === 0) {
  console.log(`manifest-test: SKIP - no plugin manifests found under ${root}`)
  process.exit(0)
}

const idPattern = /^desktop\.[a-z0-9-]+$/
const failures = []

function isSafeEntryPoint(value) {
  if (typeof value !== "string" || value.length === 0) return false
  if (/^(?:[\\/]|[A-Za-z]:[\\/])/.test(value)) return false
  return !value.includes("..")
}

for (const file of manifestFiles.sort()) {
  let manifest
  try {
    manifest = JSON.parse(fs.readFileSync(file, "utf8"))
  } catch (error) {
    failures.push(`${file}: invalid JSON: ${error.message}`)
    continue
  }
  if (manifest === null || typeof manifest !== "object" || Array.isArray(manifest)) {
    failures.push(`${file}: manifest must be a non-null JSON object`)
    continue
  }
  if (manifest.schemaVersion !== 1) {
    failures.push(`${file}: schemaVersion must be 1`)
  }
  if (typeof manifest.id !== "string" || !idPattern.test(manifest.id)) {
    failures.push(`${file}: id must match ^desktop\\.[a-z0-9-]+$`)
  }
  if (!manifest.entryPoints || typeof manifest.entryPoints !== "object" || Array.isArray(manifest.entryPoints)) {
    failures.push(`${file}: entryPoints must be an object`)
    continue
  }
  for (const [kind, entryPoint] of Object.entries(manifest.entryPoints)) {
    if (!isSafeEntryPoint(entryPoint)) {
      failures.push(`${file}: unsafe entryPoints.${kind}: ${JSON.stringify(entryPoint)}`)
    }
  }
}

assert.equal(failures.length, 0, failures.join("\n"))
console.log(`manifest-test: validated ${manifestFiles.length} plugin manifest(s)`)
NODE
