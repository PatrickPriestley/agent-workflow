#!/usr/bin/env bash
# Tests for commit-gate: real git repos and worktrees; the test command is a small script.
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
GATE="${GATE_BIN:-$here/commit-gate}"
TMPROOT="$(mktemp -d)"; trap 'rm -rf "$TMPROOT"' EXIT
pass=0; fail=0; CURRENT=""
it() { CURRENT="$1"; }
ok()  { pass=$((pass+1)); printf '  ok   %s\n' "$CURRENT"; }
bad() { fail=$((fail+1)); printf '  FAIL %s\n       %s\n' "$CURRENT" "$1"; }
assert_eq()  { [ "$1" = "$2" ] && ok || bad "expected [$1] got [$2]"; }
assert_has() { printf '%s' "$2" | grep -qF -- "$1" && ok || bad "expected [$1] in: $2"; }

repo() {  # a repo whose "tests" pass when ./status says pass
  r="$TMPROOT/$1"; git init -q "$r"
  git -C "$r" -c user.name=t -c user.email=t@t commit -q --allow-empty -m "chore: init"
  printf 'pass\n' > "$r/status"
  printf '#!/bin/sh\n[ "$(cat status)" = pass ] || { echo "tests failed" >&2; exit 1; }\necho "tests passed"\n' > "$r/check.sh"
  chmod +x "$r/check.sh"
  printf '%s' "$r"
}
commit() { git -C "$1" -c user.name=t -c user.email=t@t commit -q --allow-empty -m "chore: ${2:-x}" 2>&1; }

it "enable records the command and installs the hook"
R=$(repo basic)
out=$(cd "$R" && "$GATE" enable --tests "./check.sh" 2>&1); rc=$?
assert_eq 0 "$rc"
assert_eq "./check.sh" "$(git -C "$R" config commitgate.test)"
[ -f "$R/.git/hooks/pre-commit" ] && [ ! -L "$R/.git/hooks/pre-commit" ] && grep -q "installed by commit-gate" "$R/.git/hooks/pre-commit" && ok || bad "no commit-gate hook file"

it "a commit with passing tests goes through"
out=$(commit "$R" ok); rc=$?
assert_eq 0 "$rc"

it "a commit with failing tests is refused and says why"
printf 'fail\n' > "$R/status"
out=$(commit "$R" broken); rc=$?
[ "$rc" != 0 ] && ok || bad "commit was not refused"
assert_has "tests failed" "$out"
assert_has "./check.sh" "$out"
assert_eq "chore: ok" "$(git -C "$R" log -1 --format=%s)"

it "--no-verify still bypasses"
out=$(git -C "$R" -c user.name=t -c user.email=t@t commit -q --no-verify --allow-empty -m bypass 2>&1); rc=$?
assert_eq 0 "$rc"

it "the hook runs from the repository root, wherever the commit starts"
printf 'pass\n' > "$R/status"; mkdir -p "$R/sub"
out=$(cd "$R/sub" && git -c user.name=t -c user.email=t@t commit -q --allow-empty -m "chore: fromsub" 2>&1); rc=$?
assert_eq 0 "$rc"

it "a worktree is gated by the same hook and command"
git -C "$R" worktree add -q "$TMPROOT/wt" -b wt
printf 'fail\n' > "$TMPROOT/wt/status" 2>/dev/null || true
cp "$R/check.sh" "$TMPROOT/wt/check.sh"
out=$(commit "$TMPROOT/wt" wtbroken); rc=$?
[ "$rc" != 0 ] && ok || bad "worktree commit was not refused"

it "with no command set, a commit goes through with a notice"
R2=$(repo nocmd)
(cd "$R2" && "$GATE" enable --tests "./check.sh" >/dev/null 2>&1); git -C "$R2" config --unset commitgate.test
out=$(commit "$R2" plain); rc=$?
assert_eq 0 "$rc"
assert_has "commitgate.test" "$out"

