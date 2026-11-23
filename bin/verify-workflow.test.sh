#!/usr/bin/env bash
# Tests for .github/workflows/verify.md and its lock, read as text: who can start
# it, what the agent may run, what it is given, and that a comment is its only write.
set -u
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
root="$(cd "$here/.." && pwd)"
pass=0; fail=0; CURRENT=""
it() { CURRENT="$1"; }
ok()  { pass=$((pass+1)); printf '  ok   %s\n' "$CURRENT"; }
bad() { fail=$((fail+1)); printf '  FAIL %s\n       %s\n' "$CURRENT" "$1"; }
has() { printf '%s' "$1" | grep -qF -- "$2" && ok || bad "missing [$2]"; }
lacks() { printf '%s' "$1" | grep -qE -- "$2" && bad "unexpected [$2]" || ok; }

md="$root/.github/workflows/verify.md"
lock="$root/.github/workflows/verify.lock.yml"
w="$(grep -v '^ *#' "$md" 2>/dev/null)"
l="$(cat "$lock" 2>/dev/null)"

it "the workflow and its lock exist"; [ -n "$w" ] && [ -n "$l" ] && ok || bad "$md or $lock missing"
it "it starts on the verify label, for same-repository pull requests only"
has "$w" "  label_command:"; has "$w" "    name: verify"; has "$w" "    events: [pull_request]"
has "$w" "if: github.event.pull_request.head.repo.full_name == github.repository"
lacks "$w" 'slash_command|issue_comment|pull_request_target'
it "on Claude, with a read-only token and threat detection failing closed"
has "$w" "  id: claude"; lacks "$w" 'codex|OPENAI'
has "$w" "  contents: read"; lacks "$w" ': *write'
has "$w" "    continue-on-error: false"
it "a comment is the only write"
has "$w" "  add-comment:"; lacks "$w" 'push-to-pull-request-branch|create-pull-request|create-issue|submit-pull-request-review'
it "bash runs only the repository's scripts and the merge-base worktree"
has "$w" '- "bash bin/:*"'; has "$w" '- "bash /tmp/gh-aw/agent/verify/base/:*"'
lacks "$w" '"bash:\*"|"bash -c|"sed|"cd:\*"|"python'
it "the pull request's text reaches the step through the environment, never the script"
has "$w" 'PR_BODY: ${{ github.event.pull_request.body }}'
has "$w" 'printf '"'"'# %s\n\n%s\n'"'"' "$PR_TITLE" "$PR_BODY"'
printf '%s' "$w" | sed -n '/^    run: |/,/^safe-outputs:/p' | grep -qF '${{' && bad "an expression inside the run script" || ok
it "the step stops when there is no merge base with main"
has "$w" 'base=$(git merge-base origin/main HEAD) || { echo "::error::no merge base with origin/main"; exit 1; }'
it "the lock matches: labeled trigger, Anthropic key, no OpenAI secret, the narrowed bash"
has "$l" "      - labeled"; has "$l" "ANTHROPIC_API_KEY"; lacks "$l" 'OPENAI_API_KEY|CODEX_API_KEY'
has "$l" "Bash(bash bin/:*)"; lacks "$l" 'Bash\(bash:\*\)|Bash\(sed -n'

echo; echo "passed=$pass failed=$fail"
[ "$fail" -eq 0 ]
