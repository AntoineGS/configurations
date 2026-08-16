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
class LuaToken:
    kind: str
    value: str
    start: int
    end: int


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
    "/usr/lib/polkit-gnome/polkit-gnome-authentication-agent-1": _spec(
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

_ASSIGNMENT = re.compile(r"^[A-Za-z_][A-Za-z0-9_]*=.*$")
_IDENTIFIER = re.compile(r"[A-Za-z_][A-Za-z0-9_]*")
_LONG_STRING_OPEN = re.compile(r"\[(=*)\[")
_APPROVED_ENV_ASSIGNMENTS = frozenset({("HERDR_NAV_PASSTHROUGH_RE", "^(shell-picker|fzf)$")})

_WORKSPACE_EVAL = (
    'hl.dispatch(hl.dsp.workspace.move({workspace=1, monitor="DVI-D-1"})); '
    'hl.dispatch(hl.dsp.workspace.move({workspace=4, monitor="DVI-D-1"})); '
    'hl.dispatch(hl.dsp.workspace.move({workspace=7, monitor="DVI-D-1"})); '
    'hl.dispatch(hl.dsp.workspace.move({workspace=2, monitor="HDMI-A-1"})); '
    'hl.dispatch(hl.dsp.workspace.move({workspace=5, monitor="HDMI-A-1"})); '
    'hl.dispatch(hl.dsp.workspace.move({workspace=8, monitor="HDMI-A-1"})); '
    'hl.dispatch(hl.dsp.workspace.move({workspace=3, monitor="DP-2"})); '
    'hl.dispatch(hl.dsp.workspace.move({workspace=6, monitor="DP-2"})); '
    'hl.dispatch(hl.dsp.workspace.move({workspace=9, monitor="DP-2"})); '
    'hl.dispatch(hl.dsp.workspace.move({workspace=10, monitor="DP-2"})); '
    'hl.dispatch(hl.dsp.focus({workspace=2}))'
)
_MONITOR_EVAL_1 = 'hl.monitor({ output = "DP-2", mode = "1920x1080@60", position = "3601x0", scale = 1 })'
_MONITOR_EVAL_2 = 'hl.monitor({ output = "DP-2", mode = "1920x1080@60", position = "3600x0", scale = 1 })'

# Shell-bearing commands are allowlisted as complete strings. This prevents a recognized
# outer executable from authorizing arbitrary payloads, substitutions, or command chains.
APPROVED_FULL_COMMANDS = frozenset(
    {
        "systemctl --user import-environment $(env | cut -d'=' -f 1)",
        "dbus-update-activation-environment --systemd --all",
        f"sleep 1 && hyprctl eval '{_WORKSPACE_EVAL}'",
        f"sleep 2 && hyprctl eval '{_MONITOR_EVAL_1}' && hyprctl eval '{_MONITOR_EVAL_2}'",
    }
)


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
    if index < len(text) and text[index] in "'\"":
        quote = text[index]
        characters: list[str] = []
        index += 1
        while index < len(text):
            character = text[index]
            if character == quote:
                return "".join(characters), index + 1
            if character == "\\":
                replacement, index = _decode_lua_escape(text, index)
                characters.append(replacement)
                continue
            characters.append(character)
            index += 1
        raise AuditError("unterminated quoted Lua command")

    opening = _LONG_STRING_OPEN.match(text, index)
    if opening is None:
        raise AuditError("hl.exec_cmd first argument is not a literal Lua string")

    marker = opening.group(1)
    content_start = opening.end()
    closing_marker = "]" + marker + "]"
    content_end = text.find(closing_marker, content_start)
    if content_end < 0:
        raise AuditError("unterminated long Lua command string")
    return text[content_start:content_end], content_end + len(closing_marker)


def _scan_lua(text: str) -> list[LuaToken]:
    tokens: list[LuaToken] = []
    index = 0
    while index < len(text):
        character = text[index]
        if character.isspace():
            index += 1
            continue

        if text.startswith("--", index):
            comment_start = index + 2
            opening = _LONG_STRING_OPEN.match(text, comment_start)
            if opening is not None:
                marker = opening.group(1)
                closing_marker = "]" + marker + "]"
                comment_end = text.find(closing_marker, opening.end())
                if comment_end < 0:
                    raise AuditError("unterminated Lua block comment")
                index = comment_end + len(closing_marker)
            else:
                newline = text.find("\n", comment_start)
                index = len(text) if newline < 0 else newline + 1
            continue

        if character in "'\"" or _LONG_STRING_OPEN.match(text, index) is not None:
            value, end = _parse_lua_string(text, index)
            tokens.append(LuaToken("string", value, index, end))
            index = end
            continue

        identifier = _IDENTIFIER.match(text, index)
        if identifier is not None:
            tokens.append(LuaToken("identifier", identifier.group(), index, identifier.end()))
            index = identifier.end()
            continue

        tokens.append(LuaToken("symbol", character, index, index + 1))
        index += 1
    return tokens


def _tokens_are_adjacent(text: str, left: LuaToken, right: LuaToken) -> bool:
    return text[left.end : right.start] == ""


def _is_canonical_exec_call(tokens: Sequence[LuaToken], index: int, text: str) -> bool:
    if tokens[index].kind != "identifier" or tokens[index].value != "exec_cmd":
        return False

    direct = index >= 2 and [token.value for token in tokens[index - 2 : index]] == ["hl", "."]
    dsp = index >= 4 and [token.value for token in tokens[index - 4 : index]] == ["hl", ".", "dsp", "."]
    if direct:
        prefix_start = index - 2
    elif dsp:
        prefix_start = index - 4
    else:
        return False

    for left, right in zip(tokens[prefix_start:index], tokens[prefix_start + 1 : index + 1]):
        if not _tokens_are_adjacent(text, left, right):
            return False
    return index + 1 < len(tokens) and tokens[index + 1].value == "(" and _tokens_are_adjacent(
        text, tokens[index], tokens[index + 1]
    )


def _is_bracket_exec_reference(tokens: Sequence[LuaToken], index: int) -> bool:
    return (
        tokens[index].kind == "string"
        and tokens[index].value == "exec_cmd"
        and index > 0
        and index + 1 < len(tokens)
        and tokens[index - 1].value == "["
        and tokens[index + 1].value == "]"
        and index > 1
        and (
            tokens[index - 2].kind in {"identifier", "string"}
            or tokens[index - 2].value in {")", "]"}
        )
    )


def _matching_open_paren(tokens: Sequence[LuaToken], close_index: int) -> int | None:
    depth = 0
    for index in range(close_index, -1, -1):
        if tokens[index].value == ")":
            depth += 1
        elif tokens[index].value == "(":
            depth -= 1
            if depth == 0:
                return index
    return None


def _matching_close_paren(tokens: Sequence[LuaToken], open_index: int) -> int | None:
    depth = 0
    for index in range(open_index, len(tokens)):
        if tokens[index].value == "(":
            depth += 1
        elif tokens[index].value == ")":
            depth -= 1
            if depth == 0:
                return index
    return None


def _expression_start(tokens: Sequence[LuaToken], end: int) -> int | None:
    if end == 0:
        return None
    last = end - 1
    if tokens[last].value == ")":
        opening = _matching_open_paren(tokens, last)
        if opening is None:
            return None
        if opening > 0 and tokens[opening - 1].kind in {"identifier", "string"}:
            return _expression_start(tokens, opening)
        start = opening
    elif tokens[last].kind in {"identifier", "string"} or tokens[last].value == "]":
        start = last
    else:
        return None

    if start > 0 and tokens[start - 1].value == ".":
        return _expression_start(tokens, start - 1)
    return start


def _strip_outer_parens(tokens: Sequence[LuaToken], start: int, end: int) -> tuple[int, int]:
    while start < end and tokens[start].value == "(" and tokens[end - 1].value == ")":
        closing = _matching_open_paren(tokens, end - 1)
        if closing != start:
            break
        start += 1
        end -= 1
    return start, end


def _is_hl_rooted_expression(tokens: Sequence[LuaToken], start: int, end: int) -> bool:
    start, end = _strip_outer_parens(tokens, start, end)
    values = [token.value for token in tokens[start:end]]
    if values == ["hl"] or values == ["hl", ".", "dsp"]:
        return True
    if end - start >= 3 and tokens[end - 2].value == "." and tokens[end - 1].value == "dsp":
        return _is_hl_rooted_expression(tokens, start, end - 2)
    return False


def _is_hl_computed_access(tokens: Sequence[LuaToken], index: int) -> bool:
    if tokens[index].value != "[":
        return False
    start = _expression_start(tokens, index)
    return start is not None and _is_hl_rooted_expression(tokens, start, index)


def _is_assignment_operator(tokens: Sequence[LuaToken], index: int) -> bool:
    if tokens[index].value != "=":
        return False
    previous = tokens[index - 1].value if index > 0 else ""
    following = tokens[index + 1].value if index + 1 < len(tokens) else ""
    return previous not in {"=", "<", ">", "~"} and following != "="


def _simple_alias_expression_end(tokens: Sequence[LuaToken], start: int) -> int | None:
    if start >= len(tokens):
        return None
    if tokens[start].value == "(":
        closing = _matching_close_paren(tokens, start)
        if closing is None or not _is_hl_rooted_expression(tokens, start, closing + 1):
            return None
        end = closing + 1
        if end + 1 < len(tokens) and [token.value for token in tokens[end : end + 2]] == [".", "dsp"]:
            end += 2
        return end
    end = start + 1
    if end + 1 < len(tokens) and [token.value for token in tokens[end : end + 2]] == [".", "dsp"]:
        end += 2
    if _is_hl_rooted_expression(tokens, start, end):
        return end
    return None


def _is_alias_expression_delimited(tokens: Sequence[LuaToken], text: str, end: int) -> bool:
    if end == len(tokens):
        return True
    next_token = tokens[end]
    return next_token.value in {",", ";", ")", "}"} or "\n" in text[tokens[end - 1].end : next_token.start]


def _rhs_contains_hl_alias(tokens: Sequence[LuaToken], text: str, start: int) -> bool:
    candidate = start
    depth = 0
    for index in range(start, len(tokens)):
        if depth == 0 and index == candidate:
            end = _simple_alias_expression_end(tokens, candidate)
            if end is not None and _is_alias_expression_delimited(tokens, text, end):
                return True

        value = tokens[index].value
        if depth == 0 and value == ";":
            return False
        if depth == 0 and value == ",":
            candidate = index + 1
            continue
        if value in {"(", "[", "{"}:
            depth += 1
        elif value in {")", "]", "}"} and depth > 0:
            depth -= 1
    return False


def _reject_hl_alias_assignments(source: Path, text: str, tokens: Sequence[LuaToken]) -> None:
    for index, token in enumerate(tokens):
        if not _is_assignment_operator(tokens, index) or index == 0:
            continue
        left = tokens[index - 1]
        if left.kind != "identifier" or (index > 1 and tokens[index - 2].value in {".", "]"}):
            continue
        if _rhs_contains_hl_alias(tokens, text, index + 1):
            line = _line_number(text, token.start)
            raise AuditError(f"{source}:{line}: assignment aliases hl or hl.dsp")


def _line_number(text: str, index: int) -> int:
    return text.count("\n", 0, index) + 1


def extract_exec_commands(source: Path) -> list[Command]:
    """Extract literal command arguments from hl.exec_cmd and hl.dsp.exec_cmd calls."""

    text = source.read_text(encoding="utf-8")
    tokens = _scan_lua(text)
    _reject_hl_alias_assignments(source, text, tokens)
    commands: list[Command] = []
    consumed_exec_tokens: set[int] = set()

    for index, token in enumerate(tokens):
        if not _is_canonical_exec_call(tokens, index, text):
            continue
        argument_index = index + 2
        if argument_index >= len(tokens) or tokens[argument_index].kind != "string":
            raise AuditError(f"{source}:{_line_number(text, token.start)}: exec_cmd requires a literal string")
        if argument_index + 1 >= len(tokens) or tokens[argument_index + 1].value != ")":
            raise AuditError(f"{source}:{_line_number(text, token.start)}: exec_cmd accepts one literal string")
        command_token = tokens[argument_index]
        line = _line_number(text, token.start)
        commands.append(Command(source, command_token.value, line))
        consumed_exec_tokens.add(index)

    for index, token in enumerate(tokens):
        unconsumed_identifier = (
            token.kind == "identifier" and token.value == "exec_cmd" and index not in consumed_exec_tokens
        )
        if unconsumed_identifier or _is_bracket_exec_reference(tokens, index) or _is_hl_computed_access(tokens, index):
            line = _line_number(text, token.start)
            raise AuditError(f"{source}:{line}: unconsumed exec_cmd reference")
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
        if character in "\n\r":
            segments.append(command[segment_start:index].strip())
            index += 1
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
    executable = words[0]
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

    if words[0] not in {
        "cut",
        "dbus-update-activation-environment",
        "env",
        "hyprctl",
        "sleep",
        "systemctl",
    }:
        return False
    if command.text not in APPROVED_FULL_COMMANDS:
        raise AuditError(f"{command.source}:{command.line}: unsupported full command {command.text!r}")
    return True


def _validate_full_command(command: Command) -> None:
    if "`" in command.text:
        raise AuditError(f"{command.source}:{command.line}: backtick substitution is unsupported")
    if "$(" in command.text and command.text not in APPROVED_FULL_COMMANDS:
        raise AuditError(f"{command.source}:{command.line}: unsupported command substitution")
    if ("\n" in command.text or "\r" in command.text) and command.text not in APPROVED_FULL_COMMANDS:
        raise AuditError(f"{command.source}:{command.line}: unsupported newline in full command")
    if len(_split_shell_segments(command.text)) > 1 and command.text not in APPROVED_FULL_COMMANDS:
        raise AuditError(f"{command.source}:{command.line}: unsupported full command {command.text!r}")


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

    executable = words[0]
    if _ASSIGNMENT.fullmatch(executable):
        raise AuditError(f"{command.source}:{command.line}: unsupported leading environment assignment")
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
            assignments: list[tuple[str, str]] = []
            while target and _ASSIGNMENT.fullmatch(target[0]):
                name, value = target.pop(0).split("=", 1)
                assignments.append((name, value))
            if len(assignments) != 1 or assignments[0] not in _APPROVED_ENV_ASSIGNMENTS:
                raise AuditError(f"{command.source}:{command.line}: unsupported environment assignment")
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
        _validate_full_command(command)
        for segment in _split_shell_segments(command.text):
            _audit_segment(segment, command, packages)


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
