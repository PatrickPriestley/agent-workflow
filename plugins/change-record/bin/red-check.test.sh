#!/usr/bin/env bash
# Tests for red-check: real git repositories built in a scratch directory, with a tiny
# shell "test runner". Needs bash, git and python3 (the --json cases parse the document).
set -u
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
RC="$here/red-check"
TMPROOT="$(mktemp -d)"; trap 'rm -rf "$TMPROOT"' EXIT
pass=0; fail=0; CURRENT=""
it() { CURRENT="$1"; }
ok()  { pass=$((pass+1)); printf '  ok   %s\n' "$CURRENT"; }
bad() { fail=$((fail+1)); printf '  FAIL %s\n       %s\n' "$CURRENT" "$1"; }
assert_eq()  { [ "$1" = "$2" ] && ok || bad "expected [$1] got [$2]"; }
has()  { printf '%s' "$1" | grep -qF -- "$2" && ok || bad "missing [$2] in: $(printf '%s' "$1" | head -c 600)"; }
lacks() { printf '%s' "$1" | grep -qF -- "$2" && bad "unexpected [$2] in: $(printf '%s' "$1" | head -c 600)" || ok; }

# The runner: `bash run-tests.sh FILE...` sources each file; a file "passes" when every
# `check` in it holds. `check WORD` passes when lib.txt contains WORD.
repo() {
  r="$TMPROOT/$1"; mkdir -p "$r/tests"; cd "$r" || exit 1
  git init -q -b main; git config user.email t@example.com; git config user.name t
  git config core.hooksPath /dev/null
  cat > run-tests.sh <<'SH'
rc=0
check() { grep -qx "$1" lib.txt || { echo "FAIL: $1 missing"; rc=1; }; }
for f in "$@"; do . "./$f"; done
exit $rc
SH
  printf 'hello\n' > lib.txt
  printf 'check hello\n' > tests/test_hello.sh
  git add -A; git commit -qm "feat: base"
  git checkout -qb feature
}
commit() { git add -A; git commit -qm "$1"; }
RUN='bash run-tests.sh {files}'

it "a new test that fails on the base and passes on the head is red"
repo red; printf 'check bye\n' > tests/test_bye.sh; printf 'bye\n' >> lib.txt; commit "feat: bye"
out="$(bash "$RC" --run "$RUN" 2>&1)"; rc=$?
assert_eq 0 "$rc"; has "$out" "red: tests/test_bye.sh"

it "a new test that already passes on the base fails the check and is named"
repo green; printf 'check hello\n' > tests/test_again.sh; printf 'bye\n' >> lib.txt; commit "feat: no proof"
out="$(bash "$RC" --run "$RUN" 2>&1)"; rc=$?
assert_eq 1 "$rc"; has "$out" "passes on the base commit: tests/test_again.sh"

it "each changed test file is judged on its own, and every one is reported"
repo mixed; printf 'check bye\n' > tests/test_bye.sh; printf 'check hello\n' > tests/test_again.sh
printf 'bye\n' >> lib.txt; commit "feat: mixed"
out="$(bash "$RC" --run "$RUN" 2>&1)"; rc=$?
assert_eq 1 "$rc"; has "$out" "red: tests/test_bye.sh"; has "$out" "passes on the base commit: tests/test_again.sh"

it "a modified test counts too, taken at the head's version"
repo modified; printf 'check hello\ncheck bye\n' > tests/test_hello.sh; printf 'bye\n' >> lib.txt; commit "feat: extend"
out="$(bash "$RC" --run "$RUN" 2>&1)"; rc=$?
assert_eq 0 "$rc"; has "$out" "red: tests/test_hello.sh"

it "a deleted test is not run"
repo deleted; git rm -q tests/test_hello.sh; mkdir -p tests; printf 'check bye\n' > tests/test_bye.sh; printf 'bye\n' >> lib.txt; commit "feat: swap"
out="$(bash "$RC" --run "$RUN" 2>&1)"; rc=$?
assert_eq 0 "$rc"; lacks "$out" "test_hello"

it "no changed test files: exit 0 with a notice, or exit 1 with --require"
repo none; printf 'bye\n' >> lib.txt; commit "feat: untested"
out="$(bash "$RC" --run "$RUN" 2>&1)"; rc=$?
assert_eq 0 "$rc"; has "$out" "no test files changed"
out="$(bash "$RC" --run "$RUN" --require 2>&1)"; rc=$?
assert_eq 1 "$rc"; has "$out" "no test files changed"

