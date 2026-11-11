---
id: 2026-11-11-grading-trust
tier: 2
status: approved
requester: Patrick Priestley, in chat on 2026-11-11 ("Review the entire architecture and approach first", "Yes" to a record for the review's first three steps, and "start the grading trust in parallel")
approvers: [Patrick Priestley, 2026-11-11]
plugin: plugins/change-record
tasks:
  - name: macos
  - name: labels
  - name: evidence
    after: labels
---
# The graders' error rate is measured, and the report shows evidence in place of fixed advice

## Goal

Before anyone acts on the transcript report, its verdicts are checked against a person's: a
set of sessions labelled by hand gives each grading step a measured error rate, the report
prints that rate beside each pass rate and shows the evidence behind each failure where it
now prints one fixed sentence, and the test suites that guard all this run on macOS as well
as Linux.

## Probed facts

- Verified against the real system (the first report from the real store, 2026-11-11): five
  sessions, three failed steps, and none of the three was the session's fault. One session
  was only partly captured, and the other two failures came from the grader's reading of a
  shell command. The report proposed a skill edit for each.
- Exact source (`grade/report.py`, `EDITS`): a proposed edit is looked up in a fixed table, one
  sentence per step, whatever the session did. Several restate what the skill already says.
- Exact source (`bin/transcripts`, `grade_one`): each score row carries its evidence: why, the
  calls it cites, counts of runs and denials.
- Verified against the real system (CI on PRs #40 to #45, and on `main`): the `test
  (macos-latest)` job fails at `bin/commit-gate.test.sh`, in "a checkout path with an apostrophe
  still produces a working hook", with `passed=80 failed=1`. Every later step is skipped, so
  no change-record suite has run on macOS. The same test passes on Ubuntu.
- Not known: why that test fails on macOS. It cannot be reproduced in the Linux container. To
  be probed in task 1 on the macOS runner.
- Exact source (a search of the change-record suites and tools, 2026-11-11): one GNU-only
  construct was found, `find -perm /077` in `bin/transcripts.test.sh`. Whether the suites
  otherwise pass on macOS is not known.
- Verified against the real system (`vermin`, 2026-11-11): `bin/transcripts`, the graders and the
  store scripts need Python 3.8 or later, which a stock macOS has.
- Verified against the real system (2026-11-11): the sessions available to label are the five
  in the store, the two `dispatch` fixtures in the repository, and the 160 transcripts in the
  archive sent to the owner on 2026-11-09, most of them eval runs whose intended outcome is
  known from their eval case.
- Exact source (PRs #41 to #45): the cross-model review did not run on any of them; its
  provider answered "Insufficient balance" each time.

## Problem

The report exists to tell the owner where the `change` skill fails in real sessions. Its
first real output was wrong three times out of three, and it attached confident advice to
each. Nothing measures how often the graders are wrong, so a reader cannot tell a real
failure from a grader's mistake without reading the transcript, which is the work the report
was meant to save. The advice itself is a fixed sentence per step and adds nothing a session
showed. The suites that test the graders have never run on macOS, which is probably where the
owner will run them, and no independent reviewer looked at the last five pull requests.

## Requirements

- R1. A labelled set of at least 20 sessions is kept: for each session and step, a person's
  verdict (pass, fail or not applicable) and a one-line reason. Check: a test loads the label
  files and rejects one with a missing step or an unknown verdict.
- R2. The sheet a person labels from shows each step's evidence and hides the grader's
  verdict, so the label is not copied from it. Check: a test builds a sheet from a fixture
  session and finds the evidence and no verdict.
- R3. `transcripts accuracy DIR` compares the graders with the labels and prints, per step:
  sessions labelled, agreements, false fails and false passes, with the session ids of each
  disagreement. Check: known labels and score rows give a stored expected table.
- R4. The report prints each step's measured error beside its pass rate, and marks a step
  "not yet checked" when fewer than five labelled sessions cover it. Check: the stored expected
  report.
- R5. For each failed step the report shows what the session did: the session, the grader's
  reason, the calls it cites and a short redacted excerpt of each. The fixed table of advice is
  removed. Check: the stored expected report, and a test that no line of the old table remains.
- R6. Every change-record suite runs on macOS in CI and passes, and a failure in one plugin's
  suites does not stop another's from running. Check: the `test (macos-latest)` job on the
  task's own pull request.

## Options and concerns

**A. Hand labels, measured error, evidence in the report (recommended).** A person labels a
small set once; the graders are scored against it; the report carries the error rate and the
evidence. Cost: about two hours of the owner's time for 20 sessions of seven steps, and
labels to refresh when a grader's rules change.

**B. A second model as the reference.** No owner time. Rejected as the reference: it measures
agreement between two automated readers, not correctness, and the cross-model reviewer has no
balance today. It may pre-fill a sheet for the owner to correct, under C1.

**C. Fix graders as false verdicts are noticed.** No new mechanism. Rejected: it is what
happened so far, and it found two faults only because the first report was small enough to
read whole.

### C1: who labels, and how many
Twenty sessions of seven steps is 140 judgments. Failure case: the labelling never happens
and the report stays unchecked. Recommended: the owner labels 20 sessions from a sheet that
hides the grader's verdict; the set mixes the five stored sessions, the two `dispatch` fixtures and
13 eval runs chosen to cover each step's pass and fail. A model may pre-fill reasons, never
verdicts. Owner: Patrick Priestley.
Resolved: as recommended. Patrick Priestley, 2026-11-11 ("start the grading trust", in chat; merging this
record confirms it).

### C2: where the labelled transcripts live
CI cannot read the store, and 20 transcripts are several megabytes. Failure case: the accuracy
check runs only on the owner's machine and quietly stops being run. Recommended: the label
files live in the repository, keyed by session id with a hash of the transcript they were
made from; `accuracy` runs on a rebuilt folder on the owner's machine, and CI runs it on the
sessions already kept as fixtures. Owner: Patrick Priestley.
Resolved: as recommended. Patrick Priestley, 2026-11-11 ("start the grading trust", in chat; merging this
record confirms it).

### C3: the macOS failure is in the other plugin's test
The failing test belongs to `bin/commit-gate`, which earlier records left alone. Its cause is
not known. Failure case: task 1 grows into a fix of a tool this change was not about.
Recommended: task 1 first gives the change-record suites their own CI job, so they run on
macOS whatever happens to that test, and fixes what they need there. It then reads the macOS
log of the failing test and fixes it only if the fix is a few lines; otherwise it reports
the cause and leaves the fix to its own change. Owner: Patrick Priestley.
Resolved: as recommended. Patrick Priestley, 2026-11-11 ("start the grading trust", in chat; merging this
record confirms it).

### C4: what error rate is acceptable
No number is set today. Failure case: a threshold chosen before any measurement blocks the
report or means nothing. Recommended: no gate yet. The report prints the measured error and
lists every known false verdict; a threshold is decided after the first measurement. Owner:
Patrick Priestley.
Resolved: as recommended. Patrick Priestley, 2026-11-11 ("start the grading trust", in chat; merging this
record confirms it).

## Decisions

- A person's labels are the reference, and a model's are not. Rejected: B above.
- The sheet hides the grader's verdict. Rejected: showing it, which invites agreement.
- Labels are stored with a hash of the transcript, so a label made from an older or partial
  transcript is reported as stale and not counted.
- The report shows evidence and stops proposing edits. Rejected: generating advice with a
  model, which would hide the same uncertainty behind better prose; deciding an edit stays
  with the owner, who can now see what happened.
- The change-record suites get their own CI job. Rejected: reordering steps in the one job,
  which only moves which suite hides the others.
- Grading other agents' sessions waits for this record's first measurement
  (2026-11-11-codex-cursor-capture keeps their transcripts in the meantime).

## Tasks

One pull request each.

1. **macOS.** `.github/workflows/test.yml`: a separate job for the change-record suites on both
   systems; the suites made portable where macOS needs it (`find -perm` at least); the
   commit-gate failure probed and handled as C3 says. Test: the `test (macos-latest)` jobs on
   this pull request; it fails today because the job stops before these suites.
2. **Labels.** `transcripts sheet` (R2), the label format under `grade/labels/` (R1),
   `transcripts accuracy` (R3), and a labelling guide in the README. The owner then labels the
   set. Test: R1 to R3 in `bin/transcripts-grade.test.sh`; it fails today because the commands
   do not exist.
3. **Evidence.** `grade/report.py`: error rates (R4), evidence per failed step and the fixed
   table removed (R5). Test: the stored expected report in `bin/transcripts-judge.test.sh`; it
   fails today because the report prints the table's sentences.

## Checks

`bash plugins/change-record/bin/transcripts-grade.test.sh`, `transcripts-judge.test.sh` and the
other change-record suites, on Ubuntu and macOS. Real use, on the owner's machine: build the
sheet for the 20 sessions, label them, run `transcripts accuracy` and the report, and paste
both. Error path: a label made from a transcript that has since grown is reported as stale
and left out of the count. The reviewer should attack: whether the sheet leaks the grader's
verdict, whether a stale or partial label can be counted, whether the report can still print
advice the session's evidence does not support, and whether a suite can be skipped on macOS
without the job going red.

## Outcome
