#!/usr/bin/env bash
# Regenerate OpenCode artifacts for the enabled claude-code-workflows plugins
# and vendor them into this repo. Re-run when wshobson/agents updates.
set -euo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"        # Linux/opencode
MP="${HOME}/.claude/plugins/marketplaces/claude-code-workflows"

PLUGINS=(
  code-documentation comprehensive-review code-refactoring codebase-cleanup
  database-design database-migrations debugging-toolkit dependency-management
  deployment-strategies deployment-validation framework-migration
  full-stack-orchestration javascript-typescript performance-testing-review
  security-scanning shell-scripting systems-programming tdd-workflows
  ui-design unit-testing
)

if [[ ! -d "$MP" ]]; then
  echo "ERROR: marketplace not found at $MP (open Claude Code once to fetch it)" >&2
  exit 1
fi

echo "==> Cleaning previous OpenCode generation"
( cd "$MP" && python3 tools/generate.py --harness opencode --clean ) || true

echo "==> Generating ${#PLUGINS[@]} plugins"
for p in "${PLUGINS[@]}"; do
  echo "    - $p"
  ( cd "$MP" && python3 tools/generate.py --harness opencode --plugin "$p" )
done

echo "==> Vendoring into repo"
rm -rf "$REPO_DIR/agents" "$REPO_DIR/commands" "$REPO_DIR/skills"
cp -a "$MP/.opencode/agents"   "$REPO_DIR/agents"
cp -a "$MP/.opencode/commands" "$REPO_DIR/commands"
cp -a "$MP/.opencode/skills"   "$REPO_DIR/skills"

echo "==> Done. Agents: $(ls "$REPO_DIR/agents" | wc -l), Commands: $(ls "$REPO_DIR/commands" | wc -l), Skills: $(ls "$REPO_DIR/skills" | wc -l)"
