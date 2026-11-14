---
id: 2026-11-14-review-by-openai
tier: 1
status: open
requester: Patrick Priestley, in chat on 2026-11-14 ("Point agent-review at another model"; "Codex, OpenAI API key in cloud" to which reviewer; "Yes, move it too" to "Should it [the CI review bot] move to the new provider too?")
approvers: []
---
# The review on pull requests is done by an OpenAI model

## Goal

No independent review has run for weeks: the account both reviewers fall back to (OpenCode
Go) has no balance. The owner chose OpenAI as the other family. This record moves the review
bot that runs on every pull request; `agent-review` itself needs no change for Codex, only a
key, which is not in this session yet.

## Probed facts

- Exact source (`.github/workflows/pr-agent.yml` on `main` at `bf3901e`): PR-Agent reaches
  OpenCode Go as an OpenAI-compatible endpoint (`OPENAI__API_BASE`, the secret
  `OPENCODE_GO_KEY`, two headers Go requires), with `openai/glm-5.3`; `check-model.sh` is
  called with `--exclude claude --exclude gpt --exclude codex`.
- Exact source (record `2026-11-11-grading-trust`, Probed facts, and the one comment on each
  of pull requests 42 to 64): the review job failed with the provider's "Insufficient
  balance" each time it ran. Since 2026-11-13 it has not started at all.
- Exact source (the `pr_agent` 0.49.0 wheel from PyPI, the version the workflow pins by
  digest): `pr_agent/algo/__init__.py` has a token limit for `gpt-6.1-sol`, `gpt-6-sol`,
  `gpt-6-astra`, `gpt-6-luna`, `gpt-5.6`, `gpt-5.4`, `gpt-5.3-codex` and others, under their
  bare names. It requires `litellm==1.105.1` and calls `litellm.acompletion`. Whether a model
  takes a temperature is read from litellm's own table (`_litellm_supports_temperature`).
  A known model's token limit comes from that file; `custom_model_max_tokens` is for unknown
  ones (`token_budget.py`).
- Exact source (the `litellm` 1.105.1 wheel, its bundled model table, which may be out of
  date): `gpt-6.1-sol` is `mode: chat`, provider `openai`, 922,000 tokens of context, 2.00
  dollars per million tokens in and 10.00 out. `gpt-6-astra` is 10.00 and 50.00.
  `gpt-5.3-codex` is `mode: responses`, served only at `/v1/responses`.
- Verified against the real system (`codex-cli` 0.169.0, installed from npm in this
  container; `codex exec --help`): every flag `bin/agent-review` passes to Codex exists
  (`--sandbox read-only`, `--skip-git-repo-check`, `--ephemeral`, `-o`, `-m`, `-c`).
- Assumed (a web search's summary of OpenAI's page on non-interactive mode; the page cannot
  be opened from this session): `codex exec` takes an API key from `CODEX_API_KEY`.
- Not probed: no call to OpenAI was made. This session has no OpenAI key, and its network
  does not reach `api.openai.com`.
- Verified against the real system (the runs of 2026-11-14, GitHub API): GitHub Actions
  starts no job for this repository, so the changed workflow cannot run here.

## Decisions

- PR-Agent calls OpenAI itself: the key is the secret `OPENAI_API_KEY`, no base URL, and
  the two headers Go required go. The secret stays on the review step alone, as before.
- The default model is `gpt-6.1-sol`, under its bare name, which is how PR-Agent's own
  table knows it. A review of 16,000 tokens in and 3,000 out would cost about six cents at
  the table's price. The variable `PR_AGENT_MODEL` still names another. Rejected:
  `gpt-5.3-codex`, which the pinned litellm serves only through another endpoint than the
  one PR-Agent calls; `gpt-6-astra`, five times the price.
- The guard refuses Claude and local models, and no longer refuses GPT and Codex: the
  reviewer is one. Claude wrote every pull request in this repository so far. A pull request
  written by Codex would be reviewed here by its own family; `agent-review`, before the
  push, still refuses that.
- `CONFIG__CUSTOM_MODEL_MAX_TOKENS` goes: it was for Go's models, which PR-Agent does not
  know. The no-temperature list stays as it is; it names no model used now, and
  `pr-agent/try.sh`, which can still try a Go model, shares it.
- `pr-agent/try.sh` is not changed: it takes whatever provider its environment names.

## Tasks

1. `.github/workflows/pr-agent.yml` and the README's section on it. Test: in
   `pr-agent/workflow.test.sh`, the key's secret, no base URL, no extra headers, the default
   model, the guard's words, the notice. They fail today.

## Checks

`bash pr-agent/workflow.test.sh` and the suites beside it. Real use is not possible here:
see Probed facts. The record stays open, and the work a prototype, until one pull request
shows a review written by the new model. Error path: the secret is missing (the job ends
with a notice, as today). The reviewer should attack: a model name the guard should refuse
and does not, and the key reaching a step that runs the pull request's own code.

## Outcome

Shipped, and a prototype until a pull request shows a review by the new model:
`.github/workflows/pr-agent.yml` calls OpenAI with the secret `OPENAI_API_KEY`, no base URL
and no extra headers, with `gpt-6.1-sol` unless `PR_AGENT_MODEL` names another, and its
guard refuses Claude and local models only; the README's section on it.
`pr-agent/workflow.test.sh` goes from 61 assertions to 69; the suites beside it pass
unchanged (`pr-agent` 11, `try` 78, `verify-image` 16, `ci-workflow` 13). The workflow
parses as YAML.

Red first: 11 assertions failed on the workflow as it was, among them

    FAIL PR-Agent calls OpenAI itself with the OpenAI key: no base URL, and nothing of OpenCode Go is left
         expected [${{ secrets.OPENAI_API_KEY }}] got [${{ secrets.OPENCODE_GO_KEY }}]
    FAIL the model is checked before PR-Agent runs: Claude, who writes the pull requests here, is refused, ...
         the reviewer's own family is excluded
    FAIL the key is named on the review step and in the one expression that asks whether it is set, nowhere else
         expected [2] got [0]

One assertion of that commit was wrong in the test, not the workflow: it took `zai.glm-5`,
a name in the no-temperature list, for a setting of OpenCode Go. It now looks for
`openai/glm`, and is corrected in the fix's commit.

Guards: 11 broken by hand in the workflow's text; all 11 failed the test.

Not verified against the real system, and why:

- No review has run. GitHub Actions starts no job for this repository, and the secret
  `OPENAI_API_KEY` does not exist yet.
- No call to OpenAI was made from this session: it has no key and its network does not
  reach `api.openai.com`. That `gpt-6.1-sol` exists and is served at the chat endpoint is
  from the tables inside the two pinned packages, not from OpenAI.

What the reviewer was asked to attack:

- A model name the guard should refuse and does not. The guard matches the word `claude`
  in the model's name, ignoring case. A Claude model served under a name without that word
  would pass, as before this change.
- The key reaching a step that runs the pull request's own code. It is named on the
  PR-Agent step and in one expression that only asks whether it is set; a test fails if a
  secret is set for the whole job. The job runs for pull requests from this repository
  only, not from forks.

Not done:

- `agent-review` with Codex. It needs no change to the tool: `codex-cli` 0.169.0 has every
  flag it passes. It needs an OpenAI key this session can use and a network that reaches
  OpenAI. The owner declined moving this session to the repository's own environment, where
  the key would be saved, so no key was asked for.
- The owner adds the secret `OPENAI_API_KEY` to the repository. The secret
  `OPENCODE_GO_KEY` is no longer read and can be removed.
