#!/usr/bin/env bash
# Tests for .github/workflows/pr-agent.yml and pr-agent/check-model.sh. The workflow is read
# as text: what it pins, what it passes to PR-Agent, and that its ignore globs match
# .pr_agent.toml.
set -u
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
root="$(cd "$here/.." && pwd)"
pass=0; fail=0; CURRENT=""
it() { CURRENT="$1"; }
ok()  { pass=$((pass+1)); printf '  ok   %s\n' "$CURRENT"; }
bad() { fail=$((fail+1)); printf '  FAIL %s\n       %s\n' "$CURRENT" "$1"; }
assert_eq()  { [ "$1" = "$2" ] && ok || bad "expected [$1] got [$2]"; }
has() { printf '%s' "$1" | grep -qF -- "$2" && ok || bad "missing [$2]"; }

wf="$root/.github/workflows/pr-agent.yml"
w="$(cat "$wf" 2>/dev/null)"
envval() { sed -n "s/^ *$1: *//p" "$wf" | head -n1; }   # the raw YAML value of an env key
check() { bash "$here/check-model.sh" "$@" 2>&1; }

it "the workflow exists"
[ -n "$w" ] && ok || bad "$wf missing"

it "PR-Agent's image is pinned by digest, not by a moving tag or the action wrapper"
printf '%s\n' "$w" | grep -qE '^ *uses: docker://pragent/pr-agent@sha256:[0-9a-f]{64}( |$)' && ok || bad "no digest-pinned docker:// step"
printf '%s\n' "$w" | grep -v '^ *#' | grep -qiE 'the-pr-agent/pr-agent@|pragent/pr-agent:' && bad "an unpinned PR-Agent reference remains" || ok

it "every other action is pinned to a version"
printf '%s\n' "$w" | grep -E '^ *(- )?uses:' | grep -v 'docker://' | grep -vE '@v[0-9]+' >/dev/null && bad "an action has no version" || ok

it "runs on pull requests only, including each push to one, skipping drafts and forks"
has "$w" "pull_request:"
has "$w" "types: [opened, reopened, ready_for_review, synchronize]"
printf '%s\n' "$w" | grep -qE 'issue_comment|pull_request_target' && bad "comment or target triggers present" || ok
has "$w" "github.event.pull_request.draft == false"
has "$w" "github.event.pull_request.head.repo.full_name == github.repository"

it "the token gets no more than it needs"
has "$w" "permissions: {}"
has "$w" "contents: read"; has "$w" "pull-requests: write"
printf '%s\n' "$w" | grep -qE '^ *(contents|actions|packages|id-token): *write' && bad "extra write permission" || ok
has "$w" "persist-credentials: false"

it "only /review runs: /describe would rewrite the PR body, and /improve stays off for now"
assert_eq "'true'" "$(envval GITHUB_ACTION_CONFIG__AUTO_REVIEW)"
assert_eq "'false'" "$(envval GITHUB_ACTION_CONFIG__AUTO_DESCRIBE)"
assert_eq "'false'" "$(envval GITHUB_ACTION_CONFIG__AUTO_IMPROVE)"

it "a push runs /review only: without push_commands PR-Agent falls back to /describe and /review"
assert_eq "'true'" "$(envval GITHUB_ACTION_CONFIG__HANDLE_PUSH_TRIGGER)"
assert_eq "'[\"/review\"]'" "$(envval GITHUB_ACTION_CONFIG__PUSH_COMMANDS)"

it "the model is OpenAI's gpt-6.1-sol, under the bare name PR-Agent knows, unless the variable names another, with no fallback"
assert_eq "\${{ vars.PR_AGENT_MODEL || 'gpt-6.1-sol' }}" "$(envval CONFIG__MODEL)"
assert_eq "'[]'" "$(envval CONFIG__FALLBACK_MODELS)"

it "PR-Agent calls OpenAI itself with the OpenAI key: no base URL, and nothing of OpenCode Go is left"
assert_eq "" "$(envval OPENAI__API_BASE)"
assert_eq '${{ secrets.OPENAI_API_KEY }}' "$(envval OPENAI__KEY)"
printf '%s\n' "$w" | grep -v '^ *#' | grep -qiE 'OPENCODE|opencode\.ai|openai/glm' && bad "an OpenCode Go setting remains" || ok
assert_eq "" "$(envval LITELLM__EXTRA_HEADERS)"
assert_eq "" "$(envval CONFIG__CUSTOM_MODEL_MAX_TOKENS)"
printf '%s\n' "$w" | grep -v '^ *#' | grep -q 'OPENROUTER' && bad "an OpenRouter setting remains" || ok

