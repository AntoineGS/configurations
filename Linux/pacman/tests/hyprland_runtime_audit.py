#!/usr/bin/env python3
"""Fail-closed ownership audit for active Hyprland command sources."""

from __future__ import annotations

import argparse
import re
import sys
from dataclasses import dataclass
from pathlib import Path
from typing import Iterable, Iterator, Sequence


class AuditError(RuntimeError):
    """Raised when a source command cannot be mapped to a package owner."""


@dataclass(frozen=True)
class Command:
    source: Path
    text: str
    line: int


@dataclass(frozen=True)
class PackageOwner:
    application: str
    manager: str
    package: str


@dataclass(frozen=True)
class ExecutableSpec:
    application: str
    manager: str
    package: str
    allowed_args: tuple[tuple[str, ...], ...]


def _spec(
    application: str,
    manager: str,
    package: str,
    *allowed_args: tuple[str, ...],
) -> ExecutableSpec:
    return ExecutableSpec(application, manager, package, allowed_args or ((),))


# This registry deliberately describes complete command forms, not just executable names.
# Changes to active launcher commands should require an explicit audit update.
EXECUTABLE_SPECS: dict[str, ExecutableSpec] = {
    "1password": _spec("1password", "yay", "1password-beta"),
    "brave": _spec(
        "brave",
        "yay",
        "brave-bin",
        (),
        (
            "--enable-features=UseOzonePlatform",
            "--ozone-platform=wayland",
            "--enable-wayland-ime",
        ),
    ),
    "brave-browser": _spec("brave", "yay", "brave-bin"),
    "fcitx5": _spec("fcitx5", "pacman", "fcitx5", ("--disable", "notificationitem")),
    "hypridle": _spec("hypridle", "pacman", "hypridle"),
    "hyprpm": _spec("hyprland", "pacman", "hyprland", ("reload", "-n")),
    "launch-editor": _spec("neovim", "pacman", "neovim"),
    "lazydocker": _spec("lazydocker", "pacman", "lazydocker"),
    "mako": _spec("mako", "pacman", "mako"),
    "neovim": _spec("neovim", "pacman", "neovim"),
    "obsidian": _spec(
        "obsidian",
        "pacman",
        "obsidian",
        (),
        ("-disable-gpu", "--enable-wayland-ime"),
    ),
    "polkit-gnome-authentication-agent-1": _spec(
        "polkit-gnome",
        "pacman",
        "polkit-gnome",
    ),
    "signal": _spec("signal", "pacman", "signal-desktop"),
    "signal-desktop": _spec("signal", "pacman", "signal-desktop"),
    "swaybg": _spec("swaybg", "pacman", "swaybg", ("-c", "#1e1e2e")),
    "swayosd-server": _spec("swayosd", "pacman", "swayosd"),
    "teams-for-linux": _spec("teams-for-linux", "pacman", "teams-for-linux"),
    "uwsm": _spec("uwsm", "pacman", "uwsm"),
    "uwsm-app": _spec("uwsm", "pacman", "uwsm"),
    "vicinae": _spec(
        "vicinae",
        "yay",
        "vicinae-bin",
        ("vicinae://extensions/vicinae/file/search",),
    ),
    "waybar": _spec("waybar", "pacman", "waybar"),
    "xdg-terminal-exec": _spec("xdg-terminal-exec", "yay", "xdg-terminal-exec", (), ("herdr",)),
    "yazi": _spec("yazi", "pacman", "yazi"),
}

HELPER_COMMANDS = {"launch-or-focus", "launch-tui-large"}

_EXEC_CALL = re.compile(r"\bhl(?:\.dsp)?\.exec_cmd\s*\(")
_ASSIGNMENT = re.compile(r"^[A-Za-z_][A-Za-z0-9_]*=.*$")


def _strip_yaml_scalar(value: str) -> str:
    value = value.strip()
    if len(value) >= 2 and value[0] == value[-1] and value[0] in "'\"":
        return value[1:-1]
    return value


def _application_blocks(lines: Sequence[str]) -> Iterator[tuple[int, list[str]]]:
    starts = [index for index, line in enumerate(lines) if line.startswith("  - ")]
    for position, start in enumerate(starts):
        end = starts[position + 1] if position + 1 < len(starts) else len(lines)
        yield start, list(lines[start:end])


