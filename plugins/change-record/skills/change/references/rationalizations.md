# Rationalizations

Read this when you notice you are about to skip a step.

| Excuse | Reality |
|---|---|
| "It's small, I'll skip the test" | Tier 0 skips the record; nothing skips the red test for a behaviour change. A reviewer, or `red-check` where it runs, will see a test that passes on the base |
| "It's two files, that's a tier 2 amount of process" | Tier is risk, not file count. A two-file rename that the suite covers is tier 0 or 1 |
| "The tests pass, so it works" | Tests check what you specified. Run it as its user would, error path included |
| "The tests pass, so it's reviewed" | Tests check the guards that were written; review finds the missing ones |
| "The reviewer said so" | Probe it. A wrong fix applied on trust ships a bug |
| "The reviewer didn't answer, so it's clean" | An unfinished review is no review |
| "Mutation testing is overkill for this" | Six untested guards sat behind 32 green tests once. Every guard the change touches |
| "The feature is impossible, so I built the nearest thing" | That is scope change. Stop and report |
| "The fake server accepts it, the tests pass" | The fake accepts everything. Send the exact request to the real one |
| "The docs list that value as supported" | Docs and one parser are not the receiver. Its validator decides |
| "I should check this choice with the owner" | If both options lead to the same work, choose, record why, continue |
| "I'll write the record after, when I know what I did" | Then it is a changelog, not a record. The decisions and probes come first; the Outcome comes after |
| "It's one feature, so it's one pull request" | Split by task. A 1,300-line diff overflowed its reviewer and files went unreviewed |
| "The owner is busy, I'll approve the tier 2 record myself" | Then it was not tier 2, or the owner decides it is not. Ask |
