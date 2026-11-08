# Tiers

The agent proposes the tier from this checklist at the start of a change and writes it into
the record's frontmatter. The owner can override in either direction. Raise the tier the
moment a later answer flips; never lower it silently.

| Question | If yes |
|---|---|
| Does it change behaviour anyone can observe (output, API, data, timing)? | at least tier 1 |
| Can it be undone with `git revert` alone (no data migration, no external state, no published API)? | if no, tier 2 |
| Does another team, system or external consumer depend on what changes? | tier 2 |
| Does it touch authentication, money, personal data or infrastructure? | tier 2 |
| Does anyone other than the requester need to agree before it is built? | tier 2 |
| Will it take more than one pull request? | tier 2 |

## Tier 0: trivial

No behaviour change, whatever the file count: a typo, a comment, formatting, a rename that a
compiler or the existing suite checks completely. No record. Commit hooks only. The PR body
says `Tier: 0`, so the reviewer sees the claim (and `record-check` passes, where a repository
runs it).

## Tier 1: routine

The default for feature work. The requester owns the decision, it fits in one PR, it reverts
cleanly. The agent writes the record, builds, and opens the PR. No human gate before code.
The human reads the PR with the record beside it: Goal, Decisions, Outcome, the review
check, and a spot-check of the diff.

## Tier 2: agreed

Exactly one human gate: the record is approved before code. The approval is a PR that adds
the record to the default branch with `status: approved` and the approvers named. Then each
task runs as tier 1, and each PR body carries `Change: docs/changes/<id>.md`. The convention
is that no code PR for a tier 2 record opens until its approval PR has merged, and that a
change of tier is its own record-only PR; the reviewer holds that convention, and where a
repository runs `record-check` in CI, it refuses a code PR whose record is not already at
tier 2 and approved on the base, or that lowers a tier the base recorded.

## Escalation mid-work

Triggers: scope grows beyond the request; a probe shows a dependency on another system or
team; the change turns out not to revert cleanly; two readings of the request lead to
different work. Stop, record the new tier and why, and ask the owner.