def parse_manifest_packages(manifest: Path) -> dict[str, tuple[PackageOwner, ...]]:
    """Parse direct pacman/yay scalar declarations from tidydots.yaml."""

    lines = manifest.read_text(encoding="utf-8").splitlines()
    packages: dict[str, tuple[PackageOwner, ...]] = {}

    for line_number, block in _application_blocks(lines):
        name = next(
            (
                _strip_yaml_scalar(line.removeprefix("    name:"))
                for line in block
                if line.startswith("    name:")
            ),
            None,
        )
        if not name:
            continue

        owners_list: list[PackageOwner] = []
        for line in block:
            manager_match = re.match(r"^        (pacman|yay):\s*(\S.*)$", line)
            if manager_match is not None:
                manager, package = manager_match.groups()
                owners_list.append(PackageOwner(name, manager, _strip_yaml_scalar(package)))
        owners = tuple(owners_list)
        if name in packages:
            raise AuditError(f"duplicate manifest application {name!r} near line {line_number + 1}")
        packages[name] = owners

    return packages


def _skip_lua_space(text: str, index: int) -> int:
    while index < len(text):
        if text[index].isspace():
            index += 1
            continue
        if text.startswith("--", index):
            newline = text.find("\n", index)
            index = len(text) if newline < 0 else newline + 1
            continue
        break
    return index


def _decode_lua_escape(text: str, index: int) -> tuple[str, int]:
    if index + 1 >= len(text):
        raise AuditError("unterminated Lua string escape")

    escaped = text[index + 1]
    replacements = {
        "a": "\a",
        "b": "\b",
        "f": "\f",
        "n": "\n",
        "r": "\r",
        "t": "\t",
        "v": "\v",
        "\\": "\\",
        '"': '"',
        "'": "'",
    }
    if escaped in replacements:
        return replacements[escaped], index + 2
    if escaped == "\n":
        return "", index + 2
    if escaped.isdigit():
        match = re.match(r"[0-9]{1,3}", text[index + 1 :])
        assert match is not None
        return chr(int(match.group(), 10)), index + 1 + len(match.group())
    raise AuditError(f"unsupported Lua string escape \\{escaped}")


def _parse_lua_string(text: str, index: int) -> tuple[str, int]:
    if text[index] == '"':
        characters: list[str] = []
        index += 1
        while index < len(text):
            character = text[index]
            if character == '"':
                return "".join(characters), index + 1
            if character == "\\":
                replacement, index = _decode_lua_escape(text, index)
                characters.append(replacement)
                continue
            characters.append(character)
            index += 1
        raise AuditError("unterminated quoted Lua command")

    opening = re.match(r"\[(=*)\[", text[index:])
    if opening is None:
        raise AuditError("hl.exec_cmd first argument is not a literal Lua string")

    marker = opening.group(1)
    content_start = index + len(opening.group(0))
    closing_marker = "]" + marker + "]"
    content_end = text.find(closing_marker, content_start)
    if content_end < 0:
        raise AuditError("unterminated long Lua command string")
    return text[content_start:content_end], content_end + len(closing_marker)


def extract_exec_commands(source: Path) -> list[Command]:
    """Extract literal command arguments from hl.exec_cmd and hl.dsp.exec_cmd calls."""

    text = source.read_text(encoding="utf-8")
    commands: list[Command] = []
    for match in _EXEC_CALL.finditer(text):
        argument_start = _skip_lua_space(text, match.end())
        command, _ = _parse_lua_string(text, argument_start)
        line = text.count("\n", 0, match.start()) + 1
        commands.append(Command(source, command, line))
    return commands


def _substitution_end(text: str, start: int) -> int:
    depth = 1
    quote: str | None = None
    index = start
    while index < len(text):
        character = text[index]
        if quote == "'":
            if character == "'":
                quote = None
            index += 1
            continue
        if quote == '"':
            if character == "\\":
                index += 2
                continue
            if character == '"':
                quote = None
            elif character == "$" and text.startswith("$(", index):
                depth += 1
                index += 2
                continue
            index += 1
            continue
        if character == "\\":
            index += 2
            continue
        if character in "'\"":
            quote = character
            index += 1
            continue
        if character == "$" and text.startswith("$(", index):
            depth += 1
            index += 2
            continue
        if character == ")":
            depth -= 1
            if depth == 0:
                return index
        index += 1
    raise AuditError("unterminated shell command substitution")