it "the working tree, HEAD and branch are untouched, and no worktree is left behind"
repo clean; printf 'check bye\n' > tests/test_bye.sh; printf 'bye\n' >> lib.txt; commit "feat: bye"
printf 'scratch\n' > scratch.txt; before="$(git status --porcelain; git rev-parse HEAD; git branch --show-current)"
bash "$RC" --run "$RUN" >/dev/null 2>&1
assert_eq "$before" "$(git status --porcelain; git rev-parse HEAD; git branch --show-current)"
assert_eq "" "$(git worktree list | sed 1d)"

it "the base checkout is restored between files, so a discovering runner judges each file alone"
# The runner ignores {files} and runs every test in tests/: if the first file's head version
# were left behind, its failure would make the second look red when it is green on the base.
repo restore; printf 'check bye\n' > tests/test_a.sh; printf 'check hello\n' > tests/test_b.sh; printf 'bye\n' >> lib.txt; commit "feat: two"
out="$(bash "$RC" --run 'true {files}; bash run-tests.sh tests/*.sh' 2>&1)"; rc=$?
assert_eq 1 "$rc"; has "$out" "red: tests/test_a.sh"; has "$out" "passes on the base commit: tests/test_b.sh"

it "a lone test that cannot run on the base is inconclusive, and a run that showed nothing fails"
repo inconclusive; printf '. ./helpers.sh\ncheck bye\n' > tests/test_bye.sh; printf 'check() { grep -qx "$1" lib.txt; }\n' > helpers.sh; printf 'bye\n' >> lib.txt; commit "feat: helper"
out="$(bash "$RC" --run "$RUN" 2>&1)"; rc=$?
assert_eq 1 "$rc"; has "$out" "inconclusive: tests/test_bye.sh"; has "$out" "could not run"; has "$out" "no changed test was shown to fail"
out="$(bash "$RC" --run "$RUN" --strict 2>&1)"; rc=$?
assert_eq 1 "$rc"; has "$out" "inconclusive: tests/test_bye.sh"

it "a failure with no recognised assertion marker is inconclusive, and --red-pattern names the runner's marker"
repo marker; printf 'echo BOOM; exit 3\n' > tests/test_boom.sh; printf 'bye\n' >> lib.txt; commit "feat: boom"
out="$(bash "$RC" --run "$RUN" 2>&1)"; rc=$?
assert_eq 1 "$rc"; has "$out" "inconclusive: tests/test_boom.sh"; has "$out" "--red-pattern"
out="$(bash "$RC" --run "$RUN" --red-pattern 'BOOM' 2>&1)"; rc=$?
assert_eq 0 "$rc"; has "$out" "red: tests/test_boom.sh"
git config redcheck.redPattern 'BOOM'
out="$(bash "$RC" --run "$RUN" 2>&1)"; has "$out" "red: tests/test_boom.sh"

it "a cannot-run marker wins over an assertion marker in the same output"
repo both; printf 'echo "FAIL: suite"; echo "ModuleNotFoundError: No module named x"; exit 1\n' > tests/test_mixed.sh; printf 'bye\n' >> lib.txt; commit "feat: mixed"
out="$(bash "$RC" --run "$RUN" 2>&1)"; has "$out" "inconclusive: tests/test_mixed.sh"

it "--json prints one JSON document with a verdict per file and an overall status"
repo json; printf 'check bye\n' > tests/test_bye.sh; printf 'check hello\n' > tests/test_again.sh; printf 'echo BOOM; exit 3\n' > tests/test_boom.sh
printf 'bye\n' >> lib.txt; commit "feat: json"
out="$(bash "$RC" --run "$RUN" --json 2>/dev/null)"; rc=$?
assert_eq 1 "$rc"
parsed="$(printf '%s' "$out" | python3 -c '
import json,sys; d=json.load(sys.stdin)
v={f["file"]:f["verdict"] for f in d["files"]}
print(d["check"], d["status"], v["tests/test_bye.sh"], v["tests/test_again.sh"], v["tests/test_boom.sh"], len(d["base"])>0)' 2>&1)"
assert_eq "red-check fail red green inconclusive True" "$parsed"
repo json2; printf 'bye\n' >> lib.txt; commit "feat: none"
out="$(bash "$RC" --run "$RUN" --json 2>/dev/null)"
assert_eq "skip" "$(printf '%s' "$out" | python3 -c 'import json,sys; print(json.load(sys.stdin)["status"])')"
repo json3; printf 'echo BOOM; exit 3\n' > tests/test_boom.sh; printf 'check bye\n' > tests/test_bye.sh; printf 'bye\n' >> lib.txt; commit "feat: warn"
out="$(bash "$RC" --run "$RUN" --json 2>/dev/null)"; rc=$?; assert_eq 0 "$rc"
assert_eq "warn" "$(printf '%s' "$out" | python3 -c 'import json,sys; print(json.load(sys.stdin)["status"])')"
repo json4; printf 'echo BOOM; exit 3\n' > tests/test_boom.sh; printf 'bye\n' >> lib.txt; commit "feat: vacuous"
out="$(bash "$RC" --run "$RUN" --json 2>/dev/null)"; rc=$?; assert_eq 1 "$rc"
assert_eq "fail" "$(printf '%s' "$out" | python3 -c 'import json,sys; print(json.load(sys.stdin)["status"])')"

