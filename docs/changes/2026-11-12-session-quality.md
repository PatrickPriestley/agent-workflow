---
id: 2026-11-12-session-quality
tier: 2
status: approved
requester: Patrick Priestley, in chat on 2026-11-12 ("Does this transcription review cover more general evaluation like verbosity, test quality, etc", "This is the inspiration for the transcript evaluation and improvement loop" with Skill Doctor's skill file, "Yes, draft the change record", and "As recommended" to its seven concerns)
approvers: [Patrick Priestley, 2026-11-12]
plugin: plugins/change-record
tasks:
  - name: counts
    done: true
  - name: rubrics
    after: counts
  - name: edits
    after: rubrics
---
# The report also shows what a session cost and how its code and prose rate, and a confirmed failure can become a drafted skill edit

## Goal

The transcript review grew out of Skill Doctor, which scores a session for efficiency, code
quality, procedure compliance and verbosity and then drafts skill edits. What was built covers
one of those four, procedure compliance, and stops at a report. This change adds the other
three in the form the last two records argue for (counts where a count will do, a judge only
where its error can be measured), and brings back the step that turns a failure into a
proposed edit of the skill, for the owner to accept or not.

## Probed facts

- Exact source (`warpdotdev/common-skills` at `8792394`, 2026-10-20, `.agents/skills/skill-doctor/`,
  MIT licence, cloned 2026-11-09, and the skill file the owner pasted on 2026-11-12): four
  rubrics, each read by a model over a condensed transcript, each answering with a label and a
  fixed score. Efficiency: four labels, 1 to 0.2. Code quality: `approve` 1, `block` 0.2,
  `insufficient_evidence`. Procedure compliance: three labels. Verbosity: `proportionate` 1,
  `verbose` 0.2, `terse` 0.1. The scores are averaged, curved (`0.5 + 0.5 * score`) and weighted
  into one grade; a session "fails" when any score is under 0.5; suggestions and drafted
  edits use failed sessions only, each citing the session, the scorer and the moment. It
  writes proposed skill files beside the report and never edits the real ones.
- Exact source (this repository at `f110004`): `transcripts grade` gives seven steps of the
  `change` skill from tool calls (`fields/2`), `transcripts judge` two questions about the record
  (`judge/1`, Claude Haiku, three votes), and `transcripts report` pass rates, grader error
  against labels, and the evidence behind each failure. The report proposes nothing: its table
  of fixed advice was removed under `2026-11-11-grading-trust`. No number in it describes cost,
  code or prose.
- Verified against the real system (the five sessions rebuilt from the store on 2026-11-11,
  read again on 2026-11-12): every assistant line carries `message.usage` with `output_tokens`,
  and every line a timestamp. One message is written on several lines, each repeating the same
  usage: in the `report` task's session, 239 lines are 108 messages, and adding `output_tokens`
  line by line gives 298,907 where once per message gives 121,959. So tokens must be counted
  once per message id.
- Verified against the real system (the same sessions, `grade/fields.py`'s reader): the three
  task sessions made 50, 90 and 115 tool calls, of which 1, 3 and 2 failed or were refused;
  wrote 15, 32 and 47 messages (3,620 to 7,977 characters in all) and a last message of 198,
  3,365 and 3,415 characters; and had 3, 1 and 1 turns from a person. The long session that ran
  the whole change had 850 calls, 265 messages, 212,502 characters and 188 turns over three
  days. A command or a file read repeated word for word happened once in all five.
- Verified against the real system (git, the same sessions' first and last commits): what
  each task session changed is 22,462, 27,724 and 132,762 characters of diff (5, 2 and 29
  files). The judge today shows a model at most 12,000 characters of a section.
- Exact source (`store/schema.sql`): the store has `scores` (a verdict per session and step)
  and `judge_votes`. Nothing holds a number per session.
- Verified against the real system (the session index of the `report` task's session): its
  `skills` list is empty. It read the skill file through the shell before `transcripts`
  recorded that (fixed in pull request #44), so which skill a session used is known only for
  sessions captured since.
- Exact source (records `2026-11-11-grading-trust` and `2026-11-12-grader-fixes`, Outcome): the
  first report was wrong three times out of three; rules written from fifteen sessions left
  all eight errors on five new ones; the two judged questions passed in every session and
  have no labels; no independent review has run on a pull request since #41.
- Not known: how often a model's rubric verdict on code or prose matches a person's here. No
  session is labelled for either.

## Problem

The owner asked whether the review covers verbosity and test quality. It does not. It says
whether a session followed the skill's order of work and nothing about whether the work was
cheap to get, well made, or reported at a sensible length, which is three quarters of what
its inspiration scores. And where the inspiration ends in a drafted edit, this ends in a
report the owner must read and act on alone. The obvious fix, a model reading each transcript
against four rubrics, is what the last two records showed cannot be trusted unmeasured: the
checks that were measured were wrong often, and the judged ones never said anything but pass.

## Requirements

- R1. The report shows, for each skill version and for each session: output tokens (once per
  message), tool calls, calls that failed or were refused, messages written and their
  characters, the last message's characters, turns from a person after the first, and the
  time from first to last line. Check: a stored expected report from fixture transcripts, and
  a test that a message on three lines is counted once.
- R2. The counts are computed from the transcripts in the folder when the report runs, and
  nothing is added to the store. Check: the report on a folder with no `scores/` still prints
  them; `store/schema.sql` is unchanged.
- R3. The report shows skill coverage: of the sessions in the folder, how many recorded each
  skill, and how many recorded none. Check: the stored expected report.
- R4. `transcripts judge` can ask two more questions, `code-quality` and `verbosity`, with
  rubrics adapted from Skill Doctor's (its licence notice kept). Code quality is asked of the
  diff between the session's first and last commit; verbosity of the messages the session
  wrote. Each answer is a label from the rubric, with a reason that quotes the session. Check:
  made-up sessions and a stand-in judge give a stored expected set of rows; a session with no
  commit gets no code-quality verdict and says why.
- R5. A session can be labelled for those two questions, and the report shows each judge's
  error beside its results exactly as for the field steps, "not yet checked" under five
  labelled sessions. Check: the stored expected report; a label file with an unknown rubric
  label is rejected.
- R6. `transcripts propose` writes, for a failure a label confirms, a proposed version of the
  skill file and its diff, outside every working tree, citing the session, the step or
  rubric, and the calls. It refuses a failure no label confirms, and never writes to the
  skill. Check: a confirmed failure and a stand-in model give a stored expected proposal; an
  unconfirmed one exits 1 and writes nothing.
- R7. A proposal names the eval case that shows the failure, or says that none does. Check:
  the stored expected proposal.

## Options and concerns

**A. Counts, two measured rubrics, and proposals from confirmed failures (recommended).** What
a count can say is counted; the two things only a reader can judge are judged, with their
error shown; an edit is drafted only where a person agrees the session failed. Cost: about
ten sessions to label, and model calls for the two rubrics.

**B. Run Skill Doctor as written on a rebuilt folder.** No new code: `transcripts materialize`
already writes a folder it reads. Rejected as the answer, kept as a second opinion: it would
still count the `change` skill as unused, its four verdicts are unmeasured, and its one grade
hides which of them moved. It must run on the owner's machine.

**C. All four as model rubrics inside `transcripts judge`.** Closest to the inspiration.
Rejected: efficiency and most of verbosity are counts, a rubric for them costs a model call
to say less precisely what the transcript already holds, and four unmeasured judges are four
times the problem the last record found with two.

**D. Leave code quality to review before merge.** A reviewer on the pull request sees the code
at the right time. Not instead of this: the cross-model reviewer has had no balance since
pull request #41, and a review leaves no number to follow across skill versions. Worth doing
as well; outside this record.

### C1: one grade, or the numbers
Skill Doctor curves and weights its scores into one letter grade. Failure case: a grade
moves and nobody can say which part moved it, or it is quoted as if measured. Recommended: no
overall grade and no thresholds. The report shows the counts as a middle value and a range
per skill version, lists the sessions furthest from the middle, and leaves "too many" to the
owner until there are sessions enough to say what is usual. Owner: Patrick Priestley.
Resolved: as recommended. Patrick Priestley, 2026-11-12 ("As recommended", in chat; merging this
record confirms it).

### C2: which model judges, and what it costs
Today's judge is Claude Haiku, three votes, on at most 12,000 characters, and it has never
answered fail. A session's diff here is 22,000 to 133,000 characters. Failure case: a small
model approves everything, or the bill grows with every session captured. Recommended:
verbosity stays on Haiku; code quality uses Claude Sonnet, three votes; both only for
sessions that wrote code, at most 20 per run, with the number of calls printed before any is
made. If the first labelled measurement shows a judge wrong on more than one session in
five, it is taken out of the report and not tuned. Owner: Patrick Priestley.
Resolved: as recommended. Patrick Priestley, 2026-11-12 ("As recommended", in chat; merging this
record confirms it).

### C3: who labels the two rubrics, and how many
Nothing is labelled for code or prose. Failure case: the judges run for months marked "not
yet checked", which is where the two questions of `judge/1` are now. Recommended: ten sessions
that wrote code, labelled as before (a model's blind first pass, the owner ruling on every
disagreement with the judge and on what the labellers leave open), before the rubric results
are shown as anything but "not yet checked". Owner: Patrick Priestley.
Resolved: as recommended. Patrick Priestley, 2026-11-12 ("As recommended", in chat; merging this
record confirms it).

### C4: what the code-quality judge reads
The diff comes from the session's commits, which fixtures and cut-off sessions lack, and it
can be far larger than a model should be shown at once. Failure case: a large change is
judged on its first files and called `block` for tests that were in the part cut off.
Recommended: no commit, no verdict, said as an error like the field steps; a diff over
60,000 characters is judged on its code and test files first, generated and fixture files
left out, and a verdict on a part is marked so and counted apart. Owner: Patrick Priestley.
Resolved: as recommended. Patrick Priestley, 2026-11-12 ("As recommended", in chat; merging this
record confirms it).

### C5: what a proposed edit may be built on, and where it goes
Skill Doctor drafts from any session its own scorers failed. Here the scorers have been wrong
often. Failure case: the skill is edited to cure a grader's mistake, or grows a rule for one
odd session. Recommended: a proposal needs a failure that a label confirms; it is written
outside the repository; and it enters the skill only as a normal change with its own record,
shown by the eval suite to help with the plugin and not without. Rejected: applying edits on
request, as Skill Doctor offers. Owner: Patrick Priestley.
Resolved: as recommended. Patrick Priestley, 2026-11-12 ("As recommended", in chat; merging this
record confirms it).

### C6: more of each session goes to a model
The judge already sends a record's sections and the session's commands to Claude, redacted.
This adds the session's messages and its diff. Failure case: something the pattern redaction
misses (a name, a customer's data in a test file) is sent. Recommended: the same redaction on
everything sent; Claude only, through the owner's own account, and no other provider without
a new decision; `--limit` and `--session` so the owner chooses what is sent. Owner: Patrick
Priestley.
Resolved: as recommended. Patrick Priestley, 2026-11-12 ("As recommended", in chat; merging this
record confirms it).

### C7: using Skill Doctor's rubric text
The rubrics are MIT-licensed work of Denver Technologies, Inc. Failure case: text copied
without its notice. Recommended: adapt the two rubrics, keep the licence notice beside them,
and say in the README where they came from. Owner: Patrick Priestley.
Resolved: as recommended. Patrick Priestley, 2026-11-12 ("As recommended", in chat; merging this
record confirms it).

## Decisions

- Efficiency is counted, not judged. Rejected: Skill Doctor's efficiency rubric, which needs a
  model to read the whole transcript to estimate what the counts state.
- Test quality is not judged from the transcript. The code-quality rubric asks whether tests
  are present and would fail on a broken implementation, which is as far as a reader can go;
  whether they do is `red-check`'s and a mutation tool's to say, on the code. Rejected: a
  third judged question for tests.
- The counts are not stored. Rejected: a table in the store, which needs the owner to change
  the schema for numbers the transcripts already hold.
- Time is first line to last line, and is shown with the count of turns from a person, since
  a session that waited overnight is not a slow one. Rejected: guessing active time.
- A turn from a person after the first is counted, not called a correction. Whether it was
  one is a judgment the count does not make.
- The rubric labels are kept as labels (`approve`, `block`; `proportionate`, `verbose`, `terse`)
  and are not turned into scores or averaged. Rejected: Skill Doctor's numbers, which give
  `verbose` twice the worth of `terse` with nothing behind the ratio.
- Coverage is counted only over sessions captured since pull request #44, and the report says
  how many it left out. (Task 1 changed this: see the task's decisions below.)
- A proposal is a file for the owner, and the loop closes through the eval suite: an edit is
  kept when the with-and-without comparison improves, not when the report's next pass rate
  does. Rejected: reading the effect of an edit from captured sessions, which the review of
  2026-11-11 found too few and too mixed to show it.
- (Task 1.) Coverage reads the transcript as well as the index entry, with the capture hook's
  own rule, so every session with a transcript is counted and none is left out. This replaces
  the decision above. Rejected: a cut-off date for "captured since #44", which the index does
  not record and a re-import would make wrong.
- (Task 1.) A report with no score rows is no longer an error when the folder holds sessions:
  it prints the counts and the coverage and says to run `grade` for the steps (R2). An empty
  folder is still refused.
- (Task 1.) Sessions are grouped by the skill version their score rows carry, or, with no
  rows, by the `change` skill in their index entry; the least and the most name their session,
  which is how "the sessions furthest from the middle" (C1) are listed.
- (Task 1.) A turn from a person leaves out lines marked as the harness's, compaction
  summaries, and messages that open with a tag (`<task-notification>`, `<command-name>`). A
  person who opens a message with such a tag is missed. In the five stored sessions the rule
  counts 46 typed turns and leaves out 134 lines for a tag, all of them notifications or
  command output.
- (Task 1.) A transcript with a line that is not JSON is left out of the counts and the report
  says how many. Rejected: counting what could be read, which would understate without saying.

## Tasks

One pull request each.

1. **Counts.** `grade/measures.py` and `grade/report.py`: the counts (R1, R2) and skill coverage
   (R3). Test: the stored expected report in `bin/transcripts-judge.test.sh`, and unit cases for
   a message on several lines; they fail today because the report has no such section.
2. **Rubrics.** `grade/judge.py`, `grade/labels.py`, `bin/transcripts`, the two rubric files, the
   labelling guide: the questions (R4), their labels and error (R5); `judge/2`. The owner's ten
   sessions are labelled after it merges. Test: R4 and R5 in `bin/transcripts-judge.test.sh`
   with the stand-in judge; they fail today because the questions do not exist.
3. **Edits.** `transcripts propose` (R6, R7) and its section of the report. Test: a confirmed
   and an unconfirmed failure in `bin/transcripts-judge.test.sh`; it fails today because the
   command does not exist.

## Checks

The change-record suites on Ubuntu and macOS. Real use, on the owner's machine with the read
key: the report with counts for the sessions in the store; the two rubrics on ten sessions,
their labels, and the report with the judges' error; one proposal from a confirmed failure,
then that edit tried with `claude plugin eval`. Error paths: a session with no commit, a diff
over the limit, a failure with no label. The reviewer should attack: tokens counted twice,
anything sent to the model unredacted, a proposal built on an unconfirmed failure, and a
rubric result shown without its "not yet checked".

## Outcome

### Task 1, counts (2026-11-12)

Shipped: `grade/measures.py`; the Counts and Skill coverage sections of `grade/report.py`;
`skills_in` in `bin/transcripts`, which applies the capture hook's skill rule to a transcript
(the hook's own code now calls the same function); fixtures `grade/fixtures/counts/`; the README.
`store/schema.sql` is unchanged (R2). `transcripts-judge.test.sh` goes from 149 assertions to 167;
the other suites pass unchanged (`transcripts-grade` 168, `transcripts` 250, `transcripts-store`
82, `record-check` 85, `red-check` 107, `dispatch` 218, `evals/cases.test.cjs` 40).

Red first: the test commit failed eleven assertions. Both expected reports were written by
hand before the code and matched on its first run. Guards: 28 were broken by hand in a copy
of the plugin, one at a time, and the suite run; 27 failed it. The one that did not (a skill
version none of whose sessions has a transcript here printed an empty table) got a test, and
all 28 now fail it.

Real use, on the five sessions rebuilt from the store on 2026-11-11 (the folder still in this
container; the store was not read again):

    $ transcripts report <folder>
    ## Counts
    ... 5 of 5 sessions have a transcript here. ...
    ### change-record:change, blob unknown
    | Count | Sessions | Middle | Least | Most |
    | Output tokens | 5 | 117,122 | 4 (883c53c9) | 764,268 (5ac54a69) |
    | Tool calls | 5 | 90 | 0 (883c53c9) | 850 (5ac54a69) |
    | Calls that failed or were refused | 5 | 2 | 0 (883c53c9) | 14 (5ac54a69) |
    | Messages written | 5 | 32 | 1 (883c53c9) | 265 (5ac54a69) |
    | Characters written | 5 | 6,337 | 2 (883c53c9) | 212,502 (5ac54a69) |
    | Characters in the last message | 5 | 1,458 | 2 (883c53c9) | 3,415 (dd2defdb) |
    | Turns from a person after the first | 5 | 0 | 0 (659da00f) | 41 (5ac54a69) |
    | Minutes, first line to last | 5 | 52.5 | 0.1 (883c53c9) | 4,297.4 (5ac54a69) |

    | Session | Output tokens | Tool calls | Failed or refused | Messages | Characters | Last message | Turns from a person | Minutes |
    | 5ac54a69 | 764,268 | 850 | 14 | 265 | 212,502 | 1,458 | 41 | 4,297.4 |
    | 659da00f | 79,910 | 50 | 1 | 15 | 3,620 | 198 | 0 | 78.8 |
    | 883c53c9 | 4 | 0 | 0 | 1 | 2 | 2 | 0 | 0.1 |
    | 6cc07e5f | 117,122 | 90 | 3 | 32 | 6,337 | 3,365 | 0 | 31.9 |
    | dd2defdb | 121,959 | 115 | 2 | 47 | 7,977 | 3,415 | 0 | 52.5 |

    ## Skill coverage
    Of 5 sessions here, 4 used a skill and 1 used none. ...
    | change-record:change | 3 |
    | agent-review | 1 |
    | change | 1 |
    ... five more skills, one session each (the long session)
    | none | 1 |

The token figures are the once-per-message ones of Probed facts (121,959 where line by line
gives 298,907). The three task sessions' index entries list no skill; the transcript rule
finds the `change` skill in all three, which is the case the first decision on coverage would
have left out. Error path, the same folder with its `scores/` removed:

    $ transcripts report <folder without scores>; echo $?
    # Change skill report
    No score rows here: run `transcripts grade` for the steps. The counts and the coverage below need only ...
    0

Not done, and what the numbers do not say:

- Five sessions, all under one skill version, one of them a single word and one three days
  long. The middle of such a set means little; it is printed, not interpreted.
- One skill shows under two names (`change-record:change` and `change`), as the transcripts
  name it. They are not merged.
- Input and cached tokens are not shown; only what the session wrote.
- "Failed or refused" counts a test run that failed on purpose (red first) like any other
  failed command.
