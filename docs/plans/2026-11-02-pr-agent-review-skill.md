# PR-Agent: the working rules as a review skill, and secret files kept out

## Goal

Let PR-Agent (The-PR-Agent/pr-agent) review a pull request against the rules in
`AGENT-WORKFLOW.md`, and never send it a file that `agent-review` treats as a secret.
This repository gets a `.pr_agent.toml` and a text-only review skill. Running PR-Agent in
CI (the workflow file, the model key) is a later step.

## Probed facts (2026-11-02, PR-Agent `main` at 4686afb)

All are supported by the exact source. None was verified against a running PR-Agent when this
was written: installing and running it was not possible in that session. Later live runs
verified them; see "Image check, first live run" at the end.

- `pr_agent/algo/skills_loader.py`: `SKILL.md` needs `---` on the first line, a closing `---`,
  and a YAML mapping with non-empty `name` and `description`. Other `*.md` files in the skill
  folder are added to the prompt too; `scripts/` and `assets/` are skipped. The name,
  description and body go into the `/review`, `/improve`, `/describe` and `/ask` prompts,
  within `skills.max_skills_tokens` (default 8000).
- `pr_agent/config_security.py`: a repository may set `skills.enabled` and
  `skills.max_skills_tokens`, but not `skills.paths`, which only the host sets. A repository
  may set `ignore.glob` but not `ignore.regex`.
- `pr_agent/algo/file_filter.py`: each glob becomes `fnmatch.translate(glob)` and is matched
  with `re.match` against the file path, case-sensitively. `*` also matches `/`. A glob
  starting with `**/` also gets its root form (the glob without `**/`).
- `pr_agent/settings/ignore.toml`: the default `glob` is `['vendor/**']`. The `AGENTS.md` there
  says a repository's list replaces the default list rather than adding to it.
- PR-Agent docs (`automations_and_usage.md`): `.pr_agent.toml` is read from the default branch,
  so a pull request cannot change the ignore list used to review it.

## Decisions

1. **The skill lives in `pr-agent/skills/workflow-review/`, not in `skills/`.** `install.sh`
   and the Claude Code plugin give every folder under `skills/` to authoring agents. This one
   is guidance for a one-shot reviewer and would only add noise there. Rejected: adapting
   `feature-loop` itself, which is about 1,800 words of authoring process the reviewer
   cannot act on.
