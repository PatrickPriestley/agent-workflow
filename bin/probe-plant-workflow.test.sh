#!/usr/bin/env bash
# Tests for .github/workflows/probe-plant.md (the planter) and probe-guard.yml, read as text:
# who can start the planter, what the agent may do, and what open-probe does with its hand-over.
set -u
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
root="$(cd "$here/.." && pwd)"
pass=0; fail=0; CURRENT=""
it() { CURRENT="$1"; }
ok()  { pass=$((pass+1)); printf '  ok   %s\n' "$CURRENT"; }
bad() { fail=$((fail+1)); printf '  FAIL %s\n       %s\n' "$CURRENT" "$1"; }
assert_eq() { [ "$1" = "$2" ] && ok || bad "expected [$1] got [$2]"; }
has() { printf '%s' "$1" | grep -qF -- "$2" && ok || bad "missing [$2]"; }
lacks() { printf '%s' "$1" | grep -qE -- "$2" && bad "unexpected [$(printf '%s' "$1" | grep -oE -- "$2" | head -1)]" || ok; }
before() {  # TEXT FIRST SECOND: FIRST appears, and before SECOND
  local a b; a="$(printf '%s\n' "$1" | grep -nF -- "$2" | head -1 | cut -d: -f1)"; b="$(printf '%s\n' "$1" | grep -nF -- "$3" | head -1 | cut -d: -f1)"
  [ -n "$a" ] && [ -n "$b" ] && [ "$a" -lt "$b" ] && ok || bad "[$2] (line ${a:-none}) not before [$3] (line ${b:-none})"
}

md="$root/.github/workflows/probe-plant.md"; lock="$root/.github/workflows/probe-plant.lock.yml"
w="$(grep -v '^ *#' "$md" 2>/dev/null)"; l="$(cat "$lock" 2>/dev/null)"
front="$(printf '%s\n' "$w" | awk 'NR==1&&/^---$/{f=1;next} f&&/^---$/{exit} f')"
job="$(printf '%s\n' "$front" | awk '/^    open-probe:/ {s=1} s')"

it "the planter and its lock exist"; [ -n "$w" ] && [ -n "$l" ] && ok || bad "missing"
it "it is started by hand, or once a week, each run in its own slot"
on="$(printf '%s\n' "$front" | sed -n '/^on:/,/^[a-z]/p')"
has "$on" "workflow_dispatch:"; lacks "$on" 'pull_request|push:|label_command|issue_comment'
has "$on" 'cron: "41 6 * * 2"'
[ "$(printf '%s\n' "$on" | grep -c 'cron:')" = 1 ] && ok || bad "not exactly one schedule"
it "a scheduled run, which has no inputs, plants a silent probe of any kind in a file the agent picks"
has "$front" 'KIND="${KIND:-any}"'
pre="$(printf '%s\n' "$front" | awk '/- name: Write down what was asked/ {s=1} s && /^safe-outputs:/ {exit} s')"
out="$(cd "$(mktemp -d "${TMPDIR:-/tmp}/plant-pre.XXXXXX")" && git init -q && git commit -q --allow-empty -m x -c user.name=t -c user.email=t@t 2>/dev/null; mkdir -p tmp; \
  script="$(printf '%s\n' "$pre" | awk '/^    run: \|/ {r=1; next} r && /^      / {print substr($0, 7); next} r && /^ *$/ {print ""; next} r {exit}' | sed "s|/tmp/gh-aw/agent|$PWD/tmp|g")"; \
  env KIND= LOUD= TARGET= bash -c "$script" >/dev/null 2>&1; cat tmp/plant/asked.json 2>/dev/null)"
