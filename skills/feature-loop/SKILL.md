---
name: feature-loop
description: Use when asked to add, change or remove behaviour in a codebase, or to make any change touching more than one file (including refactors and renames), and there is no accepted intent or spec; including "quick" requests under time pressure or with "don't overthink it". Use before reading code or editing anything.
---

# Feature Loop

Seven steps from request to a pushed branch and PR, for any agent with a shell, git and a way
to start a second agent. It applies the four rules in `~/AGENT-WORKFLOW.md` (probe, red
before green, mutation-check, independent review); this page says when and how.

**Decide routine choices yourself, write them down, keep moving.** Stop only at the gates
under "When to stop".

## Steps

1. **Probe** every library, CLI or API behaviour the change depends on, a few lines each in
   a scratch directory, and list the results. If the request turns out impossible or rests
   on something false, stop and report; never build a substitute.
   **Real-contract gate:** for each new call to another system, send the exact request to
   the version you target (start it in a disposable environment if needed) and see the
   smallest outcome you need, before writing the feature. Tests against a fake, a doc, or a
   second parser that lists the value do not pass the gate. If you cannot run it, trace the
   receiver's own validation and dispatch in its exact source, and say so. Label each probed
   fact: verified against the real system, exact source, mock only, or assumed.

2. **Branch and note.** Create the feature branch in its own worktree first. If the change
   adds a command, setting, mode, file format or external call, commit a short design note
   there (`docs/plans/<date>-<topic>.md`): goal, probed facts, each
   decision with the rejected alternative, the task list with files and test names, and how
   it will be checked. No code in it. Without a note, put the probed facts and each decision
   with its rejected alternative in the commit messages instead.

3. **Build red before green**, one task at a time: write the test, see it fail on an
   assertion about the missing behaviour (if it passes, or fails on an import or compile
   error, fix the test first), write the least code that passes, run the whole suite,
   commit. If the design proves wrong, record the change (note or commit message) before
   writing more code; never diverge silently.

4. **Mutation-check** every guard the change adds or touches: break it, see a test fail,
   restore it immediately. A survivor gets a test that fails without it (rule 3). Before
   moving on, `git diff` must show no leftover mutation.

5. **Use it as its user would.** Tests prove what you specified, not that it was the right
   thing. Run the real program, command, page or API, the way a person or client will, on
   realistic data: the main path and at least one error path (bad input, a missing
   record, an unreachable dependency). Read what comes out as that user: is the error
   specific, does the output say what they need without dumping internals? Fix what is
   wrong test-first, and put the commands you ran and their output in the PR. After any
   later fix, review findings included, run them again on the final code and replace the
   output, so the PR never quotes code that has since changed.

6. **Independent review** by a model family other than yours: run
   `agent-review code --goal "<the outcome asked for>"` (the `agent-review` skill), which picks one and runs it headless and read-only. Sending the
   diff to an installed reviewer is part of the loop: do not ask. It is done only when the reviewer's reply ends with its end marker; an empty
   or cut-off reply is no review. Probe each finding. Critical or important means wrong
   behaviour, lost data, a security hole or a bypassed safeguard, with a concrete case; when
   unsure, treat it as important. Fix those test-first and have the fixes re-reviewed until
   none remain. Dismiss a finding only when a probe, or code you cite, shows it cannot
   happen. Carry minor ones to step 7. The end marker proves the review finished, not that
   the change works.

7. **Finish** on a green suite only: run it once more, push the branch (or commit, if that
   is all that was asked) and report what was done, what was not, and the open minor
   findings. The report quotes the real-use commands from step 5 and their output, main
   path and error path. If you have none, you skipped step 5: go back and do it.

## When to stop

Stop and wait for the owner only when:

1. A probe shows the request is impossible or based on something false.
2. Two readings lead to materially different work and the code cannot settle it. Ask all
   such questions together, each with your recommendation. Ask again only if a later probe
   contradicts an answer.
3. The work would grow beyond the request.
4. The next action merges into the main branch, releases or deletes.
5. Another agent shows a trust, permission, login or update prompt. Never answer it.
6. A manual or hardware check only the owner can do.

## Larger changes

For many tasks across separate modules, give each task a fresh agent: each works on its own
branch cut from the feature branch, following step 3, and you merge them back into the
feature branch in task order, re-running the suite after each merge. Tasks that touch the
same files run one after another, each cut from the feature branch after the previous merge. Step 6 reviews the
feature branch after the last merge. Start the agents however your tool allows: the
`execute-feature-plan` workflow in Claude Code, headless runs (`claude -p`, `codex exec`), or
separate sessions.

## Rationalizations

| Excuse | Reality |
|---|---|
| "It's small, I'll skip the test" | Skip the note if it qualifies; never the red test |
| "The tests pass, so it works" | Tests check what you specified. Run it as its user would, error path included |
| "The tests pass, so it's reviewed" | Tests check the guards that were written; review finds the missing ones |
| "The reviewer said so" | Probe it. A wrong fix applied on trust ships a bug |
| "The reviewer didn't answer, so it's clean" | No end marker, no review |
| "Mutation testing is overkill for this" | It found six untested guards behind 32 green tests. Every guard the change touches |
| "The feature is impossible, so I built the nearest thing" | That is scope change. Stop and report |
| "The fake server accepts it, the tests pass" | The fake accepts everything. Send the exact request to the real one |
| "The docs list that value as supported" | Docs and one parser are not the receiver. Its validator decides |
| "I should check this choice with the owner" | If both options lead to the same work, choose, record why, continue |
