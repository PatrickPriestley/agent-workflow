#!/usr/bin/env bash
# install.sh — link agent-workflow into this machine: the agent rules file, the skills (Codex
# and Cursor read ~/.agents/skills; Claude Code reaches them through ~/.claude/skills), the
# optional feature-loop workflow, and the agent-review and commit-gate commands.
#
#   install.sh [--ref REF | --dev] [--wire] [--dry-run]
#
# By default it installs from a pinned copy of this repository at
# ${XDG_DATA_HOME:-~/.local/share}/agent-workflow, checked out at origin/main (or main),
# so switching branches in this checkout does not change what every agent runs. --ref pins
# a tag or branch instead. To update: `git fetch` here, then rerun install.sh. --dev links
# this checkout itself, for working on agent-workflow.
#
# --wire also gives each installed agent the rules: an import line in ~/.claude/CLAUDE.md,
# links from ~/.codex/AGENTS.md, ~/.config/opencode/AGENTS.md and ~/.gemini/GEMINI.md, and a
# generated ~/.cursor/rules/agent-workflow.mdc. An agent whose folder does not exist is
# skipped; an instruction file with its own content is left alone and named.
#
# Safe to rerun. A file in the way is replaced only when it equals the repo copy; any other
# file or folder stops the install before anything changes. Turn on the commit hooks per
# repository with `commit-gate enable [--tests "<test command>"]`.
set -euo pipefail
root="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
usage() { echo "usage: install.sh [--ref REF | --dev] [--wire] [--dry-run]" >&2; exit 2; }
dry=0; wire=0; dev=0; ref=""
while [ "$#" -gt 0 ]; do
  case "$1" in
    --dry-run) dry=1; shift ;;
    --wire) wire=1; shift ;;
    --dev) dev=1; shift ;;
    --ref) [ -n "${2:-}" ] || usage; ref="$2"; shift 2 ;;
    *) usage ;;
  esac
done
[ "$dev" = 1 ] && [ -n "$ref" ] && usage

# The pinned copy: a separate clone, detached at the chosen commit, that the links point into.
if [ "$dev" = 0 ]; then
  if [ -z "$ref" ]; then
    if git -C "$root" rev-parse --verify --quiet "origin/main^{commit}" >/dev/null; then ref=origin/main; else ref=main; fi
  fi
  commit="$(git -C "$root" rev-parse --verify --quiet "$ref^{commit}")" \
    || { echo "install.sh: $ref is not a commit in $root" >&2; exit 1; }
  pinned="${XDG_DATA_HOME:-$HOME/.local/share}/agent-workflow"
  # The pinned path must be the root of its own clone: a plain folder inside some other
  # repository (a home folder kept in git) would otherwise have that repository checked out.
  if [ -e "$pinned" ] && { [ ! -d "$pinned" ] \
       || [ "$(git -C "$pinned" rev-parse --show-toplevel 2>/dev/null)" != "$(cd "$pinned" && pwd -P)" ]; }; then
    echo "install.sh: $pinned exists and is not a git checkout; move it aside and rerun" >&2; exit 1
  fi
  if [ -d "$pinned" ] && [ -n "$(git -C "$pinned" status --porcelain)" ]; then
    echo "install.sh: $pinned has local changes; commit or discard them there, or use --dev" >&2; exit 1
  fi
  if [ "$dry" = 1 ]; then
    echo "would: pin $pinned at $ref ($(git -C "$root" rev-parse --short "$commit"))"
  elif [ "$(git -C "$pinned" rev-parse HEAD 2>/dev/null || true)" != "$commit" ]; then
    [ -d "$pinned" ] || git clone -q --no-checkout "$root" "$pinned"
    git -C "$pinned" fetch -q "$root" "$commit"
    git -C "$pinned" -c advice.detachedHead=false checkout -q --detach "$commit"
    echo "pinned $pinned at $ref ($(git -C "$pinned" rev-parse --short HEAD))"
  fi
  # A dry run of a first install has no copy yet to link into; it shows the links it would make.
  root="$pinned"
fi

links=(
  "$HOME/AGENT-WORKFLOW.md|$root/AGENT-WORKFLOW.md"
  "$HOME/.agents/skills/feature-loop|$root/skills/feature-loop"
  "$HOME/.agents/skills/agent-review|$root/skills/agent-review"
  "$HOME/.claude/skills/feature-loop|$HOME/.agents/skills/feature-loop"
  "$HOME/.claude/skills/agent-review|$HOME/.agents/skills/agent-review"
  "$HOME/.claude/workflows/feature-loop.js|$root/workflows/feature-loop.js"
  "$HOME/.local/bin/agent-review|$root/bin/agent-review"
  "$HOME/.local/bin/commit-gate|$root/bin/commit-gate"
  "$HOME/.local/bin/pr-size|$root/bin/pr-size"
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

# Give each installed agent the rules. Claude Code imports the file; Codex, OpenCode and
# Gemini read a global instructions file, which becomes a link to it; Cursor loads only
# ~/.cursor/rules/*.mdc, so it gets a generated copy that each --wire run refreshes.
say() { if [ "$dry" = 1 ]; then echo "would: $1"; return 1; fi; }
if [ "$wire" = 1 ]; then
  rules="$HOME/AGENT-WORKFLOW.md"
  file="$HOME/.claude/CLAUDE.md"
  if ! [ "$file" -ef "$rules" ] && ! grep -qxF -e '@~/AGENT-WORKFLOW.md' -e "@$rules" "$file" 2>/dev/null; then
    if say "add @~/AGENT-WORKFLOW.md to $file"; then
      { [ -s "$file" ] && printf '\n'; printf '@~/AGENT-WORKFLOW.md\n'; } >> "$file"
      echo "wired $file"
    fi
  fi
  for file in "$HOME/.codex/AGENTS.md" "$HOME/.config/opencode/AGENTS.md" "$HOME/.gemini/GEMINI.md"; do
    [ -d "$(dirname "$file")" ] || continue
    [ -L "$file" ] && [ "$(readlink "$file")" = "$rules" ] && continue
    [ "$file" -ef "$rules" ] && continue
    if [ -e "$file" ] || [ -L "$file" ]; then
      echo "left $file alone (it has its own content); add: Follow the rules in ~/AGENT-WORKFLOW.md."
      continue
    fi
    if say "link $file -> $rules"; then ln -sfn "$rules" "$file"; echo "wired $file"; fi
  done
  if [ -d "$HOME/.cursor" ]; then
    file="$HOME/.cursor/rules/agent-workflow.mdc"; mark='<!-- generated by agent-workflow install.sh --wire; edit AGENT-WORKFLOW.md instead -->'
    want="$(printf -- '---\ndescription: Working rules shared across agents\nalwaysApply: true\n---\n%s\n\n' "$mark"; cat "$root/AGENT-WORKFLOW.md")"
    if [ -L "$file" ] || ! [ -f "$file" ] || [ "$(cat "$file")" != "$want" ]; then
      if say "write the rules into $file"; then
        mkdir -p "$(dirname "$file")"
        # A link or a hand-written rule is moved aside, never written through.
        if [ -L "$file" ] || { [ -e "$file" ] && ! grep -qF "$mark" "$file"; }; then
          bak="$file.bak"; n=1
          while [ -e "$bak" ] || [ -L "$bak" ]; do bak="$file.bak$n"; n=$((n+1)); done
          mv "$file" "$bak"; echo "kept the old $file as $bak"
        fi
        printf '%s\n' "$want" > "$file"; echo "wired $file"
      fi
    fi
  fi
fi
