# Change skill report

Score rows from 5 sessions, grouped by skill version (the git blob of the skill file), oldest first; two versions are never counted together. A pass rate is pass / (pass + fail), with not applicable counted apart. Each step keeps the latest row per session and grader. Grader error is how often that grader's verdict on the step was wrong on the sessions a person labelled, over every version together (the Grader error section has the counts); "not yet checked" means fewer than 5 labelled sessions cover the step, and says nothing for or against its verdicts.

## change-record:change, blob unknown

Sessions: 1, from 2026-11-07 to 2026-11-07.

| Step | Grader | Pass | Fail | N/A | Pass rate | Grader error |
|---|---|---|---|---|---|---|
| tier-declared | fields/1 | 0 | 1 | 0 | 0% | 20% (1 of 5 wrong) |
| red-first | fields/1 | 0 | 0 | 1 | - | not yet checked (4 of 5 needed) |

## change-record:change, blob 11111111

Sessions: 2, from 2026-11-08 to 2026-11-09.

| Step | Grader | Pass | Fail | N/A | Pass rate | Grader error |
|---|---|---|---|---|---|---|
| tier-declared | fields/1 | 2 | 0 | 0 | 100% | 20% (1 of 5 wrong) |
| red-first | fields/1 | 1 | 1 | 0 | 50% | not yet checked (4 of 5 needed) |
| change-line | fields/1 | 1 | 1 | 0 | 50% | not yet checked (3 of 5 needed) |
| outcome-filled | fields/1 | 0 | 0 | 1 | - | not yet checked (0 of 5 needed) |

## change-record:change, blob 22222222

Sessions: 2, from 2026-11-10 to 2026-11-10.

| Step | Grader | Pass | Fail | N/A | Pass rate | Grader error |
|---|---|---|---|---|---|---|
| tier-declared | fields/1 | 2 | 0 | 0 | 100% | 20% (1 of 5 wrong) |
| red-first | fields/1 | 1 | 1 | 0 | 50% | not yet checked (4 of 5 needed) |
| change-line | fields/1 | 1 | 0 | 1 | 100% | not yet checked (3 of 5 needed) |
| decisions-alternative | judge/1:haiku | 1 | 1 | 0 | 50% | not yet checked (no labels) |
| outcome-real-output | judge/1:haiku | 1 | 0 | 1 | 100% | not yet checked (no labels) |

## Pass rate over time

