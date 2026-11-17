---
id: 2026-11-17-skill-red-first-workflow
tier: 1
status: open
requester: Patrick Priestley, in chat on 2026-11-17 ("Yes" to running the comparison with more runs; "Push a draft, read red log" for a test that can only run in CI)
approvers: []
---
# The change skill says a CI workflow file is code, and what to do when its test runs only in CI

## Goal

Step 3 of the change skill gains the edit that `transcripts propose` drafted from a labelled
failure of `red-first`, kept only if the eval case that shows the failure scores better with
it than without, as concern C5 of record `2026-11-12-session-quality` asks.

## Probed facts

- Exact source (`docs/changes/2026-11-12-session-quality.md`, task 3): two runs of
  `transcripts propose` on the same labelled failure drafted two edits to step 3. Both say a
  CI workflow file is code and is not edited before a test run has reported a failed test.
  For a test that can run only in CI, the first says to push the test or job alone as a
  draft and read its red log; the second, to stop and report.
- Exact source (`plugins/change-record/skills/change/SKILL.md`, at main `e77d027`): step 3
  reads as it did in the session the drafts were made from; the first draft's diff applies
  to it unchanged.
- Exact source (`plugins/change-record/grade/fields.py`, `kind`): the field grader already
  counts `.github/workflows/test.yml` as code (not docs, not a test file or folder), so the
  edit says what sessions are graded by.
- Verified against the real system (`docs/changes/2026-11-17-eval-workflow-red-first.md`,
  2026-11-17, Claude Code 2.1.326): `evals/red-first-workflow` with the current skill scored
  1.00 and 0.50 in two runs; the run at 0.50 ran the tests green and then edited the
  workflow, the failure the drafts were made from.
- Assumed, not probed: how the case scores with the edit. That is the measurement below.

## Decisions

- The first draft's edit, word for word. Rejected: the second draft, whose "stop and report"
  the owner ruled against ("Push a draft, read red log", in chat). Rejected: rewording the
  draft, which would measure an edit no failure proposed.
- The measure is `red-first-workflow` with the current skill and with the edit, six runs an
  arm, no baseline arm without the plugin (`--ablation none`): the question is the edit, and
  the arm without the plugin was measured in the case's own record. Six and not two because
  two runs moved a mean by half; the owner said yes to more runs.
- The edit is kept only if its mean is higher than the current skill's; otherwise the record
  ends `abandoned` with the numbers. Rejected: keeping it on a tie, which C5 does not allow.
- The edit's arm runs the same plugin with only `SKILL.md` changed, from a copy outside the
  repository, so the two arms differ by that file alone.

- The root README gains a section on the whole loop (tracking, judgement, self-improvement),
  and the plugin README's Transcripts section an outline of how its parts fit, as the owner
  asked in chat on 2026-11-17 ("update the readme to include details about the transcription
  tracking, judgement and self improvement"). It goes in this change because this change is
  the loop's last step, which the section describes. Rejected: repeating the plugin README's
  detail in the root README; the root says what each part is for and points to the detail.

## Tasks

1. The comparison, then, if the edit wins, the edit in `skills/change/SKILL.md` and its row
   in `evals/README.md`. Test: `claude plugin eval` on the case, both arms. Red today: the
   current skill's arm has runs that edit the workflow without seeing a test fail.
2. The README sections above. Test: the suites that read the root README
   (`install.test.sh`, `pr-agent/workflow.test.sh`, `pr-agent/pr-agent.test.sh`) stay green.

## Checks

`node --test plugins/change-record/evals/cases.test.cjs` and `export-evals-json --check`
(the skill's text is not read by them, but the suite must stay green). Real use: the two
arms of the comparison, with every verdict read against its trace. Error path: a run of the
edit's arm that still edits the workflow first, if there is one, read for why.

## Outcome

Nothing is built yet.
