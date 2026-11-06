# agent-workflow

A lightweight development loop that any coding agent can follow (Claude Code, Codex,
Cursor, Gemini), plus the two commands that make it hold:

- `skills/feature-loop`: probe, short design note, build red before green, mutation-check,
  independent review, push and open a PR. Stops only for merges, releases, deletions,
  impossible requests and real ambiguity.
- `skills/agent-review` and `bin/agent-review`: an independent review by a different kind
  of agent, run headless and read-only (`codex exec`, `claude -p`, `cursor-agent -p`,
  `gemini -p`, `opencode run`).
- `bin/commit-gate`: git hooks that refuse a commit when the tests fail, when the subject is
  not a Conventional Commit, or when the message or an added line carries AI attribution.
- `skills/intent`, `skills/spec`, `skills/plan`: the formal SDLC for changes that need
  agreement before code exists (see "Which loop to use"), and `skills/incident-to-eval`
  to turn a fixed production failure into a permanent regression case.
- `AGENT-WORKFLOW.md`: the rules every agent loads at session start.

## Which loop to use

Use the formal `intent` → `spec` → `plan` loop when the decisions need recording and agreeing
before code exists. Use `feature-loop` when you are the one deciding and the code plus a short
note is enough record.

Choose intent, spec and plan when any of these holds:

- **Someone else has to agree:** a teammate, a stakeholder or a reviewer of the
  requirements, not just of the code. Each stage ends at a human gate for that reason.
- **The problem is clearer than the solution.** The intent captures the problem in the
  originator's words; the spec is where competing designs are argued before anyone builds.
- **The change is hard to undo or crosses boundaries:** a data model or migration, a public
  API, a security or compliance surface, or work spanning several systems or teams. The spec
  stage applies the policy skills and flags concerns.
- **You need traceability later:** an audit trail, or "why did we build it this way"
  months on, with numbered requirements tied to the plan.
- **It is more than one PR of work,** or more than one person or agent builds pieces of it.

Choose feature-loop when you own the decision and can state the goal in a sentence, it fits
on one branch and one PR and can be reverted, and what is uncertain is technical (which
probing settles) rather than what should be built. Most day-to-day features, fixes,
refactors and tooling changes fall here.

In between:

- **A small change that still needs sign-off:** write the intent with `size: small`. It
  skips the spec stage, and the plan names one requirement.
- **Starting light and finding it bigger:** feature-loop stops when two readings of the
  request lead to different work, or when scope would grow. That is the moment to write an
  intent instead of pushing on.

A quick test: if you would be comfortable explaining the decision in a PR description after
the fact, use feature-loop. If someone should approve the decision before the code exists,
use the intent path.

### Known problem, solution needs approval

A long-standing production bug or batch-job failure, where the cause is understood, there
are several candidate fixes, and the chosen one must meet internal guidelines or be approved
by an architecture team, goes through the formal path. The alignment happens in the spec.

- **Intent: short and heavy on evidence.** Incident history, failure rates or failed runs,
  business impact and hard constraints (batch window, data volume, SLA). No solutions: the
  intent skill keeps them out so the problem record is not anchored to the first idea. The
  proposed outcome says what must be true afterwards, for example "the nightly run finishes
  within its window and a failure no longer needs a manual restart".
- **Spec: where the options are argued and approved.** Describe each candidate in the
  Design section with its trade-offs and the recommended one. The spec skill checks the
  design against every policy skill and turns each conflict into a concern with a named
  owner (for example the architecture team), which must be resolved before approval. A
  production batch job is usually `risk: high`, which makes `tech_lead_signoff` mandatory.
- **Plan: only after approval,** built from the chosen option. The rejected options go in
  its "Alternatives not taken" section with the reason each lost.

To make this work well:

1. **Write your architecture guidelines as policy skills** (`policy: true` in the skill's
   frontmatter). The spec skill checks only the policies it can find, and reports any area
   left unchecked rather than inventing standards.
2. **Attack the spec before the review meeting:** `agent-review plan docs/specs/<id>.md`
   has a different model hunt the chosen option for failure modes (restarts, partial runs,
   ordering, idempotency), so reviewers spend their time on the trade-offs.
3. **After the fix ships, run the `incident-to-eval` skill** to turn the production failure
   into a permanent regression case.

