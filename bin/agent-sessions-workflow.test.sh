#!/usr/bin/env bash
# Tests for .github/workflows/agent-sessions.yml: after a GitHub agent's run, collect its
# session into the transcript store with main's tools and the insert-only key.
#   bash bin/agent-sessions-workflow.test.sh
set -u
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"; root="$(cd "$here/.." && pwd)"
wf="$root/.github/workflows/agent-sessions.yml"
pass=0; fail=0; CURRENT=""
it() { CURRENT="$1"; }
ok()  { pass=$((pass+1)); printf '  ok   %s\n' "$CURRENT"; }
bad() { fail=$((fail+1)); printf '  FAIL %s\n       %s\n' "$CURRENT" "$1"; }
assert_eq() { [ "$1" = "$2" ] && ok || bad "expected [$1] got [$2]"; }
has()   { printf '%s' "$1" | grep -qF -- "$2" && ok || bad "missing: $2"; }
lacks() { printf '%s' "$1" | grep -qE -- "$2" && bad "found: $2" || ok; }
w="$(grep -v '^ *#' "$wf" 2>/dev/null)"

it "it runs when one of the agents' runs completes, never the planter's"
has "$w" 'workflows: ["Verify PR claims", "CI diagnosis", "CI fix", "Property Scout"]'
has "$w" "types: [completed]"; lacks "$w" "Plant a probe|pull_request|push:|schedule"
it "every workflow named is a gh-aw agent on Claude: the collector reads Claude's output only"
# A rename would silently stop collection; another engine's output has no Claude lines.
names="$(printf '%s\n' "$w" | sed -n 's/^ *workflows: \[\(.*\)\]$/\1/p' | tr ',' '\n' | sed 's/^ *"//; s/"$//')"
[ -n "$names" ] && ok || bad "no workflows list"
while IFS= read -r n; do
  f="$(grep -lx "name: $n" "$root"/.github/workflows/*.md 2>/dev/null | head -1)"
  if [ -z "$f" ]; then bad "no agent workflow named $n"; continue; fi
  awk '/^engine:/ {e=1; next} e && /^  id:/ {print $2; exit} e && /^[a-z]/ {exit}' "$f" | grep -qx claude && ok || bad "$n does not run on Claude"
