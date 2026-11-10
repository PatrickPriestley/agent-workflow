# Change skill report

Score rows from 5 sessions, grouped by skill version (the git blob of the skill file), oldest first; two versions are never counted together. A pass rate is pass / (pass + fail), with not applicable counted apart. Each step keeps the latest row per session and grader.

## change-record:change, blob unknown

Sessions: 1, from 2026-11-07 to 2026-11-07.

| Step | Grader | Pass | Fail | N/A | Pass rate |
|---|---|---|---|---|---|
| tier-declared | fields/1 | 0 | 1 | 0 | 0% |
| red-first | fields/1 | 0 | 0 | 1 | - |

## change-record:change, blob 11111111

Sessions: 2, from 2026-11-08 to 2026-11-09.

| Step | Grader | Pass | Fail | N/A | Pass rate |
|---|---|---|---|---|---|
| tier-declared | fields/1 | 2 | 0 | 0 | 100% |
| red-first | fields/1 | 1 | 1 | 0 | 50% |
| change-line | fields/1 | 1 | 1 | 0 | 50% |
| outcome-filled | fields/1 | 0 | 0 | 1 | - |

## change-record:change, blob 22222222

Sessions: 2, from 2026-11-10 to 2026-11-10.

| Step | Grader | Pass | Fail | N/A | Pass rate |
|---|---|---|---|---|---|
| tier-declared | fields/1 | 2 | 0 | 0 | 100% |
| red-first | fields/1 | 1 | 1 | 0 | 50% |
| change-line | fields/1 | 1 | 0 | 1 | 100% |
| decisions-alternative | judge/1:haiku | 1 | 1 | 0 | 50% |
| outcome-real-output | judge/1:haiku | 1 | 0 | 1 | 100% |

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

## Judge agreement

The Haiku judge and opencode-go/kimi-k3.1-pro agree on 2 of 3 judgments (67%), over 2 sessions judged by both. Below 80%: per C3, the default judge should move to the other model family.

## Proposed skill edits

From failed sessions only, citing each session and step, per skill version, newest first.

### change-record:change, blob 22222222

- red-first, in "3. Loop", step 3 (Red, then green): require the failing test run's output to be seen before the first code edit, and say that a denied or skipped test run does not count. Failed in:
  - b4000000 (b4000000-0000-0000-0000-000000000004): no test run that ran failed before the code
- decisions-alternative, in "2. Probe, then record": ask for each Decision to name the alternative it rejected and why, as `Rejected: <option>, because <reason>`. Failed in:
  - b3000000 (b3000000-0000-0000-0000-000000000003): 2 of 3 votes fail: the Decisions name no rejected alternative

### change-record:change, blob 11111111

- red-first, in "3. Loop", step 3 (Red, then green): require the failing test run's output to be seen before the first code edit, and say that a denied or skipped test run does not count. Failed in:
  - a1000000 (a1000000-0000-0000-0000-000000000001): no test ran before the code
- change-line, in "3. Loop", step 6 (Push): give the exact first line of the PR body to copy, `Change: docs/changes/<id>.md`, with nothing before it. Failed in:
  - a2000000 (a2000000-0000-0000-0000-000000000002): the PR description opens with 'Summary'

### change-record:change, blob unknown

- tier-declared, in "1. Tier": make the tier the first thing written: `tier:` in the record's frontmatter, or `Tier: 0` in the PR body for a change with no behaviour change. Failed in:
  - c5000000 (c5000000-0000-0000-0000-000000000005): code written with no record and no Tier: 0
