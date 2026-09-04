import argparse
import json
import os
import stat
import sys
import tempfile
from pathlib import Path


VALID_VARIANTS = {"none", "low", "medium", "high", "xhigh", "max"}


class RoutingError(Exception):
  pass


def _load_routing(routing_path: Path) -> dict[str, dict[str, str]]:
  try:
    routing = json.loads(routing_path.read_text(encoding="utf-8"))
  except (OSError, UnicodeError, json.JSONDecodeError) as error:
    raise RoutingError(f"invalid routing manifest: {error}") from error

  if not isinstance(routing, dict):
    raise RoutingError("invalid routing manifest: expected an object")

  for name, route in routing.items():
    if not isinstance(route, dict) or set(route) != {"model", "variant"}:
      raise RoutingError(f"invalid route for {name}: expected exactly model and variant")
    model = route["model"]
    variant = route["variant"]
    if not isinstance(model, str) or "/" not in model or "\n" in model or "\r" in model:
      raise RoutingError(f"invalid model for {name}")
    if not isinstance(variant, str) or variant not in VALID_VARIANTS:
      raise RoutingError(f"invalid variant for {name}")

  return routing


def _rewritten_content(path: Path, route: dict[str, str]) -> tuple[bytes, bytes]:
  try:
    content = path.read_bytes()
  except OSError as error:
    raise RoutingError(f"cannot read agent {path.name}: {error}") from error

  lines = content.splitlines(keepends=True)
  if not lines or lines[0].rstrip(b"\r\n") != b"---":
    raise RoutingError(f"invalid frontmatter in {path.name}: missing opening delimiter")

  closing = next((index for index, line in enumerate(lines[1:], 1) if line.rstrip(b"\r\n") == b"---"), None)
  if closing is None:
    raise RoutingError(f"invalid frontmatter in {path.name}: missing closing delimiter")

  newline = b"\r\n" if lines[0].endswith(b"\r\n") else b"\n"
  frontmatter = [line for line in lines[1:closing] if not line.startswith((b"model:", b"variant:"))]
  model = route["model"].encode("utf-8")
  variant = route["variant"].encode("utf-8")
  routed = [b"model: " + model + newline, b"variant: " + variant + newline]
  return content, b"".join([lines[0], *frontmatter, *routed, *lines[closing:]])


def _cleanup_staged(staged: list[tuple[Path, Path]]) -> OSError | None:
  cleanup_error = None
  for _, temporary in staged:
    try:
      temporary.unlink(missing_ok=True)
    except OSError as error:
      if cleanup_error is None:
        cleanup_error = error
  return cleanup_error


def _apply_routing(agents_dir: Path, routing_path: Path) -> int:
  routing = _load_routing(routing_path)
  if not agents_dir.is_dir():
    raise RoutingError(f"invalid agent inventory: {agents_dir} is not a directory")
  try:
    agent_paths = sorted(agents_dir.glob("*.md"))
  except OSError as error:
    raise RoutingError(f"invalid agent inventory: {error}") from error

  inventory = {path.stem for path in agent_paths}
  route_names = set(routing)
  if inventory != route_names:
    missing = sorted(inventory - route_names)
    unexpected = sorted(route_names - inventory)
    raise RoutingError(f"inventory mismatch: missing={missing}; unexpected={unexpected}")

  updates = []
  for path in agent_paths:
    original, rewritten = _rewritten_content(path, routing[path.stem])
    if rewritten != original:
      try:
        mode = stat.S_IMODE(path.stat().st_mode)
      except OSError as error:
        raise RoutingError(f"cannot read mode for agent {path.name}: {error}") from error
      updates.append((path, rewritten, mode))

  staged = []
  for path, content, mode in updates:
    try:
      with tempfile.NamedTemporaryFile("wb", dir=path.parent, prefix=f".{path.name}.", delete=False) as temporary:
        temporary_path = Path(temporary.name)
        staged.append((path, temporary_path))
        temporary.write(content)
        temporary.flush()
        os.fsync(temporary.fileno())
        os.chmod(temporary_path, mode)
    except OSError as error:
      cleanup_error = _cleanup_staged(staged)
      detail = f"; cleanup failed: {cleanup_error}" if cleanup_error else ""
      raise RoutingError(f"cannot stage agent {path.name}: {error}{detail}") from error

  for path, temporary in staged:
    try:
      os.replace(temporary, path)
    except OSError as error:
      cleanup_error = _cleanup_staged(staged)
      detail = f"; cleanup failed: {cleanup_error}" if cleanup_error else ""
      raise RoutingError(f"cannot replace agent {path.name}: {error}{detail}") from error
  return len(updates)


def apply_routing(agents_dir: Path, routing_path: Path) -> None:
  _apply_routing(agents_dir, routing_path)


def main() -> int:
  base = Path(__file__).parent
  parser = argparse.ArgumentParser(description="Apply model routing to OpenCode agent frontmatter.")
  parser.add_argument("--agents", type=Path, default=base / "agents")
  parser.add_argument("--routing", type=Path, default=base / "agent-routing.json")
  args = parser.parse_args()

  try:
    updated = _apply_routing(args.agents, args.routing)
  except RoutingError as error:
    print(f"error: {error}", file=sys.stderr)
    return 1

  print(f"updated {updated} agent files")
  return 0


if __name__ == "__main__":
  raise SystemExit(main())
