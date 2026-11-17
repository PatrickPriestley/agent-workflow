---
id: 2026-11-17-skill-red-first-workflow
tier: 1
status: done
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

The comparison, with the owner's leave ("Yes", in chat), on 2026-11-17 with Claude Code
2.1.326. The edit's arm was a copy of the plugin whose only difference was step 3 of
`SKILL.md` (`diff -r` showed that one hunk and nothing else):

```
$ claude plugin eval plugins/change-record --case red-first-workflow --scaffold \
    --allow-tools Bash Write Edit --trust-plugin --no-publish --ablation none --runs 6 -j 4 --max-cost-usd 2
current skill: 6 runs, $0.62
$ claude plugin eval <copy with the edit> ...the same...
with the edit: 6 runs, $0.66
```

| Arm | `test-run-before` | `saw-it-fail` | Mean of the two scored graders |
|---|---|---|---|
| current skill | 6 of 6 | 3 of 6 | 0.75 |
| with the edit | 6 of 6 | 6 of 6 | 1.00 |

(The runner's own score also counts `skill-fired` when there is no arm without the plugin,
so it printed 0.83 and 1.00; `skill-fired` passed in all twelve runs.)

Every verdict was read against its trace, and each is right. What the traces show:

- The three runs of the current skill that failed `saw-it-fail` each appended a test with a
  shell here-document and ran the suite in the same step, which still ran only the two old
  tests (`Ran 2 tests ... OK`): the new test never ran. Each then edited the workflow, then
  fixed the test, and saw it pass. No test failed before the workflow changed.
- Three runs with the edit made the same slip (`Ran 2 tests ... OK` after the append). Each
  then fixed the test, ran it, saw `FAILED (failures=1)`, and only then edited the workflow.
  That is the sentence the edit adds: no such file is edited until a test run has reported
  a failed test.

So the edit is kept, and `skills/change/SKILL.md` now carries it, the same text as the
measured arm (`diff` of the two files is empty). Six runs an arm is still few: across the
two runs of the case's own record and these six, the current skill saw a test fail first in
4 of 8 runs and the edit in 6 of 6, which a one-sided Fisher exact test puts at p = 0.07. The
direction is clear and the traces show the mechanism; the size is not settled.

The error path: no run with the edit edited the workflow first, so the failure the edit is
for was read in the current skill's three runs above, where it happened.

Checks after the edit: `node --test plugins/change-record/evals/cases.test.cjs`: 46 tests, 46 pass, none fail; `export-evals-json --check` exit 0.

Not done, and not verified:

- The clause for a test that can run only in CI (push the test or job alone as a draft, read
  its red log) is in the skill as the owner ruled, but no eval case exercises it: the eval
  runner can neither push nor run CI.
- The other eight cases were not run with the edit. It changes step 3 only, but a case such
  as `red-first` could move with it; a run of the whole suite with the edit and without
  would show that, and spends model calls.
- The second draft ("stop and report") was not measured, by the owner's ruling.
- The traces are kept in `plugins/change-record/evals/results/cmp-skill-edit/` on the machine
  that ran them, which is not committed.
