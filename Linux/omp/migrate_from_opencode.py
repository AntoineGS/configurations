import argparse
import re
import shutil
from pathlib import Path


COMPONENTS = ("agents", "skills", "commands")

AGENT_ALIASES = {
  "general-purpose": "task",
  "comprehensive-review-architect-review": "comprehensive-review__architect-review",
  "comprehensive-review-code-reviewer": "comprehensive-review__code-reviewer",
  "comprehensive-review-security-auditor": "comprehensive-review__security-auditor",
  "debugging-toolkit-debugger": "debugging-toolkit__debugger",
  "framework-migration-architect-review": "framework-migration__architect-review",
  "framework-migration-legacy-modernizer": "framework-migration__legacy-modernizer",
  "full-stack-orchestration-deployment-engineer": "full-stack-orchestration__deployment-engineer",
  "full-stack-orchestration-performance-engineer": "full-stack-orchestration__performance-engineer",
  "full-stack-orchestration-security-auditor": "full-stack-orchestration__security-auditor",
  "full-stack-orchestration-test-automator": "full-stack-orchestration__test-automator",
  "security-scanning-security-auditor": "security-scanning__security-auditor",
  "tdd-workflows-code-reviewer": "tdd-workflows__code-reviewer",
  "tdd-workflows-tdd-orchestrator": "tdd-workflows__tdd-orchestrator",
  "threat-modeling-expert": "security-scanning__threat-modeling-expert",
  "suite-reviewer": "suite__reviewer",
}

TEXT_REPLACEMENTS = {
  "AskUserQuestion tool": "`ask` tool",
  "EnterPlanMode": "plan mode",
  "Task tool": "`task` tool",
  "subagent_type": "agent",
  "general-purpose": "task",
  "/ui-design:design-system-setup": "/ui-design__design-system-setup",
  "/ui-design:create-component": "/ui-design__create-component",
  "/ui-design:design-review": "/ui-design__design-review",
  "/ui-design:accessibility-audit": "/ui-design__accessibility-audit",
}

SEQUENTIAL_TASK_LIFECYCLE = (
  "After this dispatch, use the `hub` tool with `op: \"wait\"` and the returned job ID(s) "
  "(or omit `ids` to wait on all jobs you own) until every spawned job has delivered its final result. "
  "Associate each delivered result with this task before saving artifacts or advancing state."
)

PARALLEL_TASK_LIFECYCLE = (
  "After dispatching this parallel group, use the `hub` tool with `op: \"wait\"` and the returned job IDs "
  "(or omit `ids` to wait on all jobs you own) until every job in the group has delivered its final result. "
  "Associate each delivered result with its task before consolidating the group or advancing state."
)


def parse_frontmatter(text: str) -> tuple[list[str], str]:
  lines = text.splitlines()
  preserved_lines = text.splitlines(keepends=True)
  if not lines or lines[0] != "---":
    raise ValueError("expected frontmatter opening delimiter")

  try:
    closing = lines.index("---", 1)
  except ValueError as error:
    raise ValueError("expected frontmatter closing delimiter") from error

  return lines[1:closing], "".join(preserved_lines[closing + 1 :])


def render_frontmatter(frontmatter: list[str], body: str) -> str:
  return "---\n" + "\n".join(frontmatter) + "\n---\n\n" + body.lstrip()


def migrate_agent(text: str) -> str:
  frontmatter, body = parse_frontmatter(text)
  kept = [line for line in frontmatter if line.startswith(("name:", "description:"))]
  return render_frontmatter(kept, body)


def _render_task_dispatch(agent: str, description: str, prompt_lines: list[str]) -> list[str]:
  punctuation = "" if description.endswith((".", "!", "?")) else "."
  rendered = [
    "Task:",
    "  context: |",
    f"    This batch handles the workflow assignment: {description}{punctuation}",
    "    Use the current workspace and return the complete final result to the parent.",
    "  tasks:",
    f'    - agent: "{agent}"',
    "      task: |",
  ]
  for line in prompt_lines:
    rendered.append(f"        {line}" if line else "")
  return rendered


def _is_parallel_boundary(line: str) -> bool:
  return line.startswith(("###", "**7b", "**7c", "After both complete", "After all three complete"))