it "a modified test that already fails on the base before the change is inconclusive, not red"
repo prefail; git checkout -q main; printf 'check nothere\n' > tests/test_flaky.sh; commit "test: already failing"; git checkout -q feature; git merge -q main
printf 'check nothere\ncheck bye\n' > tests/test_flaky.sh; printf 'bye\n' >> lib.txt; commit "feat: extend a failing test"
out="$(bash "$RC" --run "$RUN" 2>&1)"; rc=$?
assert_eq 1 "$rc"; has "$out" "inconclusive: tests/test_flaky.sh"; has "$out" "already fails on the base"

it "with a discovering runner, a pre-existing failure elsewhere does not make a modified green test red"
repo discover; git checkout -q main; printf 'check nothere\n' > tests/test_other.sh; commit "test: already failing"; git checkout -q feature; git merge -q main
printf 'check hello\ncheck hello\n' > tests/test_hello.sh; printf 'bye\n' >> lib.txt; commit "feat: no proof"
out="$(bash "$RC" --run 'true {files}; bash run-tests.sh tests/*.sh' 2>&1)"; rc=$?
lacks "$out" "red: tests/test_hello.sh"; has "$out" "inconclusive: tests/test_hello.sh"

it "a file name with a newline cannot inject a workflow command into --github annotations"
repo inject; printf 'check hello\n' > "tests/test_a
::error::forged.sh"; printf 'bye\n' >> lib.txt; commit "feat: odd name"
out="$(bash "$RC" --run "$RUN" --github 2>&1)"
if printf '%s\n' "$out" | grep -qE '^::error::forged'; then bad "a line starts with the forged command"; else ok; fi
has "$out" "::error file=tests/test_a::error::forged.sh::"

it "--json and --github together are a usage error, since both want stdout"
repo both; printf 'bye\n' >> lib.txt; commit "feat: x"
out="$(bash "$RC" --run "$RUN" --json --github 2>&1)"; rc=$?; assert_eq 2 "$rc"; has "$out" "--json and --github"

it "with a discovering runner, a pre-existing failure elsewhere does not make a NEW green test red either"
repo discovernew; git checkout -q main; printf 'check nothere\n' > tests/test_other.sh; commit "test: already failing"; git checkout -q feature; git merge -q main
printf 'check hello\n' > tests/test_newgreen.sh; printf 'bye\n' >> lib.txt; commit "feat: new test proves nothing"
out="$(bash "$RC" --run 'true {files}; bash run-tests.sh tests/*.sh' 2>&1)"; rc=$?
lacks "$out" "red: tests/test_newgreen.sh"; has "$out" "inconclusive: tests/test_newgreen.sh"; has "$out" "already has failing assertions"

it "a named-file runner that errors on a missing file does not make a new red test inconclusive"
repo namednew; printf 'check bye\n' > tests/test_bye.sh; printf 'bye\n' >> lib.txt; commit "feat: bye"
out="$(bash "$RC" --run 'test -f {files} || { echo "ERROR: file or directory not found: {files}"; exit 4; }; bash run-tests.sh {files}' 2>&1)"; rc=$?
assert_eq 0 "$rc"; has "$out" "red: tests/test_bye.sh"

it "a run where every changed test is inconclusive fails: nothing was shown, even without --strict"
repo vacuous; printf 'echo BOOM; exit 3\n' > tests/test_a.sh; printf 'echo "ModuleNotFoundError: No module named x"; exit 1\n' > tests/test_b.sh; printf 'bye\n' >> lib.txt; commit "feat: nothing shown"
out="$(bash "$RC" --run "$RUN" 2>&1)"; rc=$?
assert_eq 1 "$rc"; has "$out" "no changed test was shown to fail"
# One red among inconclusive files is evidence, so that run passes with warnings.
printf 'check bye\n' > tests/test_c.sh; commit "test: one real red"
out="$(bash "$RC" --run "$RUN" 2>&1)"; rc=$?
assert_eq 0 "$rc"; has "$out" "red: tests/test_c.sh"; has "$out" "2 inconclusive"