it "enable refuses to replace a different existing hook"
R3=$(repo existing)
printf '#!/bin/sh\nexit 0\n' > "$R3/.git/hooks/pre-commit"; chmod +x "$R3/.git/hooks/pre-commit"
out=$(cd "$R3" && "$GATE" enable --tests "./check.sh" 2>&1); rc=$?
assert_eq 1 "$rc"
assert_has "pre-commit" "$out"
[ ! -L "$R3/.git/hooks/pre-commit" ] && ok || bad "existing hook was replaced"

it "enable uses an absolute core.hooksPath"
R4=$(repo hookspath); mkdir -p "$TMPROOT/sharedhooks"; git -C "$R4" config core.hooksPath "$TMPROOT/sharedhooks"
(cd "$R4" && "$GATE" enable --tests "./check.sh" >/dev/null 2>&1)
grep -q "installed by commit-gate" "$TMPROOT/sharedhooks/pre-commit" 2>/dev/null && ok || bad "hook not placed in core.hooksPath"

it "enable refuses a relative core.hooksPath, which worktrees would not share"
R5=$(repo relhooks); git -C "$R5" config core.hooksPath .githooks
out=$(cd "$R5" && "$GATE" enable --tests "./check.sh" 2>&1); rc=$?
assert_eq 1 "$rc"
assert_has "core.hooksPath" "$out"
assert_eq "" "$(git -C "$R5" config commitgate.test)"

it "enable fails, and records nothing, when the hook cannot be written"
R6=$(repo unwritable); : > "$TMPROOT/notadir"; git -C "$R6" config core.hooksPath "$TMPROOT/notadir"
out=$(cd "$R6" && "$GATE" enable --tests "./check.sh" 2>&1); rc=$?
assert_eq 1 "$rc"
assert_eq "" "$(git -C "$R6" config commitgate.test)"

it "a missing commit-gate refuses the commit instead of skipping the check"
R7=$(repo missing); mkdir -p "$TMPROOT/g"; cp "$GATE" "$TMPROOT/g/commit-gate"
(cd "$R7" && "$TMPROOT/g/commit-gate" enable --tests "./check.sh" >/dev/null 2>&1)
rm -rf "$TMPROOT/g"
out=$(cd "$R7" && PATH=/usr/bin:/bin git -c user.name=t -c user.email=t@t commit -q --allow-empty -m "chore: gone" 2>&1); rc=$?
[ "$rc" != 0 ] && ok || bad "commit went through with commit-gate missing"
assert_has "commit-gate" "$out"

it "a moved checkout falls back to commit-gate on PATH and still gates"
R11=$(repo moved); mkdir -p "$TMPROOT/old" "$TMPROOT/newbin"; cp "$GATE" "$TMPROOT/old/commit-gate"
(cd "$R11" && "$TMPROOT/old/commit-gate" enable --tests "./check.sh" >/dev/null 2>&1)
rm -rf "$TMPROOT/old"; cp "$GATE" "$TMPROOT/newbin/commit-gate"
out=$(cd "$R11" && PATH="$TMPROOT/newbin:/usr/bin:/bin" git -c user.name=t -c user.email=t@t commit -q --allow-empty -m "chore: viapath" 2>&1); rc=$?
assert_eq 0 "$rc"
printf 'fail\n' > "$R11/status"
out=$(cd "$R11" && PATH="$TMPROOT/newbin:/usr/bin:/bin" git -c user.name=t -c user.email=t@t commit -q --allow-empty -m "chore: viapathfail" 2>&1); rc=$?
[ "$rc" != 0 ] && ok || bad "fallback commit-gate did not gate"

it "a checkout path with an apostrophe still produces a working hook"
R12=$(repo apostrophe); mkdir -p "$TMPROOT/Pat's tools"; cp "$GATE" "$TMPROOT/Pat's tools/commit-gate"
(cd "$R12" && "$TMPROOT/Pat's tools/commit-gate" enable --tests "./check.sh" >/dev/null 2>&1)
out=$(cd "$R12" && PATH=/usr/bin:/bin git -c user.name=t -c user.email=t@t commit -q --allow-empty -m "chore: quote" 2>&1); rc=$?
assert_eq 0 "$rc"
printf 'fail\n' > "$R12/status"
out=$(cd "$R12" && PATH=/usr/bin:/bin git -c user.name=t -c user.email=t@t commit -q --allow-empty -m "chore: quotefail" 2>&1); rc=$?
[ "$rc" != 0 ] && ok || bad "apostrophe path hook did not gate"

