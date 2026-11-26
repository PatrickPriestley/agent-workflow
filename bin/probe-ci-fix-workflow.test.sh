#!/usr/bin/env bash
# Tests for .github/workflows/probe-ci-fix.yml: when a held probe's test run fails (a loud
# probe), label it ci-fix, once, so CI fix starts after there is a failure to fix.
#   bash bin/probe-ci-fix-workflow.test.sh
set -u
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"; root="$(cd "$here/.." && pwd)"
wf="$root/.github/workflows/probe-ci-fix.yml"
pass=0; fail=0; CURRENT=""
it() { CURRENT="$1"; }
ok()  { pass=$((pass+1)); printf '  ok   %s\n' "$CURRENT"; }
bad() { fail=$((fail+1)); printf '  FAIL %s\n       %s\n' "$CURRENT" "$1"; }
assert_eq() { [ "$1" = "$2" ] && ok || bad "expected [$1] got [$2]"; }
has()   { printf '%s' "$1" | grep -qF -- "$2" && ok || bad "missing: $2"; }
lacks() { printf '%s' "$1" | grep -qE -- "$2" && bad "found: $2" || ok; }
w="$(grep -v '^ *#' "$wf" 2>/dev/null)"

it "it runs when a test run completes, and acts only on a failed pull request run"
has "$w" 'workflows: ["test"]'; has "$w" "types: [completed]"
has "$w" "github.event.workflow_run.conclusion == 'failure'"; has "$w" "github.event.workflow_run.event == 'pull_request'"
lacks "$w" "pull_request_target|issue_comment"
it "the built-in token only reads; the label is added with PROBE_TOKEN, in that step alone"
assert_eq "permissions:
  contents: read
  pull-requests: read
  issues: read" "$(printf '%s\n' "$w" | awk '/^permissions:/ {p=1; print; next} p && /^  / {print; next} p {exit}')"
assert_eq 1 "$(grep -c 'secrets\.' "$wf")"; has "$w" 'PROBE_TOKEN: ${{ secrets.PROBE_TOKEN }}'
lacks "$w" "actions/checkout"

script="$(awk '/- name: Label a held probe ci-fix, once/ {g=1; next}
  g && /^        run: \|/ {r=1; next} r && /^          / {print substr($0, 11); next} r && /^ *$/ {print ""; next} r {exit}' "$wf")"
it "the script takes nothing from the event directly, and runs in bash with pipefail"
[ -n "$script" ] && ok || bad "no script"; lacks "$script" '\$\{\{'
has "$(awk '/- name: Label a held probe ci-fix, once/ {g=1; print; next} g && /^      - / {exit} g' "$wf")" "shell: bash"

T="$(mktemp -d "${TMPDIR:-/tmp}/probe-ci-fix.XXXXXX")"; [ -n "${KEEP:-}" ] || trap 'rm -rf "$T"' EXIT
mkdir -p "$T/stub"
cat > "$T/stub/gh" <<'STUB'
#!/usr/bin/env bash
printf '%s|%s\n' "$GH_TOKEN" "$*" >> "$STUB_LOG"
case "$*" in
  "api repos/o/r/commits/"*"/pulls") printf '%s' "$STUB_PULLS" ;;
  "api repos/o/r/issues/"*"/events?per_page=100") printf '%s' "$STUB_EVENTS" ;;
  "pr edit "*) [ -z "${STUB_EDIT_FAILS:-}" ] ;;
  *) echo "stub gh: unexpected $*" >&2; exit 1 ;;
esac
STUB
chmod +x "$T/stub/gh"
SHA=0123456789abcdef0123456789abcdef01234567
held='[{"number": 77, "state": "open", "labels": [{"name": "hold"}, {"name": "verify"}]}]'
step() {  # -> $rc; gh calls in $T/gh.log, output in $T/out
  : > "$T/gh.log"; : > "$T/summary"
  env -i PATH="$T/stub:$PATH" STUB_LOG="$T/gh.log" STUB_PULLS="${PULLS-$held}" STUB_EVENTS="${EVENTS-[]}" \
    STUB_EDIT_FAILS="${EDITFAIL:-}" GH_TOKEN=builtin PROBE_TOKEN=probe-token HEAD_SHA="${HSHA-$SHA}" REPO=o/r \
    GITHUB_STEP_SUMMARY="$T/summary" bash --noprofile --norc -eo pipefail -c "$script" > "$T/out" 2>&1; rc=$?
}
edits() { grep '|pr edit' "$T/gh.log"; }
it "a held probe whose tests failed is labelled ci-fix, with PROBE_TOKEN, so CI fix starts"
step; assert_eq 0 "$rc"
assert_eq "probe-token|pr edit 77 --repo o/r --add-label ci-fix" "$(edits)"
grep -q "builtin|api repos/o/r/commits/$SHA/pulls" "$T/gh.log" && ok || bad "did not look up the commit's pull requests: $(cat "$T/gh.log")"
grep -q '#77' "$T/summary" && ok || bad "summary: $(cat "$T/summary")"
it "only once: a probe ever labelled ci-fix before is not labelled again"
EVENTS='[{"event": "labeled", "label": {"name": "verify"}}, {"event": "labeled", "label": {"name": "ci-fix"}}, {"event": "unlabeled", "label": {"name": "ci-fix"}}]' step
assert_eq "0 " "$rc $(edits)"; grep -q 'already' "$T/out" && ok || bad "$(cat "$T/out")"
it "a pull request that is not held, or is closed, is left alone"
PULLS='[{"number": 5, "state": "open", "labels": [{"name": "verify"}]}]' step; assert_eq "0 " "$rc $(edits)"
PULLS='[{"number": 77, "state": "closed", "labels": [{"name": "hold"}]}]' step; assert_eq "0 " "$rc $(edits)"
PULLS='[]' step; assert_eq "0 " "$rc $(edits)"
it "a pull request number GitHub gives oddly is never passed to gh"
PULLS='[{"number": "77 --add-label x", "state": "open", "labels": [{"name": "hold"}]}]' step; assert_eq "" "$(edits)"
it "a head that is not a commit sha stops it"
HSHA='main; true' step; assert_eq 1 "$rc"; assert_eq "" "$(cat "$T/gh.log")"
it "a failed label fails the run"
EDITFAIL=1 step; assert_eq 1 "$rc"

it "this test runs in CI"
grep -qF 'bash bin/probe-ci-fix-workflow.test.sh' "$root/.github/workflows/test.yml" && ok || bad "not in test.yml"

echo; echo "passed=$pass failed=$fail"
[ "$fail" -eq 0 ]
