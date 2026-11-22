#!/usr/bin/env bash
# Tests for bin/mutate, against a scratch repository whose test checks some of
# the changed lines and not others.
#   bash bin/mutate.test.sh
# The Python part needs mutmut 2.x (MUTMUT=/path/to/mutmut, or mutmut on
# PATH); without it only the "not run" report is checked.
set -u
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
M="$here/mutate"
pass=0; fail=0; CURRENT=""
it() { CURRENT="$1"; }
ok()  { pass=$((pass+1)); printf '  ok   %s\n' "$CURRENT"; }
bad() { fail=$((fail+1)); printf '  FAIL %s\n       %s\n' "$CURRENT" "$1"; }
assert_eq() { [ "$1" = "$2" ] && ok || bad "expected [$1] got [$2]"; }
has() { printf '%s' "$1" | grep -qF -- "$2" && ok || bad "missing [$2] in: $(printf '%s' "$1" | head -c 600)"; }

T=$(mktemp -d "${TMPDIR:-/tmp}/mutate-test.XXXXXX"); trap 'rm -rf "$T"' EXIT
repo="$T/repo"; mkdir -p "$repo" && cd "$repo" || exit 1
g() { git -c user.name=t -c user.email=t@t "$@"; }
git init -q -b main

cat > tool <<'EOF'
#!/usr/bin/env bash
n="${1:-}"
echo small
EOF
cat > tool.test.sh <<'EOF'
#!/usr/bin/env bash
# Checks the usage guard and the first line of output; never the "negative" line.
here="$(cd "$(dirname "$0")" && pwd)"
[ "$(bash "$here/tool" 11 | head -n1)" = big ] || { echo "FAIL 11"; exit 1; }
[ "$(bash "$here/tool" 3 | head -n1)" = small ] || { echo "FAIL 3"; exit 1; }
err=$(bash "$here/tool" 2>&1 >/dev/null); rc=$?
[ "$rc" -eq 2 ] && [ "$err" = "usage: tool N" ] || { echo "FAIL empty: $rc $err"; exit 1; }
echo ok
EOF
printf '#!/usr/bin/env bash\necho one\n' > untested.sh
printf '#!/usr/bin/env bash\necho broken\n' > broken
printf '#!/usr/bin/env bash\nexit 1\n' > broken.test.sh
printf 'def clamp(n):\n    return max(0, n)\n' > calc.py
cat > calc.test.sh <<'EOF'
#!/usr/bin/env bash
r=$(python3 -c 'import calc; print(calc.clamp(-3), calc.clamp(5))')
[ "$r" = "0 5" ] || { echo "FAIL got $r"; exit 1; }
EOF
printf '# glob command\ncalc.py bash calc.test.sh\n' > .mutate-tests
g add -A && g commit -qm base

cat > tool <<'EOF'
#!/usr/bin/env bash
n="${1:-}"
[ -n "$n" ] || { echo "usage: tool N" >&2; exit 2; }
if [ "$n" -gt 10 ]; then echo big; else echo small; fi
[ "$n" -lt 0 ] && echo negative
EOF
printf '#!/usr/bin/env bash\necho two\n' > untested.sh
printf '#!/usr/bin/env bash\necho still broken\n' > broken
printf '# Head version: the usage message is part of the contract.\n' >> tool.test.sh
printf 'def clamp(n, hi=10):\n    if n > hi:\n        return hi\n    return max(0, n)\n' > calc.py
g commit -qam head
base=$(git rev-parse HEAD~1)

nomm_path() { local d out=""; IFS=:; for d in $PATH; do [ -x "$d/mutmut" ] || out="${out:+$out:}$d"; done; unset IFS; printf '%s' "$out"; }

echo "1. shell: tested lines are killed, the untested line survives"
out=$(MUTMUT= PATH="$(nomm_path)" "$M" "$base..HEAD" 2>&1); rc=$?
it "exit 0 without --strict, even with survivors"; assert_eq 0 "$rc"
it "the untested line 5 has a surviving mutant"; has "$out" "tool:5  -lt -> -ge"
it "and the survivor is shown with its code"; has "$out" "SURVIVED  [[ \"\$n\" -ge 0 ] && echo negative]"
it "nothing on the tested lines 3 and 4 survives"
printf '%s\n' "$out" | grep -E '^  tool:(3|4) ' | grep -q SURVIVED && bad "a mutant of line 3 or 4 survived: $out" || ok
it "the guard on line 3 is deleted and killed"; has "$out" "tool:3  delete guard                 killed"
it "a script with no test beside it is reported, not mutated"; has "$out" "untested.sh: no test"
it "a file whose test fails on the head is not mutated"; has "$out" "broken: baseline fails"
it "the test files themselves are not mutated"
printf '%s\n' "$out" | grep -q 'tool.test.sh:' && bad "a test file was mutated" || ok
it "without mutmut, Python files are reported not run"; has "$out" "calc.py: not run"

echo "2. the repository is left as it was"
it "working tree clean"; assert_eq "" "$(git status --porcelain)"
it "no worktree left behind"; assert_eq 1 "$(git worktree list | wc -l | tr -d ' ')"

echo "3. --json and --strict"
js=$(MUTMUT= PATH="$(nomm_path)" "$M" "$base..HEAD" --json 2>/dev/null)
it "one JSON document with status fail and counted survivors"
assert_eq "fail" "$(printf '%s' "$js" | python3 -c 'import json,sys; print(json.load(sys.stdin)["status"])')"
it "the JSON survivors are all on line 5"
printf '%s' "$js" | python3 -c '
import json,sys
d=json.load(sys.stdin)
bad=[m for f in d["files"] for m in f["mutants"] if m["result"]=="survived" and f["file"]=="tool" and m["line"]!=5]
sys.exit(1 if bad or d["counts"]["survived"]<1 else 0)' && ok || bad "survivors outside line 5, or none: $js"
it "--strict exits 1 when a mutant survives"
MUTMUT= PATH="$(nomm_path)" "$M" "$base..HEAD" --strict >/dev/null 2>&1; assert_eq 1 "$?"