it "a file removed from the commit but left on disk refuses the commit"
R13=$(repo rmcached)
(cd "$R13" && "$GATE" enable --tests "sh check.sh" >/dev/null 2>&1)
printf 'x\n' > "$R13/required"; git -C "$R13" add check.sh status required
git -C "$R13" -c user.name=t -c user.email=t@t commit -q --no-verify -m base
git -C "$R13" rm -q --cached required
out=$(commit "$R13" dropreq); rc=$?
[ "$rc" != 0 ] && ok || bad "a staged deletion still on disk was committed unchecked"
assert_has "required" "$out"

it "a disabled repository under a shared hooks folder commits even when commit-gate is gone"
R14=$(repo disabledshared); mkdir -p "$TMPROOT/sh2" "$TMPROOT/g2"; cp "$GATE" "$TMPROOT/g2/commit-gate"
git -C "$R14" config core.hooksPath "$TMPROOT/sh2"
(cd "$R14" && "$TMPROOT/g2/commit-gate" enable --tests "./check.sh" >/dev/null 2>&1 && "$TMPROOT/g2/commit-gate" disable >/dev/null 2>&1)
rm -rf "$TMPROOT/g2"
out=$(cd "$R14" && PATH=/usr/bin:/bin git -c user.name=t -c user.email=t@t commit -q --allow-empty -m "chore: off" 2>&1); rc=$?
assert_eq 0 "$rc"

it "unstaged edits to tracked files refuse the commit, since tests would not see the commit"
R8=$(repo unstaged)
(cd "$R8" && "$GATE" enable --tests "sh check.sh" >/dev/null 2>&1)
git -C "$R8" add check.sh status; git -C "$R8" -c user.name=t -c user.email=t@t commit -q --no-verify -m base
printf '#!/bin/sh
exit 1
' > "$R8/check.sh"; git -C "$R8" add check.sh
printf '#!/bin/sh
exit 0
' > "$R8/check.sh"
out=$(commit "$R8" staged-fails); rc=$?
[ "$rc" != 0 ] && ok || bad "a staged failing script was committed"
assert_has "unstaged" "$out"
it "commit -a stages everything first, so it is checked normally"
printf '#!/bin/sh
exit 0
' > "$R8/check.sh"
out=$(git -C "$R8" -c user.name=t -c user.email=t@t commit -q -am "chore: all" 2>&1); rc=$?
assert_eq 0 "$rc"

it "enable is idempotent and status reports the state"
out=$(cd "$R" && "$GATE" enable --tests "./check.sh" 2>&1); rc=$?
assert_eq 0 "$rc"
out=$(cd "$R" && "$GATE" status 2>&1)
assert_has "./check.sh" "$out"
assert_has "enabled" "$out"

it "disable keeps a shared hook that another repository uses"
R9=$(repo shareda); R10=$(repo sharedb); mkdir -p "$TMPROOT/both"
git -C "$R9" config core.hooksPath "$TMPROOT/both"; git -C "$R10" config core.hooksPath "$TMPROOT/both"
(cd "$R9" && "$GATE" enable --tests "./check.sh" >/dev/null 2>&1); (cd "$R10" && "$GATE" enable --tests "./check.sh" >/dev/null 2>&1)
(cd "$R9" && "$GATE" disable >/dev/null 2>&1)
printf 'fail\n' > "$R10/status"
out=$(commit "$R10" stillgated); rc=$?
[ "$rc" != 0 ] && ok || bad "disabling one repo ungated the other"

