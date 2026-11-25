#!/usr/bin/env bash
# Tests for .github/workflows/probe-report.yml: once a week, the probe report goes to the run's
# summary, and nowhere the review agents read.
#   bash bin/probe-report-workflow.test.sh
set -u
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"; root="$(cd "$here/.." && pwd)"
wf="$root/.github/workflows/probe-report.yml"
pass=0; fail=0; CURRENT=""
it() { CURRENT="$1"; }
ok()  { pass=$((pass+1)); printf '  ok   %s\n' "$CURRENT"; }
bad() { fail=$((fail+1)); printf '  FAIL %s\n       %s\n' "$CURRENT" "$1"; }
assert_eq() { [ "$1" = "$2" ] && ok || bad "expected [$1] got [$2]"; }
has()   { printf '%s' "$1" | grep -qF -- "$2" && ok || bad "missing: $2"; }
lacks() { printf '%s' "$1" | grep -qE -- "$2" && bad "found: $2" || ok; }
w="$(grep -v '^ *#' "$wf" 2>/dev/null)"

it "it runs on Tuesday after the morning's scoring, and by hand"
has "$w" 'cron: "17 12 * * 2"'; has "$w" "workflow_dispatch:"; lacks "$w" "pull_request|push:"
it "it may read the repository and nothing else: it cannot post an issue or a comment"
assert_eq "permissions:
  contents: read" "$(printf '%s\n' "$w" | awk '/^permissions:/ {p=1; print; next} p && /^  / {print; next} p {exit}')"
lacks "$w" 'gh issue|gh pr|gh api|add-comment|issues:|pull-requests:'
has "$w" "persist-credentials: false"
it "the store's secrets are in the report step alone"
assert_eq 2 "$(grep -c 'secrets\.' "$wf")"
assert_eq "" "$(awk '/- name:/ {s=$0} /secrets\./ && s !~ /Write the report to this run/ {print s}' "$wf")"

script="$(awk '/- name: Write the report to this run/ {g=1; next}
  g && /^        run: \|/ {r=1; next} r && /^          / {print substr($0, 11); next} r && /^ *$/ {print ""; next} r {exit}' "$wf")"
it "the script takes nothing from the event, and runs in bash with pipefail"
[ -n "$script" ] && ok || bad "no script"; lacks "$script" '\$\{\{'
has "$(awk '/- name: Write the report to this run/ {g=1; print; next} g && /^      - / {exit} g' "$wf")" "shell: bash"

T="$(mktemp -d "${TMPDIR:-/tmp}/probe-report-wf.XXXXXX")"; [ -n "${KEEP:-}" ] || trap 'rm -rf "$T"' EXIT
mkdir -p "$T/ws/bin"
cat > "$T/ws/bin/probe-report" <<'STUB'
#!/usr/bin/env python3
import os, sys
if os.environ.get("STUB_FAIL"):
    print("probe-report: the store answered 500", file=sys.stderr); sys.exit(1)
print("## Review loops against planted bugs\n\n2 probes scored")
STUB
step() {  # -> $rc; output in $T/out, summary in $T/summary
  : > "$T/summary"
  (cd "$T/ws" && env -i PATH="$PATH" HOME="$T" RUNNER_TEMP="$T" GITHUB_STEP_SUMMARY="$T/summary" \
    AGENT_TRANSCRIPTS_URL="${URL-https://example.supabase.co}" AGENT_TRANSCRIPTS_INSERT_KEY="${KEY-sb_publishable_test}" \
    STUB_FAIL="${FAILS:-}" bash --noprofile --norc -eo pipefail -c "$script") > "$T/out" 2>&1; rc=$?
}
it "the report is written to the run summary"
step; assert_eq 0 "$rc"; grep -q '2 probes scored' "$T/summary" && ok || bad "summary: $(cat "$T/summary")"
it "a store that fails fails the run, and the summary says so"
FAILS=1 step; assert_eq 1 "$rc"; grep -q 'could not be read' "$T/summary" && ok || bad "summary: $(cat "$T/summary")"
it "without both secrets the run fails and says which are needed"
KEY="" step; assert_eq 1 "$rc"; grep -q 'AGENT_TRANSCRIPTS_INSERT_KEY' "$T/out" && ok || bad "$(cat "$T/out")"

it "this test runs in CI"
grep -qF 'bash bin/probe-report-workflow.test.sh' "$root/.github/workflows/test.yml" && ok || bad "not in test.yml"

echo; echo "passed=$pass failed=$fail"
[ "$fail" -eq 0 ]