it "the model is checked before PR-Agent runs: Claude, who writes the pull requests here, is refused, and the reviewer's own family is not"
has "$w" 'bash pr-agent/check-model.sh "$MODEL" '"'"'[]'"'"' --exclude claude'
printf '%s\n' "$w" | grep -qE -- '--exclude (gpt|codex|openai)' && bad "the reviewer's own family is excluded" || ok
assert_eq "\${{ vars.PR_AGENT_MODEL || 'gpt-6.1-sol' }}" "$(envval MODEL)"
has "$w" "KEY_SET: \${{ secrets.OPENAI_API_KEY != '' }}"
has "$w" "add the secret OPENAI_API_KEY"
it "the default model passes the guard as the workflow calls it, and a Claude model named in the variable does not"
out=$(check gpt-6.1-sol '[]' --exclude claude); assert_eq 0 "$?"
out=$(check claude-sonnet-5-5 '[]' --exclude claude); assert_eq 2 "$?"
out=$(check anthropic/Claude-opus '[]' --exclude claude); assert_eq 2 "$?"
it "the key is named on the review step and in the one expression that asks whether it is set, nowhere else"
assert_eq 2 "$(printf '%s\n' "$w" | grep -v '^ *#' | grep -c 'secrets.OPENAI_API_KEY')"
printf '%s\n' "$w" | awk '/^    env:/{job=1} /^    steps:/{job=0} job' | grep -q 'secrets\.' && bad "a secret is set for the whole job" || ok
has "$w" "if: steps.check.outputs.ready == 'true'"

it "Kimi gets no temperature: PR-Agent 0.49.0's no_temperature_models lacks it, later releases list it"
python3 -I - "$(envval CONFIG__NO_TEMPERATURE_MODELS)" <<'PY' && ok || bad "CONFIG__NO_TEMPERATURE_MODELS is missing kimi-k3.1-pro or 0.49.0's defaults"
import json, sys
raw = sys.argv[1]
assert raw.startswith("'") and raw.endswith("'"), raw
models = json.loads(raw[1:-1])
v049 = ["deepseek/deepseek-reasoner", "o1-mini", "o1-mini-2024-09-12", "o1", "o1-2024-12-17", "o3-mini",
        "o3-mini-2025-01-31", "o3", "o3-2025-04-16", "o4-mini", "o4-mini-2025-04-16", "gpt-5.1-codex",
        "gpt-5.1-codex-mini", "gpt-5.2-codex", "gpt-5.3-codex", "gpt-5-mini", "moonshotai.kimi-k3",
        "us.moonshotai.kimi-k3", "global.moonshotai.kimi-k3", "zai.glm-5"]
assert all(m in models for m in v049), [m for m in v049 if m not in models]
assert "kimi-k3.1-pro" in models and "kimi-k3" in models
PY

it "try.sh sends Go the same no-temperature list as the workflow"
want="$(envval CONFIG__NO_TEMPERATURE_MODELS)"
got="$(sed -n "s/^ *no_temperature_models=//p" "$here/try.sh")"
assert_eq "$want" "$got"

it "a slow reasoning model gets 10 minutes for one call, no client retries, and a job that outlasts it"
assert_eq "'600'" "$(envval CONFIG__AI_TIMEOUT)"
assert_eq "'0'" "$(envval CONFIG__NUM_RETRIES)"
assert_eq "25" "$(envval timeout-minutes)"

it "the protections are checked inside the same pinned image, before the review"
python3 -I - "$wf" <<'PY' && ok || bad "the verify-image step is missing, misplaced or differs from the review step"
import re, sys
text = open(sys.argv[1]).read()
steps = text.split("\n      - ")
names = [s.splitlines()[0] for s in steps]
vi = next(i for i, s in enumerate(steps) if "pr-agent/verify-image.py" in s)
rv = next(i for i, s in enumerate(steps) if s.startswith("name: PR-Agent review"))
assert vi < rv, names
digest = re.findall(r"pragent/pr-agent@(sha256:[0-9a-f]{64})", text)
assert len(digest) == 2 and digest[0] == digest[1], digest
v = steps[vi]
assert "if: steps.check.outputs.ready == 'true'" in v
assert '-v "$GITHUB_WORKSPACE:/github/workspace:ro"' in v
for name in ("IGNORE__GLOB", "SKILLS__ENABLED", "SKILLS__PATHS"):
    assert f"-e {name}" in v, name