it "a file under tests/ that holds no tests (a conftest, a helper) is 'no tests', never inconclusive"
repo helper; printf 'echo "collected 0 items"; echo "no tests ran"; exit 5\n' > tests/conftest.sh; printf 'check bye\n' > tests/test_bye.sh; printf 'bye\n' >> lib.txt; commit "feat: helper and test"
out="$(bash "$RC" --run "$RUN" --strict 2>&1)"; rc=$?
assert_eq 0 "$rc"; has "$out" "no tests: tests/conftest.sh"; has "$out" "red: tests/test_bye.sh"; lacks "$out" "inconclusive"
repo helperonly; printf 'echo "no tests ran"; exit 5\n' > tests/conftest.sh; printf 'bye\n' >> lib.txt; commit "feat: helper only"
out="$(bash "$RC" --run "$RUN" 2>&1)"; rc=$?
assert_eq 0 "$rc"; has "$out" "no test files changed"
out="$(bash "$RC" --run "$RUN" --require 2>&1)"; rc=$?
assert_eq 1 "$rc"; has "$out" "no test files changed"

it "a helper that already existed on the base is 'no tests' too, whether its runner exits 5 or 0"
repo oldhelper; git checkout -q main; printf 'echo "no tests ran"; exit 5\n' > tests/conftest.sh; commit "test: helper"; git checkout -q feature; git merge -q main
printf 'echo "no tests ran"; echo helper v2; exit 5\n' > tests/conftest.sh; printf 'check bye\n' > tests/test_bye.sh; printf 'bye\n' >> lib.txt; commit "feat: touch helper"
out="$(bash "$RC" --run "$RUN" --strict 2>&1)"; rc=$?
assert_eq 0 "$rc"; has "$out" "no tests: tests/conftest.sh"; lacks "$out" "inconclusive"
repo oldhelper0; git checkout -q main; printf 'echo "No tests found"; exit 0\n' > tests/helpers.sh; commit "test: helper"; git checkout -q feature; git merge -q main
printf 'echo "No tests found"; echo v2; exit 0\n' > tests/helpers.sh; printf 'check bye\n' > tests/test_bye.sh; printf 'bye\n' >> lib.txt; commit "feat: touch helper"
out="$(bash "$RC" --run "$RUN" --strict 2>&1)"; rc=$?
assert_eq 0 "$rc"; has "$out" "no tests: tests/helpers.sh"; lacks "$out" "passes on the base"

it "a collection error that also says 'collected 0 items' is inconclusive, not 'no tests', so a lone one still fails"
repo collecterr; printf 'echo "collected 0 items / 1 error"; echo "ERROR collecting tests/test_new.sh"; echo "ModuleNotFoundError: No module named newmod"; exit 2\n' > tests/test_new.sh; printf 'bye\n' >> lib.txt; commit "feat: new module and test"
out="$(bash "$RC" --run "$RUN" 2>&1)"; rc=$?
assert_eq 1 "$rc"; has "$out" "inconclusive: tests/test_new.sh"; lacks "$out" "no tests:"; has "$out" "no changed test was shown to fail"

it "each defence against a false 'no tests' holds on its own: the anchored pytest marker, and cannot-run checked first"
repo anchor; printf 'echo "collected 0 items / 1 error"; echo "something else went wrong"; exit 2\n' > tests/test_new.sh; printf 'bye\n' >> lib.txt; commit "feat: collection error without a known marker"
out="$(bash "$RC" --run "$RUN" 2>&1)"; rc=$?
assert_eq 1 "$rc"; has "$out" "inconclusive: tests/test_new.sh"; lacks "$out" "no tests:"
repo order; printf 'echo "no tests ran"; echo "ImportError: cannot import name f"; exit 1\n' > tests/test_new.sh; printf 'bye\n' >> lib.txt; commit "feat: import error that also says no tests ran"
out="$(bash "$RC" --run "$RUN" 2>&1)"; rc=$?
assert_eq 1 "$rc"; has "$out" "inconclusive: tests/test_new.sh"; lacks "$out" "no tests:"