Passes of graded sessions, per skill version, oldest first (the date is the version's first session).

| Step | Grader | unknown (2026-11-07) | 11111111 (2026-11-08) | 22222222 (2026-11-10) |
|---|---|---|---|---|
| tier-declared | fields/1 | 0 of 1 | 2 of 2 | 2 of 2 |
| red-first | fields/1 | - | 1 of 2 | 1 of 2 |
| change-line | fields/1 | - | 1 of 2 | 1 of 1 |
| outcome-filled | fields/1 | - | - | - |
| decisions-alternative | judge/1:haiku | - | - | 1 of 2 |
| outcome-real-output | judge/1:haiku | - | - | 1 of 1 |

## Counts

What each session took, read from the transcripts in this folder and not from a grader: 5 of 5 sessions have a transcript here. Output tokens are counted once per message, and "-" means the transcript carries no token usage. Minutes run from a session's first line to its last, waiting included. A turn from a person is a message a person typed after the first one; whether it was a correction is not judged. No threshold is applied: the middle is the median, and the least and the most name their session.

### change-record:change, blob unknown

| Count | Sessions | Middle | Least | Most |
|---|---|---|---|---|
| Output tokens | 0 | - | - | - |
| Tool calls | 1 | 1 | 1 (c5000000) | 1 (c5000000) |
| Calls that failed or were refused | 1 | 0 | 0 (c5000000) | 0 (c5000000) |
| Messages written | 1 | 1 | 1 (c5000000) | 1 (c5000000) |
| Characters written | 1 | 21 | 21 (c5000000) | 21 (c5000000) |
| Characters in the last message | 1 | 21 | 21 (c5000000) | 21 (c5000000) |
| Turns from a person after the first | 1 | 0 | 0 (c5000000) | 0 (c5000000) |
| Minutes, first line to last | 1 | 0 | 0 (c5000000) | 0 (c5000000) |

| Session | Output tokens | Tool calls | Failed or refused | Messages | Characters | Last message | Turns from a person | Minutes |
|---|---|---|---|---|---|---|---|---|
| c5000000 | - | 1 | 0 | 1 | 21 | 21 | 0 | 0 |

### change-record:change, blob 11111111

| Count | Sessions | Middle | Least | Most |
|---|---|---|---|---|
| Output tokens | 0 | - | - | - |
| Tool calls | 2 | 3.5 | 3 (a2000000) | 4 (a1000000) |
| Calls that failed or were refused | 2 | 1 | 1 (a1000000) | 1 (a1000000) |
| Messages written | 2 | 1.5 | 1 (a2000000) | 2 (a1000000) |
| Characters written | 2 | 73.5 | 68 (a2000000) | 79 (a1000000) |
| Characters in the last message | 2 | 36.5 | 5 (a1000000) | 68 (a2000000) |
| Turns from a person after the first | 2 | 0 | 0 (a1000000) | 0 (a1000000) |
| Minutes, first line to last | 2 | 0.1 | 0.1 (a2000000) | 0.1 (a1000000) |

| Session | Output tokens | Tool calls | Failed or refused | Messages | Characters | Last message | Turns from a person | Minutes |
|---|---|---|---|---|---|---|---|---|
| a1000000 | - | 4 | 1 | 2 | 79 | 5 | 0 | 0.1 |
| a2000000 | - | 3 | 1 | 1 | 68 | 68 | 0 | 0.1 |

### change-record:change, blob 22222222

| Count | Sessions | Middle | Least | Most |
|---|---|---|---|---|
| Output tokens | 0 | - | - | - |
| Tool calls | 2 | 3 | 3 (b3000000) | 3 (b3000000) |
| Calls that failed or were refused | 2 | 0.5 | 0 (b4000000) | 1 (b3000000) |
| Messages written | 2 | 1 | 1 (b3000000) | 1 (b3000000) |
| Characters written | 2 | 20.5 | 5 (b4000000) | 36 (b3000000) |
| Characters in the last message | 2 | 20.5 | 5 (b4000000) | 36 (b3000000) |
| Turns from a person after the first | 2 | 0 | 0 (b3000000) | 0 (b3000000) |
| Minutes, first line to last | 2 | 0.1 | 0.1 (b3000000) | 0.1 (b3000000) |

| Session | Output tokens | Tool calls | Failed or refused | Messages | Characters | Last message | Turns from a person | Minutes |
|---|---|---|---|---|---|---|---|---|
| b3000000 | - | 3 | 1 | 1 | 36 | 36 | 0 | 0.1 |
| b4000000 | - | 3 | 0 | 1 | 5 | 5 | 0 | 0.1 |

## Skill coverage

Of 5 sessions here, 4 used a skill and 1 used none. A session used a skill when its index entry lists it, or its transcript shows the skill called or its file read, by the rule the capture tool applies today.

| Skill | Sessions |
|---|---|
| change-record:change | 4 |
| none | 1 |

## Said again

How much of a session's closing message says a point a second time, as Claude Sonnet took the message apart (`transcripts judge --repeats`). A pair is counted only when both of its quotes are in the message and differ. It is a count, with no label and no pass rate. 3 of 5 sessions here have a counted answer.

### change-record:change, blob 11111111

| Session | Points | Said again | Share |
|---|---|---|---|
| a1000000 | 6 | 2 | 0.33 |
| a2000000 | 4 | 0 | 0.00 |
| Together (2) | 10 | 2 | 0.20 |

### change-record:change, blob 22222222

| Session | Points | Said again | Share |
|---|---|---|---|
| b3000000 | 10 | 9 | 0.90 |

Not counted: b4000000 (malformed: the answer holds no JSON object with a list of points).

Its error: 20% (2 of 10 ruled pairs wrong). A person rules a pair by the id the session's sheet shows, in the session's label file: `said-again: wrong <id>... | right <id>...`; under 10 ruled, the measure is not yet checked.

Ruled wrong: b3000000 `cb33eb` `336aee`.

Stale rulings, not counted: b3000000 `0a0b0c`. No counted answer here for the session holds the id: it was asked again and answered differently, or the id is not the sheet's.

## Defects shown

The defects a reviewer that runs the code could show in a session's own commits (`transcripts judge --review`): each is a script that exits 0 at the session's last commit and not at its base. The count is a floor: a reviewer shows different defects on different runs, so none shown is weak evidence of none. Changed lines are the lines added plus the lines removed between the base and the last commit, binary files left out. No label and no pass rate. 3 of 5 sessions here have a counted review.

### change-record:change, blob 11111111

| Session | Reviewer | Changed lines | Defects shown | Per 1,000 lines | Kinds |
|---|---|---|---|---|---|
| a2000000 | sonnet | unknown | 1 | - | 1 wrong result |

### change-record:change, blob 22222222

| Session | Reviewer | Changed lines | Defects shown | Per 1,000 lines | Kinds |
|---|---|---|---|---|---|
| b3000000 | sonnet | 400 | 2 | 5.0 | 1 crash, 1 stated guarantee broken |
| b3000000 | opus | 400 | 2 | 5.0 | 1 data lost or leaked, 1 not named in the answer |
| b4000000 | sonnet | 120 | 0 | 0.0 | none |
| Together (2) | sonnet | 520 | 2 | 3.8 | 1 crash, 1 stated guarantee broken |

Not counted: a1000000 sonnet (looked outside).

Its error: not yet checked (3 of 10 ruled defects needed). A person rules a defect by the id the session's sheet shows, in the session's label file: `defects: wrong <id>... | right <id>...`; under 10 ruled, the measure is not yet checked.

Ruled wrong: b3000000 `f7c8a1`.

Stale rulings, not counted: b4000000 `ffffff`. No counted answer here for the session holds the id: it was asked again and answered differently, or the id is not the sheet's.

## Judge agreement

The Haiku judge and opencode-go/kimi-k3.1-pro agree on 2 of 3 judgments (67%), over 2 sessions judged by both. Below 80%: per C3, the default judge should move to the other model family.

## Grader error

Each field grader's latest row for a session and step, against a person's label of that session. 5 sessions are counted, of 5 with a transcript here and 5 label files. A labelled session covers a step when its label or the grader says pass or fail; where both say not applicable nothing was put to the test, and it is counted apart. Wrong is a false fail (a fail the label does not share), a false pass (a pass the label does not share) or a false n/a (not applicable where the label says pass or fail). A step covered by fewer than 5 labelled sessions is not yet checked: nothing here says its verdicts are right.

| Step | Grader | Covered | Wrong | Error | False fail | False pass | False n/a | Both n/a |
|---|---|---|---|---|---|---|---|---|
| tier-declared | fields/1 | 5 | 1 | 20% | 0 | 1 | 0 | 0 |
| red-first | fields/1 | 4 | 1 | not yet checked | 1 | 0 | 0 | 1 |
| change-line | fields/1 | 3 | 0 | not yet checked | 0 | 0 | 0 | 1 |
| outcome-filled | fields/1 | 0 | 0 | not yet checked | 0 | 0 | 0 | 1 |

The labels cover the field graders' steps only: decisions-alternative and outcome-real-output are not yet checked.

### Known false verdicts

- tier-declared, false pass, a1000000 (a1000000-0000-0000-0000-000000000001): the label says fail (made up: the record's frontmatter holds no tier); the grader says pass (tier 1)
- red-first, false fail, b4000000 (b4000000-0000-0000-0000-000000000004): the label says pass (made up: run-tests.sh printed a failed test before greet.py was edited); the grader says fail (no test run that ran failed before the code)

### Not counted

- probe-before-record: no score row, in 4 sessions (a1000000, a2000000, b3000000, b4000000)
- probe-before-record: not labelled yet, in 1 session (c5000000)
- record-before-code: no score row, in 4 sessions (a1000000, a2000000, b3000000, b4000000)
- record-before-code: not labelled yet, in 1 session (c5000000)
- change-line: no score row, in 1 session (c5000000)
- record-check: no score row, in 4 sessions (a1000000, a2000000, b3000000, b4000000)
- record-check: not labelled yet, in 1 session (c5000000)
- outcome-filled: no score row, in 4 sessions (a2000000, b3000000, b4000000, c5000000)

### Rows that are no verdict

None: no row here says its grader could not read what it needed.

## Failed steps

Each session and step whose latest row, whatever the grader, is a fail, per skill version, newest first: the grader's reason, the rest of its evidence, and the calls it cites, each with a redacted excerpt from the transcript. [n] is the call's number in the session's label sheet. A fail is a grader's verdict, to be read against that grader's error above. No edit is proposed: what to change, if anything, is the reader's to decide from what the session did.

### change-record:change, blob 22222222

#### red-first, b4000000 (b4000000-0000-0000-0000-000000000004)

fields/1 says fail: no test run that ran failed before the code

Its error on this step: not yet checked (4 of 5 needed). A person's label says pass (made up: run-tests.sh printed a failed test before greet.py was edited): this fail is a known false fail.

Its evidence: record docs/changes/2026-11-10-title.md; test_runs_before_code 1; denied_test_runs 0; failing_runs none.

first_code_write (greet.py), **[3] Edit** `c1` /work/made-up/greet.py:

    -     return n
    +     return n.title()

Result:

    The file /work/made-up/greet.py has been updated.

Shell commands before [3]:

- [2] `sh run-tests.sh`: ran; its result opens `test_title: not ok (made up: a failed test in a form the grader does not read)` and ends `done`

#### decisions-alternative, b3000000 (b3000000-0000-0000-0000-000000000003)

judge/1:haiku says fail: 2 of 3 votes fail: the Decisions name no rejected alternative

Its error on this step: not yet checked (no labels).

Its votes:

- vote 1, fail: No Decision names what it rejected.
- vote 2, pass: One Decision rejects a config file, as <redacted:email> asked.
- vote 3, fail: The Decisions state choices only.

### change-record:change, blob 11111111

#### red-first, a1000000 (a1000000-0000-0000-0000-000000000001)

fields/1 says fail: no test ran before the code

Its error on this step: not yet checked (4 of 5 needed).

Its evidence: record docs/changes/2026-11-08-shout.md; test_runs_before_code 0; denied_test_runs 1; failing_runs none.

first_code_write (greet.py), **[5] Write** `c1` /work/made-up/greet.py:

    def greet(n, shout=False):
        return n.upper() if shout else n

Result:

    File created successfully

Shell commands before [5]:

- [3] `python3 -m unittest discover -s tests`: never answered
- [4] `curl -H 'Authorization: Bearer <redacted:token>' https://x.example.org/ok`: ran; its result is `ok`

#### change-line, a2000000 (a2000000-0000-0000-0000-000000000002)

fields/1 says fail: the PR description opens with 'Summary'

Its error on this step: not yet checked (3 of 5 needed).

Its evidence: record docs/changes/2026-11-09-whisper.md; source pull request.

It cites no call.

### change-record:change, blob unknown

#### tier-declared, c5000000 (c5000000-0000-0000-0000-000000000005)

fields/1 says fail: code written with no record and no Tier: 0

Its error on this step: 20% (1 of 5 wrong).

Its evidence: record none.

first_code_write (greet.py), **[1] Write** `c1` /work/made-up/greet.py:

    def greet(n):
        return 'hello, ' + n

Result:

    File created successfully
