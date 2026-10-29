# agent-workflow

A lightweight development loop that any coding agent can follow (Claude Code, Codex,
Cursor, Gemini), plus the two commands that make it hold:

- `skills/feature-loop`: probe, short design note, build red before green, mutation-check,
  independent review, push and open a PR. Stops only for merges, releases, deletions,
  impossible requests and real ambiguity.
- `skills/agent-review` and `bin/agent-review`: an independent review by a different kind
  of agent, run headless and read-only (`codex exec`, `claude -p`, `cursor-agent -p`,
  `gemini -p`).
- `bin/commit-gate`: git hooks that refuse a commit when the tests fail, when the subject is
  not a Conventional Commit, or when the message or an added line carries AI attribution.
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
    ./install.sh --dry-run  # show what it would link

Skills go into `~/.agents/skills` (read directly by Codex and Cursor) with `~/.claude/skills`
links for Claude Code; the commands go into `~/.local/bin`; the rules file is linked to
`~/AGENT-WORKFLOW.md`. Point each agent's config at it, for example a line in
`~/.claude/CLAUDE.md` or `~/AGENTS.md`: `Follow the rules in ~/AGENT-WORKFLOW.md.`

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
    agent-review plan docs/plan.md    # attack a plan
    git config agentreview.reviewer codex   # default reviewer for this repository

The reviewer is never the caller's own kind. Exit 0 means a complete review; 3 means the
reply had no end marker; 4 means the reviewer failed or timed out.

## Tests and evals

    bash install.test.sh
    bash bin/commit-gate.test.sh
    bash bin/agent-review.test.sh
    claude plugin eval . --scaffold --allow-tools Bash Write Edit   # skill evals, with and without

The repository is also a Claude Code plugin (`.claude-plugin/plugin.json`), which is what
lets `claude plugin eval` load the skill. The eval cases in `evals/` run each scenario with
and without the skill in an isolated session.

## License

MIT.
