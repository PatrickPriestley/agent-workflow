---
name: plan
description: Start AI-native SDLC Stage 3 Build for an approved spec. Produces the plan (docs/plans/<change_id>.md, or plans/ without docs/) while read-only, gets it accepted before any code, then runs a test-first build loop with verification. Use when a spec is approved, or when asked to plan and build a change.
---

`<root>`, artifact paths, `change_id` and "accept" follow the conventions in the `intent`
skill.
The rule this skill enforces: **nothing is implemented without an accepted plan.**

## 0. Find the verify commands

Read the Commands section of the agent instructions file (per Conventions). If it has
none, detect them (Makefile targets, `package.json` scripts, `Cargo.toml`,
`pyproject.toml`, `go.mod`) and ask the engineer to confirm build, test and lint. Offer
to add them to `AGENTS.md`, each with an
example of healthy output. You need one command per check that exits non-zero on failure.

## 1. Preconditions

`git fetch` if there is a remote. `<root>specs/<change_id>.md` must be on the default branch
with `status: approved`. If not, stop and finish the `spec` skill first, unless the accepted
intent's frontmatter says `size: small`: a small change has no spec. Then there must be no
spec for it, the plan's only requirement is `R1`, the intent's Proposed outcome, and each
step's contract carries `planned_lines`, your estimate of lines changed. At acceptance the
plan is measured: over 3 files, 50 planned lines or one requirement means offering the spec
stage instead, which the owner can override with a recorded reason.

## 2. Plan (read-only)

Work read-only until the plan is accepted: no file edits, no commits. Use the agent's
read-only mode if it has one, and ask the engineer to switch if the session is not in it:
Claude Code plan mode (Shift+Tab, or `claude --permission-mode plan`), Codex
`--sandbox read-only`, Cursor Ask mode in the editor (or `cursor-agent --mode plan`),
Gemini CLI `--approval-mode plan`. Without such a mode, hold
yourself to it. Read the intent, the spec and the code.
Draft a plan with this shape:

```markdown
---
change_id: <change_id>
status: draft          # draft -> approved -> implemented | diverged
accepted_by: null
accepted_on: null
divergences: []
---
# Plan: <title> (from <root>specs/<change_id>.md, or <root>intent/<change_id>.md for a small change)
## Files that change
## Order of work        (numbered steps, each naming the requirement ids it covers)
## Tests that prove it  (per step: test name, what it asserts, why it fails today)
## Risks
## Alternatives not taken
```

## 3. Interrogate

Interview the engineer the way the `intent` skill interviews the originator: each
message holds exactly one question, and you wait for the answer before the next. Cover
what this could break, which step is most risky, and what options were rejected and why;
write the answers into the plan. Iterate until someone who never saw this conversation
could implement it from the plan alone.

## 4. Accept before code

Who accepts: the engineer for routine changes; a tech lead or architect when the spec
is `risk: high` or touches auth, payments, migrations or infra. The author of a
high-risk plan does not accept it. Solo, you accept, but note the risk in the plan.

On acceptance, leave read-only mode, write `<root>plans/<change_id>.md` with `status: approved`,
`accepted_by`, `accepted_on`, and accept it on its own:
- With a remote: branch `plan/<change_id>`, PR with only the plan, merge. The merge
  records that the plan preceded the code. (A solo owner cannot approve their own PR,
  so merging is the acceptance.)
- Without a remote: commit the plan on its own branch (`plan/<change_id>`, or
  `plan/<key>/<change_id>` in the store in external mode), then accept it with
  `git merge --no-ff` and an `Accepted-by:` trailer, per the intent skill's Conventions.
  Stage only the plan file; follow the user's commit rules on trailers.

## 5. Build, test-first

Branch `feat/<change_id>` from the updated default branch (use a worktree,
`git worktree add ../<repo>-<change_id> -b feat/<change_id>`, if other sessions are
running). For each plan step:

1. **Red.** Write the step's test. Run it. It must fail, and for the reason the plan
   gives. If it passes or fails for another reason, fix the test first. Commit
   `test: <change_id> step N`.
2. **Green.** Make it pass **without editing any test file committed in the red step**.
   Verify with `git diff HEAD~1 --stat -- <test paths>` before committing; if a test
   must change, stop and tell the engineer why. Commit `feat: <change_id> step N`.