it "a helper on the base that the PR turns into a real test is judged by its head version"
repo converted; git checkout -q main; printf 'echo "no tests ran"; exit 5\n' > tests/test_utils.sh; commit "test: helpers only"; git checkout -q feature; git merge -q main
printf 'check bye\n' > tests/test_utils.sh; printf 'bye\n' >> lib.txt; commit "feat: real tests in the helper file"
out="$(bash "$RC" --run "$RUN" --strict 2>&1)"; rc=$?
assert_eq 0 "$rc"; has "$out" "red: tests/test_utils.sh"; lacks "$out" "no tests:"
repo convertedgreen; git checkout -q main; printf 'echo "no tests ran"; exit 5\n' > tests/test_utils.sh; commit "test: helpers only"; git checkout -q feature; git merge -q main
printf 'check hello\n' > tests/test_utils.sh; printf 'bye\n' >> lib.txt; commit "feat: a test that proves nothing"
out="$(bash "$RC" --run "$RUN" 2>&1)"; rc=$?
assert_eq 1 "$rc"; has "$out" "passes on the base commit: tests/test_utils.sh"

it "--match replaces the default patterns"
repo match; mkdir -p checks; printf 'check hello\n' > checks/c1.sh; printf 'bye\n' >> lib.txt; commit "feat: custom"
out="$(bash "$RC" --run "$RUN" 2>&1)"; rc=$?
assert_eq 0 "$rc"; has "$out" "no test files changed"                       # checks/ is not a default pattern
out="$(bash "$RC" --run "$RUN" --match 'checks/**' 2>&1)"; rc=$?
assert_eq 1 "$rc"; has "$out" "passes on the base commit: checks/c1.sh"

it "redcheck.run and redcheck.match come from git config when flags are absent"
repo config; mkdir -p checks; printf 'check bye\n' > checks/c1.sh; printf 'bye\n' >> lib.txt; commit "feat: cfg"
git config redcheck.run "$RUN"; git config redcheck.match 'checks/**'
out="$(bash "$RC" 2>&1)"; rc=$?
assert_eq 0 "$rc"; has "$out" "red: checks/c1.sh"

it "an explicit BASE..HEAD range is honoured"
repo range; printf 'check bye\n' > tests/test_bye.sh; printf 'bye\n' >> lib.txt; commit "feat: bye"
printf 'check hello\n' > tests/test_again.sh; commit "test: redundant"
out="$(bash "$RC" main..HEAD~1 --run "$RUN" 2>&1)"; rc=$?
assert_eq 0 "$rc"; lacks "$out" "test_again"

it "--link puts an untracked directory from the working tree into the base checkout"
repo link; mkdir -p node_modules; printf 'linked\n' > node_modules/marker.txt; printf 'node_modules\n' > .gitignore
printf 'check bye\n' > tests/test_bye.sh; printf 'bye\n' >> lib.txt; commit "feat: bye"
out="$(bash "$RC" --run 'test -f node_modules/marker.txt || exit 0; bash run-tests.sh {files}' --link node_modules 2>&1)"; rc=$?
assert_eq 0 "$rc"; has "$out" "red: tests/test_bye.sh"                     # without the link the runner would exit 0 (green)

it "--link refuses a tracked directory, which would let runs write into the real tree"
repo linktracked; printf 'check bye\n' > tests/test_bye.sh; printf 'bye\n' >> lib.txt; commit "feat: bye"
out="$(bash "$RC" --run "$RUN" --link tests 2>&1)"; rc=$?
assert_eq 2 "$rc"; has "$out" "tracked"
assert_eq "" "$(git status --porcelain)"

it "--github writes an error annotation for a test that is green on the base"
repo gh; printf 'check hello\n' > tests/test_again.sh; printf 'bye\n' >> lib.txt; commit "feat: no proof"
out="$(bash "$RC" --run "$RUN" --github 2>&1)"
has "$out" "::error file=tests/test_again.sh::"

it "usage errors: no --run, a bad range, an unknown option"
repo usage; printf 'bye\n' >> lib.txt; commit "feat: x"
out="$(bash "$RC" 2>&1)"; rc=$?; assert_eq 2 "$rc"; has "$out" "--run"
out="$(bash "$RC" --run "$RUN" nope..HEAD 2>&1)"; rc=$?; assert_eq 2 "$rc"; has "$out" "unknown base"
out="$(bash "$RC" --run "$RUN" --bogus 2>&1)"; rc=$?; assert_eq 2 "$rc"

printf 'passed=%d failed=%d\n' "$pass" "$fail"
[ "$fail" -eq 0 ]
