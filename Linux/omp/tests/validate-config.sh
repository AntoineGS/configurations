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
}

extract_tidydots_entry() {
  local target="$1"

  awk -v target="$target" '
    function flush(  i, key) {
      if (!matched) {
        return
      }
      for (i = 1; i <= count; i++) {
        print lines[i]
      }
      matches++
    }

    /^      - / {
      if (in_entry) {
        flush()
      }
      for (key in lines) {
        delete lines[key]
      }
      count = 0
      matched = 0
      in_entry = 1
    }

    in_entry {
      lines[++count] = $0
      if ($0 == target) {
        matched = 1
      }
    }

    END {
      if (in_entry) {
        flush()
      }
      if (matches != 1) {
        exit 1
      }
    }
  '
}

validate_tidydots() {
  local config="$ROOT/tidydots.yaml"
  local app_start app_end zsh_start app_block
  local package_installer_line binary_line app_name_line commands_target_line setup_start_line
  local root_entry agents_entry skills_entry commands_entry setup_entries

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

  test "$(printf '%s\n' "$app_block" | rg -Fxc '    name: oh-my-pi' || printf '0')" -eq 1
  test "$(printf '%s\n' "$app_block" | rg -Fxc "    when: '{{ eq .OS \"linux\" }}'" || printf '0')" -eq 1
  test "$(printf '%s\n' "$app_block" | rg -c '^    when:' || printf '0')" -eq 1
  if printf '%s\n' "$app_block" | rg -ni 'windows:|opencode'; then
    return 1
  fi

  test "$(printf '%s\n' "$app_block" | rg -Fxc '      managers:' || printf '0')" -eq 1
  test "$(printf '%s\n' "$app_block" | rg -Fxc '        installer:' || printf '0')" -eq 1
  test "$(printf '%s\n' "$app_block" | rg -Fxc '            linux: curl -fsSL https://omp.sh/install | sh' || printf '0')" -eq 1
  test "$(printf '%s\n' "$app_block" | rg -Fxc '          binary: omp' || printf '0')" -eq 1
  package_installer_line="$(printf '%s\n' "$app_block" | awk '$0 == "            linux: curl -fsSL https://omp.sh/install | sh" { print NR; exit }')"
  binary_line="$(printf '%s\n' "$app_block" | awk '$0 == "          binary: omp" { print NR; exit }')"
  app_name_line="$(printf '%s\n' "$app_block" | awk '$0 == "    name: oh-my-pi" { print NR; exit }')"
  test "$package_installer_line" -lt "$app_name_line"
  test "$binary_line" -lt "$app_name_line"

  test "$(printf '%s\n' "$app_block" | rg -Fxc '    entries:' || printf '0')" -eq 1
  test "$(printf '%s\n' "$app_block" | rg -c '^      - ' || printf '0')" -eq 7

  root_entry="$(printf '%s\n' "$app_block" | extract_tidydots_entry '          linux: ~/.omp/agent')"
  cmp <(printf '%s\n' "$root_entry") <(printf '%s\n' \
    '      - targets:' \
    '          linux: ~/.omp/agent' \
    '        name: config' \
    '        backup: ./Linux/omp/agent' \
    '        files:' \
    '          - config.yml' \
    '          - AGENTS.md' \
    '          - lsp-first.md' \
    '          - worktree-preferences.md' \
    '          - commit-exclusions.md')

  agents_entry="$(printf '%s\n' "$app_block" | extract_tidydots_entry '          linux: ~/.omp/agent/agents')"
  cmp <(printf '%s\n' "$agents_entry") <(printf '%s\n' \
    '      - targets:' \
    '          linux: ~/.omp/agent/agents' \
    '        name: agents' \
    '        backup: ./Linux/omp/agent/agents')

  skills_entry="$(printf '%s\n' "$app_block" | extract_tidydots_entry '          linux: ~/.omp/agent/skills')"
  cmp <(printf '%s\n' "$skills_entry") <(printf '%s\n' \
    '      - targets:' \
    '          linux: ~/.omp/agent/skills' \
    '        name: skills' \
    '        backup: ./Linux/omp/agent/skills')

  commands_entry="$(printf '%s\n' "$app_block" | extract_tidydots_entry '          linux: ~/.omp/agent/commands')"
  cmp <(printf '%s\n' "$commands_entry") <(printf '%s\n' \
    '      - targets:' \
    '          linux: ~/.omp/agent/commands' \
    '        name: commands' \
    '        backup: ./Linux/omp/agent/commands')

  commands_target_line="$(printf '%s\n' "$app_block" | awk '$0 == "          linux: ~/.omp/agent/commands" { print NR; exit }')"
  setup_start_line="$(printf '%s\n' "$app_block" | awk '$0 == "      - check:" { print NR; exit }')"
  test "$setup_start_line" -gt "$commands_target_line"

  setup_entries="$(printf '%s\n' "$app_block" | awk '
    /^      - check:$/ { in_setup = 1 }
    in_setup { print }
  ')"
  cmp <(printf '%s\n' "$setup_entries") <(printf '%s\n' \
    '      - check:' \
    '          linux: >-' \
    '            test -f "$HOME/.omp/plugins/node_modules/superpowers/package.json" &&' \
    "            jq -e '.plugins.superpowers.enabled == true'" \
    '            "$HOME/.omp/plugins/omp-plugins.lock.json" >/dev/null' \
    '        run:' \
    '          linux: omp plugin install github:obra/superpowers' \
    '        name: superpowers' \
    '      - check:' \
    "          linux: \"herdr integration status | grep -q '^omp: current '\"" \
    '        run:' \
    '          linux: herdr integration install omp' \
    '        name: herdr-integration' \
    '      - check:' \
    '          linux: test -s ~/.local/share/zsh/completions/_omp' \
    '        run:' \
    '          linux: mkdir -p ~/.local/share/zsh/completions && omp completions zsh > ~/.local/share/zsh/completions/_omp' \
    '        name: zsh-completion')

  if printf '%s\n' "$app_block" | rg -n 'tidydots[[:space:]]+install[[:space:]]+(herdr|oh-my-pi)|herdr[[:space:]]+install([[:space:]]|$)'; then
    return 1
  fi

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
