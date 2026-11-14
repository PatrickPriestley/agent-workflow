#!/usr/bin/env bash
# selftest.sh: the checks' own red step (requirement R1 of record 2026-11-08-outcome-evals).
# For each task it builds the scaffold in a scratch repository, applies a deliberately naive
# implementation and expects every trap check to fail and every plain one to pass, then
# applies a reference implementation and expects every check to pass. A check that passes
# against anything, or fails against anything, shows here. It also holds each prompt to
# requirement R10. No agent and no model is run. Needs bash, git and python3.
set -u
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
tasks_dir="$here/../tasks"
# The real path, not a link to it: on macOS the temporary folder is /var/..., a link to /private/var/...,
# and git and python name the real one.
# a suite that cannot make its temporary folder must not go on: TMPROOT would be the folder it was started in
TMPROOT="$(mktemp -d)" && TMPROOT="$(cd "$TMPROOT" && pwd -P)" || { echo "cannot make a temporary folder" >&2; exit 1; }
trap 'rm -rf "$TMPROOT"' EXIT
pass=0; fail=0; CURRENT=""
it() { CURRENT="$1"; }
ok()  { pass=$((pass+1)); printf '  ok   %s\n' "$CURRENT"; }
bad() { fail=$((fail+1)); printf '  FAIL %s\n       %s\n' "$CURRENT" "$1"; }
assert_eq()  { [ "$1" = "$2" ] && ok || bad "expected [$1] got [$2]"; }
has()  { printf '%s' "$1" | grep -qF -- "$2" && ok || bad "missing [$2] in: $(printf '%s' "$1" | head -c 400)"; }
TASKS="names-file names-csv format-json repeat defect-whitespace"
suite() { (cd "$1" && python3 -B -m unittest discover -s tests -t . > /dev/null 2>&1); echo $?; }
# build TASK DIR: the task's scaffold as a repository in DIR
build() { mkdir -p "$2" && (cd "$2" && bash "$tasks_dir/$1/scaffold.sh") > /dev/null 2>&1; }
# expect TASK ARM LINES: one assertion a check. Against the naive arm a trap must fail and a
# plain check pass; against the reference every check must pass.
expect() {
  local where kind name verdict want
  while read -r where kind name verdict; do
    [ -n "$where" ] || continue
    want=pass; [ "$2" = naive ] && [ "$kind" = trap ] && want=fail
    it "$1: the $2 implementation: $where, $kind, $name: $want"
    assert_eq "$want" "$verdict"
  done <<< "$3"
}

echo "the five tasks, each against a naive and a reference implementation"
for t in $TASKS; do
  repo="$TMPROOT/$t"
  it "$t: the scaffold builds, is one commit, and its own suite passes"
  build "$t" "$repo"; assert_eq "0 1 0" "$? $(git -C "$repo" rev-list --count HEAD 2>/dev/null) $(suite "$repo")"
  it "$t: the scaffold's README holds the conventions the prompts leave out"
  has "$(cat "$repo/README.md" 2>/dev/null)" "exits with status 2"
  for arm in naive reference; do
    git -C "$repo" checkout -q -- . 2>/dev/null; git -C "$repo" clean -qfd 2>/dev/null
    it "$t: $arm.patch applies to the scaffold"
    (cd "$repo" && git apply "$here/$t/$arm.patch" 2>&1); assert_eq 0 "$?"
    lines="$(bash "$here/run-checks.sh" "$t" "$repo" 2>&1)"; rc=$?
    it "$t: the checks ran against the $arm implementation and printed only checks"
    assert_eq "0 0" "$rc $(printf '%s\n' "$lines" | grep -vcE '^(acceptance|probe) (trap|plain) [a-z0-9-]+ (pass|fail)$')"
    expect "$t" "$arm" "$lines"
    if [ "$arm" = naive ]; then
      it "$t: there is at least one trap and one plain check, so neither rule is empty"
      [ "$(printf '%s\n' "$lines" | grep -c ' trap ')" -ge 1 ] && [ "$(printf '%s\n' "$lines" | grep -c ' plain ')" -ge 1 ] && ok || bad "$(printf '%s' "$lines" | head -c 300)"
      it "$t: the naive implementation still passes the scaffold's own suite: it is plausible, not broken"
      assert_eq 0 "$(suite "$repo")"
    else
      it "$t: the reference implementation's own tests pass"
      assert_eq 0 "$(suite "$repo")"
    fi
    it "$t: the checks left nothing in the repository under test"
    assert_eq "" "$(git -C "$repo" status --porcelain --ignored | grep -v ' greet.py$' | grep -v ' tests/test_greet.py$')"
  done
done

echo "the prompts (R10)"
for t in $TASKS; do
  p="$(cat "$tasks_dir/$t/prompt.md" 2>/dev/null)"
  it "$t: the prompt names the record id to use"
  has "$p" "docs/changes/2026-11-14-$t.md"
  it "$t: the prompt says there is no remote"
  has "$p" "has no remote"
  it "$t: the prompt ends the work at a commit on a branch, with the PR body as the last message"
  has "$p" "committed on a branch"; has "$p" "as your last"
  it "$t: the prompt names the test command"
  has "$p" 'python3 -m unittest discover -s tests -t .'
  it "$t: the prompt spells out no trap: none of the words the hidden checks turn on"
  printf '%s' "$p" | grep -qiE 'status 2|exit|stderr|standard error|blank|byte order|BOM|trailing|negative|whitespace-only|traceback' && bad "the prompt gives a trap away" || ok
