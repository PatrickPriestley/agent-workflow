#!/usr/bin/env bash
# Tests for .github/workflows/red-check.yml, read as text: when it runs, what it may
# do, which tests it checks, and that it reports without failing on a verdict.
set -u
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
root="$(cd "$here/.." && pwd)"
pass=0; fail=0; CURRENT=""
it() { CURRENT="$1"; }
ok()  { pass=$((pass+1)); printf '  ok   %s\n' "$CURRENT"; }
bad() { fail=$((fail+1)); printf '  FAIL %s\n       %s\n' "$CURRENT" "$1"; }
has() { printf '%s' "$1" | grep -qF -- "$2" && ok || bad "missing [$2]"; }
lacks() { printf '%s' "$1" | grep -qE -- "$2" && bad "unexpected [$2]" || ok; }

wf="$root/.github/workflows/red-check.yml"
w="$(grep -v '^ *#' "$wf" 2>/dev/null)"

it "the workflow exists"; [ -n "$w" ] && ok || bad "$wf missing"
it "it runs on pull requests only, never with secrets or a write token"
has "$w" "  pull_request:"; lacks "$w" 'pull_request_target|workflow_run|issue_comment|secrets\.'
has "$w" "  contents: read"; lacks "$w" ': *write'
has "$w" "persist-credentials: false"
it "it checks against the merge base with the pull request's base branch"
has "$w" 'range="$(git merge-base "origin/$BASE_REF" HEAD)..HEAD"'
has "$w" "fetch-depth: 0"
it "it checks bash tests with the FAIL marker, node:test files, and the Hegel properties"
has "$w" "check bash --run 'bash {files}' --match '**/*.test.sh' --red-pattern '^[[:space:]]*FAIL[[:space:]]'"
has "$w" "check node --run 'node --test {files}' --match '**/*.test.cjs' --match '**/*.test.js'"
has "$w" "check properties --run 'python3 -I {files}' --match 'properties/*.py'"
has "$w" "pip install 'hegeltest==0.5.1'"
it "report only: a verdict never fails the job, red-check failing to run does"
has "$w" '[ "$code" -eq 2 ] && { cat "$out/$name.err"; worst=2; }'
has "$w" 'exit "$worst"'
lacks "$w" '--strict|--require'
it "green files are annotated, and every verdict goes to the job summary"
has "$w" 'select(.verdict == "green")'
has "$w" '>> "$GITHUB_STEP_SUMMARY"'

echo "passed=$pass failed=$fail"
[ "$fail" -eq 0 ]