2. **The skill checks what the diff and PR description can show:** red-first tests, mutation
   evidence for new guards, evidence labels on claims about other systems, real-program
   output (#16), the named independent reviewer (#14), AI attribution, Conventional Commit
   titles, secrets. It does not ask for anything the reviewer cannot see.
   It also says that a missing evidence item is a finding, not a pass.
3. **The ignore globs copy `agent-review`'s `secret_re`, rule by rule,** and a test reads
   `secret_re` out of `bin/agent-review`, so the two cannot drift apart without a failure.
   Brackets such as `[sS]` make the globs match regardless of case, as `grep -i` does.
   The regex `(^|/)id_[a-z0-9]+$` cannot be written as a glob; see "First review" below for
   how it is covered.
   Rejected: a narrower list. Paths containing `token`, `secret` or `credential` are skipped
   whole, which also hides ordinary code with such names from review. That matches
   `agent-review` and the "never send secret files" rule; narrowing it is a policy change for
   both tools together (#4).
4. **`vendor/**` stays in the list,** because the repository list replaces PR-Agent's default.
5. **`.pr_agent.toml` turns skills on** (`skills.enabled = true`), which does nothing until the
   host points `skills.paths` at the skill folder.

## Tasks

1. `pr-agent/pr-agent.test.sh`, tests: "the config parses and keeps vendor/**", "every path
   agent-review calls a secret is ignored", "ordinary paths are still reviewed", "the globs
   and agent-review agree on every sample path", "the skill parses as PR-Agent parses it",
   "the skill fits well inside the token budget", "the skill is not installed for authoring
   agents". Then `.pr_agent.toml` and the skill.
2. CI runs the new test. README: a PR-Agent section.

## Local trial (added 2026-11-02)

`pr-agent/try.sh` runs PR-Agent's plain-diff mode on the branch; `pr-agent/scratch.sh` makes
two local branches to test it on. Further facts, from the exact source at 4686afb:

- `local_git_provider.get_repo_settings` and `plain_diff_provider.get_repo_settings` return
  nothing, so `.pr_agent.toml` is not read locally. `try.sh` passes `IGNORE__GLOB`,
  `SKILLS__ENABLED` and `SKILLS__PATHS` as environment variables instead. Assumed when
  written: Dynaconf parses the JSON list in `IGNORE__GLOB` as a list. Verified later in the
  pinned image (see "Image check, first live run"); a local install of another version is not.
- Plain-diff mode reads the changed files' working-tree contents into the prompt
  (`plain_diff_provider.py`), after the ignore filter. So `try.sh` refuses uncommitted changes
  to tracked files.
- `config.verbosity_level >= 2` logs the full system and user prompts
  (`litellm_ai_handler.py`), which is what the canary check greps.
- PR-Agent's default model is an OpenAI one, with an OpenAI fallback, so `try.sh` requires
  `CONFIG__MODEL`, sets no fallback unless one is given, and refuses local providers.

Decisions: the scratch branches are created locally in a temporary worktree and never
pushed (rejected: pushed branches, which would put the fake secret on GitHub for no gain,
since local mode needs no PR). `try.sh` runs PR-Agent with `python -I` so a `pr_agent/`
folder in the reviewed repository cannot shadow the installed package. Its globs are
agent-workflow's plus the reviewed repository's own, so another repository's config can add
to the secret list but not drop it.

Tests: `pr-agent/try.test.sh`, with a fake PR-Agent.

## GitHub workflow (added 2026-11-02)

`.github/workflows/pr-agent.yml` runs `/review` on pull requests. Facts:

- Exact source, `action.yaml` and `Dockerfile.github_action_dockerhub` at 4686afb: the action
  wrapper builds `FROM pragent/pr-agent:github_action`, a moving tag, whatever ref the
  `uses:` line names. `SECURITY.md` recommends `docker://pragent/pr-agent@sha256:<digest>`.
- Docker Hub API, 2026-11-02: `pragent/pr-agent:0.49.0-github_action` is the index digest
  `sha256:b1ed6e8de56eb4d6e4169ee0d5c209bb5ed1ef071a01c0c042c64b80192a785c` (amd64
  `sha256:cf517e40...`, arm64 `sha256:d76c21f7...`), pushed 2026-10-25. The registry itself
  rate-limited the session, so this comes from the Hub API, not a manifest read. Not checked:
  the image's build attestation (`gh attestation verify`).
- Exact source: the image's entrypoint runs `pr_agent/servers/github_action_runner.py`;
  settings load from every environment variable (`envvar_prefix=False`), so `CONFIG__MODEL`
  style names work as they do for `try.sh`. `fail_on_tool_errors` fails the Action on a
  recorded tool failure.
- Assumed: the runner mounts the checkout at `/github/workspace` inside the container, as it
  does for Docker actions, so `SKILLS__PATHS` finds the skill there.

Decisions:

1. **Pinned by digest**, with the version and date in a comment. Rejected: `@v0.49.0` of the
   action, which pins nothing that runs.
2. **Model from the variable `PR_AGENT_MODEL`, key from the secret `OPENROUTER_KEY`** (superseded: see "OpenCode Go as the model"). Without
   them the job ends with a notice instead of failing every pull request. The model goes
   through `pr-agent/check-model.sh` (shared with `try.sh`) with Claude, GPT, Codex and
   `openai/` excluded, the families that author pull requests here, and no fallback models.
3. **`pull_request` only, opened, reopened, ready for review, and every push
   (`synchronize`, added at the owner's request after the first run: a fix pushed to a PR
   otherwise got no fresh review); no drafts or forks.** Verified in run 41527871923: PR-Agent
   logs "Skipping action: synchronize" unless `handle_push_trigger` is on, and then runs
   `push_commands`, whose default (`/describe`, `/review`, from `github_app`) would rewrite the
   PR body; the workflow sets it to `/review`. Rejected for now: `issue_comment`
   commands.
4. **Only `/review`.** `/describe` rewrites the PR body, which a squash merge copies into the
   commit (rule 6); `/improve` waits until the reviews prove useful.
5. **The skill comes from the pull request's own checkout,** so this branch can test itself.
   Rejected for now: checking out the default branch, which has no skill until this merges.
   Revisit before anyone but the owner opens pull requests.
6. **The ignore globs are repeated in the workflow,** since PR-Agent reads `.pr_agent.toml`
   only from the default branch; `pr-agent/workflow.test.sh` fails if the two differ.
7. **Prompt logging only on request** (`PR_AGENT_VERBOSITY`), because the log keeps the diff.

## OpenCode Go as the model (added 2026-11-02)

The workflow uses OpenCode Go instead of OpenRouter, at the owner's request.

- Exact source, OpenCode at 1bf08ae (`packages/console/app/src/middleware.ts`): `/zen/go/v1/*`
  on opencode.ai is Go's inference API. Its FAQ (`i18n/en.ts`): "you can use Go with any
  agent"; $10 a month. Its model list (`routes/go/index.tsx`): Kimi K3.1 Pro has 0-day
  retention and is not used for training; Go also serves GPT and Claude models.
- PR-Agent docs (`changing_a_model.md`): an OpenAI-compatible endpoint takes the `openai/`
  model prefix with `OPENAI__API_BASE` and `OPENAI__KEY`.
- Assumed, not probed (opencode.ai is outside this session's network): the endpoint accepts
  OpenAI chat completions at `https://opencode.ai/zen/go/v1`, and the model ID is
  `kimi-k3.1-pro`, as in OpenCode's `opencode-go/kimi-k3.1-pro`. The first workflow run, or
  `curl .../zen/go/v1/models` with the key, settles both. Verified later: the endpoint
  answered OpenAI-style, and `kimi-k3.1-pro` was routed upstream (Actions run 41528638829).

Decisions: the key is the secret `OPENCODE_GO_KEY`; the model defaults to
`openai/kimi-k3.1-pro`, the same model `agent-review` falls back to, so only the secret is
required. `check-model.sh` no longer excludes `openai/`, which PR-Agent needs as the prefix,
but still refuses names containing claude, gpt or codex. Rejected: keeping OpenRouter
alongside, which doubles the setup for one reviewer.

## First live run (PR #27, Actions run 41526750774)

Verified against the real system:

- The digest-pinned image runs as a Docker step, and the `GITHUB_ACTION_CONFIG__*` settings
  take effect ("auto_describe=False, auto_review=True, auto_improve=False").
- `fail_on_tool_errors` turns a failed model call into a red job, so a broken run cannot pass
  as a clean review (check 3).
- `https://opencode.ai/zen/go/v1` answers as an OpenAI-compatible endpoint, but rejected the
  call: "Request is missing x-opencode-session and cannot be routed efficiently". OpenCode's
  docs (`services/www/src/docs/content/console/go.mdx`, "Where can I use it?") ask every
  client to send coding-agent traffic, name itself in its user agent, and send one stable
  `x-opencode-session` per conversation.
- PR-Agent capped the prompt at 32,000 tokens ("total tokens under limit: 32000") even with
  `custom_model_max_tokens` at 100,000; this PR's diff (23,014 tokens) fitted whole.

Fix: `LITELLM__EXTRA_HEADERS` (a JSON object, host-only in PR-Agent) sends
`User-Agent: pr-agent/0.49.0 (agent-workflow)` and `x-opencode-session:
pr-agent-<repository id>-<PR number>`, one session per pull request, in the workflow;
`try.sh` sends the same for Go with one session per branch head, unless the caller set
headers. Rejected: posing as OpenCode's own client. Not yet seen: the model ID being
accepted, and the skill loading.

## Third live run (Actions run 41528638829)

Verified against the real system: with the headers, Go accepted the request and passed it
upstream, so the endpoint and the model ID `kimi-k3.1-pro` are right. The model then refused
it: "invalid temperature: only 1 is allowed for this model". PR-Agent sends `temperature=0.2`
unless the model is in `config.no_temperature_models`. That list at `v0.49.0` (the pinned
image) lacks `kimi-k3` and `kimi-k3.1-pro`; `main` at 4686afb has both, matched through any
provider prefix. The workflow and `try.sh` (for Go) therefore set `CONFIG__NO_TEMPERATURE_MODELS`
to `main`'s list, keeping every 0.49.0 entry. Rejected: `CONFIG__TEMPERATURE=1`, which would
also change models that do accept a low temperature. Drop the override when the pin moves past
a release that lists Kimi.

## Fourth live run (Actions run 41529229286)

Verified: with no temperature sent, Kimi took the request, but the call ran 361 seconds
against PR-Agent's `ai_timeout` of 120 ("Request timed out ... time taken=361.52 seconds"),
and the job spent about 13 minutes in retries. The workflow now sets `CONFIG__AI_TIMEOUT=600`,
`CONFIG__NUM_RETRIES=0` (LiteLLM's retries multiply PR-Agent's own) and a 25-minute job
limit. Rejected for now: a faster Go model, which would trade review depth for speed; worth
revisiting if reviews keep taking minutes.

## First review (PR-Agent comment on 189c1eb)

PR-Agent's one finding was real: the four ssh key names left any other `id_<name>` file,
which `agent-review` treats as a secret, free to reach the model (`keys/id_work`). Decision 3's
"known gap" was the wrong call. The globs now skip `**/[iI][dD]_*`, a superset of the regex
that also skips ordinary names such as `id_utils.py`. `pr-agent.test.sh` checks the globs skip
everything the regex calls a secret, and that each extra skip is listed as an accepted
over-match.

## Default model: GLM-5.3 (owner's decision, after Actions run 41533824510)

Verified against the real system: Kimi K3.1 Pro through Go produced one review in four tries.
The rest failed on the 120-second default, then twice on the full 600 seconds, with
PR-Agent retrying once, for a 20-minute job. The default is now `openai/glm-5.3` (Go lists it
with 0-day retention and no training on request data). Assumed until its first run: that Go
serves it under that ID, and that it accepts PR-Agent's temperature of 0.2. Verified on fc90996:
GLM-5.3 wrote PR-Agent's review there, and on 752a535 in about seven minutes. Kimi stays
available through `PR_AGENT_MODEL`, and the no-temperature list still covers it.

## Second review (GLM-5.3, on fc90996)

GLM-5.3 produced the review, so Go serves `glm-5.3` and accepts temperature 0.2 for it
(verified). Its blocking finding was fair: the globs and the skill had no real-system evidence
against the pinned image. Exact source at `v0.49.0` has the skills loader, but a plain-string
`SKILLS__PATHS` would become one path that does not exist (no skill, silently), and a
plain-string `IGNORE__GLOB` would be split on commas with its JSON quotes kept, matching
nothing (secrets sent, silently). Whether Dynaconf parses those values as lists was assumed.

Decision: a workflow step runs `pr-agent/verify-image.py` inside the same pinned image, with
the same job-level settings, before every review. It fails the job unless both settings are
lists, PR-Agent's own `filter_ignored` drops sample secret paths and keeps ordinary ones, and
`get_skills_context()` contains the workflow-review skill. Rejected: a one-off probe, which
would go stale when the pin moves.

## Image check, first live run (Actions run 41538960049, 752a535)

Verified against the real system, in the pinned image with the workflow's settings:
`verify-image: ok: globs and skills paths are lists, 9 secret paths filtered, 4 ordinary paths
kept, workflow-review loaded`. So the 0.49.0 image parses `IGNORE__GLOB` and `SKILLS__PATHS`
as lists, PR-Agent's own `filter_ignored` drops `.env`, `keys/id_work`, `config/secrets.yml`
and the other samples, and the skill is in its prompt context. The step runs before every
review, so a later image or setting that breaks this fails the job.

Seen in the same run: PR-Agent caps the prompt at 32,000 tokens (`config.max_model_tokens`).
This PR's diff reached 30,723 tokens and `.github/workflows/test.yml` was left out of the
review. Raising the cap, which repositories with large PRs (pactling) will need, is left for
then.

## Local run (PR-Agent review on 83d902c)

PR-Agent found `try.sh`'s command line unverified: the README installed an unpinned
`pr-agent`, and the plain-diff flags came from `main`. Exact source at `v0.49.0`: `cli.py`
defines `--stdin`, `--output` and `--json-output` (lines 165 to 172) and runs as `-m`; PyPI
has `pr-agent` 0.49.0. The README and `try.sh` now install `pr-agent==0.49.0`, the image's
version (a test keeps the two equal), and `verify-image.py` also checks, in the image, that
`python -m pr_agent.cli --help` lists every flag `try.sh` passes. Still not run: a local
review with a real model, which the scratch branches are for.

## Plain-diff filtering (PR-Agent review on 961060b)

PR-Agent flagged that `try.sh`'s plain-diff mode relied on the ignore filter, sourced from
`main`. Exact source at `v0.49.0`: `PlainDiffGitProvider.get_diff_files` calls
`filter_ignored(files, platform="plain_diff")` (line 62), and `filter_ignored` handles
`plain_diff` (line 54). `verify-image.py` now also feeds that provider, in the image, a
synthetic diff adding `.env`, `keys/id_work`, `config/secrets.yml` and `README.md`, each with
a canary line, and fails unless only `README.md` comes back. A local review with a real model
(the scratch canary branch) is still for the owner to run.

## Checking

`bash pr-agent/pr-agent.test.sh` with the other suites; mutation-check each test guard by
removing a glob or breaking the skill frontmatter; review by a model family other than the
author's.