assert_eq '{"kind": "any", "loud": false, "target": ""}' "$out"
has "$front" 'job-discriminator: ${{ github.run_id }}'
it "the agent has a read-only token, the network's defaults, and no output but open-probe"
has "$front" "  contents: read"; lacks "$(printf '%s\n' "$front" | sed '/^  jobs:/,$d')" ': *write'
so="$(printf '%s\n' "$front" | sed -n '/^safe-outputs:/,$p')"
lacks "$so" 'add-comment:|create-pull-request:|push-to-pull-request-branch:|create-issue:'
has "$front" "    continue-on-error: false"
it "the inputs reach the agent through a file, never interpolated into a script"
printf '%s\n' "$front" | grep -E '^\s+run: |^\s{6,}[^ ]' | grep -F '${{ inputs.' | grep -vE '^\s+(KIND|LOUD|TARGET): ' | grep -q . && bad "an input is interpolated" || ok
it "open-probe runs only after threat detection succeeds"
has "$(printf '%s\n' "$l" | awk '/^  open_probe:/ {s=1; next} s && /^  [a-z_]+:$/ {exit} s')" "needs.detection.result == 'success'"
it "open-probe checks out the default branch without keeping credentials, and checks the hand-over first"
has "$job" 'ref: ${{ github.event.repository.default_branch }}'; has "$job" 'persist-credentials: false'
before "$job" 'bin/probe-open' 'bin/probe-key seal'
before "$job" 'bin/probe-key seal' 'git -c http.extraheader'
it "a silent probe must leave its file's properties holding, checked after the build and before the push, with no secret (#69)"
before "$job" 'bin/probe-open' 'bash bin/probe-properties "$RUNNER_TEMP/probe/key.json" .'
before "$job" 'bash bin/probe-properties' 'bin/probe-key seal'
pstep="$(printf '%s\n' "$job" | awk '/- name: A silent probe leaves/ {s=1; print; next} s && /^        - name:/ {exit} s')"
[ -n "$pstep" ] && ok || bad "no properties step"
lacks "$pstep" 'secrets\.|GH_TOKEN'
it "the agent is told which properties cover each candidate, and that a silent probe must keep them holding"
has "$front" 'grep -lF -- "$f" properties/*.py'
has "$(cat "$md")" "A silent probe must leave them holding as well as the test"
it "the key is sealed with PROBE_KEY in one step, its plain copy deleted, and kept as probe-key"
[ "$(printf '%s\n' "$job" | grep -c 'secrets.PROBE_KEY')" -eq 1 ] && ok || bad "PROBE_KEY not in exactly one step"
has "$job" 'rm -f "$RUNNER_TEMP/probe/key.json"'; has "$job" 'name: probe-key'; has "$job" 'retention-days: 90'
it "the hash goes on the planted commit as a provenance status, before the pull request is opened"
before "$job" '-f context=provenance' 'gh pr create'
has "$job" '-f description="sha256:$(cat "$p/key.sha256")"'
it "the pull request is labelled hold before verify and properties"
before "$job" '--add-label hold' '--add-label verify'; before "$job" '--add-label hold' '--add-label properties'
it "nothing an agent can read (a label, a status context) says probe"
printf '%s\n' "$job" | grep -E -- "--add-label|context=" | grep -qi probe && bad "a probe label or status" || ok
it "the push token reaches git only as a header for that push, masked"
has "$job" 'echo "::add-mask::$auth"'; lacks "$job" 'token: \$\{\{ secrets'
it "the prompt keeps the probe blind and the change small"
raw="$(cat "$md")"
has "$raw" "## Rules for blindness"; has "$raw" "of at most 40 changed lines, in at most 2 files, none"
has "$raw" "call \`open_probe\` once"
it "the agent hands over edits to re-apply, never a diff it copied out"
inputs="$(printf '%s\n' "$front" | awk '/^      inputs:/ {s=1; next} s && /^      [a-z_]+:/ {exit} s')"
has "$inputs" "        edits:"; lacks "$inputs" "        patch:"
has "$raw" "Do not copy a diff."

g="$(grep -v '^ *#' "$root/.github/workflows/probe-guard.yml" 2>/dev/null)"
it "probe-guard fails a pull request labelled hold, and passes any other"
has "$g" "types: [opened, reopened, synchronize, labeled, unlabeled]"
has "$g" "if: contains(github.event.pull_request.labels.*.name, 'hold')"
has "$g" "exit 1"; has "$g" "if: \${{ !contains(github.event.pull_request.labels.*.name, 'hold') }}"
has "$g" "permissions: {}"
it "this test runs in CI"
grep -qF 'bash bin/probe-plant-workflow.test.sh' "$root/.github/workflows/test.yml" && ok || bad "not in test.yml"

echo; echo "passed=$pass failed=$fail"
[ "$fail" -eq 0 ]
