#!/usr/bin/env bash
# Tests for install.sh: a scratch HOME and real symlinks.
set -u
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TMPROOT="$(mktemp -d)"; trap 'rm -rf "$TMPROOT"' EXIT
pass=0; fail=0; CURRENT=""
it() { CURRENT="$1"; }
ok()  { pass=$((pass+1)); printf '  ok   %s\n' "$CURRENT"; }
bad() { fail=$((fail+1)); printf '  FAIL %s\n       %s\n' "$CURRENT" "$1"; }
assert_eq()  { [ "$1" = "$2" ] && ok || bad "expected [$1] got [$2]"; }
assert_link(){ [ -L "$1" ] && [ "$(readlink "$1")" = "$2" ] && ok || bad "$1 should link to $2, is $(readlink "$1" 2>/dev/null || echo 'not a link')"; }
fresh_home() { h="$TMPROOT/$1"; mkdir -p "$h"; printf '%s' "$h"; }
run() { HOME="$1" bash "$here/install.sh" "${@:2}"; }

it "fresh install links the rules, skills, workflow and commands"
H=$(fresh_home fresh)
out=$(run "$H" 2>&1); rc=$?
assert_eq 0 "$rc"
assert_link "$H/AGENT-WORKFLOW.md" "$here/AGENT-WORKFLOW.md"
assert_link "$H/.agents/skills/feature-loop" "$here/skills/feature-loop"
assert_link "$H/.claude/skills/feature-loop" "$H/.agents/skills/feature-loop"
assert_link "$H/.agents/skills/agent-review" "$here/skills/agent-review"
assert_link "$H/.claude/skills/agent-review" "$H/.agents/skills/agent-review"
assert_link "$H/.claude/workflows/feature-loop.js" "$here/workflows/feature-loop.js"
assert_link "$H/.local/bin/agent-review" "$here/bin/agent-review"
assert_link "$H/.local/bin/commit-gate" "$here/bin/commit-gate"
it "fresh install does not create or edit Claude settings"
[ ! -e "$H/.claude/settings.json" ] && ok || bad "settings.json was written"

it "second run is idempotent"
out=$(run "$H" 2>&1); rc=$?
assert_eq 0 "$rc"
printf '%s' "$out" | grep -q "^linked" && bad "second run relinked: $out" || ok

it "refuses to overwrite a differing file, before changing anything"
H=$(fresh_home conflict)
printf 'my own rules\n' > "$H/AGENT-WORKFLOW.md"
out=$(run "$H" 2>&1); rc=$?
assert_eq 1 "$rc"
assert_eq "my own rules" "$(cat "$H/AGENT-WORKFLOW.md")"
printf '%s' "$out" | grep -q "AGENT-WORKFLOW.md" && ok || bad "error does not name the file: $out"
[ ! -e "$H/.claude/workflows/feature-loop.js" ] && ok || bad "later links were created despite the refusal"

it "refuses to replace a real folder"
H=$(fresh_home folder)
mkdir -p "$H/.claude/skills/feature-loop"
out=$(run "$H" 2>&1); rc=$?
assert_eq 1 "$rc"
[ -d "$H/.claude/skills/feature-loop" ] && [ ! -L "$H/.claude/skills/feature-loop" ] && ok || bad "folder was replaced"

it "replaces an identical file with a link"
H=$(fresh_home identical)
cp "$here/AGENT-WORKFLOW.md" "$H/AGENT-WORKFLOW.md"
run "$H" >/dev/null 2>&1; rc=$?
assert_eq 0 "$rc"
assert_link "$H/AGENT-WORKFLOW.md" "$here/AGENT-WORKFLOW.md"

it "repoints a stale link"
H=$(fresh_home stale)
mkdir -p "$H/.claude/workflows"; ln -s /nowhere/feature-loop.js "$H/.claude/workflows/feature-loop.js"
run "$H" >/dev/null 2>&1
assert_link "$H/.claude/workflows/feature-loop.js" "$here/workflows/feature-loop.js"

it "dry run changes nothing"
H=$(fresh_home dry)
out=$(run "$H" --dry-run 2>&1); rc=$?
assert_eq 0 "$rc"
[ ! -e "$H/AGENT-WORKFLOW.md" ] && ok || bad "dry run created files"
printf '%s' "$out" | grep -q "would" && ok || bad "dry run printed no plan: $out"

printf 'passed=%d failed=%d\n' "$pass" "$fail"
[ "$fail" = 0 ]
