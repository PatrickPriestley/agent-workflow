#!/usr/bin/env bash
# install.sh — link agent-workflow into this machine: the agent rules file, the skills (Codex
# and Cursor read ~/.agents/skills; Claude Code reaches them through ~/.claude/skills), the
# optional feature-loop workflow, and the agent-review and commit-gate commands.
#
#   install.sh [--dry-run]
#
# Safe to rerun. A file in the way is replaced only when it equals the repo copy; any other
# file or folder stops the install before anything changes. Turn on the commit hooks per
# repository with `commit-gate enable [--tests "<test command>"]`.
set -euo pipefail
root="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
dry=0
case "${1:-}" in
  --dry-run) dry=1 ;;
  "") ;;
  *) echo "usage: install.sh [--dry-run]" >&2; exit 2 ;;
esac

links=(
  "$HOME/AGENT-WORKFLOW.md|$root/AGENT-WORKFLOW.md"
  "$HOME/.agents/skills/feature-loop|$root/skills/feature-loop"
  "$HOME/.agents/skills/agent-review|$root/skills/agent-review"
  "$HOME/.claude/skills/feature-loop|$HOME/.agents/skills/feature-loop"
  "$HOME/.claude/skills/agent-review|$HOME/.agents/skills/agent-review"
  "$HOME/.claude/workflows/feature-loop.js|$root/workflows/feature-loop.js"
  "$HOME/.local/bin/agent-review|$root/bin/agent-review"
  "$HOME/.local/bin/commit-gate|$root/bin/commit-gate"
)

for pair in "${links[@]}"; do
  target="${pair%%|*}"; source="${pair#*|}"
  if [ -e "$target" ] && [ ! -L "$target" ] && ! cmp -s "$target" "$source"; then
    echo "install.sh: $target exists and differs from $source; move it aside and rerun" >&2
    exit 1
  fi
done

for pair in "${links[@]}"; do
  target="${pair%%|*}"; source="${pair#*|}"
  [ -L "$target" ] && [ "$(readlink "$target")" = "$source" ] && continue
  if [ "$dry" = 1 ]; then echo "would: link $target -> $source"; continue; fi
  mkdir -p "$(dirname "$target")"
  ln -sfn "$source" "$target"
  echo "linked $target -> $source"
done
