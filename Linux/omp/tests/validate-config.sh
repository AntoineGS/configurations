#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd -- "$SCRIPT_DIR/../../.." && pwd)"
AGENT_DIR="$ROOT/Linux/omp/agent"

validate_base() {
  test -f "$AGENT_DIR/config.yml"
  test -f "$AGENT_DIR/AGENTS.md"
  cmp <(
    printf '%s\n' \
      'tools:' \
      '  approvalMode: write' \
      'disabledProviders:' \
      '  - opencode'
  ) "$AGENT_DIR/config.yml"

  for policy in lsp-first.md worktree-preferences.md commit-exclusions.md; do
    cmp "$ROOT/Linux/opencode/$policy" "$AGENT_DIR/$policy"
    rg -q "^@$policy$" "$AGENT_DIR/AGENTS.md"
  done

  test ! -e "$AGENT_DIR/models.yml"
  test ! -e "$AGENT_DIR/agent.db"
}

validate_agents() {
  mapfile -t agent_files < <(rg --files "$AGENT_DIR/agents" -g '*.md' | sort)
  test "${#agent_files[@]}" -eq 46
  if rg -n '^(mode|model|variant):' "$AGENT_DIR/agents"; then
    return 1
  fi

  for agent in "${agent_files[@]}"; do
    test "$(rg --count --no-filename '^name:' "$agent" || printf '0')" -eq 1
    test "$(rg --count --no-filename '^description:' "$agent" || printf '0')" -eq 1
  done

  test "$(
    rg --no-filename '^name:' "${agent_files[@]}" |
      while IFS=: read -r _ value; do
        printf '%s\n' "${value# }"
      done |
      sort -u |
      wc -l
  )" -eq 46
}

validate_skills() {
  test "$(rg --files "$AGENT_DIR/skills" -g 'SKILL.md' | wc -l)" -eq 26

  while IFS= read -r skill; do
    test "$(rg --count --no-filename '^name:' "$skill" || printf '0')" -eq 1
    test "$(rg --count --no-filename '^description:' "$skill" || printf '0')" -eq 1
  done < <(rg --files "$AGENT_DIR/skills" -g 'SKILL.md' | sort)
}

validate_commands() {
  test "$(rg --files "$AGENT_DIR/commands" -g '*.md' | wc -l)" -eq 36
  test ! -e "$AGENT_DIR/commands/context.md"
  ! rg -n '^(subtask|argument-hint):|subagent_type|AskUserQuestion|EnterPlanMode|/ui-design:' "$AGENT_DIR/commands"
}

validate_tidydots() {
  printf 'tidydots validation not implemented until Task 6\n' >&2
  return 1
}

if (( $# != 1 )); then
  printf 'usage: %s [base|agents|skills|commands|tidydots|all]\n' "$0" >&2
  exit 2
fi

section="$1"
case "$section" in
  base)
    validate_base
    ;;
  agents)
    validate_agents
    ;;
  skills)
    validate_skills
    ;;
  commands)
    validate_commands
    ;;
  tidydots)
    validate_tidydots
    ;;
  all)
    validate_base
    validate_agents
    validate_skills
    validate_commands
    validate_tidydots
    ;;
  *)
    printf 'usage: %s [base|agents|skills|commands|tidydots|all]\n' "$0" >&2
    exit 2
    ;;
esac

printf 'OMP configuration validation passed: %s\n' "$section"