def _split_shell_segments(command: str) -> list[str]:
    segments: list[str] = []
    segment_start = 0
    quote: str | None = None
    index = 0

    while index < len(command):
        character = command[index]
        if quote == "'":
            if character == "'":
                quote = None
            index += 1
            continue
        if quote == '"':
            if character == "\\":
                index += 2
                continue
            if character == '"':
                quote = None
                index += 1
                continue
            if character == "$" and command.startswith("$(", index):
                index = _substitution_end(command, index + 2) + 1
                continue
            index += 1
            continue
        if character == "\\":
            index += 2
            continue
        if character in "'\"":
            quote = character
            index += 1
            continue
        if character == "$" and command.startswith("$(", index):
            index = _substitution_end(command, index + 2) + 1
            continue
        if command.startswith("&&", index) or command.startswith("||", index):
            segments.append(command[segment_start:index].strip())
            index += 2
            segment_start = index
            continue
        if character in ";|":
            segments.append(command[segment_start:index].strip())
            index += 1
            segment_start = index
            continue
        if character in "<>&":
            raise AuditError(f"unsupported shell operator {character!r}")
        index += 1

    if quote is not None:
        raise AuditError("unterminated shell quote")
    segments.append(command[segment_start:].strip())
    return [segment for segment in segments if segment]


def _shell_words(segment: str) -> list[str]:
    words: list[str] = []
    word: list[str] = []
    quote: str | None = None
    index = 0

    def flush() -> None:
        if word:
            words.append("".join(word))
            word.clear()

    while index < len(segment):
        character = segment[index]
        if quote == "'":
            if character == "'":
                quote = None
            else:
                word.append(character)
            index += 1
            continue
        if quote == '"':
            if character == '"':
                quote = None
                index += 1
                continue
            if character == "\\":
                if index + 1 >= len(segment):
                    raise AuditError("unterminated shell escape")
                word.append(segment[index + 1])
                index += 2
                continue
            if character == "$" and segment.startswith("$(", index):
                end = _substitution_end(segment, index + 2)
                word.append(segment[index : end + 1])
                index = end + 1
                continue
            word.append(character)
            index += 1
            continue
        if character.isspace():
            flush()
            index += 1
            continue
        if character == "\\":
            if index + 1 >= len(segment):
                raise AuditError("unterminated shell escape")
            word.append(segment[index + 1])
            index += 2
            continue
        if character in "'\"":
            quote = character
            index += 1
            continue
        if character == "$" and segment.startswith("$(", index):
            end = _substitution_end(segment, index + 2)
            word.append(segment[index : end + 1])
            index = end + 1
            continue
        word.append(character)
        index += 1

    if quote is not None:
        raise AuditError("unterminated shell quote")
    flush()
    return words


def _substitutions(segment: str) -> Iterator[str]:
    quote: str | None = None
    index = 0
    while index < len(segment):
        character = segment[index]
        if quote == "'":
            if character == "'":
                quote = None
            index += 1
            continue
        if quote == '"':
            if character == "\\":
                index += 2
                continue
            if character == '"':
                quote = None
                index += 1
                continue
        else:
            if character == "\\":
                index += 2
                continue
            if character in "'\"":
                quote = character
                index += 1
                continue
        if character == "$" and segment.startswith("$(", index):
            end = _substitution_end(segment, index + 2)
            yield segment[index + 2 : end]
            index = end + 1
            continue
        index += 1


def _assert_package_owner(
    spec: ExecutableSpec,
    command: Command,
    packages: dict[str, tuple[PackageOwner, ...]],
) -> None:
    owners = packages.get(spec.application, ())
    if not owners:
        raise AuditError(
            f"{command.source}:{command.line}: executable {spec.application!r} "
            f"has no manifest application owner"
        )
    if not any(owner.manager == spec.manager and owner.package == spec.package for owner in owners):
        raise AuditError(
            f"{command.source}:{command.line}: executable {spec.application!r} "
            f"requires direct {spec.manager}:{spec.package} ownership"
        )


def _audit_owned_words(
    words: Sequence[str],
    command: Command,
    packages: dict[str, tuple[PackageOwner, ...]],
) -> None:
    if not words:
        raise AuditError(f"{command.source}:{command.line}: empty command segment")
    executable = Path(words[0]).name
    spec = EXECUTABLE_SPECS.get(executable)
    if spec is None:
        raise AuditError(
            f"{command.source}:{command.line}: unsupported executable {words[0]!r} "
            f"in {command.text!r}"
        )
    arguments = tuple(words[1:])
    if arguments not in spec.allowed_args:
        raise AuditError(
            f"{command.source}:{command.line}: unsupported full command {command.text!r}"
        )
    _assert_package_owner(spec, command, packages)


def _audit_target_words(
    words: Sequence[str],
    command: Command,
    packages: dict[str, tuple[PackageOwner, ...]],
) -> None:
    if not words:
        raise AuditError(f"{command.source}:{command.line}: launcher has no target executable")
    _audit_owned_words(words, command, packages)


