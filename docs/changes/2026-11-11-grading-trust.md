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
    done: true
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
- (Task 2.) The sheet shows the session itself, every call with its input and result, and for
  each step the question and pointers found by plain text matches. Rejected: printing the score
  rows' evidence with the verdict taken out; the reason, the counts and the list of calls a
  grader picked give the verdict away, and the first report's errors were in which calls it
  picked.
- (Task 2.) A label file is plain lines, one per step, `grade/labels/<sessionId>.txt`; sheets are
  separate files kept outside every working tree. Rejected: one file as both sheet and label,
  which would commit transcript text and bury seven lines in several hundred.
- (Task 2.) `accuracy` prints a fifth count R3 does not name, false n/a: the grader says not
  applicable where the label says pass or fail. A step whose row carries an error (the grader
  could not read what it needed) is listed and not counted. Rejected: counting either as a
  false fail, which it is not.
- (Task 2.) A label file with no verdict yet is listed as not labelled and is no error; a
  malformed one is rejected whole and makes `accuracy` exit 1. Rejected: counting the well
  formed lines of a malformed file.
- (Task 2.) The hash is of the main transcript's lines as the folder holds them, so labels made
  from the store's redacted copy are stale against the unredacted local archive. Rejected:
  hashing a re-redacted copy, which would tie every label to the redaction version.
- (Task 2.) CI runs `accuracy` on the fixture sessions from inside `bin/transcripts-grade.test.sh`,
  not as its own workflow step: the suite already runs on every push, and the workflow file is
  task 1's.

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

### Task 2, labels (2026-11-11)

Shipped: `transcripts sheet`, the label format and its loader (`grade/labels.py`), `transcripts
accuracy`, the labelling guide in the plugin README, and an empty label file for each of the
fifteen fixture sessions in `grade/labels/`, each holding its transcript's hash. Not done here,
by design: the labelling itself, which is the owner's, and the five store sessions, whose
label files `transcripts sheet <rebuilt folder>` leaves on the owner's machine. R1's "at least
20 sessions" is met only once those are labelled.

Found on the way: from transcript files alone (the fixtures have no commits) the graders
cannot grade `tier-declared` for a session with a record, and give `record-check` and
`outcome-filled` as not applicable. On the fifteen fixtures those three steps will be measured
only where the label is also `na`; their real measurement needs the store sessions, graded
with `--repo-dir` on a checkout that has their commits.

Guards: sixteen were broken by hand, one at a time, and the suite run. Three survived the
first round (subagent lines kept out of the sheet, a label with the right hash called stale
by `sheet`, rows of another grader read for a field step); each got a test, and all sixteen
now fail the suite.

