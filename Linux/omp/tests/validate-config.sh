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
    awk '
      NR == 1 && $0 == "---" { in_frontmatter = 1; next }
      in_frontmatter && $0 == "---" { closed = 1; in_frontmatter = 0; next }
      in_frontmatter && /^name:/ { name++ }
      in_frontmatter && /^description:/ { description++ }
      END { exit !(closed && name == 1 && description == 1) }
    ' "$skill"
  done < <(rg --files "$AGENT_DIR/skills" -g 'SKILL.md' | sort)
}

validate_commands() {
  test "$(rg --files "$AGENT_DIR/commands" -g '*.md' | wc -l)" -eq 36
  test ! -e "$AGENT_DIR/commands/context.md"
  ! rg -n '^(subtask|argument-hint):|subagent_type|AskUserQuestion|EnterPlanMode|/ui-design:' "$AGENT_DIR/commands"

  local raw_numeric_dollars
  raw_numeric_dollars="$(rg -n '\$[0-9]+' "$AGENT_DIR/commands" || true)"
  if [[ -n "$raw_numeric_dollars" ]]; then
    printf 'unclassified raw numeric dollar tokens in generated commands:\n%s\n' "$raw_numeric_dollars" >&2
    return 1
  fi
}

validate_tidydots() {
  local config="$ROOT/tidydots.yaml"
  local app_count app_start app_end zsh_start app_block
  local -a expected_omp_application=(
    '  - package:'
    '      managers:'
    '        installer:'
    '          command:'
    '            linux: curl -fsSL https://omp.sh/install | sh -s -- --binary'
    '          binary: omp'
    '    name: oh-my-pi'
    '    description: Batteries-included Pi fork with native LSP, subagents, and Agent Hub'
    '    when: '\''{{ eq .OS "linux" }}'\'''
    '    entries:'
    '      - targets:'
    '          linux: ~/.omp/agent'
    '        name: config'
    '        backup: ./Linux/omp/agent'
    '        files:'
    '          - config.yml'
    '          - AGENTS.md'
    '          - lsp-first.md'
    '          - worktree-preferences.md'
    '          - commit-exclusions.md'
    '      - targets:'
    '          linux: ~/.omp/agent/agents'
    '        name: agents'
    '        backup: ./Linux/omp/agent/agents'
    '      - targets:'
    '          linux: ~/.omp/agent/skills'
    '        name: skills'
    '        backup: ./Linux/omp/agent/skills'
    '      - targets:'
    '          linux: ~/.omp/agent/commands'
    '        name: commands'
    '        backup: ./Linux/omp/agent/commands'
    '      - check:'
    '          linux: >-'
    '            omp plugin list --json | awk '\''BEGIN { in_npm = 0; in_entry = 0; target = 0; enabled = 0; found = 0 } /^  "npm": \[$/ { in_npm = 1; next } in_npm && /^  "marketplace":/ { in_npm = 0; next } in_npm && /^    \{$/ { in_entry = 1; target = 0; enabled = 0; next } in_npm && in_entry && /^      "name": "superpowers",?$/ { target = 1; next } in_npm && in_entry && /^      "enabled": true,?$/ { enabled = 1; next } in_npm && in_entry && /^      "enabled": false,?$/ { enabled = 0; next } in_npm && in_entry && /^    \},?$/ { if (target && enabled) found = 1; in_entry = 0 } END { exit !found }'\'''
    '        run:'
    '          linux: omp plugin install github:obra/superpowers'
    '        name: superpowers'
    '      - check:'
    "          linux: \"herdr integration status | grep -q '^omp: current '\""
    '        run:'
    '          linux: herdr integration install omp'
    '        name: herdr-integration'
    '      - check:'
    '          linux: >-'
    '            omp plugin list --json | awk '\''BEGIN { in_npm = 0; in_entry = 0; target = 0; enabled = 0; found = 0 } /^  "npm": \[$/ { in_npm = 1; next } in_npm && /^  "marketplace":/ { in_npm = 0; next } in_npm && /^    \{$/ { in_entry = 1; target = 0; enabled = 0; next } in_npm && in_entry && /^      "name": "@andrewjacop\/pi-herdr",?$/ { target = 1; next } in_npm && in_entry && /^      "enabled": true,?$/ { enabled = 1; next } in_npm && in_entry && /^      "enabled": false,?$/ { enabled = 0; next } in_npm && in_entry && /^    \},?$/ { if (target && enabled) found = 1; in_entry = 0 } END { exit !found }'\'''
    '        run:'
    '          linux: omp plugin install @andrewjacop/pi-herdr'
    '        name: pi-herdr'
    '      - check:'
    '          linux: test -s ~/.local/share/zsh/completions/_omp'
    '        run:'
    '          linux: mkdir -p ~/.local/share/zsh/completions && omp completions zsh > ~/.local/share/zsh/completions/_omp'
    '        name: zsh-completion'
  )

  app_count="$(awk '$0 == "  - name: oh-my-pi" || $0 == "    name: oh-my-pi" { count++ } END { print count + 0 }' "$config")"
  test "$app_count" -eq 1

  app_start="$(awk '
    /^  - (package:|name:)/ { candidate = NR }
    $0 == "    name: oh-my-pi" { print candidate; exit }
  ' "$config")"
  test -n "$app_start"

  zsh_start="$(awk '
    /^  - (package:|name:)/ { candidate = NR }
    $0 == "    name: zsh" { print candidate; exit }
  ' "$config")"
  test -n "$zsh_start"
  test "$app_start" -gt "$zsh_start"

  app_end="$(awk -v start="$app_start" '
    NR > start && /^  - (package:|name:)/ { print NR; exit }
  ' "$config")"
  if [[ -z "$app_end" ]]; then
    app_end="$(awk 'END { print NR + 1 }' "$config")"
  fi
  app_block="$(awk -v start="$app_start" -v end="$app_end" 'NR >= start && NR < end' "$config")"
  test -n "$app_block"

  if printf '%s\n' "$app_block" | rg -ni 'windows:|opencode'; then
    return 1
  fi
  cmp <(printf '%s\n' "$app_block") <(printf '%s\n' "${expected_omp_application[@]}")

  if printf '%s\n' "$app_block" | rg -n 'tidydots[[:space:]]+install[[:space:]]+(herdr|oh-my-pi)|herdr[[:space:]]+install([[:space:]]|$)'; then
    return 1
  fi

  bash "$ROOT/Linux/omp/tests/test_superpowers_check.sh"
  bash "$ROOT/Linux/omp/tests/test_pi_herdr_check.sh"
  test "$(rg -Fxc 'Linux/zsh/completions/_omp' "$ROOT/.gitignore" || printf '0')" -eq 1
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
