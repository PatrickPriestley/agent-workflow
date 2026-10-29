#!/usr/bin/env python3
"""PreToolUse hook: during a green step, block tool calls that would change the red
step's tests. Active while <git-dir>/green-phase exists; it lists the protected paths,
one per line, relative to the repo root.

Reads the hook's JSON on stdin. Understands Claude Code (Edit, Write, MultiEdit,
NotebookEdit: tool_input.file_path) and Codex (apply_patch: patch text in
tool_input.command) edits, and shell commands from either (Bash: tool_input.command).
Exit 2 with the reason on stderr blocks the call in both agents.

Shell detection is a heuristic: a command is blocked when it names a protected path
and contains a write operator. The git pre-commit hook is the backstop for anything
this misses.

The marker protects itself. While it exists, writes to `green-phase*` files in the git
dir, and any `herd-sdlc phase` command, are allowed only from the Herdr pane named in
<git-dir>/green-phase.owner, checked against this hook's own HERDR_PANE_ID (inherited
from the agent process, so a command cannot set it). Without an owner file, no agent may
change the marker; a person removes it by hand.
"""
import json
import os
import re
import subprocess
import sys

PATCH_FILE = re.compile(r"^\*\*\* (?:Update|Add|Delete) File: (.+)$|^\*\*\* Move to: (.+)$", re.M)
SHELL_WRITE = re.compile(
    r">|\btee\b|\bsed\b[^|;&]*\s-i|\bperl\b[^|;&]*\s-[a-z]*i|\b(?:mv|cp|rm|truncate|touch|ln|dd)\b"
    r"|\bgit\s+(?:checkout|restore|apply|stash|reset)\b")
PHASE_HELPER = re.compile(r"\bherd-sdlc(?:\s+phase|-phase)(?:\.sh)?\b")  # spelled as a subcommand, the installed helper, or its script


def git(cwd, *args):
    out = subprocess.run(["git", "-C", cwd, *args], capture_output=True, text=True)
    return out.stdout.strip() if out.returncode == 0 else None


def main():
    event = json.load(sys.stdin)
    cwd = event.get("cwd") or os.getcwd()
    root = git(cwd, "rev-parse", "--show-toplevel")
    if root is None:
        return 0
    gitdir = git(cwd, "rev-parse", "--absolute-git-dir")
    marker = os.path.join(gitdir, "green-phase")
    if not os.path.exists(marker):
        return 0
    protected = {line.strip() for line in open(marker) if line.strip()}
    owner_file = marker + ".owner"
    owner = open(owner_file).read().strip() if os.path.exists(owner_file) else ""
    is_owner = bool(owner) and os.environ.get("HERDR_PANE_ID", "") == owner

    def rel(path):
        full = os.path.realpath(path if os.path.isabs(path) else os.path.join(cwd, path))
        return os.path.relpath(full, os.path.realpath(root))

    def is_marker(path):
        full = os.path.realpath(path if os.path.isabs(path) else os.path.join(cwd, path))
        return os.path.dirname(full) == os.path.realpath(gitdir) \
            and os.path.basename(full).startswith("green-phase")

    tool, args = event.get("tool_name", ""), event.get("tool_input") or {}
    hit, marker_hit = set(), False
    if tool in ("Edit", "Write", "MultiEdit", "NotebookEdit"):
        path = args.get("file_path") or args.get("notebook_path")
        if path:
            hit = {rel(path)} & protected
            marker_hit = is_marker(path)
    elif tool == "apply_patch":
        paths = [(a or b).strip() for a, b in PATCH_FILE.findall(args.get("command", ""))]
        hit = {rel(p) for p in paths} & protected
        marker_hit = any(is_marker(p) for p in paths)
    elif tool == "Bash":
        command = args.get("command", "")
        if SHELL_WRITE.search(command):
            hit = {p for p in protected if p in command}  # also matches absolute paths
            marker_hit = "green-phase" in command
        marker_hit = marker_hit or bool(PHASE_HELPER.search(command))

    if marker_hit and not is_owner:
        print("green step: the phase marker (.git/green-phase) can only be changed by the"
              " conductor's pane" + (f" ({owner})" if owner else "") + ". Finish the step"
              " and let the conductor clear it, or ask the engineer.", file=sys.stderr)
        return 2

    if hit:
        print("green step: these tests were committed in the red step and must not change: "
              + ", ".join(sorted(hit))
              + ". Make the test pass without editing it, or stop and tell the engineer why"
              " it must change.", file=sys.stderr)
        return 2
    return 0


if __name__ == "__main__":
    sys.exit(main())
