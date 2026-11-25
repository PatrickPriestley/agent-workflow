#!/usr/bin/env bash
# Tests for .github/workflows/probe-score-auto.yml: on a schedule, find the probes whose review
# loops have finished (bin/probe-ready) and dispatch probe-score for each.
#   bash bin/probe-score-auto-workflow.test.sh
set -u
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"; root="$(cd "$here/.." && pwd)"
wf="$root/.github/workflows/probe-score-auto.yml"
pass=0; fail=0; CURRENT=""
it() { CURRENT="$1"; }
ok()  { pass=$((pass+1)); printf '  ok   %s\n' "$CURRENT"; }
bad() { fail=$((fail+1)); printf '  FAIL %s\n       %s\n' "$CURRENT" "$1"; }
assert_eq() { [ "$1" = "$2" ] && ok || bad "expected [$1] got [$2]"; }
has()   { printf '%s' "$1" | grep -qF -- "$2" && ok || bad "missing: $2"; }
lacks() { printf '%s' "$1" | grep -qE -- "$2" && bad "found: $2" || ok; }
w="$(grep -v '^ *#' "$wf" 2>/dev/null)"

it "it runs every three hours, and by hand"
has "$w" "workflow_dispatch:"; printf '%s' "$w" | grep -qE 'cron: "[0-9]+ \*/3 \* \* \*"' && ok || bad "no three-hourly cron"
lacks "$w" "pull_request|push:"
it "it reads, and may only dispatch: no write to contents, pull requests or issues, no secret"
assert_eq "permissions:
  contents: read
  pull-requests: read
  issues: read
  actions: write" "$(printf '%s\n' "$w" | awk '/^permissions:/ {p=1; print; next} p && /^  / {print; next} p {exit}')"
lacks "$w" 'secrets\.'
has "$w" "persist-credentials: false"
it "one at a time"
has "$w" "group: probe-score-auto"; has "$w" "cancel-in-progress: false"

script="$(awk '/- name: Score each probe that is ready/ {g=1; next}
  g && /^        run: \|/ {r=1; next} r && /^          / {print substr($0, 11); next} r && /^ *$/ {print ""; next} r {exit}' "$wf")"
it "the step runs in bash with pipefail, as the test runs it"
has "$(awk '/- name: Score each probe that is ready/ {g=1; print; next} g && /^      - / {exit} g' "$wf")" "shell: bash"
it "the step's script takes nothing from the event"
[ -n "$script" ] && ok || bad "no script"; lacks "$script" '\$\{\{'

# The script, run with a stub probe-ready (its output from PROBE_READY_OUT) and a stub gh.
T="$(mktemp -d "${TMPDIR:-/tmp}/probe-score-auto.XXXXXX")"; [ -n "${KEEP:-}" ] || trap 'rm -rf "$T"' EXIT
mkdir -p "$T/ws/bin" "$T/stub"
cat > "$T/ws/bin/probe-ready" <<'STUB'
#!/usr/bin/env python3
import os, sys
sys.stdout.write(os.environ.get("PROBE_READY_OUT", "")); sys.exit(int(os.environ.get("PROBE_READY_RC", "0")))
STUB
cat > "$T/stub/gh" <<'STUB'
#!/usr/bin/env bash
printf '%s\n' "$*" >> "$STUB_LOG"
case "$*" in *"pr=${STUB_GH_FAILS_FOR:-none} "*) echo "HTTP 500" >&2; exit 1 ;; esac
STUB
chmod +x "$T/stub/gh"
step() {  # -> $rc; output in $T/out, gh calls in $T/gh.log, summary in $T/summary
  : > "$T/gh.log"; : > "$T/summary"
  (cd "$T/ws" && env -i PATH="$T/stub:$PATH" HOME="$T" STUB_LOG="$T/gh.log" GITHUB_REPOSITORY=o/r \
    GITHUB_STEP_SUMMARY="$T/summary" DEFAULT_BRANCH=main PROBE_READY_OUT="${OUT-}" PROBE_READY_RC="${RRC:-0}" \
    STUB_GH_FAILS_FOR="${GHFAIL:-none}" bash --noprofile --norc -eo pipefail -c "$script") > "$T/out" 2>&1; rc=$?
}
it "each ready probe is scored once, closing it, on the default branch"
OUT='{"pr": 69, "key_run": 500}
{"pr": 71, "key_run": 600}
' step; assert_eq 0 "$rc"
assert_eq "workflow run probe-score.yml --repo o/r --ref main -f pr=69 -f key_run=500 -f close=true
workflow run probe-score.yml --repo o/r --ref main -f pr=71 -f key_run=600 -f close=true" "$(cat "$T/gh.log")"
grep -q '#69' "$T/summary" && grep -q '#71' "$T/summary" && ok || bad "summary: $(cat "$T/summary")"
it "no ready probe dispatches nothing"
OUT='' step; assert_eq "0 " "$rc $(cat "$T/gh.log")"
it "the finder failing fails the run, and dispatches nothing"
OUT='{"pr": 69, "key_run": 500}
' RRC=1 step; assert_eq 1 "$rc"; assert_eq "" "$(cat "$T/gh.log")"
it "a line that is not a probe number and run id is refused, not passed to gh"
for bad_line in '{"pr": "69 -f close=false", "key_run": 500}' '{"pr": 69, "key_run": "500"}' '{"pr": true, "key_run": 500}' \
                '{"pr": 0, "key_run": 500}' '{"pr": 69, "key_run": true}' '{"pr": 69, "key_run": -5}' '{"pr": 69}' 'not json'; do
  OUT="$bad_line
" step; [ "$rc" -ne 0 ] && ok || bad "accepted [$bad_line]"; assert_eq "" "$(cat "$T/gh.log")"
done
it "a bad line, or a failed dispatch, does not stop the others; the run fails at the end and says which"
OUT='{"pr": 69, "key_run": 500}
not json
{"pr": 71, "key_run": 600}
' step; assert_eq 1 "$rc"
assert_eq "workflow run probe-score.yml --repo o/r --ref main -f pr=69 -f key_run=500 -f close=true
workflow run probe-score.yml --repo o/r --ref main -f pr=71 -f key_run=600 -f close=true" "$(cat "$T/gh.log")"
OUT='{"pr": 69, "key_run": 500}
{"pr": 71, "key_run": 600}
' GHFAIL=69 step; assert_eq 1 "$rc"; assert_eq 2 "$(grep -c . "$T/gh.log")"
grep -q '#69' "$T/summary" && bad "summary lists the failed dispatch: $(cat "$T/summary")" || ok
grep -q '#71' "$T/summary" && ok || bad "summary: $(cat "$T/summary")"
grep -q 'could not dispatch #69' "$T/out" && ok || bad "$(cat "$T/out")"
it "the summary says the probes were sent, not that they were scored"
OUT='{"pr": 69, "key_run": 500}
' step; grep -qi 'dispatched' "$T/summary" && ok || bad "$(cat "$T/summary")"

it "this test runs in CI"
grep -qF 'bash bin/probe-score-auto-workflow.test.sh' "$root/.github/workflows/test.yml" && ok || bad "not in test.yml"

echo; echo "passed=$pass failed=$fail"
[ "$fail" -eq 0 ]