## Install

    ./install.sh            # links everything into place; safe to rerun
    ./install.sh --wire     # also give each installed agent the rules
    ./install.sh --dry-run  # show what it would do

Skills go into `~/.agents/skills` (read directly by Codex and Cursor) with `~/.claude/skills`
links for Claude Code; the commands go into `~/.local/bin`; the rules file is linked to
`~/AGENT-WORKFLOW.md`. `--wire` gives each installed agent the rules:

- **Claude Code:** one `@~/AGENT-WORKFLOW.md` import line in `~/.claude/CLAUDE.md`, added once.
- **Codex, OpenCode, Gemini:** `~/.codex/AGENTS.md`, `~/.config/opencode/AGENTS.md` and
  `~/.gemini/GEMINI.md` become links to the rules. A file there with its own content is left
  alone and named, so you can add the line yourself.
- **Cursor:** the CLI loads only `~/.cursor/rules/*.mdc`, and only in projects under your home
  folder, so `--wire` writes the rules into `agent-workflow.mdc`. Rerun it after changing the
  rules. A hand-written file there is kept as `.bak`.

Agents that are not installed are skipped.

A file in the way is replaced only when it equals the repo copy; anything else stops the
install and names the file. Updates are a `git pull`.

## Commit hooks, per repository

    commit-gate enable                              # conventional + no-attribution checks
    commit-gate enable --tests "cargo test --locked" # and run the tests on what is committed
    commit-gate status
    commit-gate disable

Turn a single check off with `git config commitgate.conventional false` or
`git config commitgate.attribution false`. `git commit --no-verify` bypasses everything.

## Review

    agent-review code                 # branch since main plus uncommitted work
    agent-review code --goal "page_up scrolls the focused pane"   # check feasibility first
    agent-review plan docs/plan.md    # attack a plan
    git config agentreview.reviewer codex   # default reviewer for this repository

The reviewer is never the caller's own kind. If it fails, the review switches to the same
reviewer's fallback model (`agentreview.<kind>.fallbackModel`; `sonnet` for Claude), then to
OpenCode Go (`agentreview.opencode.model`, default `opencode-go/kimi-k3.1-pro`). Local models
are refused. Exit 0 means a complete review, headed `Reviewed by: <kind> <model>`; 3 means
the reply had no end marker; 4 means every reviewer tried failed or timed out; 5 means a reviewer changed the working tree.

## PR-Agent

