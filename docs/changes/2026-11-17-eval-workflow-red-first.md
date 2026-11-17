---
id: 2026-11-17-eval-workflow-red-first
tier: 1
status: open
requester: Patrick Priestley, in chat on 2026-11-16 ("What's left to implement for self improvement"; then "Run it" on the first proposal, whose record names this case as the next step)
approvers: []
---
# An eval case shows whether a change to a CI workflow file is made test first

## Goal

The change skill's evals gain a case in which the code to change is a CI workflow file,
so that an edit to the skill about such files can be tried with the edit and without, as
concern C5 of record `2026-11-12-session-quality` asks before any edit is kept.

## Probed facts

- Exact source (`docs/changes/2026-11-12-session-quality.md`, task 3): `transcripts
  propose` drafted two edits to step 3 of the change skill from one labelled failure of
  `red-first`. Both begin by saying that a CI workflow file is code and is not edited
  before a test run has reported a failed test. They then differ on a test that can run
  only in CI: one says to push the test or job alone as a draft and read its red log, the
  other to stop and report.
- Exact source (`plugins/change-record/evals/red-first/`): the one case for this step
  asks for a flag in `greet.py`, whose tests run on the machine. Its two scored graders
  are regexes over the ordered trace: a unittest run before the first write of
  `greet.py`, and a unittest run whose own result reports a failure before that write. A
  write is the Write or Edit tool on the file, or a shell redirect, `tee`, `cp` or
  `sed -i` onto it.
- Exact source (`plugins/change-record/evals/_scaffold/greet.sh`): the shared scaffold is
  a Python CLI with one test file, committed on `main`, with `docs/changes/` from the
  plugin's templates. It has no workflow file.
- Exact source (`evals/cases.test.cjs`): a case needs `case.yaml` naming itself and
  `scaffold.sh`, a `prompt.md`, and graders of a known type with `skill-fired.md` among
  them; a record id in a prompt is read as `2026-11-08-<slug>`.
- Verified against the real system (this container, 2026-11-17): `node --test
  plugins/change-record/evals/cases.test.cjs` runs 40 tests, none failing. `claude plugin
  eval --help` (Claude Code 2.1.325) lists `--case <glob>`, so one case can be run alone.
- Assumed, not probed: what an agent does with this case, with the plugin or without. No
  run has been made: a run spends model calls and waits for the owner's leave.

## Decisions

- The case is the part both drafts share: a workflow file is code, and a test fails
  before it is edited. The scaffold gives the repository a test of its workflow file, so
  that a failing test can be written and run on the machine. Rejected for now: a case
  for a test that can run only in CI. The two drafts ask for different things there, the
  eval environment can neither push nor run CI, and which of the two the owner wants is
  the owner's to say before a case can hold an agent to it.
- The graders are the two of `red-first`, with the workflow file in the place of
  `greet.py`. Rejected: a grader that reads the final workflow file, which would score
  whether the task was done and not whether it was done test first.
- `transcripts propose` still names `evals/red-first` for the step. Its page already says
  to check that the case shows the failure; naming two cases for one step waits until
  this one has been run and shown to measure something.

## Tasks

1. The case `red-first-workflow`: scaffold, prompt, graders, their fixtures in
   `evals/cases.test.cjs`, and the README's row. Test: `node --test
   plugins/change-record/evals/cases.test.cjs`. Red today: there is no such case.

## Checks

`node --test plugins/change-record/evals/cases.test.cjs`. Real use: `claude plugin eval
plugins/change-record --case red-first-workflow`, with the plugin and without, which
needs the owner's leave for the spend; then the same with each proposed edit in the
skill. Error path: a trace in which the workflow file is written before any test run
fails both graders.

## Outcome

Nothing is built yet.
