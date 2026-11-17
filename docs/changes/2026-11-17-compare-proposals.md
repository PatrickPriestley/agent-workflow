---
id: 2026-11-17-compare-proposals
tier: 1
status: done
requester: Patrick Priestley, in chat on 2026-11-17 ("Go ahead with 1 and 3", of the list of what is left of the self-improvement loop)
approvers: []
---
# A proposed skill edit is compared by one command, and every step that has an eval case names it

## Goal

Two of the parts left of the loop. (1) The comparison that kept the edit of
`2026-11-17-skill-red-first-workflow` was made by hand: copy the plugin, put the proposed
skill file in, run the case with and without, read the results. One command does it from a
proposal, says what it would spend before it spends, and applies the rule that keeps an edit
(concern C5 of `2026-11-12-session-quality`). (3) `transcripts propose` names an eval case for
two of the seven steps; every step that has a case showing its failure names it, with the
grader that shows it.

## Probed facts

- Exact source (`plugins/change-record/evals/*/graders/`): the grader that tests each step's
  rule, by its statement. `probe-before-record`: `probed-facts-labelled/probed-before-record`.
  `record-before-code`: `record-before-code/record-before-code`. `red-first`:
  `red-first/saw-it-fail` and `test-run-before-code-change`, `red-first-workflow/saw-it-fail`
  and `test-run-before-workflow-change`. `change-line`: `record-before-code/pr-body-names-record`
  (the final message holds the `Change:` line). `tier-declared`: `tier-0-no-record/declares-tier-0`
  and `tier-2-stops-before-code/record-is-tier-2`. `outcome-filled`:
  `outcome-has-real-output/outcome-quotes-main-path`, which asks more than the step (an Outcome
  that quotes a run, not only one that is there). `record-check`: none; the runner cannot commit.
- Exact source (`plugins/change-record/evals/README.md`, results of 2026-11-08): each of those
  graders failed in at least one run of that table or of the records after it, so each case can
  show its step failing.
- Verified against the real system (`claude plugin eval --help`, Claude Code 2.1.326): it takes
  `--case <glob>`, `--ablation none`, `--runs`, `--max-cost-usd`, `--json <path>`, `--scaffold`,
  `--allow-tools`, `--trust-plugin` and `--no-publish`.
- Verified against the real system (`evals/results/cmp-skill-edit/*.json`, the runs of
  2026-11-17): a result holds `cases[].graders[]` with `name`, `type` and `config`, and per run
  `arms.with[]` with `error` and `graders[]` of `name`, `passed`, `scored`. Under
  `--ablation none` the activation grader `skill-fired` (`type: tool_used`, `tool: Skill`) is
  `scored: true`, so the runner's own score counts it; the comparison has to leave it out
  itself. The runner exited 1 for an arm that was not all passes, and its help says 2 when the
  cost ceiling stops it.
- Exact source (`bin/transcripts`, `cmd_propose`): a proposal is
  `DIR/proposals/<session>/<step>/` holding `SKILL.md`, `SKILL.diff` (against the file the
  session used) and `proposal.json` (`skill`, `skill_blob`, `eval`).

## Decisions

- The map is `propose.EVALS`, a step to a list of (case, graders): the table above. The
  proposal page names every case of its step. Rejected: one case a step, which would drop
  `red-first-workflow`, the case that showed the failure the first edit came from.
- `transcripts compare [DIR] --session ID --step STEP [--repo-dir DIR] [--runs N]
  [--max-cost USD] [--run]`. Without `--run` it prints what it would run and the most it could
  spend, and calls nothing. Rejected: asking on the terminal, which an agent or a scheduled job
  cannot answer; running by default, which spends without leave.
- The edit is put on the skill as it is now. If the file is the one the session used, the
  proposal's `SKILL.md` is taken; otherwise each hunk of `SKILL.diff` must be found once, as
  it stands, in the current file, or it stops and says the edit must be made again by hand.
  Rejected: a fuzzy patch, which could put an edit where nobody read it.
- Two arms for each case: the plugin in `--repo-dir`, and a copy of it under
  `DIR/compare/<session>/<step>/plugin` that differs only in that skill file. Both with
  `--ablation none`: the question is the edit, not the plugin. Defaults: 6 runs, a ceiling of
  $2 for each arm of each case.
- Kept when the step's graders pass more often with the edit than without, summed over its
  cases, and no case's mean over its scored graders (without `skill-fired`) is lower with the
  edit. Dropped otherwise, a tie included (C5). No verdict when a run has an error, a result is
  partial, or the runner exits other than 0 or 1.
- It writes `compare.json` and `compare.md` beside the proposal and never writes the skill:
  keeping an edit stays a change of its own.
- Two pull requests, one for each task: together they are over the 400-line aim, and the
  map is of use on its own (a proposal names its cases) before `compare` exists.

