#!/usr/bin/env bash
# Tests for .github/workflows/probe-score.yml, read as text: who can start it, what it may do,
# where the PROBE_KEY secret goes, and that it checks the key before it trusts it.
set -u
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
root="$(cd "$here/.." && pwd)"
pass=0; fail=0; CURRENT=""
it() { CURRENT="$1"; }
ok()  { pass=$((pass+1)); printf '  ok   %s\n' "$CURRENT"; }
bad() { fail=$((fail+1)); printf '  FAIL %s\n       %s\n' "$CURRENT" "$1"; }
has() { printf '%s' "$1" | grep -qF -- "$2" && ok || bad "missing [$2]"; }
lacks() { printf '%s' "$1" | grep -qE -- "$2" && bad "unexpected [$2]" || ok; }

wf="$root/.github/workflows/probe-score.yml"
w="$(grep -v '^ *#' "$wf" 2>/dev/null)"
step() { printf '%s\n' "$w" | awk -v n="      - name: $1" 'index($0, n) == 1 {s=1; print; next} s && /^      - / {exit} s'; }

it "the workflow exists"; [ -n "$w" ] && ok || bad "$wf missing"
it "it is started by hand only"
on="$(printf '%s\n' "$w" | sed -n '/^on:/,/^[a-z]/p')"
has "$on" "workflow_dispatch:"; lacks "$on" 'pull_request|push:|schedule|workflow_run|issue_comment'
it "the token can read code and runs and write only pull request comments"
has "$w" "permissions: {}"; has "$w" "      contents: read"; has "$w" "      actions: read"
has "$w" "      pull-requests: write"; lacks "$w" 'contents: write|actions: write'
has "$w" "persist-credentials: false"
it "it checks out the default branch, never the probe's code"
lacks "$w" 'ref:|head\.sha|head_ref|pull/'
it "the inputs reach the scripts only through the environment, and are checked as numbers"
printf '%s\n' "$w" | sed -n '/^    steps:/,$p' | grep -F '${{ inputs.' | grep -vE 'name: probe-score-\$\{\{ inputs.pr \}\}|if: inputs.close' | grep -q . && bad "an input is interpolated into a step" || ok
has "$w" '[[ "$PR" =~ ^[0-9]+$ ]]'; has "$w" '[[ "$KEY_RUN" =~ ^[0-9]+$ ]]'
it "only a pull request labelled probe is scored or closed"
has "$(step 'Check the inputs, and that the pull request is a probe')" 'grep -qx probe'
it "PROBE_KEY reaches one step, the one that checks and opens the key"
assert_one="$(grep -c 'secrets.PROBE_KEY' "$wf")"; [ "$assert_one" -eq 1 ] && ok || bad "PROBE_KEY appears $assert_one times"
has "$(step 'Check the key against')" 'PROBE_KEY: ${{ secrets.PROBE_KEY }}'
it "the key is checked against the pull request's hash before it is opened"
s="$(step 'Check the key against')"
printf '%s\n' "$s" | grep -n 'probe-key check\|probe-key open' | cut -d: -f2- | tr -d ' ' | head -2 | tr '\n' ' ' | grep -q '^bashbin/probe-keycheck.*bashbin/probe-keyopen' && ok || bad "check does not come before open: $s"
has "$s" 'probe-key-sha256: \([0-9a-f]\{64\}\)'
it "evidence is read at the planted commit, and the scores are kept and posted"
has "$(step 'Collect the evidence')" '--sha "$sha"'
has "$w" 'bin/probe-score --markdown'; has "$w" 'retention-days: 90'; has "$w" 'gh pr comment "$PR"'
it "closing is optional and never deletes the branch"
has "$(step 'Close the probe')" 'if: inputs.close'; lacks "$w" 'delete-branch|git push'
it "this test runs in CI"
grep -qF 'bash bin/probe-score-workflow.test.sh' "$root/.github/workflows/test.yml" && ok || bad "not in test.yml"

echo; echo "passed=$pass failed=$fail"
[ "$fail" -eq 0 ]
