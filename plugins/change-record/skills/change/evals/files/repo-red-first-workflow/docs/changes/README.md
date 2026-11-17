# Change records

One file per change, `YYYY-MM-DD-<slug>.md`, from `TEMPLATE.md`. It is created on the feature
branch before code and finished when the last PR for it merges. Every PR names its record in
the body (`Change: docs/changes/<id>.md`) or declares `Tier: 0`; a reviewer checks that, and a
repository may run `record-check` in CI to enforce it.

## Tier

| Question | If yes |
|---|---|
| Does it change behaviour anyone can observe? | at least tier 1 |
| Can it be undone with `git revert` alone? | if no, tier 2 |
| Does another team, system or external consumer depend on what changes? | tier 2 |
| Does it touch authentication, money, personal data or infrastructure? | tier 2 |
| Does anyone other than the requester need to agree before it is built? | tier 2 |
| Will it take more than one pull request? | tier 2 |

- **Tier 0:** no behaviour change. No record; the PR body says `Tier: 0`.
- **Tier 1:** the requester decides, one PR, reverts cleanly. Record, build, PR. No gate
  before code.
- **Tier 2:** the record (with Problem, Requirements, Options and concerns) is approved in a
  PR of its own before any code. Each code PR then names it.

## Status

`open` while being written or built; `approved` once the tier 2 approval PR merges; `done`
when the last PR merges and Outcome is filled; `abandoned` with a line in Outcome saying why.
