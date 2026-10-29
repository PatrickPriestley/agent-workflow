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