3. **Sync.** If the work departed from the plan, add an entry to `divergences` in the
   plan **in the same commit** as the departing code.

Once the plan is accepted, routine steps (tight spec, small blast radius, covered by
tests) can run with fewer approval prompts; the red/green discipline still applies.

## 6. Verify

Run build, test and lint and paste the literal output; never report done without it.
Then check the result with fresh eyes: a fresh session, ideally a different model family
(e.g. `agent-review code --goal "<the plan's outcome>"`, or a subagent where the agent has
them), given only the plan and the diff, told to run the app or the tests, exercise the change and its two nearest neighbouring
flows, and report mismatches against the plan **without fixing anything**. Any mismatch
goes back to step 5.

## 7. Finish

Set `status: implemented` (or `diverged` if `divergences` is non-empty), commit, and
open the code PR with `Change-Id: <change_id>` on the first line of the body and the
plan's summary below it (or merge locally with `Accepted-by:` if there is no remote).
Before merging, confirm the diff still matches the plan's "Files that change", and list
any files outside it in the PR body.

## Optional: make the test rule deterministic

The green-step rule above is advisory. Two scripts in this skill enforce it, both keyed
on `.git/green-phase`, which lists the red step's test paths, one per line. At the start
of each green step, write it:
`git diff --name-only HEAD~1 HEAD -- <test paths> > "$(git rev-parse --git-dir)/green-phase"`.
Delete it once the step is committed. Without it, both scripts do nothing.

Pick by agent:

- **Any agent, Cursor included:** install the git hook only. The agent writes and deletes
  the marker itself, and the hook refuses any commit that changes a protected test while
  the marker exists. It catches an accidental test edit, not an agent set on removing it.
- **Claude Code or Codex, for a stronger guard:** add the agent hook too. It also stops the
  agent from changing the marker, so the agent writes it at the start of the step and you
  remove it from your own terminal once the step is committed:
  `rm "$(git rev-parse --git-dir)/green-phase"`. The agent's refusal says so.
- **With Herdr:** the conductor pane can own the marker instead (below), so no one has to
  clear it by hand.

- **Agent hook** (stops the edit before it happens): `scripts/pretooluse-green-phase.py`,
  registered as a `PreToolUse` hook. It blocks Claude Code `Edit`/`Write`/`MultiEdit`/
  `NotebookEdit`, Codex `apply_patch`, and shell commands from either that name a
  protected path and contain a write operator. Claude Code: `hooks.PreToolUse` in
  `settings.json`, matcher `Edit|Write|MultiEdit|NotebookEdit|Bash`. Codex:
  `hooks.PreToolUse` in `~/.codex/hooks.json` or `<repo>/.codex/hooks.json`; Codex runs
  a hook only after you review and trust it (`/hooks`), or with
  `--dangerously-bypass-hook-trust` for one headless run. Gemini CLI has an equivalent
  `BeforeTool` event; this script is untested there.
- **git hook** (backstop at commit time, for every agent and for people):
  `scripts/pre-commit-green-phase.sh`. Install it where git actually runs hooks
  (`git rev-parse --git-path hooks/pre-commit`, which honours `core.hooksPath` and linked
  worktrees), chaining any existing hook rather than replacing it. It rejects a commit
  that stages a protected path, including either side of a rename, a deletion or a mode
  change, with paths read NUL-separated so unusual names are not quoted past it. It fails
  closed on an empty or unreadable marker or a git error. `git commit --no-verify` skips it.

The marker protects itself: with the agent hook installed, no agent may change
`green-phase*` while it exists, so you clear it from your own terminal. Both agents also
guard `.git` natively: Claude Code asks for approval before writing there, and Codex's
`workspace-write` sandbox makes it read-only.

*Herdr only, optional:* if `.git/green-phase.owner` names a Herdr pane, that pane may
change the marker and run `herd-sdlc phase`; the hook checks its own inherited
`HERDR_PANE_ID`, which a command cannot set. The conductor changes the marker through a
helper run in a plain shell pane (`herdr pane run`), not through its own tools. Without
Herdr, leave the owner file out.

Cursor's own hooks are not covered: the agent hook is untested there, so Cursor relies on
the git hook.

The shell check is a heuristic, which is why the git hook stays. Tests:
`scripts/test-pretooluse-green-phase.sh` and `scripts/test-pre-commit-green-phase.sh`.
