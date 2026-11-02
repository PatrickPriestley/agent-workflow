# Reviewer fallback: change the model, then OpenCode Go, never a local model

## Goal

When the chosen reviewer fails (out of credits, crash, timeout), `agent-review` should
still produce a strong independent review: first by the same CLI with a different model,
then by OpenCode with an OpenCode Go model. It must never use a local model.

Why: on 2026-11-01 every Claude review run from Codex failed with "You're out of usage
credits. Switch to another model". The author fell back by hand to a local Gemma model,
whose eight reviews all reported no findings, while a human-side review of one of those
diffs found two real defects.

## Probed facts (2026-11-01, this machine)

- Verified against the real system: `claude -p "Reply with exactly OK"` on the default
  model exits 1 and prints the out-of-credits message; the same with `--model sonnet`
  exits 0 and prints OK.
- Verified: OpenCode 1.19.4 is installed with an OpenCode Go credential;
  `opencode models` lists `opencode-go/*` models. `opencode run -m opencode-go/kimi-k3.1-pro`,
  `qwen3.8-max` and `glm-5.3` each answered a one-line prompt headless.
- Verified: an agent defined in `OPENCODE_CONFIG_CONTENT` with permissions
  `{"*":"deny","read":"allow","grep":"allow","glob":"allow","list":"allow"}` read a file
  (including one under `.git/agent-review/`) and could not edit, create or run a shell
  command; the file and directory were unchanged afterwards.
- Verified, and the reason for the rule above: the same agent with the deny rules first and
  `"*":"allow"` last overwrote a file and ran `touch`. The last matching rule wins. The
  built-in `plan` agent also lists `"*":"allow"` and no deny rules.

### Added during review (all 2026-11-01)

- Verified with OpenCode 1.19.4: a repository whose committed `opencode.json` sets
  `"permission":{"*":"allow"}` and `agent.agentreview` with `"*":"allow"` made a reviewer
  under that fixed name overwrite a file and run `touch`. OpenCode also rewrote that file on
  load, adding `"$schema"`. With `OPENCODE_DISABLE_PROJECT_CONFIG=1` the same request under the
  fixed name could not write, and the file stayed unchanged.
- Verified end to end: `agent-review code --reviewer opencode`, final command line, in that
  hostile repository completed with `Reviewed by: opencode opencode-go/kimi-k3.1-pro`, exit 0,
  and a clean `git status`.
- Supported by exact source (reviewer's trace of 1.19.4): `OPENCODE_CONFIG` and
  `OPENCODE_CONFIG_DIR` load regardless of that flag, so both are unset for the reviewer.
- Verified with Codex 0.166.0: `codex exec -c 'model_provider="openai"'` answers with the
  configured default, and `-m gemma4:e4b` with that override fails ("not supported").
  `-c model_provider="ollama" -m gemma4:e4b` runs the local model. The run header prints
  `model: gpt-6-astra` and `provider: openai`; a real `agent-review code` run reported
  `codex gpt-6-astra`.
- Verified: an endless `tr -dc ... </dev/urandom | head -c 12` hung under the pre-commit
  hook. The agent name now comes from `od -An -N8 -tx1 /dev/urandom`.

## Decisions

1. **New reviewer kind `opencode`**, read-only through the deny-by-default inline agent
   above, run with `--agent agentreview`. Rejected: OpenCode's `plan` agent (no enforced
   deny rules, probed) and a config file on disk (state outside the run).
2. **Only OpenCode Go models** (`opencode-go/...`) for that kind; anything else is a usage
   error. Default `opencode-go/kimi-k3.1-pro`, overridable with
   `git config agentreview.opencode.model`. Rejected: allowing any OpenCode provider, which
   includes local ones (Ollama, LM Studio).
3. **Same family stays excluded** for every reviewer: a model whose name contains `claude` is
   refused for a Claude caller, and one containing `gpt` or `codex` for a Codex caller.
   Codex always runs with `-c model_provider="openai"` so its config cannot select a local
   model; the model it used is read from its run header.
   Open (minor): Claude, Cursor and Gemini defaults are reported as "default model"; edits to
   pre-existing untracked files are not detected (#22).
4. **Fallback chain on failure** (non-zero exit or timeout, exit 4 today): the chosen
   reviewer and model; then the same reviewer with `git config agentreview.<kind>.fallbackModel`
   (built-in for Claude: `sonnet`); then `opencode` with its Go model, unless already tried.
   A reply without the end marker stays exit 3 and does not fall back: the reviewer ran, so
   rerun it. Rejected: falling through every installed kind, which could pick a weak or
   local one, and retrying the same model.
5. **Never a local model.** `--model` values naming a local provider (`ollama/`, `lmstudio/`,
   `llama.cpp`, `local/`) are refused for every kind, and the rules say a review by a local
   model does not count.
6. **Say who reviewed.** Each failed attempt is reported on stderr; the review on stdout
   starts with `Reviewed by: <kind> <model>`, and `reviewer.txt` in the run folder records
   the same, so a PR can name the reviewer actually used.

## Tasks

1. `bin/agent-review.test.sh`: fake `opencode`; tests "opencode reviews read-only with a Go
   model", "a non-Go opencode model is refused", "a local model is refused", "a same-family
   opencode model is refused", "a failing reviewer falls back to its fallback model",
   "then to OpenCode Go", "all attempts failing exits 4 and lists them", "no end marker
   does not fall back", "the review names the reviewer used". Then `bin/agent-review`.
2. `AGENT-WORKFLOW.md` rule 4, `skills/agent-review/SKILL.md`, `README.md`: the fallback
   and "never a local model".

## Checking

`bash bin/agent-review.test.sh` and `bash install.test.sh`; mutation-check each new guard;
one real run of `agent-review code` against this branch by a reviewer other than Claude.