it "disable removes only our hook and the command"
out=$(cd "$R" && "$GATE" disable 2>&1); rc=$?
assert_eq 0 "$rc"
[ ! -e "$R/.git/hooks/pre-commit" ] && ok || bad "hook still present"
assert_eq "" "$(git -C "$R" config commitgate.test)"
out=$(cd "$R3" && "$GATE" disable 2>&1)
[ -f "$R3/.git/hooks/pre-commit" ] && ok || bad "disable removed someone else's hook"

it "enable outside a repository fails"
out=$(cd "$TMPROOT" && "$GATE" enable --tests "true" 2>&1); rc=$?
assert_eq 1 "$rc"

it "enable --tests without a command fails with usage"
out=$(cd "$R" && "$GATE" enable --tests 2>&1); rc=$?
assert_eq 2 "$rc"

# ---- commit messages: conventional format and no attribution trailers ----
msgcommit() { git -C "$1" -c user.name=t -c user.email=t@t commit -q --allow-empty -F - 2>&1; }

it "enable installs a commit-msg hook too"
RM=$(repo msgs)
(cd "$RM" && "$GATE" enable >/dev/null 2>&1)
grep -q "installed by commit-gate" "$RM/.git/hooks/commit-msg" 2>/dev/null && ok || bad "no commit-msg hook"

it "enable without --tests turns on the message checks and no test command"
assert_eq "" "$(git -C "$RM" config commitgate.test)"

it "a conventional subject is accepted, with or without a scope or breaking mark"
for m in "feat: add shout" "fix(cli): handle empty name" "refactor!: drop python 2" "docs(readme): typo"; do
  out=$(printf '%s\n' "$m" | msgcommit "$RM"); rc=$?
  [ "$rc" = 0 ] && ok || bad "rejected [$m]: $out"
done

it "a non-conventional subject is refused and the message says what format is expected"
out=$(printf 'Add shout flag\n' | msgcommit "$RM"); rc=$?
[ "$rc" != 0 ] && ok || bad "accepted a non-conventional subject"
assert_has "feat" "$out"
out=$(printf 'feature: add shout\n' | msgcommit "$RM"); rc=$?
[ "$rc" != 0 ] && ok || bad "accepted an unknown type"
out=$(printf 'feat:add shout\n' | msgcommit "$RM"); rc=$?
[ "$rc" != 0 ] && ok || bad "accepted a subject with no space after the colon"

it "merge, revert and fixup subjects that git writes are accepted"
for m in "Merge branch 'x' into main" 'Revert "feat: add shout"' "fixup! feat: add shout" "squash! fix: thing"; do
  out=$(printf '%s\n' "$m" | msgcommit "$RM"); rc=$?
  [ "$rc" = 0 ] && ok || bad "rejected [$m]: $out"
done

it "comment lines git adds to the message are ignored"
out=$(printf '# Please enter the commit message\nfeat: add shout\n# comment\n' | msgcommit "$RM"); rc=$?
assert_eq 0 "$rc"

it "a Co-Authored-By trailer is refused, whatever its case or name"
out=$(printf 'feat: add shout\n\nCo-Authored-By: Claude <noreply@anthropic.com>\n' | msgcommit "$RM"); rc=$?
[ "$rc" != 0 ] && ok || bad "accepted a Co-Authored-By trailer"
assert_has "Co-Authored-By" "$out"
out=$(printf 'feat: add shout\n\nco-authored-by: A Person <a@b.c>\n' | msgcommit "$RM"); rc=$?
[ "$rc" != 0 ] && ok || bad "accepted a lower-case co-authored-by trailer"

it "other AI attribution lines are refused"
out=$(printf 'feat: add shout\n\n🤖 Generated with [Claude Code](https://claude.com/claude-code)\n' | msgcommit "$RM"); rc=$?
[ "$rc" != 0 ] && ok || bad "accepted a Generated with Claude Code line"
out=$(printf 'feat: add shout\n\nClaude-Session: https://claude.ai/code/x\n' | msgcommit "$RM"); rc=$?
[ "$rc" != 0 ] && ok || bad "accepted a Claude-Session trailer"

