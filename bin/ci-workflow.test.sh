#!/usr/bin/env bash
# Tests for .github/workflows/test.yml (record docs/changes/2026-11-14-ci-macos-cost.md). The
# workflow is read as text: which runners its two suites' jobs ask for and when, how a run is
# started, and which runs are cancelled. That GitHub evaluates it so is shown only by a run.
set -u
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
root="$(cd "$here/.." && pwd)"
pass=0; fail=0; CURRENT=""
it() { CURRENT="$1"; }
ok()  { pass=$((pass+1)); printf '  ok   %s\n' "$CURRENT"; }
bad() { fail=$((fail+1)); printf '  FAIL %s\n       %s\n' "$CURRENT" "$1"; }
assert_eq()  { [ "$1" = "$2" ] && ok || bad "expected [$1] got [$2]"; }
has() { printf '%s' "$1" | grep -qF -- "$2" && ok || bad "missing [$2]"; }

wf="$root/.github/workflows/test.yml"
w="$(grep -v '^ *#' "$wf" 2>/dev/null)"
# Linux alone on a pull request to a private repository; Linux and macOS on everything else.
OS="os: \${{ fromJSON(github.event_name == 'pull_request' && github.event.repository.private && '[\"ubuntu-latest\"]' || '[\"ubuntu-latest\",\"macos-latest\"]') }}"

it "the test and change-record jobs take their runners from one expression: macOS is left out of a pull request only where the repository is private"
assert_eq 2 "$(printf '%s\n' "$w" | grep -cF -- "$OS")"
it "no job names macOS in any other way, so none runs there whatever the event"
assert_eq 2 "$(printf '%s\n' "$w" | grep -c 'macos')"
it "the two lists in the expression are JSON: Linux, and Linux with macOS"
assert_eq '["ubuntu-latest"] ["ubuntu-latest", "macos-latest"]' "$(printf '%s\n' "$w" | grep -m1 -F 'fromJSON(' | python3 -c '
import json, re, sys
print(" ".join(json.dumps(json.loads(s)) for s in re.findall(r"\x27(\[[^\x27]*\])\x27", sys.stdin.read())))')"
it "both jobs still run every runner of the list, one failing or not"
assert_eq 2 "$(printf '%s\n' "$w" | grep -c 'fail-fast: false')"
assert_eq 2 "$(printf '%s\n' "$w" | grep -c 'runs-on: \${{ matrix.os }}')"
it "it runs on pull requests, on pushes to main, and when started by hand"
on="$(printf '%s\n' "$w" | sed -n '/^on:/,/^[a-z]/p')"
has "$on" "  pull_request:"; has "$on" "  push:"; has "$on" "    branches: [main]"; has "$on" "  workflow_dispatch:"
it "a pull request's run is cancelled by a newer one for the same pull request; a run on main never is"
has "$w" "  group: test-\${{ github.event.pull_request.number || github.ref }}"
has "$w" "  cancel-in-progress: \${{ github.event_name == 'pull_request' }}"
it "the jobs that only make sense on a pull request still run on nothing else"
assert_eq 2 "$(printf '%s\n' "$w" | grep -c "if: github.event_name == 'pull_request'")"
it "the Linux runner is given a box before the suites, so the review's boxed tests run there (record 2026-11-15-checkable-judges)"
box="$(printf '%s\n' "$w" | sed -n "/name: A box for the review's scripts (Linux)/,/name: red-check/p")"
has "$box" "if: \${{ runner.os == 'Linux' }}"; has "$box" "bubblewrap"; has "$box" "bwrap --unshare-all --ro-bind / / true"; has "$box" "::warning::"
it "this test runs in CI"
has "$w" "run: bash bin/ci-workflow.test.sh"

printf 'passed=%d failed=%d\n' "$pass" "$fail"
[ "$fail" -eq 0 ]