## Tasks

1. The map: `propose.EVALS` and the proposal page. Test: `bin/transcripts-judge.test.sh`. Red
   today: five steps name no case.
2. `transcripts compare`, its suite `bin/transcripts-compare.test.sh` against a stand-in for
   `claude plugin eval`, the CI line that runs it, and the README. Red today: no such command.

## Checks

`bash plugins/change-record/bin/transcripts-compare.test.sh` and `transcripts-judge.test.sh`.
Real use: `transcripts compare` without `--run` on the real proposal of session `bf01bd72`
(no spend). A run with `--run` spends model calls and waits for the owner's leave. Error
path: a proposal whose diff no longer applies to the current skill.

## Outcome

Task 1, the map. Built test first: 11 assertions failing in `bin/transcripts-judge.test.sh`
(the proposal page names one case, the proposal's `eval` is a string, a step whose case is
one of the earlier eight names none, the report lists one case), then `propose.EVALS` as the
table under Probed facts, the page and the report.

```
$ bash plugins/change-record/bin/transcripts-judge.test.sh | tail -1
transcripts judge and report: 526 passed, 0 failed
```

A proposal drafted before this change holds its case as a string, and the report still lists
it (a test holds that). On the real folder `materialize` rebuilt from the store, which holds the
proposal drafted for session `bf01bd72` on 2026-11-16 (`"eval": "red-first"`), on the final code:

```
$ transcripts report <folder> | sed -n '/## Proposed edits/,$p'
## Proposed edits
...
| Session | Step | Eval case |
|---|---|---|
| bf01bd72... | red-first | plugins/change-record/evals/red-first |
exit 0
$ transcripts propose <folder> --session bf01bd72... --step change-line        (the error path)
transcripts: no label confirms that bf01bd72... failed change-line: a proposal is drafted only from a failure a person has labelled (transcripts sheet, then the session's file in <repo>/plugins/change-record/grade/labels)
exit 1
```

Not run: `propose` drafting a new proposal on the final code, which is one call to Claude
Sonnet and waits for the owner's leave; the page and `proposal.json` it writes are held by the
suite, against a stand-in for `claude`. The review of task 1 also found that the page named
`transcripts compare` before that command exists; it now says how the comparison is made and
names no command, and task 2 names it.

Task 2, `transcripts compare`. Built test first: the suite of `compare` against a stand-in
for the eval runner (61 failing with no such command), then `grade/compare.py` and the
command; then tests for five guards the first tests left open, before any break was tried.

```
$ bash plugins/change-record/bin/transcripts-compare.test.sh | tail -1
transcripts compare: 89 passed, 0 failed
$ bash plugins/change-record/bin/transcripts-judge.test.sh | tail -1
transcripts judge and report: 526 passed, 0 failed
```

The other suites that read what changed:

```
$ bash plugins/change-record/bin/transcripts.test.sh | tail -1
passed=364 failed=0
$ bash plugins/change-record/bin/transcripts-grade.test.sh | tail -1
transcripts grade: 212 passed, 0 failed
$ bash plugins/change-record/bin/transcripts-store.test.sh | tail -1
passed=440 failed=0
$ bash plugins/change-record/bin/record-check.test.sh | tail -1
passed=117 failed=0
$ node --test plugins/change-record/evals/cases.test.cjs
46 tests, 46 pass, none fail
$ bash bin/ci-workflow.test.sh | tail -1
passed=21 failed=0
$ bash install.test.sh | tail -1
passed=112 failed=0
$ bash pr-agent/workflow.test.sh | tail -1
passed=69 failed=0
```

The real use, with no spend: `compare` without `--run` on the real proposal of session
`bf01bd72` (the second draft, from the folder `materialize` rebuilt), against a checkout of
`main`, where the skill is not the version the session used and does not yet hold the edit of
`2026-11-17-skill-red-first-workflow`:

```
$ transcripts compare <folder> --session bf01bd72... --step red-first --repo-dir <checkout of main>
transcripts compare: the edit to change-record:change proposed from session bf01bd72... at step red-first, the edit put on the skill as it is now.
It would run, with no arm without the plugin:
  plugins/change-record/evals/red-first (graders saw-it-fail, test-run-before-code-change): 6 runs with the skill as it is and 6 with the edit
  plugins/change-record/evals/red-first-workflow (graders saw-it-fail, test-run-before-workflow-change): 6 runs with the skill as it is and 6 with the edit
Each arm of each case stops at $2.00, so at most $8.00 in all.
Nothing was run: add --run to run it.
exit 0
```

The error path, the same proposal against this branch, whose skill already holds the edit
of `2026-11-17-skill-red-first-workflow`, which changed the lines the draft changes:

