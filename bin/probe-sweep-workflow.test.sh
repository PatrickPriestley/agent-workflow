#!/usr/bin/env bash
# Tests for .github/workflows/probe-sweep.yml: daily, bin/probe-sweep tidies up after the probe
# loop with the built-in token; by hand it can only say what it would do.
#   bash bin/probe-sweep-workflow.test.sh
set -u
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"; root="$(cd "$here/.." && pwd)"
wf="$root/.github/workflows/probe-sweep.yml"
pass=0; fail=0; CURRENT=""
it() { CURRENT="$1"; }
ok()  { pass=$((pass+1)); printf '  ok   %s\n' "$CURRENT"; }
bad() { fail=$((fail+1)); printf '  FAIL %s\n       %s\n' "$CURRENT" "$1"; }
assert_eq() { [ "$1" = "$2" ] && ok || bad "expected [$1] got [$2]"; }
has()   { printf '%s' "$1" | grep -qF -- "$2" && ok || bad "missing: $2"; }
lacks() { printf '%s' "$1" | grep -qE -- "$2" && bad "found: $2" || ok; }
w="$(grep -v '^ *#' "$wf" 2>/dev/null)"

it "it runs daily and by hand, never on a pull request or a push"
has "$w" 'cron: "29 5 * * *"'; has "$w" "workflow_dispatch:"; lacks "$w" "pull_request|push:|workflow_run"
it "the built-in token may change branches, pull requests and issues, and nothing else; no secret"
assert_eq "permissions:
  contents: write
  pull-requests: write
  issues: write" "$(printf '%s\n' "$w" | awk '/^permissions:/ {p=1; print; next} p && /^  / {print; next} p {exit}')"
assert_eq 0 "$(grep -c 'secrets\.' "$wf")"; has "$w" 'GH_TOKEN: ${{ github.token }}'
it "it checks out only the tools, without keeping credentials"
has "$w" "ref: \${{ inputs.tools-ref || 'main' }}"; has "$w" "persist-credentials: false"; lacks "$w" "head_sha|head_ref|pull/"

script="$(awk '/- name: Sweep/ {g=1; next}
  g && /^        run: \|/ {r=1; next} r && /^          / {print substr($0, 11); next} r && /^ *$/ {print ""; next} r {exit}' "$wf")"
it "the script takes nothing from the event, and runs in bash with pipefail"
[ -n "$script" ] && ok || bad "no script"; lacks "$script" '\$\{\{'
has "$(awk '/- name: Sweep/ {g=1; print; next} g && /^      - / {exit} g' "$wf")" "shell: bash"

T="$(mktemp -d "${TMPDIR:-/tmp}/probe-sweep-wf.XXXXXX")"; [ -n "${KEEP:-}" ] || trap 'rm -rf "$T"' EXIT
mkdir -p "$T/ws/bin"
cat > "$T/ws/bin/probe-sweep" <<'STUB'
#!/usr/bin/env python3
import os, sys
print("args: " + " ".join(sys.argv[1:]))
if os.environ.get("STUB_SAYS"):
    print(os.environ["STUB_SAYS"])
sys.exit(int(os.environ.get("STUB_RC") or 0))
STUB
step() {  # -> $rc; output in $T/out, summary in $T/summary
  : > "$T/summary"
  (cd "$T/ws" && env -i PATH="$PATH" HOME="$T" RUNNER_TEMP="$T" GITHUB_STEP_SUMMARY="$T/summary" GH_TOKEN=t \
    REPO=o/r DRY_RUN="${DRY-}" STUB_RC="${SRC:-0}" STUB_SAYS="${SAYS:-}" bash --noprofile --norc -eo pipefail -c "$script") > "$T/out" 2>&1; rc=$?
}
it "on schedule it sweeps this repository; ticked, it only says what it would do"
step; assert_eq 0 "$rc"; grep -qx -- '- args: --repo o/r' "$T/summary" && ok || bad "$(cat "$T/summary")"
DRY=false step; grep -qx -- '- args: --repo o/r' "$T/summary" && ok || bad "$(cat "$T/summary")"
DRY=true step; grep -qx -- '- args: --repo o/r --dry-run' "$T/summary" && ok || bad "$(cat "$T/summary")"
it "what it did goes to the summary, and a failure still writes it and fails the run"
SAYS="deleted feat/x-a1b2c3, the branch of closed probe #68" SRC=1 step; assert_eq 1 "$rc"
grep -qF -- '- deleted feat/x-a1b2c3' "$T/summary" && ok || bad "$(cat "$T/summary")"

it "this test runs in CI"
grep -qF 'bash bin/probe-sweep-workflow.test.sh' "$root/.github/workflows/test.yml" && ok || bad "not in test.yml"

echo; echo "passed=$pass failed=$fail"
[ "$fail" -eq 0 ]
