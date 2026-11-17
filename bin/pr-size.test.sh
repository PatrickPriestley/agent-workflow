#!/usr/bin/env bash
# Tests for pr-size: real git repositories built in a scratch directory.
set -u
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PS="$here/pr-size"
TMPROOT="$(mktemp -d)"; trap 'rm -rf "$TMPROOT"' EXIT
pass=0; fail=0; CURRENT=""
it() { CURRENT="$1"; }
ok()  { pass=$((pass+1)); printf '  ok   %s\n' "$CURRENT"; }
bad() { fail=$((fail+1)); printf '  FAIL %s\n       %s\n' "$CURRENT" "$1"; }
assert_eq()  { [ "$1" = "$2" ] && ok || bad "expected [$1] got [$2]"; }
has()  { printf '%s' "$1" | grep -qF -- "$2" && ok || bad "missing [$2] in: $(printf '%s' "$1" | head -c 500)"; }
lacks() { printf '%s' "$1" | grep -qF -- "$2" && bad "unexpected [$2] in: $(printf '%s' "$1" | head -c 500)" || ok; }

repo() {  # main with one commit; feature branch checked out; a later main commit
  r="$TMPROOT/$1"; mkdir -p "$r"; cd "$r" || exit 1
  git init -q -b main; git config user.email t@example.com; git config user.name t
  git config core.hooksPath /dev/null
  seq 1 50 > app.txt; seq 1 30 > old.txt; printf '\x00\x01' > logo.bin
  git add -A; git -c commit.gpgsign=false commit -qm "feat: base"
  git checkout -qb feature
}
lines() { seq 1 "$1"; }  # N lines of text
commit() { git add -A; git -c commit.gpgsign=false commit -qm "$1"; }
# main later drops 30 lines the branch still has: diffing from main's tip, not the merge base,
# would count them as added.
later_main() { git checkout -q main; lines 500 > main-only.txt; lines 20 > app.txt; commit "feat: later"; git checkout -q feature; }
count() { sed -n 's/^pr-size: \([0-9][0-9]*\) reviewable lines.*/\1/p' <<<"$1" | head -n1; }

it "counts added lines of a branch since its merge base, not main's later commits"
repo base; lines 20 >> app.txt; commit "feat: a"; later_main
out="$(bash "$PS" 2>&1)"; rc=$?
assert_eq 0 "$rc"; assert_eq 20 "$(count "$out")"

it "skips lockfiles, fixtures, captures, testdata and snapshots, and says how many"
repo gen; lines 10 >> app.txt
mkdir -p tests/fixtures api/captures pkg/testdata ui/__snapshots__ sub
lines 100 > tests/fixtures/f.json; lines 100 > api/captures/c.txt; lines 100 > pkg/testdata/t.txt
lines 100 > ui/__snapshots__/s.txt; lines 100 > ui/view.snap
for f in Cargo.lock package-lock.json yarn.lock pnpm-lock.yaml poetry.lock uv.lock Gemfile.lock go.sum composer.lock; do lines 10 > "sub/$f"; done
commit "feat: generated"
out="$(bash "$PS" 2>&1)"
assert_eq 10 "$(count "$out")"; has "$out" "590 more in generated files"

it "skips files marked linguist-generated, in both the set and =true forms"
repo attr; lines 7 >> app.txt; mkdir -p a b
lines 40 > a/x.js; lines 40 > b/y.js
printf 'a/** linguist-generated\nb/** linguist-generated=true\n' > .gitattributes
commit "feat: attrs"
assert_eq 9 "$(count "$(bash "$PS" 2>&1)")"   # app.txt 7 + .gitattributes 2

it "a pure rename and a binary file count nothing"
repo rename; git mv old.txt new.txt; printf '\x02\x03' >> logo.bin; commit "refactor: rename"
assert_eq 0 "$(count "$(bash "$PS" 2>&1)")"

it "prsize.exclude adds a repository's own globs"
repo own; lines 5 >> app.txt; mkdir -p docs/api; lines 300 > docs/api/ref.md; commit "docs: ref"
git config --add prsize.exclude 'docs/api/**'
assert_eq 5 "$(count "$(bash "$PS" 2>&1)")"

it "says the size is fine under the aim"
repo small; lines 100 >> app.txt; commit "feat: small"
out="$(bash "$PS" 2>&1)"
has "$out" "within the 400-line aim"; lacks "$out" "split"

it "says it is over the aim but may stay one pull request, between aim and stop"
repo mid; lines 600 >> app.txt; commit "feat: mid"
out="$(bash "$PS" 2>&1)"
has "$out" "over the 400-line aim"; lacks "$out" "split it"