```
$ transcripts compare <folder> --session bf01bd72... --step red-first --repo-dir <this branch>
transcripts: the edit does not apply to <repo>/plugins/change-record/skills/change/SKILL.md as it is now (the part around '`references/splitting.md`.' is not in it): make it again by hand on the current file, as its own proposal, before it is compared
exit 1
```

Nothing was written by either: no `compare/` folder and no `compare.json`.

Guards, each broken by hand in a clone: 34 breaks. The first round caught 28 of 34. The six
that survived were tests too loose to tell: the edit put on the current file was checked by
words in it, not whole (two breaks of the diff reading); an errored run, a partial result and
a runner stopped by its ceiling were each also missing something else, so another check
caught them first (three); and the unscored graders, counted, tied the means instead of
lowering one (one). Each fixture was made to turn on its one guard and the six were broken
again and caught. All 34 were then broken once more on the final tests, and each is caught,
by the test that failed first for each:

- `R7: a step whose case is one of the earlier eight names it with its grader: probe-before-record and probed-facts-labelled`:
  - map: a grader is named that its case has not
- `R7: the note names every eval case of the step and the graders that show it, says to check that they show this failure, and that the edit is kept only if they improve with it`:
  - map: red-first names one case
  - propose: the proposal names no case
- `a folder inside a working tree is refused, as for grade and propose`:
  - cmd: a folder inside a working tree is written to
- `a grader the runner does not score is not counted: failing it alone would have made the edit's case lower`:
  - tally: a grader the runner does not score is counted
- `a part of the edit that stands more than once in the skill as it is now: it is not guessed at, and nothing runs`:
  - apply: a part that stands twice is taken at its first place
- `a run that errored, a result cut short by the ceiling, or a runner that exits otherwise gives no verdict, exit 1, and says which`:
  - cmd: no verdict exits 0
  - run_eval: a runner stopped by its ceiling is read
  - tally: a partial result is read
  - tally: a run that errored is read
  - verdict: an arm with no result still gives a verdict
- `a run with no result for one of the step's graders gives no verdict, naming the grader`:
  - tally: a run with no step grader is read
- `a skill that changed since the session, away from the edit: the edit is put on the skill as it is now`:
  - cmd: the drafted file is always taken
  - hunks: a removed line is kept
  - hunks: context is not part of the old text
- `a step no eval case shows says that one is written first, and runs nothing`:
  - cmd: a step with no case is compared
- `a tie is no improvement: the edit is dropped`:
  - cmd: an earlier run's results are kept
  - verdict: a tie keeps the edit
- `an empty diff is no edit, and nothing runs`:
  - apply: an empty diff is an edit
- `compare.json and compare.md hold the verdict and each case's counts for each arm`:
  - tally: skill-fired is counted
- `it ran each case once for each arm, with no arm without the plugin, at the runs and ceiling asked, and wrote the runner's results beside the proposal`:
  - command: an arm without the plugin is run too
  - command: the case's scaffold is not run
  - command: the ceiling is not passed
  - command: the runs asked are not passed
  - run_eval: the eval sessions are captured
- `no claude to run gives no verdict, never a traceback`:
  - run_eval: no claude to run is not caught
- `the edit's plugin is a copy that differs from the plugin only in the skill file, without the plugin's old results`:
  - cmd: the plugin's old results are copied
- `a proposal drafted before a step could name several cases, one case as a string, is still listed`:
  - report: a proposal of one case as a string is not listed
- `the step's graders pass more often, but a case scores lower on its other graders: dropped, naming the case`:
  - verdict: a case that scores lower is not looked at
- `with no session or no step, an unknown step, runs that are not a whole number above 0, or a ceiling that is no amount, it says how to use it`:
  - cmd: --runs takes 0
  - cmd: any step's name is taken
- `without --run it says what it would run and the most it could spend, and runs nothing and writes nothing`:
  - cmd: it runs without --run
  - cmd: the edit is always put on the current file
  - plan: the most it could spend is one arm's

Found by that run, and fixed: the README's new table of steps and cases made the test that
holds each step's rule to the README's grading table read the wrong table (its rows also
begin with a step's name), so the judge suite had one failure that the suites run before
the README change did not show. The test now reads the grading table by its heading, and
still fails when a rule there is changed.

Not done, and not verified:

- No comparison has been run with `--run` against the real eval runner: that spends model
  calls and waits for the owner's leave. The runner's result format and exit codes the code
  reads were taken from the real runs of `2026-11-17-skill-red-first-workflow`, and the
  stand-in writes the same fields; the real runner may say more ways a run went wrong.
- Whether each newly named case shows its step's failure for a given session is still for a
  person to check, as the proposal page says; the map says only which grader tests the rule.
- `transcripts report` lists proposals but not their comparison's verdict.
