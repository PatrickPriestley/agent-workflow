---
id: 2026-11-12-judge-asks-again
tier: 1
status: done
requester: Patrick Priestley, in chat on 2026-11-12 ("Yes, tier 1, test first", to "The two cmd_judge gaps the labeller found in dd2defdb are still on main ... Fix them?")
approvers: []
---
# The judge asks again where it has no verdict, and `--store` sends what was judged before

## Goal

Close the two gaps a blind labeller found in `transcripts judge` when labelling session
`dd2defdb` for code quality (record `2026-11-12-session-quality`, concern C3), and which the
owner ruled a reviewer would block on: a session whose answers were all errors is never asked
again, and a session judged without `--store` can never be sent to the store.

## Probed facts

- Exact source (`plugins/change-record/bin/transcripts`, `cmd_judge`, on `main` at `86eeb6d`): a
  session is "already judged" when a file in `judges/` has the same judge version and the same
  record hash. What the file holds is not read.
- Verified against the real system (`bin/transcripts-judge.test.sh` with the tests of this
  record added, the stand-in judge answering `error` six times, in this container): the run
  prints `undecided (error error error)` for both questions and exits 0; the next run makes 0
  calls and prints `1 already judged`. The same with the agreement judge (`--judge opencode`).
- Verified against the real system (the same suite): the rubric judge (`judge --rubrics`)
  already asks again a question whose verdict is neither pass nor fail, and keeps the other.
  It also exits 0 when all three answers to a question were errors.
- Verified against the real system (the same suite, the stand-in store): a session judged
  without `--store`, then run with `--store`, sends 0 rows (`1 already judged; stored 0 rows`).
  So does a session whose first `--store` run was refused part way (`its rows are kept in`),
  and so does `judge --rubrics --store` for sessions judged before (`0 rows stored`).
- Exact source (`plugins/change-record/store/schema.sql`): `scores` has the primary key
  (session_id, step, grader, graded_at) and `judge_votes` (session_id, question, judge, vote,
  judged_at). `insert` in `bin/transcripts` counts a 409 duplicate as a row the store has.
  So a row sent twice with the same time changes nothing.
- Exact source (`grade/judge.py`): a vote's status is `vote`, `malformed`, `refused` or
  `error`. `error` is the CLI not starting, no answer in time, an API error, or an answer from
  another model than the one asked for. Three counted votes on a pass or fail question always
  decide, so undecided means answers were not counted.

## Decisions

- A session is already judged only when every question has a verdict. A question left
  undecided is asked again at the next run, three votes; the questions that have a verdict
  are kept as they are, votes and time included. Rejected: asking the whole session again,
  which pays for the decided question a second time and writes its votes to the store twice.
- A run in which an answer was an error exits 1 and says, per session, how many. Answers the
  model gave that are not votes (malformed, refused) do not change the exit status: they are
  the model's, are recorded, and the question is asked again all the same. Rejected: exit 1 on
  any undecided question, which fails a scheduled run for a model's bad JSON.
- Each question keeps the time it was judged, and its rows carry that time. Rejected: the
  time of the run for every row, as now, which stores a kept question's rows a second time
  under a new time.
- `--store` also sends the rows of sessions judged before that have not been sent: the judge
  file is marked `stored_at` when all of a session's rows went, and a file without the mark is
  owed. Rejected: sending every judged session's rows at each `--store` run and relying on the
  store's 409, which is a request per row per session for ever.
- No limit on sessions whose rows are owed: sending is no model call. `--limit` stays the
  number of sessions judged.

## Tasks

1. `bin/transcripts` (`cmd_judge`, `judge_rubrics`), `grade/judge.py` (`judge_record` keeps
   the questions that have a verdict). Test: in `bin/transcripts-judge.test.sh`, a run of
   errors then a run that answers; one question undecided and the other kept; the agreement
   judge; the rubric judge's exit status; rows sent later, once, with the time of judging,
   after a refused store too, and for the rubric rows. They fail today as Probed facts say.

## Checks

`bash plugins/change-record/bin/transcripts-judge.test.sh` and the other change-record suites.
Real use: the three task sessions judged for the rubrics on 2026-11-12 without `--store`
cannot be sent from here (the read key is not in this session), so real use is the stand-in
store. Error path: a store that refuses, and a judge that does not start. The reviewer should
attack: a session asked again at every run for ever, and a row stored twice.

## Outcome

Shipped: `cmd_judge` and `judge_rubrics` in `bin/transcripts`, `judge_record(keep=...)` in
`grade/judge.py`, and the README's two paragraphs on judging. `transcripts-judge.test.sh` goes
from 238 assertions to 278; `transcripts` (250), `transcripts-grade` (168) and
`transcripts-store` (89) pass unchanged.

Red first: 15 of the first 25 new assertions failed on the old code, among them

    FAIL a run in which every answer was an error leaves both questions undecided, says so and exits 1
         expected [1 undecided undecided] got [0 undecided undecided]
    FAIL the next run asks that session again, and it has its verdicts
         expected [0 6 pass pass] got [0 0 undecided undecided]
    FAIL --store sends the rows of a session judged before without it, and asks no judge
         expected [0 0 2 6] got [0 0 0 0]
    FAIL --rubrics --store sends the rubric rows judged before without it
         expected [0 0 10] got [0 0 0]

One assertion of that commit was wrong in the test, not the code (its helper read the
report's GET requests as rows), and is corrected in the fix's commit. Fifteen more assertions
came with the fix, for what the first set left open: an old error on a kept question, kept
times on rows, the agreement judge's rows, and rubric rows sent in the run that judged them.

Use, against the stand-in judge and the stand-in store, which is the test:

- six errors: `d1000000: 6 of the judge's answers were errors; a question left with no
  verdict is asked again at the next run`, exit 1; the next run makes six calls and both
  questions pass;
- one question decided and one not: the next run makes three calls, and the decided
  question's votes are byte for byte what they were;
- judged without `--store`, then with it: no call to a judge, 2 score rows and 6 votes sent,
  `stored 8 rows`, each with the time in the judge file; the run after sends nothing;
- a store that refuses `judge_votes`: exit 1, `its rows are kept in`; the next run against a
  store that accepts sends all 8;
- a question asked again with `--store`: `stored 4 rows` (its score and three votes); the kept
  question's rows go with their first time and the store answers that it has them.

Guards: 24 broken by hand, one at a time. 22 failed the suite. One survivor was a condition
that could not be false (`owed` is only filled with `--store`) and is removed. The other, an
old error on a kept rubric question counted again at the next run, now has a test and fails
it.

What the reviewer was asked to attack:

- Asked again for ever. A question the model never answers as a vote is asked at every run,
  three calls each time, and is printed as undecided each time. It is bounded by `--limit`
  and not otherwise capped. The rubric judge already behaved this way.
- A row stored twice. A kept question's rows are sent with their first time, so the store's
  primary key refuses them. Rows stored before this change by a run that then asked a
  question again do not exist: before it, nothing was asked again.

Not done: the rubric rows of the three task sessions judged on 2026-11-12 are still only in
this container's folder. `transcripts judge DIR --rubrics --store` on the owner's machine
would send them, if that folder is copied there; they are also pasted in the Outcome of
`2026-11-12-session-quality`.