def _audit_system_words(words: Sequence[str], command: Command) -> bool:
    if not words:
        raise AuditError(f"{command.source}:{command.line}: empty command segment")

    executable = Path(words[0]).name
    if executable == "sleep":
        if len(words) == 2 and words[1].isdigit():
            return True
        raise AuditError(f"{command.source}:{command.line}: unsupported sleep command {command.text!r}")
    if executable == "hyprctl":
        if len(words) >= 3 and words[1] == "eval":
            return True
        raise AuditError(f"{command.source}:{command.line}: unsupported hyprctl command {command.text!r}")
    if executable == "systemctl":
        if words == ["systemctl", "--user", "is-active"]:
            return True
        if words[:3] == ["systemctl", "--user", "import-environment"] and len(words) == 4:
            normalized = words[3].replace("'", "")
            if normalized == "$(env | cut -d= -f 1)":
                return True
        raise AuditError(f"{command.source}:{command.line}: unsupported systemctl command {command.text!r}")
    if executable == "dbus-update-activation-environment":
        if words == ["dbus-update-activation-environment", "--systemd", "--all"]:
            return True
        raise AuditError(f"{command.source}:{command.line}: unsupported dbus command {command.text!r}")
    if executable == "env":
        if len(words) == 1:
            return True
        raise AuditError(f"{command.source}:{command.line}: unsupported env command {command.text!r}")
    if executable == "cut":
        if words == ["cut", "-d=", "-f", "1"]:
            return True
        raise AuditError(f"{command.source}:{command.line}: unsupported cut command {command.text!r}")
    return False


def _audit_segment(
    segment: str,
    command: Command,
    packages: dict[str, tuple[PackageOwner, ...]],
) -> None:
    for substitution in _substitutions(segment):
        for nested_segment in _split_shell_segments(substitution):
            _audit_segment(nested_segment, command, packages)

    words = _shell_words(segment)
    if not words:
        return

    executable = Path(words[0]).name
    if _audit_system_words(words, command):
        return
    if executable in HELPER_COMMANDS:
        if executable == "launch-or-focus":
            if len(words) not in (2, 3):
                raise AuditError(f"{command.source}:{command.line}: unsupported launch-or-focus command")
            _audit_target_words(words[1:2], command, packages)
            if len(words) == 3:
                _audit_segment(words[2], command, packages)
            return
        if len(words) != 2:
            raise AuditError(f"{command.source}:{command.line}: unsupported launch-tui-large command")
        _audit_target_words(words[1:], command, packages)
        return
    if executable == "uwsm-app":
        if len(words) < 3 or words[1] != "--":
            raise AuditError(f"{command.source}:{command.line}: unsupported uwsm-app command")
        _assert_package_owner(EXECUTABLE_SPECS["uwsm-app"], command, packages)
        target = list(words[2:])
        if target[0] == "env":
            target.pop(0)
            while target and _ASSIGNMENT.fullmatch(target[0]):
                target.pop(0)
        _audit_target_words(target, command, packages)
        return
    if executable == "uwsm":
        if len(words) < 4 or words[1:3] != ["app", "--"]:
            raise AuditError(f"{command.source}:{command.line}: unsupported uwsm command")
        _assert_package_owner(EXECUTABLE_SPECS["uwsm"], command, packages)
        _audit_target_words(words[3:], command, packages)
        return
    _audit_owned_words(words, command, packages)


def audit_commands(
    commands: Iterable[Command],
    packages: dict[str, tuple[PackageOwner, ...]],
) -> None:
    for command in commands:
        try:
            for segment in _split_shell_segments(command.text):
                _audit_segment(segment, command, packages)
        except AuditError:
            raise


def audit_sources(manifest: Path, sources: Iterable[Path]) -> list[Command]:
    commands = [command for source in sources for command in extract_exec_commands(source)]
    audit_commands(commands, parse_manifest_packages(manifest))
    return commands


def _default_sources(manifest: Path) -> tuple[Path, Path]:
    root = manifest.parent
    return root / "Linux/hypr/bindings/apps.lua", root / "Linux/hypr/autostart.lua"


def main(argv: Sequence[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--manifest", required=True, type=Path)
    parser.add_argument("sources", nargs="*", type=Path)
    arguments = parser.parse_args(argv)
    sources = tuple(arguments.sources) or _default_sources(arguments.manifest)
    try:
        commands = audit_sources(arguments.manifest, sources)
    except (AuditError, OSError) as error:
        print(f"FAIL: {error}", file=sys.stderr)
        return 1
    print(f"PASS: Hyprland runtime ownership audit ({len(commands)} commands)")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
