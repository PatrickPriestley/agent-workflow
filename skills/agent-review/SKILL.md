---
name: agent-review
description: Use when finished work needs an independent review by a different kind of agent before it is pushed, or when a plan or design should be attacked before implementing it.
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

Options: `--reviewer codex|claude|cursor|gemini`, `--model M`, `--timeout SECONDS`. Set a
default with `git config agentreview.reviewer codex` and a model with
`git config agentreview.codex.model <model>`. It refuses to use your own kind.

## Reading the result

| Exit | Meaning | What to do |
|---|---|---|
| 0 | Complete review on stdout, ending with the end marker | Evaluate the findings |
| 3 | No end marker | Not a review. Run it again, or with a longer `--timeout` |
| 4 | The reviewer failed or timed out | Read the log path it prints; fix or pick another reviewer |
| 2 | Usage or setup problem | Read the message |

## Evaluating findings

Findings are claims, not orders. For each one, probe it against the real code. Fix verified
ones test-first, dismiss one only when a probe or cited code shows it cannot happen, and list
minor ones for the owner. After fixing, run `agent-review` again on the new commits until no
critical or important finding remains.

The review material is kept in `.git/agent-review/<run>/` (prompt, diff, review, log) and is
never committed.
