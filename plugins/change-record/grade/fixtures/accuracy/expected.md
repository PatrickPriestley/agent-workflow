# Grader accuracy

The field graders' latest row for each session and step, against a person's label. 3 sessions are counted, of 7 with a transcript here and 7 label files. A false fail is a fail the label does not share, a false pass a pass the label does not share, and a false n/a a not applicable where the label says pass or fail.

| Step | Labelled | Agree | False fail | False pass | False n/a |
|---|---|---|---|---|---|
| tier-declared | 2 | 2 | 0 | 0 | 0 |
| probe-before-record | 3 | 2 | 0 | 0 | 1 |
| record-before-code | 3 | 3 | 0 | 0 | 0 |
| red-first | 3 | 2 | 1 | 0 | 0 |
| change-line | 3 | 2 | 0 | 1 | 0 |
| record-check | 3 | 3 | 0 | 0 | 0 |
| outcome-filled | 2 | 2 | 0 | 0 | 0 |

## Disagreements

- probe-before-record, false n/a, e3000000-0000-0000-0000-000000000003: the label says fail (it wrote the record itself, with no probe before); the grader says not applicable (the record was there when the session started)
- red-first, false fail, e2000000-0000-0000-0000-000000000002: the label says pass (the test ran red inside `cd app && npm test`, before the first code); the grader says fail (no test ran before the code)
- change-line, false pass, e2000000-0000-0000-0000-000000000002: the label says fail (the PR body opens with a heading, the Change: line is second); the grader says pass (the PR description opens with the Change: line)

## Not counted

- e3000000-0000-0000-0000-000000000003, tier-declared: the grader could not grade it (commit 0123456789 is not in /work/made-up)
- e3000000-0000-0000-0000-000000000003, outcome-filled: not labelled yet
- e4000000-0000-0000-0000-000000000004: stale label, made from a transcript of 2 lines (sha256 64ed8c4aae); it now has 5 lines (sha256 08efb73ff2)
- e5000000-0000-0000-0000-000000000005: no label file
- e6000000-0000-0000-0000-000000000006: labelled, but its transcript is not here
- e7000000-0000-0000-0000-000000000007: labelled, but not graded; run transcripts grade
- e8000000-0000-0000-0000-000000000008: not labelled yet
