#!/usr/bin/env bash
# Tests for pre-commit-green-phase.sh. Run: bash test-pre-commit-green-phase.sh
set -u
hook="$(cd "$(dirname "$0")" && pwd)/pre-commit-green-phase.sh"
fail=0; ok() { echo "ok   $1"; }; bad() { echo "FAIL $1"; fail=1; }
repo=$(mktemp -d); trap 'rm -rf "$repo"' EXIT
cd "$repo" && git init -q && git config user.name t && git config user.email t@t
[ -f "$hook" ] && cp "$hook" .git/hooks/pre-commit && chmod +x .git/hooks/pre-commit
mkdir -p src test && echo 1 > test/a.test.ts && echo 1 > src/a.ts
git add -A && git -c commit.gpgsign=false commit -qm red >/dev/null 2>&1

echo 0 > src/a.ts && git add src/a.ts
if git -c commit.gpgsign=false commit -qm no-marker >/dev/null 2>err && [ ! -s err ]; then ok "outside green, commits pass silently"
else bad "outside green, commits pass silently ($(cat err))"; fi
echo test/a.test.ts > .git/green-phase

echo 2 > test/a.test.ts && git add test/a.test.ts
if git -c commit.gpgsign=false commit -qm green-edits-test >/dev/null 2>err; then bad "rejects a commit touching a listed test during green"
else grep -q "test/a.test.ts" err && ok "rejects a commit touching a listed test during green" || bad "rejection names the file"; fi
git reset -q --hard

echo 2 > src/a.ts && git add src/a.ts
git -c commit.gpgsign=false commit -qm green-impl >/dev/null 2>&1 && ok "allows implementation commits during green" || bad "allows implementation commits during green"

# expect_reject <name> <path the reason must name>: commit what is staged; it must fail
expect_reject() {
  if git -c commit.gpgsign=false commit -qm "$1" >/dev/null 2>err; then bad "$1"; git reset -q --hard HEAD~1  # undo the wrongly allowed commit
  elif grep -qF -- "$2" err; then ok "$1"; else bad "$1: reason does not name $2 ($(cat err))"; fi
  git reset -q --hard
}
git mv test/a.test.ts test/renamed.test.ts;            expect_reject "rejects renaming a protected test" "test/a.test.ts"
git rm -q test/a.test.ts;                              expect_reject "rejects deleting a protected test" "test/a.test.ts"
chmod +x test/a.test.ts && git add test/a.test.ts;     expect_reject "rejects a mode change to a protected test" "test/a.test.ts"

printf 'x\n' > "test/my spec.test.ts"; printf 'x\n' > "test/é.test.ts"; printf 'x\n' > "$(printf 'test/tab\tname.test.ts')"
rm .git/green-phase; git add -A && git -c commit.gpgsign=false commit -qm more-tests >/dev/null 2>&1
printf 'test/my spec.test.ts\ntest/é.test.ts\n%s\n' "$(printf 'test/tab\tname.test.ts')" > .git/green-phase
echo y >> "test/my spec.test.ts" && git add -A;        expect_reject "rejects a protected path containing a space" "my spec"
echo y >> "test/é.test.ts" && git add -A;              expect_reject "rejects a protected non-ASCII path (git quotes it)" "é.test.ts"
echo y >> "$(printf 'test/tab\tname.test.ts')" && git add -A; expect_reject "rejects a protected path containing a tab" "name.test.ts"

: > .git/green-phase
echo 5 > src/a.ts && git add src/a.ts;                 expect_reject "an empty active marker fails closed" "green-phase"
echo test/a.test.ts > .git/green-phase; chmod 000 .git/green-phase
echo 6 > src/a.ts && git add src/a.ts;                 expect_reject "an unreadable marker fails closed" "green-phase"
chmod 644 .git/green-phase

# A git failure while listing staged paths must reject, not read as "nothing staged".
# Git puts its exec-path (which holds a git binary) first on PATH for hooks, so a fake
# git cannot intercept a real commit's hook: run the hook directly for this guard.
fake=$(mktemp -d); real_git=$(command -v git)
printf '#!/bin/sh\ncase "$*" in *"diff --cached"*) echo "fatal: simulated" >&2; exit 128;; esac\nexec "%s" "$@"\n' "$real_git" > "$fake/git"; chmod +x "$fake/git"
if PATH="$fake:$PATH" .git/hooks/pre-commit >/dev/null 2>err; then bad "a git error fails closed"
elif grep -q "could not list staged paths" err; then ok "a git error fails closed"; else bad "a git error fails closed: $(cat err)"; fi
rm -rf "$fake"

rm .git/green-phase; echo 3 > test/a.test.ts && git add test/a.test.ts
git -c commit.gpgsign=false commit -qm after-green >/dev/null 2>&1 && ok "allows test edits once green-phase is removed" || bad "allows test edits once green-phase is removed"
exit $fail