echo "4. limits and usage"
out=$(MUTMUT= PATH="$(nomm_path)" "$M" "$base..HEAD" --max 2 2>&1)
it "--max stops after that many mutants and says so"; has "$out" "(stopped at --max 2 mutants)"
it "a bad range is a usage error"
"$M" "a...b" >/dev/null 2>&1; assert_eq 2 "$?"
it "an unknown option is a usage error"
"$M" --nope >/dev/null 2>&1; assert_eq 2 "$?"

echo "5. Python through mutmut"
mm="${MUTMUT:-$(command -v mutmut || true)}"
if [ -n "$mm" ] && "$mm" --help >/dev/null 2>&1; then
  out=$(MUTMUT="$mm" "$M" "$base..HEAD" 2>&1)
  it "the untested hi parameter survives mutmut"; has "$out" "calc.py: tested by bash calc.test.sh"
  printf '%s\n' "$out" | grep -E '^  calc.py:' | grep -q SURVIVED && ok || bad "no surviving calc.py mutant: $out"
  it "working tree still clean after mutmut"; assert_eq "" "$(git status --porcelain)"
  out=$(MUTMUT="$mm" "$M" "$base..HEAD" --py-lines 2 2>&1)
  it "a Python file with more changed lines than --py-lines is not mutated"
  has "$out" "calc.py: too large (3 changed lines, above --py-lines 2)"
else
  echo "  skip mutmut not installed: set MUTMUT or put mutmut 2.x on PATH"
fi

echo "6. a for list, a guard whose deletion does not parse, fixtures, hangs and HOME"
cd "$repo" || exit 1
printf '#!/usr/bin/env bash\nfor f in a b; do echo "$f"; done\n' > loop
printf '#!/usr/bin/env bash\nhere="$(cd "$(dirname "$0")" && pwd)"\n[ "$(bash "$here/loop" | tr "\\n" " ")" = "a b " ] || exit 1\n' > loop.test.sh
g add -A && g commit -qm "loop: fully tested"
clean=$(git rev-parse HEAD)
it "--strict exits 0 when every mutant is killed"
MUTMUT= PATH="$(nomm_path)" "$M" "$clean~1..$clean" --strict > "$T/strict.txt" 2>&1; assert_eq 0 "$?"
it "dropping each item from a for list is a mutant, and the test kills it"
has "$(cat "$T/strict.txt")" "loop:2  drop 'a' from list           killed"
cat > guard <<'EOF2'
#!/usr/bin/env bash
[ -n "${1:-}" ] || {
  echo "usage: guard X" >&2; exit 2; }
echo "$1"
EOF2
printf '#!/usr/bin/env bash\nhere="$(cd "$(dirname "$0")" && pwd)"\n[ "$(bash "$here/guard" x)" = x ] || exit 1\nbash "$here/guard" 2>/dev/null; [ $? -eq 2 ] || exit 1\n' > guard.test.sh
cat > sleeper <<'EOF2'
#!/usr/bin/env bash
[ "${1:-}" = go ] || exit 0
sleep 30
EOF2
printf '#!/usr/bin/env bash\nhere="$(cd "$(dirname "$0")" && pwd)"\nbash "$here/sleeper" stop\n' > sleeper.test.sh
mkdir -p fixtures; printf '#!/usr/bin/env bash\necho fixture\n' > fixtures/f.sh; printf '#!/usr/bin/env bash\nexit 0\n' > fixtures/f.sh.test.sh
printf '#!/usr/bin/env bash\ntrue && echo home\n' > homey
printf '#!/usr/bin/env bash\ntouch "$HOME/.mutate-probe"\nexit 0\n' > homey.test.sh
g add -A && g commit -qm "guard, sleeper, fixtures, homey"
mkdir -p "$T/realhome"
start=$(date +%s)
out=$(HOME="$T/realhome" MUTMUT= PATH="$(nomm_path)" "$M" "HEAD~1..HEAD" --timeout 2 2>&1)
took=$(( $(date +%s) - start ))
it "a guard whose deletion leaves a dangling } is invalid, not survived"; has "$out" "guard:2  delete guard                 invalid"
it "a test that hangs through a child process is killed at --timeout"; has "$out" "sleeper:2  || -> &&                     timed out"
it "and the run does not wait for the child (took ${took}s)"; [ "$took" -lt 25 ] && ok || bad "took ${took}s"
it "files under fixtures/ are not mutated"
printf '%s\n' "$out" | grep -q 'fixtures/f.sh' && bad "fixtures/f.sh was mutated: $out" || ok
it "tests run with HOME in a scratch directory, not the caller's"
[ -e "$T/realhome/.mutate-probe" ] && bad "the test wrote to the real HOME" || ok
it "--deadline 0 starts no mutant and says so"
has "$(MUTMUT= PATH="$(nomm_path)" "$M" "HEAD~1..HEAD" --deadline 0 2>&1)" "(stopped at --deadline 0 seconds)"
it "--timeout, --max, --py-lines and --deadline need a number"
for o in --timeout --max --py-lines --deadline; do "$M" "$o" x >/dev/null 2>&1 || [ $? -ne 2 ] || continue; bad "$o x was accepted"; done; ok

echo; echo "passed=$pass failed=$fail"
[ "$fail" -eq 0 ]
