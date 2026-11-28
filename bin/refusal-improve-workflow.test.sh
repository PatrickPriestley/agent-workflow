#!/usr/bin/env bash
# Tests for .github/workflows/refusal-improve.yml: weekly, the refused-call rules go to the agents'
# prompts in one pull request a person merges; PROBE_TOKEN only where it pushes and opens it.
#   bash bin/refusal-improve-workflow.test.sh
set -u
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"; root="$(cd "$here/.." && pwd)"
wf="$root/.github/workflows/refusal-improve.yml"
pass=0; fail=0; CURRENT=""
it() { CURRENT="$1"; }
ok()  { pass=$((pass+1)); printf '  ok   %s\n' "$CURRENT"; }
bad() { fail=$((fail+1)); printf '  FAIL %s\n       %s\n' "$CURRENT" "$1"; }
assert_eq() { [ "$1" = "$2" ] && ok || bad "expected [$1] got [$2]"; }
has()   { printf '%s' "$1" | grep -qF -- "$2" && ok || bad "missing: $2"; }
lacks() { printf '%s' "$1" | grep -qE -- "$2" && bad "found: $2" || ok; }
w="$(grep -v '^ *#' "$wf" 2>/dev/null)"
step_of() { awk -v n="$1" 'index($0, "- name: " n) {g=1; print; next} g && /^      - / {exit} g' "$wf"; }
script_of() { awk -v n="$1" 'index($0, "- name: " n) {g=1; next}
  g && /^        run: \|/ {r=1; next} r && /^          / {print substr($0, 11); next} r && /^ *$/ {print ""; next} r {exit}' "$wf"; }

it "weekly, the day after the report, and by hand; never on a pull request or a push"
has "$w" 'cron: "13 9 * * 3"'; has "$w" "workflow_dispatch:"; lacks "$w" "pull_request|push:|workflow_run"
it "the built-in token only reads"
assert_eq "permissions:
  contents: read
  pull-requests: read" "$(printf '%s\n' "$w" | awk '/^permissions:/ {p=1; print; next} p && /^  / {print; next} p {exit}')"
has "$w" "persist-credentials: false"; has "$w" "fetch-depth: 0"
it "PROBE_TOKEN is in the step that opens the pull request alone, never beside the compiler"
assert_eq 1 "$(grep -c 'secrets.PROBE_TOKEN' "$wf")"
has "$(step_of 'Open the pull request')" 'PROBE_TOKEN: ${{ secrets.PROBE_TOKEN }}'
lacks "$(step_of 'Rebuild the changed')" "PROBE_TOKEN"
it "the compiler is pinned to the version the lock files were built with"
has "$(script_of 'Rebuild the changed')" 'gh extension install github/gh-aw --pin "$version"'
has "$(script_of 'Rebuild the changed')" "bin/agent-allowlists-sync --check"
has "$(script_of 'Rebuild the changed')" "bash bin/agent-allowlists.test.sh"
it "no script takes anything from the event directly, and each runs in bash with pipefail"
for n in "Find the rules to add" "Rebuild the changed" "Open the pull request"; do
  s="$(script_of "$n")"; [ -n "$s" ] && ok || bad "no script for $n"; lacks "$s" '\$\{\{'
  has "$(step_of "$n")" "shell: bash"
done
it "it pushes only a new chore/refusal-rules- branch and never merges"
s="$(script_of 'Open the pull request')"
has "$s" 'branch="chore/refusal-rules-$(date -u +%Y-%m-%d)"'; has "$s" 'HEAD:refs/heads/$branch'
lacks "$w" "gh pr merge|--force|push -f|refs/heads/main"

# The planning step, run with stubs: the improver and gh.
T="$(mktemp -d "${TMPDIR:-/tmp}/refusal-improve-wf.XXXXXX")"; [ -n "${KEEP:-}" ] || trap 'rm -rf "$T"' EXIT
mkdir -p "$T/ws/.agent-workflow-tools/bin" "$T/stub"
cat > "$T/ws/.agent-workflow-tools/bin/refusal-improve" <<'STUB'
#!/usr/bin/env python3
import os, sys
args = sys.argv[1:]
open(args[args.index("--body") + 1], "w").write("body: " + " ".join(a for a in args if a != args[args.index("--body") + 1]) + "\n")
if "--write" in args and os.environ.get("STUB_CHANGES"):
    print(".github/workflows/ci-diagnose.md")
STUB
cat > "$T/stub/gh" <<'STUB'
#!/usr/bin/env bash
printf '%s' "${STUB_OPEN:-}"
STUB
chmod +x "$T/stub/gh"
plan() {  # -> $rc; summary in $T/summary, outputs in $T/output
  : > "$T/summary"; : > "$T/output"
  (cd "$T/ws" && env -i PATH="$T/stub:$PATH" HOME="$T" RUNNER_TEMP="$T" GITHUB_STEP_SUMMARY="$T/summary" GITHUB_OUTPUT="$T/output" \
    GH_TOKEN=t AGENT_TRANSCRIPTS_URL=https://x AGENT_TRANSCRIPTS_INSERT_KEY=k REPO=o/r DRY_RUN="${DRY-}" \
    STUB_CHANGES="${CHANGES:-}" STUB_OPEN="${OPEN:-}" bash --noprofile --norc -eo pipefail -c "$(script_of 'Find the rules to add')") > "$T/out" 2>&1; rc=$?
}
it "on schedule it writes the rules, and a change goes on to a pull request"
CHANGES=1 plan; assert_eq 0 "$rc"; has "$(cat "$T/summary")" "body: --repo o/r --root . --write --body"; assert_eq "changed=true" "$(cat "$T/output")"
it "with nothing to change, no pull request"
plan; assert_eq "changed=false" "$(cat "$T/output")"
it "a dry run only says what it would do"
DRY=true CHANGES=1 plan; lacks "$(cat "$T/summary")" "--write"; assert_eq "changed=false" "$(cat "$T/output")"
it "while its earlier pull request is open, it only measures"
OPEN="chore/refusal-rules-2026-11-25" CHANGES=1 plan; assert_eq 0 "$rc"
has "$(cat "$T/summary")" "still open: measuring only"; lacks "$(cat "$T/summary")" "--write"; assert_eq "changed=false" "$(cat "$T/output")"
OPEN="feat/other" CHANGES=1 plan; assert_eq "changed=true" "$(cat "$T/output")"

it "other repositories call it: the caller is checked out with its history, the tools beside it, both without credentials"
has "$w" "workflow_call:"; has "$w" "path: .agent-workflow-tools"
has "$w" "repository: \${{ inputs.tools-repository || 'PatrickPriestley/agent-workflow' }}"
assert_eq 2 "$(grep -c 'persist-credentials: false' "$wf")"
has "$(script_of 'Find the rules to add')" "python3 -I .agent-workflow-tools/bin/refusal-improve --repo \"\$REPO\" --root ."
it "the compiler is the version the changed agent's own lock was built with, and the allowlist checks run where the caller has them"
s="$(script_of 'Rebuild the changed')"
has "$s" "lock=\"\$(head -1 \"\$RUNNER_TEMP/changed.txt\" | sed 's/\\.md\$/.lock.yml/')\""
has "$s" "if [ -x bin/agent-allowlists-sync ]; then"
lacks "$s" "ci-diagnose.lock.yml"
it "the pull request goes to the caller's default branch"
has "$(step_of 'Open the pull request')" 'DEFAULT_BRANCH: ${{ github.event.repository.default_branch }}'
has "$(script_of 'Open the pull request')" '--base "${DEFAULT_BRANCH:-main}"'

it "this test runs in CI"
grep -qF 'bash bin/refusal-improve-workflow.test.sh' "$root/.github/workflows/test.yml" && ok || bad "not in test.yml"

echo; echo "passed=$pass failed=$fail"
[ "$fail" -eq 0 ]