done <<EOF
$names
EOF
it "every Claude agent but the planter is collected"
for f in "$root"/.github/workflows/*.md; do
  awk '/^engine:/ {e=1; next} e && /^  id:/ {print $2; exit} e && /^[a-z]/ {exit}' "$f" | grep -qx claude || continue
  n="$(sed -n 's/^name: //p' "$f" | head -1)"; [ "$n" = "Plant a probe" ] && continue
  printf '%s\n' "$names" | grep -qxF "$n" && ok || bad "$n is a Claude agent the collector does not watch"
done
it "it reads actions and contents only, and checks out main without keeping credentials"
assert_eq "permissions:
  actions: read
  contents: read" "$(printf '%s\n' "$w" | awk '/^permissions:/ {p=1; print; next} p && /^  / {print; next} p {exit}')"
has "$w" "ref: \${{ inputs.tools-ref || 'main' }}"; has "$w" "persist-credentials: false"
lacks "$w" "head_sha|head_branch|pull_requests"
it "the artifact action is pinned to a commit"
has "$w" "actions/download-artifact@9000827ccba6bdab643e8b6fd33ac0654aef8333"

# The collect step, run as GitHub runs it, against a scratch copy of the tools in which
# `transcripts push` is recorded instead of sent.
script="$(awk '/- name: Collect the session and push it/ {g=1; next}
  g && /^        run: \|/ {r=1; next} r && /^          / {print substr($0, 11); next} r && /^ *$/ {print ""; next} r {exit}' "$wf")"
it "the run script takes event data and secrets through env, never interpolated"
[ -n "$script" ] && ok || bad "no run script found"
lacks "$script" '\$\{\{'
it "the store's secrets reach only the collect step"
assert_eq "2" "$(grep -c 'secrets\.AGENT_TRANSCRIPTS' "$wf")"
assert_eq "" "$(awk '/- name:/ {s=$0} /secrets\./ && s !~ /Collect the session and push it/ {print s}' "$wf")"

T="$(mktemp -d "${TMPDIR:-/tmp}/agent-sessions-wf.XXXXXX")"; [ -n "${KEEP:-}" ] || trap 'rm -rf "$T"' EXIT
W="$T/ws"; mkdir -p "$W/bin" "$W/plugins/change-record/bin"
cp "$root/bin/agent-session-collect" "$W/bin/"
cat > "$W/plugins/change-record/bin/transcripts" <<STUB
#!/usr/bin/env bash
printf '%s\n' "\$*" >> "$T/calls"
if [ "\$1" = push ]; then ls -l "\$XDG_CONFIG_HOME/agent-transcripts/insert-key" | cut -c1-10 >> "$T/calls"; exit 0; fi
[ -n "\${STUB_ARCHIVE_DROPS:-}" ] && exit 0
exec "$root/plugins/change-record/bin/transcripts" "\$@"
STUB
chmod +x "$W/plugins/change-record/bin/transcripts"
git -C "$W" init -q && git -C "$W" remote add origin https://github.com/Owner/Repo.git
artifact() {  # LOG_SOURCE: a fresh RUNNER_TEMP with the agent artifact as gh-aw lays it out
  rm -rf "$T/rt" "$T/calls" "$T/summary"; mkdir -p "$T/rt/agent/aw-prompts"
  [ -n "$1" ] && cp "$1" "$T/rt/agent/agent-stdio.log"; printf 'Check the claims.\n' > "$T/rt/agent/aw-prompts/prompt.txt"
}
step() {  # runs the script with the env the workflow gives it -> $rc, output in $T/out
  (cd "$W" && env -i PATH="$PATH" HOME="$T" RUNNER_TEMP="$T/rt" GITHUB_WORKSPACE="$W" GITHUB_STEP_SUMMARY="$T/summary" \
    WORKFLOW="Verify PR claims" RUN_ID=4242 ATTEMPT=1 DOWNLOADED="${DL:-success}" \
    AGENT_TRANSCRIPTS_URL="${URL-https://example.supabase.co}" INSERT_KEY="${KEY-sb_publishable_test}" STUB_ARCHIVE_DROPS="${DROPS:-}" \
    bash -e -o pipefail -c "$script") >"$T/out" 2>&1; rc=$?
}
fx="$root/bin/testdata/agent-sessions/agent-stdio.log"

it "a finished run's session is archived, then pushed with the key in a 0600 file, and summarised"
artifact "$fx"; step; assert_eq 0 "$rc"
[ -f "$T/rt/archive/sessions/gh-aw-verify-pr-claims-4242-1.json" ] && ok || bad "not archived: $(cat "$T/out")"
assert_eq "push
-rw-------" "$(grep -v '^archive' "$T/calls" 2>/dev/null)"
grep -q '::add-mask::sb_publishable_test' "$T/out" && ok || bad "key not masked"
grep -q 'gh-aw-verify-pr-claims-4242-1' "$T/summary" 2>/dev/null && ok || bad "no summary"
it "a run with no artifact, or no log in it, is a notice and nothing more"
artifact "$fx"; DL=failure step; assert_eq "0 no" "$rc $([ -e "$T/calls" ] && echo yes || echo no)"
grep -q '::notice::run 4242 of Verify PR claims has no agent artifact' "$T/out" && ok || bad "$(cat "$T/out")"
artifact ""; step; assert_eq "0 no" "$rc $([ -e "$T/calls" ] && echo yes || echo no)"
it "without both secrets it warns and sends nothing, and writes no key"
artifact "$fx"; KEY="" step; assert_eq "0 no" "$rc $([ -e "$T/calls" ] && echo yes || echo no)"
grep -q '::warning::the AGENT_TRANSCRIPTS_URL and AGENT_TRANSCRIPTS_INSERT_KEY secrets' "$T/out" && ok || bad "$(cat "$T/out")"
[ ! -e "$T/rt/config" ] && ok || bad "wrote a key"
it "an agent that said nothing is a notice"
grep -v '"type":"\(user\|assistant\)"' "$fx" > "$T/empty.log"; artifact "$T/empty.log"; step
assert_eq "0 no" "$rc $([ -e "$T/calls" ] && echo yes || echo no)"
it "a session archive did not keep fails the job before any push"
artifact "$fx"; DROPS=1 step; assert_eq 1 "$rc"
grep -q '::error::gh-aw-verify-pr-claims-4242-1 was not archived' "$T/out" && ok || bad "$(cat "$T/out")"
grep -q '^push' "$T/calls" && bad "pushed anyway" || ok

it "this test runs in CI"
grep -qF 'bash bin/agent-sessions-workflow.test.sh' "$root/.github/workflows/test.yml" && ok || bad "not in test.yml"

echo; echo "passed=$pass failed=$fail"
[ "$fail" -eq 0 ]
