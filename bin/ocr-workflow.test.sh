#!/usr/bin/env bash
# Tests for .github/workflows/ocr-review.yml, read as text: when a paid review
# can start, what the token may do, what is pinned, and that the label is
# taken off after a label run. That GitHub evaluates it so is shown only by a
# run.
set -u
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
root="$(cd "$here/.." && pwd)"
pass=0; fail=0; CURRENT=""
it() { CURRENT="$1"; }
ok()  { pass=$((pass+1)); printf '  ok   %s\n' "$CURRENT"; }
bad() { fail=$((fail+1)); printf '  FAIL %s\n       %s\n' "$CURRENT" "$1"; }
has() { printf '%s' "$1" | grep -qF -- "$2" && ok || bad "missing [$2]"; }
lacks() { printf '%s' "$1" | grep -qE -- "$2" && bad "unexpected [$2]" || ok; }

wf="$root/.github/workflows/ocr-review.yml"
w="$(grep -v '^ *#' "$wf" 2>/dev/null)"
job_if="$(printf '%s\n' "$w" | sed -n '/^    if: >-/,/^    runs-on:/p')"

it "the workflow exists"
[ -n "$w" ] && ok || bad "$wf missing"

it "it starts on pull request events only: opened, reopened, ready for review, labeled"
has "$w" "types: [opened, reopened, ready_for_review, labeled]"
lacks "$w" 'synchronize|pull_request_target|issue_comment|workflow_run|schedule'

it "only same-repository pull requests reach the secret: forks get no review"
has "$job_if" "github.event.pull_request.head.repo.full_name == github.repository &&"

it "a label run needs the ocr-review label; any other label starts nothing"
has "$job_if" "github.event.action == 'labeled' && github.event.label.name == 'ocr-review'"

it "the other events skip drafts"
has "$job_if" "github.event.action != 'labeled' && github.event.pull_request.draft == false"

it "the workflow token has nothing; the job can read code, comment, and take the label off"
has "$w" "permissions: {}"
has "$w" "      contents: read"; has "$w" "      pull-requests: write"; has "$w" "      issues: write"
lacks "$w" '^ *(contents|actions|packages|id-token|checks|statuses|deployments): *write'

it "the action and the CLI are pinned: the action to a full commit, the CLI to a version"
printf '%s\n' "$w" | grep -qE '^ *- uses: alibaba/open-code-review@[0-9a-f]{40}$' && ok || bad "action not pinned to a 40-character commit"
has "$w" "ocr_version: '1.14.1'"

it "the model is Anthropic's Claude, over its own protocol"
has "$w" "llm_url: https://api.anthropic.com"
has "$w" "llm_use_anthropic: 'true'"
printf '%s\n' "$w" | grep -qE "^ +llm_model: claude-[a-z0-9.-]+$" && ok || bad "no claude-* model"
# The action's default body is {"thinking": {"type": "disabled"}}, which Claude Sonnet 5.5 rejects
# with a 400 (run 45071344142). An empty body leaves the model's default adaptive thinking.
# reasoning_effort is not an Anthropic field.
has "$w" "llm_extra_body: '{}'"
lacks "$w" 'llm_reasoning_effort|"disabled"'

it "the key is named once, as the action's llm_auth_token input, never in a run: script"
[ "$(printf '%s\n' "$w" | grep -c 'secrets.ANTHROPIC_API_KEY')" = 1 ] && ok || bad "ANTHROPIC_API_KEY not named exactly once"
printf '%s\n' "$w" | grep -qE '^ +llm_auth_token: \$\{\{ secrets\.ANTHROPIC_API_KEY \}\}$' && ok || bad "the key is not the llm_auth_token input"
lacks "$w" 'OPENAI_API_KEY'

it "the review is capped in tokens"
printf '%s\n' "$w" | grep -qE "max_tokens_budget: '[1-9][0-9]*'" && ok || bad "no token cap"

it "after a label run the label is removed whatever happened, so adding it again re-runs"
has "$w" "if: always() && github.event.action == 'labeled'"
has "$w" '--remove-label ocr-review'

it "another label (verify, properties) never shares a review's concurrency group, so it cannot cancel it"
group="$(printf '%s\n' "$w" | sed -n 's/^  group: //p')"
printf '%s' "$group" | python3 -c '
import re, sys
g = sys.stdin.read()
def run(action, label):
    # Evaluate the ${{ }} parts the way GitHub does, for these few operators.
    def ev(m):
        e = m.group(1).replace("&&", " and ").replace("||", " or ")
        e = e.replace("github.event.pull_request.number", "45").replace("github.run_id", "\"RUN\"")
        e = e.replace("github.event.action", repr(action)).replace("github.event.label.name", repr(label))
        return str(eval(e))
    return re.sub(r"\$\{\{(.*?)\}\}", ev, g)
review = run("opened", "")
assert run("labeled", "ocr-review") == review, "an ocr-review label run is not in the review group"
assert run("reopened", "") == review
for label in ("verify", "properties", "ci-fix"):
    assert run("labeled", label) != review, label + " shares the review group"
' && ok || bad "group: $group"

echo "passed=$pass failed=$fail"
[ "$fail" -eq 0 ]