it "says to split above the stop limit, and lists added lines per commit"
repo big; lines 700 >> app.txt; commit "feat: one"; lines 600 > two.txt; commit "feat: two"
out="$(bash "$PS" 2>&1)"; rc=$?
assert_eq 0 "$rc"
has "$out" "above the 1000-line stop: split it"
has "$out" "  700  feat: one"; has "$out" "  600  feat: two"

it "--fail exits 1 above the stop limit and 0 below it"
bash "$PS" --fail >/dev/null 2>&1; assert_eq 1 "$?"
cd "$TMPROOT/mid" && { bash "$PS" --fail >/dev/null 2>&1; assert_eq 0 "$?"; }

it "aim and stop come from git config, and flags override them"
cd "$TMPROOT/mid"; git config prsize.aim 1000; git config prsize.stop 2000
has "$(bash "$PS" 2>&1)" "within the 1000-line aim"
has "$(bash "$PS" --aim 50 --stop 100 2>&1)" "above the 100-line stop: split it"

it "prefers origin/main to a stale local main"
R="$TMPROOT/stale"; mkdir -p "$R"; cd "$R" || exit 1
git init -q --bare remote.git; git init -q -b main work; cd work
git config user.email t@example.com; git config user.name t; git config core.hooksPath /dev/null
lines 10 > app.txt; commit "feat: base"; git remote add origin ../remote.git; git push -q origin main 2>/dev/null
git checkout -qb other; lines 300 > merged.txt; commit "feat: merged elsewhere"; git push -q origin other:main 2>/dev/null
git checkout -q main; git fetch -q origin                    # local main stays at base
git checkout -qb feature origin/main; lines 25 > mine.txt; commit "feat: mine"
assert_eq 25 "$(count "$(bash "$PS" 2>&1)")"

it "an explicit BASE..HEAD range is used as given"
cd "$TMPROOT/big"; first="$(git rev-list --reverse main..feature | head -n1)"
assert_eq 600 "$(count "$(bash "$PS" "$first..feature" 2>&1)")"

it "--github writes a warning annotation above the aim and a step summary"
cd "$TMPROOT/big"; S="$TMPROOT/summary.md"; : > "$S"
out="$(GITHUB_STEP_SUMMARY="$S" bash "$PS" --github 2>&1)"
has "$out" "::warning title=PR size::1300 reviewable lines"
has "$(cat "$S")" "| 1300 |"
cd "$TMPROOT/small"; : > "$S"
out="$(GITHUB_STEP_SUMMARY="$S" bash "$PS" --github 2>&1)"
lacks "$out" "::warning"; has "$(cat "$S")" "| 100 |"

it "moving a file out of an excluded folder never reports a negative generated count"
repo moved; mkdir -p api/captures; lines 300 > api/captures/c.json; commit "test: capture"
git checkout -q main; git -c commit.gpgsign=false merge -q --ff-only feature; git checkout -q -B feature
mkdir -p docs; git mv api/captures/c.json docs/c.json; commit "docs: move capture"
S="$TMPROOT/moved-summary.md"
out="$(GITHUB_STEP_SUMMARY="$S" bash "$PS" --github main..feature 2>&1)"
lacks "$(cat "$S")" "| -"; lacks "$out" "(-"

it "rejects an unknown option, a bad range and a bad limit, each with its own message"
cd "$TMPROOT/small"
out="$(bash "$PS" --bogus 2>&1)"; assert_eq 2 "$?"; has "$out" "usage: pr-size"
out="$(bash "$PS" nope..feature 2>&1)"; assert_eq 2 "$?"; has "$out" "unknown base"
out="$(bash "$PS" feature 2>&1)"; assert_eq 2 "$?"; has "$out" "must look like BASE..HEAD"
out="$(bash "$PS" main...feature 2>&1)"; assert_eq 2 "$?"; has "$out" "two dots"
out="$(bash "$PS" --stop many 2>&1)"; assert_eq 2 "$?"; has "$out" "whole numbers"
out="$(bash "$PS" --aim 500 --stop 100 2>&1)"; assert_eq 2 "$?"; has "$out" "is above the stop limit"

it "fails outside a git repository, and says so"
cd "$TMPROOT"; out="$(bash "$PS" 2>&1)"; assert_eq 2 "$?"; has "$out" "not inside a git repository"

printf 'passed=%d failed=%d\n' "$pass" "$fail"
[ "$fail" = 0 ]
