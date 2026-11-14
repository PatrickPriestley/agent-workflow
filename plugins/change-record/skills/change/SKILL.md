---
name: change
description: Use for any change to a codebase - adding, changing or removing behaviour, refactors, renames, new integrations, and also typo, comment or formatting fixes, which it clears as tier 0 in one line - including "quick" requests under time pressure. Use before reading code or editing anything. It sets the tier, keeps one change record, and runs the loop; a repository may add checks that verify the evidence.
---

# Change

One record per change. A tier by risk, not by file count. Evidence as things a check could
verify, not sentences, whether or not the repository runs the checks (they are optional; see
the plugin README). The rules are in `${CLAUDE_PLUGIN_ROOT}/RULES.md`. Read a reference below only
when its step comes up.

**Decide routine choices yourself, write them in the record, keep moving.** Stop only at the
gates under "When to stop".

## 1. Tier

Answer the six questions in `references/tiers.md`. No observable behaviour change: tier 0.
Stop here, make the change, and put `Tier: 0` in the PR body; nothing else from this skill
applies. Reversible, one PR, the requester decides: tier 1. Hard
to undo, crosses a team or system boundary, touches auth, money, personal data or
infrastructure, needs someone else's agreement, or takes more than one PR: tier 2. Record
the tier and raise it the moment a later answer flips.

## 2. Probe, then record

Probe what the change depends on first (`references/probing.md`): run the library, command
or API in a scratch directory and note what you saw. Then create
`docs/changes/<YYYY-MM-DD>-<slug>.md` from `references/record-template.md` on the feature
branch, before code. Fill Goal (the requester's words), Probed facts (what you just probed,
each labelled), Decisions (each with the rejected alternative), Tasks (files, test, why the
test fails today) and Checks. Tier 2 adds Problem, Requirements and Options
and concerns, is read by a fresh session with no context, and stops for approval: see
`references/tier-2.md`.

## 3. Loop

For each task:

1. **Probe** what the task depends on; for a new call to another system, send the real
   request to the real version first (`references/probing.md`). Impossible or built on a
   false premise: stop and report; never build a substitute.
2. **Size.** Over about 400 reviewable lines in total (`pr-size`): one PR per task,
   `references/splitting.md`.
3. **Red, then green.** Write the test, run it, see it fail on an assertion about the
   missing behaviour (a test that fails on an import or compile error has not run, and shows
   nothing), commit the test, make it pass, run the whole suite, commit. Where the repository
   runs `red-check`, locally or in CI, it verifies this with verdicts: red, green on the base
   (fails), inconclusive (did not run), no tests (a helper, not judged).
4. **Guards.** Run the language's mutation tool on the changed files where one exists;
   otherwise break each new guard, see a test fail, restore it. Survivors get a test or a
   reason in the record. At most two rounds of fixing findings from this step or step 6;
   after that, stop and report what remains rather than reshaping tests to chase a score.
5. **Use it.** Run the real program as its user would, main path and one error path. Paste
   the commands and output into the record's Outcome.
6. **Push** the branch and open the PR. The first line of the PR body is
   `Change: docs/changes/<id>.md`, on its own, so a reader or a check finds the record. The
   independent review runs there. Treat each finding as a claim
   (`references/review-findings.md`); re-push until nothing critical or important remains.

Finish on a green suite only. Set the record's status to `done` and report what shipped,
what did not, and the open minor findings. When tempted to skip a step, read
`references/rationalizations.md`.

## When to stop

Only when: a probe shows the request impossible or false; two readings of the request lead to
materially different work (ask all such questions in one message, each with a
recommendation); the tier needs raising; the next action merges into the default branch,
releases or deletes; another tool shows a trust, permission or login prompt (never answer
it); a check needs hardware or access only the owner has.