it "a body that only mentions co-authorship in prose is accepted"
out=$(printf 'docs: explain the commit gate\n\nThe gate refuses Co-Authored-By trailers in messages.\n' | msgcommit "$RM"); rc=$?
assert_eq 0 "$rc"

it "each message check can be turned off on its own"
git -C "$RM" config commitgate.conventional false
out=$(printf 'Add shout flag\n' | msgcommit "$RM"); rc=$?
assert_eq 0 "$rc"
out=$(printf 'Add shout flag\n\nCo-Authored-By: X <x@y.z>\n' | msgcommit "$RM"); rc=$?
[ "$rc" != 0 ] && ok || bad "attribution check stopped working when conventional was turned off"
git -C "$RM" config commitgate.conventional true; git -C "$RM" config commitgate.attribution false
out=$(printf 'feat: add shout\n\nCo-Authored-By: X <x@y.z>\n' | msgcommit "$RM"); rc=$?
assert_eq 0 "$rc"
git -C "$RM" config commitgate.attribution true

# ---- staged files: no attribution lines added to docs or code ----
it "a staged file adding a Co-Authored-By line is refused and named"
printf '# Notes\n\nCo-Authored-By: Claude <noreply@anthropic.com>\n' > "$RM/NOTES.md"; git -C "$RM" add NOTES.md
out=$(printf 'docs: add notes\n' | msgcommit "$RM"); rc=$?
[ "$rc" != 0 ] && ok || bad "a staged attribution line was committed"
assert_has "NOTES.md" "$out"
it "a staged Generated-with-Claude-Code footer is refused"
printf '# Notes\n\n🤖 Generated with [Claude Code](https://claude.com/claude-code)\n' > "$RM/NOTES.md"; git -C "$RM" add NOTES.md
out=$(printf 'docs: add notes\n' | msgcommit "$RM"); rc=$?
[ "$rc" != 0 ] && ok || bad "a staged Generated with footer was committed"
it "prose that mentions the trailer inside a sentence is accepted"
printf '# Notes\n\nThe gate refuses `Co-Authored-By:` trailers.\n' > "$RM/NOTES.md"; git -C "$RM" add NOTES.md
out=$(printf 'docs: add notes\n' | msgcommit "$RM"); rc=$?
assert_eq 0 "$rc"
it "prose that mentions a Generated-with line mid-sentence is accepted"
printf '# Notes\n\nThe gate refuses a Generated with Claude Code footer.\n' > "$RM/NOTES.md"; git -C "$RM" add NOTES.md
out=$(printf 'docs: add notes\n' | msgcommit "$RM"); rc=$?
assert_eq 0 "$rc"
it "a plain Generated-with footer without an emoji is refused"
printf '# Notes\n\nGenerated with Claude Code\n' > "$RM/NOTES.md"; git -C "$RM" add NOTES.md
out=$(printf 'docs: add notes\n' | msgcommit "$RM"); rc=$?
[ "$rc" != 0 ] && ok || bad "a plain Generated with footer was committed"
it "an attribution line already in the file, untouched by this commit, is not blamed"
printf 'Co-Authored-By: Old <o@l.d>\n' > "$RM/LEGACY.md"; git -C "$RM" add LEGACY.md
git -C "$RM" -c user.name=t -c user.email=t@t commit -q --no-verify -m "chore: legacy"
printf 'Co-Authored-By: Old <o@l.d>\nnew line\n' > "$RM/LEGACY.md"; git -C "$RM" add LEGACY.md
out=$(printf 'docs: extend legacy\n' | msgcommit "$RM"); rc=$?
assert_eq 0 "$rc"

it "disable removes the commit-msg hook as well"
(cd "$RM" && "$GATE" disable >/dev/null 2>&1)
[ ! -e "$RM/.git/hooks/commit-msg" ] && ok || bad "commit-msg hook still present"
out=$(printf 'Add whatever\n' | msgcommit "$RM"); rc=$?
assert_eq 0 "$rc"

printf 'passed=%d failed=%d\n' "$pass" "$fail"
[ "$fail" = 0 ]