done

echo "run-checks.sh refuses what it cannot check"
it "an unknown task and a folder with no greet.py exit 2"
msg="$(bash "$here/run-checks.sh" no-such-task "$TMPROOT/names-file" 2>&1)"; a=$?
mkdir -p "$TMPROOT/empty"; bash "$here/run-checks.sh" names-file "$TMPROOT/empty" > /dev/null 2>&1; b=$?
bash "$here/run-checks.sh" > /dev/null 2>&1; c=$?
assert_eq "2 2 2" "$a $b $c"
has "$msg" "no checks for task 'no-such-task'"

it "a probes.sh that fails after a probe, one that prints no probe, and an acceptance file the runner refuses are each exit 2"
mkdir -p "$TMPROOT/checks/dies" "$TMPROOT/checks/mute" "$TMPROOT/checks/unmarked"
cp "$here/run-checks.sh" "$here/acceptance_runner.py" "$here/cli.py" "$here/probes.lib.sh" "$TMPROOT/checks/"
for d in dies mute; do cp "$here/repeat/acceptance.py" "$TMPROOT/checks/$d/"; done
printf 'echo "probe trap x pass"\nexit 1\n' > "$TMPROOT/checks/dies/probes.sh"; : > "$TMPROOT/checks/mute/probes.sh"
printf 'import cli\n\n\nclass X(cli.Case):\n    def test_other(self):\n        pass\n' > "$TMPROOT/checks/unmarked/acceptance.py"
printf 'echo "probe trap x pass"\n' > "$TMPROOT/checks/unmarked/probes.sh"
bash "$TMPROOT/checks/run-checks.sh" dies "$TMPROOT/names-file" > /dev/null 2>&1; a=$?
bash "$TMPROOT/checks/run-checks.sh" mute "$TMPROOT/names-file" > /dev/null 2>&1; b=$?
bash "$TMPROOT/checks/run-checks.sh" unmarked "$TMPROOT/names-file" > /dev/null 2>&1; c=$?
assert_eq "2 2 2" "$a $b $c"

echo "the two libraries the checks are written with"
# a program that answers as told: FAKE_OUT on standard output, FAKE_ERR on standard error, exit FAKE_RC
mkdir -p "$TMPROOT/fake"; printf 'import os, sys\nsys.stdout.write(os.environ.get("FAKE_OUT", ""))\nsys.stderr.write(os.environ.get("FAKE_ERR", ""))\nsys.exit(int(os.environ.get("FAKE_RC", "0")))\n' > "$TMPROOT/fake/greet.py"
cat > "$TMPROOT/fake/probes.sh" <<PROBES
. "$here/probes.lib.sh"
refuses trap refused 'bad-input' -- python3 -B greet.py
holds plain held -- python3 -B greet.py
PROBES
probe() { (cd "$TMPROOT/fake" && env "$@" bash probes.sh 2>&1 | tr '\n' ';'); }
it "refuses passes on status 2, a message that names the input and no traceback"
assert_eq "probe trap refused pass;probe plain held fail;" "$(probe FAKE_RC=2 FAKE_ERR='greet: cannot use bad-input')"
it "refuses fails on another status, though the message is right"
assert_eq "probe trap refused fail;probe plain held fail;" "$(probe FAKE_RC=1 FAKE_ERR='greet: cannot use bad-input')"
it "refuses fails on a message that does not name the input"
assert_eq "probe trap refused fail;probe plain held fail;" "$(probe FAKE_RC=2 FAKE_ERR='greet: something went wrong')"
it "refuses fails on a traceback, though the status and the input are right"
assert_eq "probe trap refused fail;probe plain held fail;" "$(probe FAKE_RC=2 FAKE_ERR='Traceback (most recent call last): bad-input')"
it "refuses reads standard error, not standard output"
assert_eq "probe trap refused fail;probe plain held fail;" "$(probe FAKE_RC=2 FAKE_OUT='bad-input')"
it "holds passes on status 0 only"
assert_eq "probe trap refused fail;probe plain held pass;" "$(probe FAKE_RC=0)"
it "an acceptance test fails on the right output with a wrong exit status"
out="$(cd "$TMPROOT/fake" && FAKE_OUT='Hello, Ana!
' FAKE_RC=3 python3 -B "$here/acceptance_runner.py" "$here/names-csv/acceptance.py" 2>&1 | grep ' one-name ')"
assert_eq "acceptance plain one-name fail" "$out"
out="$(cd "$TMPROOT/fake" && FAKE_OUT='Hello, Ana!
' python3 -B "$here/acceptance_runner.py" "$here/names-csv/acceptance.py" 2>&1 | grep ' one-name ')"
assert_eq "acceptance plain one-name pass" "$out"
it "the runner refuses a test that is neither trap nor plain, a file with no test and a file that does not load"
printf 'import cli\n\n\nclass X(cli.Case):\n    def test_other(self):\n        pass\n' > "$TMPROOT/unmarked.py"
printf 'import cli\n' > "$TMPROOT/none.py"; printf 'import nothing_of_that_name\n' > "$TMPROOT/broken.py"
r=""; for f in unmarked none broken; do (cd "$TMPROOT/fake" && python3 -B "$here/acceptance_runner.py" "$TMPROOT/$f.py" > /dev/null 2>&1); r="$r$?"; done
assert_eq 222 "$r"

echo "passed=$pass failed=$fail"; [ "$fail" -eq 0 ]