Real use, in this session's container, with `$U` a scratch folder holding a copy of
`grade/labels/`. The sheets for the fifteen fixture sessions:

    $ transcripts sheet --transcript plugins/change-record/grade/fixtures/*.jsonl.gz plugins/change-record/grade/fixtures/evals/*.jsonl.gz --out $U/sheets --labels $U/labels
    transcripts: wrote 15 sheets into $U/sheets; label files in $U/labels: 0 new, 15 kept

One of them, `$U/sheets/8dee9822-0a46-4b4c-8891-d973d7242829.md` (eval-07, 135 lines), cut where marked:

    # Label sheet: 8dee9822-0a46-4b4c-8891-d973d7242829

    Write your verdicts in `$U/labels/8dee9822-0a46-4b4c-8891-d973d7242829.txt`: after each step, `pass`, `fail` or `na`, then ` | ` and a one-line reason; and your name and the date after `labelled-by:`. This sheet shows what the session did and nothing a grader concluded from it. Judge each step from the calls below. A call did something only if its own result shows it ran: one that was denied, refused, interrupted or never answered did nothing.

    Transcript: 36 lines, sha256 e62d52dbe1. Lines of subagents kept inline are left out, as the graders leave them out.

    ## The steps

    ### tier-declared

    Did the session declare a tier? Yes if its record's frontmatter holds tier 0, 1 or 2, or, with no record, if its own text or pull request description says `Tier: 0`.

    Label it `na` when the session wrote no record and no code.

    The session's own texts with "tier" in them: [4], [7].
    Calls that name a file under docs/changes/: none.

    [... probe-before-record and record-before-code, the same way ...]

    ### red-first

    Before the first code was written, did a test run actually run and report a failed test? A run that was denied, refused or never answered did not run; a run that stopped on a syntax or import error is no failed test.

    Label it `na` when no code was written, or the change is tier 0.

    Shell commands with "test", "spec" or "check" in them: none.
    Calls of the file tools: [6] Edit /tmp/claude-eval-9pSSDg/home/cwd/README.md. A shell command can write a file too.

    [... change-line, record-check and outcome-filled ...]

    ## The record at the session's last commit

    Not shown: no commit is known for this transcript. The record's text is in the calls that wrote it, below.

    ## The session, in order

    [... [1] the prompt, [2] the Skill call, [3] the skill's text ...]

    **[4] The session:**

        Tier 0 (typo, no behaviour change). Let me find the typo.

    **[5] Bash** `toolu_01KApMc26sQLik4YqqNm2f7L`

        cat README.md; git status --short

    Result, flagged as an error:

        Exit code 1
        # greet

        `python3 greet.py NAME` prints a greating. Tests: `python3 -m unittest discover -s tests -t .`
        /bin/bash: line 1: /tmp/claude-eval-9pSSDg/tmp/claude-0/cwd-a665: Read-only file system

    **[6] Edit** `toolu_012YCzxe8Lq5kKn17s6rsWbH` /tmp/claude-eval-9pSSDg/home/cwd/README.md

        - greating
        + greeting

    Result:

        The file /tmp/claude-eval-9pSSDg/home/cwd/README.md has been updated successfully.

    [... [7] its last message, with the pull request description ...]

`accuracy`, after writing made-up verdicts into three of the copied label files (one session
fully, one with a step left open and two verdicts chosen to disagree, one all `na`):

    $ transcripts accuracy --transcript plugins/change-record/grade/fixtures/*.jsonl.gz plugins/change-record/grade/fixtures/evals/*.jsonl.gz --labels $U/labels
    # Grader accuracy

    The field graders' latest row for each session and step, against a person's label. 3 sessions are counted, of 15 with a transcript here and 15 label files. A false fail is a fail the label does not share, a false pass a pass the label does not share, and a false n/a a not applicable where the label says pass or fail.

    | Step | Labelled | Agree | False fail | False pass | False n/a |
    |---|---|---|---|---|---|
    | tier-declared | 1 | 1 | 0 | 0 | 0 |
    | probe-before-record | 3 | 3 | 0 | 0 | 0 |
    | record-before-code | 3 | 3 | 0 | 0 | 0 |
    | red-first | 3 | 1 | 1 | 1 | 0 |
    | change-line | 3 | 1 | 0 | 2 | 0 |
    | record-check | 3 | 3 | 0 | 0 | 0 |
    | outcome-filled | 2 | 2 | 0 | 0 | 0 |

    ## Disagreements

    - red-first, false fail, 95e399c5-a1ef-4de4-8612-001551b4f84d: the label says pass (made up, to show a disagreement); the grader says fail (no test ran before the code)
    - red-first, false pass, da1017af-e406-4505-ade7-a5b331fa0989: the label says not applicable (made up); the grader says pass (a test run failed before the code (toolu_01Hi1bjGyT1tDD7TMdSnAcSF))
    - change-line, false pass, 95e399c5-a1ef-4de4-8612-001551b4f84d: the label says fail (made up, to show a disagreement); the grader says pass (the PR description opens with the Change: line)
    - change-line, false pass, da1017af-e406-4505-ade7-a5b331fa0989: the label says not applicable (made up); the grader says pass (the description in the last message has the Change: line on its own)

    ## Not counted

    [... 12 lines: <session id>: not labelled yet ...]
    - 95e399c5-a1ef-4de4-8612-001551b4f84d, tier-declared: the grader could not grade it (no commit for the session)
    - 95e399c5-a1ef-4de4-8612-001551b4f84d, outcome-filled: not labelled yet
    - da1017af-e406-4505-ade7-a5b331fa0989, tier-declared: the grader could not grade it (no commit for the session)
    $ echo $?
    0

Error path: a label whose transcript has since grown. The same labels, against a copy of
dispatch-2 with one more line than when it was labelled:

    $ gzip -dc plugins/change-record/grade/fixtures/dispatch-2-da1017af.jsonl.gz > $U/dispatch-2.jsonl; tail -1 $U/dispatch-2.jsonl >> $U/dispatch-2.jsonl
    $ transcripts accuracy --transcript $U/dispatch-2.jsonl --labels $U/labels
    # Grader accuracy

    The field graders' latest row for each session and step, against a person's label. 0 sessions are counted, of 1 with a transcript here and 15 label files. A false fail is a fail the label does not share, a false pass a pass the label does not share, and a false n/a a not applicable where the label says pass or fail.

    | Step | Labelled | Agree | False fail | False pass | False n/a |
    |---|---|---|---|---|---|
    | tier-declared | 0 | 0 | 0 | 0 | 0 |
    | probe-before-record | 0 | 0 | 0 | 0 | 0 |
    | record-before-code | 0 | 0 | 0 | 0 | 0 |
    | red-first | 0 | 0 | 0 | 0 | 0 |
    | change-line | 0 | 0 | 0 | 0 | 0 |
    | record-check | 0 | 0 | 0 | 0 | 0 |
    | outcome-filled | 0 | 0 | 0 | 0 | 0 |

    ## Disagreements

    None.

    ## Not counted

    [... 14 lines: <session id>: labelled, but its transcript is not here ...]
    - da1017af-e406-4505-ade7-a5b331fa0989: stale label, made from a transcript of 110 lines (sha256 b508b426bc); it now has 111 lines (sha256 c72512a016)

Its made-up verdicts, which disagreed with the grader twice in the run above, are in no count.
A malformed file is the other error path, here with a verdict misspelt:

    $ transcripts accuracy --transcript plugins/change-record/grade/fixtures/*.jsonl.gz --labels $U/labels > /dev/null; echo $?
    transcripts: $U/labels/95e399c5-a1ef-4de4-8612-001551b4f84d.txt: red-first: unknown verdict 'passed' (pass, fail or na); the file is rejected
    1