[PR-Agent](https://github.com/The-PR-Agent/pr-agent) can review each pull request on GitHub as
a second check. It does not replace `agent-review`, which runs before the push and reads
the receiver's code; PR-Agent makes one call over the diff after it.

- `.pr_agent.toml` keeps secret files away from the model, with globs that copy
  `agent-review`'s secret list (a test fails if they drift), and turns skills on.
- `pr-agent/skills/workflow-review/SKILL.md` has PR-Agent review against the rules in
  `AGENT-WORKFLOW.md`: real-system evidence, red-first tests, mutation results, the named
  reviewer, hands-on output, Conventional Commits and no AI attribution. It is kept out of
  `skills/` so that authoring agents do not load it.

`.github/workflows/pr-agent.yml` runs it on each pull request (opened, reopened, ready for
review, and on every push to it; not drafts or forks) and posts the review as a comment. Only `/review` runs. The model
is served by OpenCode Go, which PR-Agent reaches as an OpenAI-compatible endpoint. To turn it
on, add under Settings > Secrets and variables > Actions:

- secret `OPENCODE_GO_KEY`: the OpenCode Go API key. Without it the job ends with a notice.
- optional variable `PR_AGENT_MODEL`: another Go model, as `openai/<go-model-id>`. The default
  is `openai/glm-5.3`. Claude, GPT, Codex and local models are refused, since Claude and
  Codex author the pull requests here.
- optional variable `PR_AGENT_VERBOSITY=2` for a first run: the job log then shows the full
  prompt, to check that the skill loads and secret files stay out. Remove it afterwards.

The image is pinned by digest, because `the-pr-agent/pr-agent@<tag>` always pulls a moving
image. PR-Agent reads `.pr_agent.toml`
from the default branch only, so the workflow repeats the ignore globs, and a test fails if
they differ. Before each review, a step runs `pr-agent/verify-image.py` inside the same pinned
image and fails the job unless the globs filter sample secret paths and the skill loads. The
skill is read from the pull request's own checkout, which is fine while only
the owner opens pull requests. Both were verified in the pinned image on the first live run;
see `docs/plans/2026-11-02-pr-agent-review-skill.md`.

To try it locally, with nothing posted anywhere:

    python3.12 -m venv ~/.venvs/pr-agent && ~/.venvs/pr-agent/bin/pip install pr-agent==0.49.0
    export CONFIG__MODEL=openai/glm-5.3 OPENAI__API_BASE=https://opencode.ai/zen/go/v1 \
           OPENAI__KEY=<OpenCode Go key>      # or any hosted model not of the author's family
    pr-agent/scratch.sh            # two local test branches, and the three checks to run on them
    pr-agent/try.sh                # review this branch; also describe, improve
    pr-agent/try.sh --no-skill     # control run; --no-ignore and --verbose (log the prompts) too

PR-Agent ignores `.pr_agent.toml` in local mode, so `try.sh` passes the globs and the skill
as environment variables. It reviews committed work only, and refuses uncommitted changes to
tracked files because PR-Agent reads the working tree. Each run is kept in `.git/pr-agent/`.

## Tests and evals

    bash install.test.sh
    bash bin/commit-gate.test.sh
    bash bin/agent-review.test.sh
    bash pr-agent/pr-agent.test.sh   # needs python3 3.11 or later
    bash pr-agent/try.test.sh
    bash pr-agent/workflow.test.sh
    bash pr-agent/verify-image.test.sh
    claude plugin eval . --scaffold --allow-tools Bash Write Edit   # skill evals, with and without

The repository is also a Claude Code plugin (`.claude-plugin/plugin.json`), which is what
lets `claude plugin eval` load the skill. The eval cases in `evals/` run each scenario with
and without the skill in an isolated session.

## License

MIT; see [LICENSE](LICENSE).

### Native evaluation contexts

The optional plan execution workflow is named `execute-feature-plan`; the skill remains
`feature-loop`. Its file and installer link remain `workflows/feature-loop.js` for existing
installations. Distinct runtime names prevent the workflow from shadowing the skill's
activation description in Claude Code.

The false-review-finding task has three separate cases:

| Case | Context in both arms | What it measures |
| --- | --- | --- |
| `wrong-finding` | No installed working rules or explicit skill request | Automatic package skill discovery |
| `wrong-finding-rules` | Canonical working rules supplied directly in the prompt and copied into project `CLAUDE.md`, with a fallback for unavailable skills/helpers | Plugin benefit on top of the same written rules |
| `wrong-finding-explicit` | Conditional request to invoke `agent-workflow:feature-loop` if available | Compliance with an explicit invocation request, not automatic discovery |

Start with `wrong-finding-rules`, then compare the discovery and explicit cases separately.
All three use the same task and outcome graders. Native with/without ablation treats the
with-only `skill-fired` grader as an activation indicator rather than part of the score.
A good outcome without activation does not establish that the plugin caused that outcome.
The baseline receives the same prompt/context and can proceed without an absent skill.

These cases evaluate the plugin package, not a complete `install.sh --wire` environment:
`agent-review`, `commit-gate`, global configuration and additional reviewer credentials
are not installed by the scaffolds. The rules variant copies current repository rules
into the shared prompt and isolated project, rather than reading the user's home configuration.
Claude Code 2.1.316 did not automatically load the scaffold's `CLAUDE.md` in our real CLI
probe, so the prompt supplies the rules explicitly. The test checks for drift against
`AGENT-WORKFLOW.md`; update this fixture when the canonical rules change.

    node --test evals/context.test.cjs
    claude plugin eval . --case wrong-finding-rules --runs 1 --scaffold --allow-tools Read Bash Write Edit --trust-plugin --no-publish

The native CLI still applies its sandbox. Commit-dependent cases need a separate proven
Git capability check in the runner; this context change does not bypass that protection.

`red-first` evaluates test-first behavior only. Its former `committed` grader matched
an attempted Bash command and could pass even when Git failed; it and the commit request
have been removed. Successful Git writes were probed with native Claude Code 2.1.316 on
macOS, but hosted Linux writes remain unverified: the earlier hosted result reported a
read-only error without retaining the underlying tool trace. Older commit-oriented cases
outside this recommended CI set are not validated by these probes.