PY

it "the checked settings are set once, for the whole job, so the check and the review read the same values"
python3 -I - "$wf" <<'PY' && ok || bad "IGNORE__GLOB, SKILLS__ENABLED or SKILLS__PATHS is not job-level, or is set twice"
import sys
lines = open(sys.argv[1]).read().splitlines()
for name in ("IGNORE__GLOB", "SKILLS__ENABLED", "SKILLS__PATHS"):
    hits = [l for l in lines if l.strip().startswith(name + ":")]
    assert len(hits) == 1 and hits[0].startswith("      " + name + ":"), (name, hits)
PY

it "the local install is pinned to the same PR-Agent version as the image"
image="$(sed -n 's/^ *# pragent\/pr-agent:\([0-9][0-9.]*\)-github_action.*/\1/p' "$wf" | head -n1)"
[ -n "$image" ] && ok || bad "no version comment on the pinned image"
has "$(cat "$root/README.md")" "pip install pr-agent==$image"
has "$(cat "$here/try.sh")" "pip install pr-agent==$image"

it "a tool failure fails the job"
assert_eq "'true'" "$(envval GITHUB_ACTION_CONFIG__FAIL_ON_TOOL_ERRORS)"

it "the skill is loaded from the checkout"
assert_eq "'[\"/github/workspace/pr-agent/skills\"]'" "$(envval SKILLS__PATHS)"
assert_eq "'true'" "$(envval SKILLS__ENABLED)"
[ -f "$here/skills/workflow-review/SKILL.md" ] && ok || bad "pr-agent/skills/workflow-review/SKILL.md missing"

it "the workflow's ignore globs are exactly .pr_agent.toml's"
python3 -I - "$root/.pr_agent.toml" "$(envval IGNORE__GLOB)" <<'PY' && ok || bad "IGNORE__GLOB differs from .pr_agent.toml"
import json, sys, tomllib
want = tomllib.load(open(sys.argv[1], "rb"))["ignore"]["glob"]
raw = sys.argv[2]
assert raw.startswith("'") and raw.endswith("'"), raw
assert json.loads(raw[1:-1]) == want, (json.loads(raw[1:-1]), want)
PY

it "prompt logging is off unless the repository variable turns it on"
assert_eq "\${{ vars.PR_AGENT_VERBOSITY || '0' }}" "$(envval CONFIG__VERBOSITY_LEVEL)"

# ---- check-model.sh ---------------------------------------------------------------------
it "check-model: a hosted model passes"
out=$(check openrouter/example/model '[]'); assert_eq 0 "$?"

it "check-model: an empty model is refused"
out=$(check "" '[]'); rc=$?
assert_eq 2 "$rc"; has "$out" "CONFIG__MODEL"

it "check-model: a local model or local fallback is refused"
out=$(check ollama/llama3); rc=$?; assert_eq 2 "$rc"; has "$out" "local model"
out=$(check openrouter/x/y '["lm_studio/qwen"]'); rc=$?; assert_eq 2 "$rc"; has "$out" "local model"
out=$(check openrouter/x/y '["vLLM/m"]'); assert_eq 2 "$?"

it "check-model: an excluded family is refused, in the model or a fallback, ignoring case"
out=$(check openrouter/anthropic/Claude-x '[]' --exclude claude); rc=$?
assert_eq 2 "$rc"; has "$out" "claude"
out=$(check openrouter/x/y '["openai/gpt-6"]' --exclude gpt); assert_eq 2 "$?"
out=$(check openrouter/x/y '[]' --exclude claude --exclude gpt); assert_eq 0 "$?"

it "check-model: bad usage exits 2"
out=$(check); assert_eq 2 "$?"
out=$(check m '[]' --exclude); assert_eq 2 "$?"
out=$(check m '[]' --bogus); assert_eq 2 "$?"

printf 'passed=%d failed=%d\n' "$pass" "$fail"
[ "$fail" = 0 ]