def _migrate_task_dispatches(body: str) -> str:
  lines = body.splitlines()
  migrated: list[str] = []
  index = 0

  while index < len(lines):
    if lines[index] != "Task:" or index + 3 >= len(lines):
      migrated.append(lines[index])
      index += 1
      continue

    agent_match = re.fullmatch(r'  (?:subagent_type|agent): "([^"]+)"', lines[index + 1])
    description_match = re.fullmatch(r'  description: "([^"]+)"', lines[index + 2])
    if not agent_match or not description_match or lines[index + 3] != "  prompt: |":
      migrated.append(lines[index])
      index += 1
      continue

    prompt_start = index + 4
    prompt_end = prompt_start
    while prompt_end < len(lines) and lines[prompt_end] != "```":
      if lines[prompt_end] and not lines[prompt_end].startswith("    "):
        raise ValueError("expected an indented task prompt")
      prompt_end += 1
    if prompt_end == len(lines):
      raise ValueError("expected a task dispatch closing fence")

    prompt_lines = [line[4:] if line else "" for line in lines[prompt_start:prompt_end]]
    migrated.extend(_render_task_dispatch(agent_match.group(1), description_match.group(1), prompt_lines))
    migrated.append(lines[prompt_end])

    following = next((line.strip() for line in lines[prompt_end + 1 :] if line.strip()), "")
    if not _is_parallel_boundary(following):
      migrated.extend(["", SEQUENTIAL_TASK_LIFECYCLE])
    index = prompt_end + 1

  migrated_body = "\n".join(migrated)
  if body.endswith("\n") and not migrated_body.endswith("\n"):
    migrated_body += "\n"
  return migrated_body


def migrate_command(text: str) -> str:
  frontmatter, body = parse_frontmatter(text)
  description = next(line for line in frontmatter if line.startswith("description:"))
  argument_hint = next(
    (line.partition(":")[2].strip() for line in frontmatter if line.startswith("argument-hint:")),
    None,
  )
  body = _migrate_task_dispatches(body)
  body = re.sub(r"subagent_type(?P<separator>\s*[:=]\s*)", r"agent\g<separator>", body)
  body = body.replace(
    "After both complete, consolidate into ",
    f"{PARALLEL_TASK_LIFECYCLE}\n\nThen consolidate into ",
  )
  body = body.replace(
    "After all three complete, consolidate results into ",
    f"{PARALLEL_TASK_LIFECYCLE}\n\nThen consolidate results into ",
  )
  for old, new in AGENT_ALIASES.items():
    body = body.replace(f'"{old}"', f'"{new}"')
  for old, new in TEXT_REPLACEMENTS.items():
    body = body.replace(old, new)
  if argument_hint:
    body = f"**Arguments:** `{argument_hint}`\n\n{body.lstrip()}"
  return render_frontmatter([description], body)


def _copy_skill_tree(source: Path, destination: Path) -> None:
  destination.mkdir(parents=True)
  for path in sorted(source.rglob("*")):
    target = destination / path.relative_to(source)
    if path.is_dir():
      target.mkdir()
    else:
      shutil.copy2(path, target)


def _remove_destination(path: Path) -> None:
  if path.is_dir() and not path.is_symlink():
    shutil.rmtree(path)
  elif path.exists() or path.is_symlink():
    path.unlink()


def migrate_component(source_root: Path, destination_root: Path, component: str) -> None:
  if component not in COMPONENTS:
    raise ValueError(f"unsupported component: {component}")

  source = source_root / component
  destination = destination_root / component
  _remove_destination(destination)

  if component == "skills":
    _copy_skill_tree(source, destination)
    return

  destination.mkdir(parents=True)
  for source_file in sorted(source.glob("*.md")):
    if component == "commands" and source_file.name == "context.md":
      continue
    text = source_file.read_text(encoding="utf-8")
    if component == "agents":
      output = migrate_agent(text)
    else:
      output = migrate_command(text)
    (destination / source_file.name).write_text(output, encoding="utf-8")


def main() -> None:
  parser = argparse.ArgumentParser(description="Migrate OpenCode capabilities to OMP format")
  parser.add_argument("--component", choices=(*COMPONENTS, "all"), required=True)
  args = parser.parse_args()

  script_path = Path(__file__).resolve()
  repository_root = script_path.parents[2]
  source_root = repository_root / "Linux" / "opencode"
  destination_root = script_path.parent / "agent"

  components = COMPONENTS if args.component == "all" else (args.component,)
  for component in components:
    migrate_component(source_root, destination_root, component)


if __name__ == "__main__":
  main()
