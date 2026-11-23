---
name: agent-review
description: Use when finished work should get a review by a different kind of agent before it is pushed, or when a plan or design should be attacked before implementing it.
---

# Agent Review

Run `agent-review`, which starts a different kind of agent headless and read-only, gives it
the pinned diff (or the plan), and prints its findings. It works the same from Claude Code,
Codex, Cursor or a terminal; no multiplexer is needed.

```bash
agent-review code                 # the branch since main, plus uncommitted work
agent-review code BASE..HEAD      # an explicit range
agent-review plan path/to/plan.md # attack a plan before building it
```

Pass `--goal "<the outcome asked for>"` so the reviewer can check first whether the change
can achieve it: it traces every new call to another system through the receiver's own
validation and treats missing real-system evidence as blocking.

Options: `--reviewer codex|claude|cursor|gemini|opencode`, `--model M`, `--timeout SECONDS`.
Set a default with `git config agentreview.reviewer codex` and a model with
`git config agentreview.codex.model <model>`. It refuses to use your own kind.

If the reviewer fails or times out (for example out of credits), it falls back by itself:
first the same reviewer with `git config agentreview.<kind>.fallbackModel` (Claude: `sonnet`
built in), then OpenCode with an OpenCode Go model (`git config agentreview.opencode.model`,
default `opencode-go/kimi-k3.1-pro`). OpenCode takes only `opencode-go/` models, never one of
your own family. A local model is always refused, and a review by one does not count: never
run one by hand as a substitute. The first line of the output, `Reviewed by: <kind> <model>`,
names the reviewer actually used; report that one.

## Reading the result

| Exit | Meaning | What to do |
|---|---|---|
| 0 | Complete review on stdout, ending with the end marker | Evaluate the findings |
| 3 | No end marker | Not a review. Run it again, or with a longer `--timeout` |
| 4 | Every reviewer tried failed or timed out, fallbacks included | Read the log path it prints; stop and tell the owner. Never substitute a local model |
| 2 | Usage or setup problem | Read the message |
| 5 | The reviewer changed the working tree | Not a review. Inspect `git status`, restore, report it |

## Evaluating findings

Findings are claims, not orders. For each one, probe it against the real code. Fix verified
ones test-first, dismiss one only when a probe or cited code shows it cannot happen, and list
minor ones for the owner. After fixing, run `agent-review` again on the new commits until no
critical or important finding remains. A complete review means the reviewer finished, not
that the change works.

The review material is kept in `.git/agent-review/<run>/` (prompt, diff, review, log) and is
never committed.
