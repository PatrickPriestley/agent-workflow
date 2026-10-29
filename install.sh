#!/usr/bin/env bash
# install.sh — link agent-workflow into this machine: the agent rules file, the skills (Codex
# and Cursor read ~/.agents/skills; Claude Code reaches them through ~/.claude/skills), the
# optional feature-loop workflow, and the agent-review and commit-gate commands.
#
#   install.sh [--wire] [--dry-run]
#
# --wire also adds one line to each installed agent's global instructions so it loads the
# rules: ~/.claude/CLAUDE.md (Claude Code) and ~/.codex/AGENTS.md (Codex). It is added once;
# an agent whose folder does not exist is skipped.
#
# Safe to rerun. A file in the way is replaced only when it equals the repo copy; any other
# file or folder stops the install before anything changes. Turn on the commit hooks per
# repository with `commit-gate enable [--tests "<test command>"]`.
set -euo pipefail
root="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
dry=0; wire=0
for arg in "$@"; do
  case "$arg" in
    --dry-run) dry=1 ;;
    --wire) wire=1 ;;
    *) echo "usage: install.sh [--wire] [--dry-run]" >&2; exit 2 ;;
  esac
done

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
# The formal SDLC: intent -> spec -> plan, and incident-to-eval for after a fix ships.
for s in intent spec plan incident-to-eval; do
  links+=("$HOME/.agents/skills/$s|$root/skills/$s" "$HOME/.claude/skills/$s|$HOME/.agents/skills/$s")
done

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

# Tell each installed agent to load the rules.
if [ "$wire" = 1 ]; then
  line='Follow the rules in `~/AGENT-WORKFLOW.md` (canonical, shared across agents).'
  for pair in "$HOME/.claude|CLAUDE.md" "$HOME/.codex|AGENTS.md"; do
    dir="${pair%%|*}"; file="$dir/${pair#*|}"
    [ -d "$dir" ] || continue
    grep -qF 'AGENT-WORKFLOW.md' "$file" 2>/dev/null && continue
    if [ "$dry" = 1 ]; then echo "would: add the rules line to $file"; continue; fi
    { [ -s "$file" ] && printf '\n'; printf '%s\n' "$line"; } >> "$file"
    echo "wired $file"
  done
fi
