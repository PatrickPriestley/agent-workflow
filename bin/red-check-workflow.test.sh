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
it "report only: a verdict (exit 0 or 1) never fails the job; any other exit, or no JSON, does"
has "$w" 'if [ "$code" -gt 1 ] || ! jq -e . "$out/$name.json" >/dev/null 2>&1; then'
has "$w" 'exit "$worst"'
lacks "$w" '--strict|--require'
it "a file name or detail from the pull request cannot inject a workflow command or a table row"
printf '%s\n' "$w" | grep -qF 'gsub("[\\n\\r,:]"; "")' && ok || bad "annotation file name not sanitised"
printf '%s\n' "$w" | grep -qF 'def clean: gsub("[\\n\\r|`]"; " ");' && ok || bad "summary not sanitised"
printf '%s\n' "$w" | grep -qF '`\(.file | clean)` | \(.verdict) | \(.detail | clean) |' && ok || bad "file and detail not cleaned"

it "green files are annotated, and every verdict goes to the job summary"
has "$w" 'select(.verdict == "green")'
has "$w" '>> "$GITHUB_STEP_SUMMARY"'

# Run the step itself, as GitHub runs a "shell: bash" step (bash -e -o pipefail), with a
# stub in place of red-check that answers with a given exit code.
step="$(awk '/- name: red-check the changed tests/ {s=1} s && /^        run: \|/ {r=1; next}
  r && /^          / {print substr($0, 11); next} r && NF {exit}' "$wf")"
T="$(mktemp -d "${TMPDIR:-/tmp}/red-check-step.XXXXXX")"; trap 'rm -rf "$T"' EXIT
run_step() {  # EXIT_CODE JSON -> sets rc and log
  printf '#!/usr/bin/env bash\nprintf "%%s" %q\nexit %s\n' "$2" "$1" > "$T/stub"
  printf '%s\n' "$step" | sed "s|^rc=.*|rc=$T/stub|; s|^range=.*|range=a..b|" > "$T/step.sh"
  rm -rf "$T/rt"; mkdir -p "$T/rt"; : > "$T/summary"
  log="$(RUNNER_TEMP="$T/rt" GITHUB_STEP_SUMMARY="$T/summary" bash --noprofile --norc -e -o pipefail "$T/step.sh" 2>&1)"; rc=$?
}
green='{"status":"fail","summary":"1 green","files":[{"file":"bin/x.test.sh","verdict":"green","detail":"passes on the base"}]}'
it "the step's script was found in the workflow"; [ -n "$step" ] && ok || bad "no run: block for the red-check step"
it "under bash -e, a green verdict (red-check exit 1) is reported, not a failed job"
run_step 1 "$green"
[ "$rc" -eq 0 ] && ok || bad "step exited $rc: $log"
printf '%s' "$log" | grep -qF '::warning file=bin/x.test.sh::' && ok || bad "no annotation: $log"
grep -qF '| bash | `bin/x.test.sh` | green |' "$T/summary" && ok || bad "no summary row"
it "under bash -e, all red (exit 0) passes"
run_step 0 '{"status":"pass","summary":"1 red","files":[{"file":"bin/x.test.sh","verdict":"red","detail":"fails on the base"}]}'
[ "$rc" -eq 0 ] && ok || bad "step exited $rc: $log"
it "a usage error (2) or a crash (127, no JSON) fails the step"
run_step 2 ''; [ "$rc" -eq 2 ] && ok || bad "usage error: step exited $rc"
run_step 127 ''; [ "$rc" -eq 2 ] && ok || bad "crash: step exited $rc"

echo "passed=$pass failed=$fail"
[ "$fail" -eq 0 ]
