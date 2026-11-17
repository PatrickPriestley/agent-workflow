---
id: 2026-11-17-compare-proposals
tier: 1
status: open
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
it (a test holds that). Task 2, `transcripts compare`, follows in its own pull request.
