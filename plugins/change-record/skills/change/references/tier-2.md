# Tier 2: agreed before code

A tier 2 change needs someone other than the requester to agree, is hard to undo, crosses a
team or system boundary, touches auth, money, personal data or infrastructure, or takes more
than one PR. It has exactly one human gate: the record is approved on the default branch
before any code is built. Be plain about what this is: Problem and Requirements are a PRD,
Decisions and Probed facts are a design document. The difference is that they live in one
file next to the code and are only as long as the change needs.

## The extra sections

Added before Decisions, in this order:

- **Problem.** The evidence that this is a problem: an incident, a measurement, a complaint,
  failed runs, business impact, hard constraints (a batch window, a data volume, an SLA).
  No solutions here, so the record is not anchored to the first idea.
- **Requirements.** R1, R2, ... each a testable statement with an acceptance check a test
  could encode, three lines or fewer. Split one that needs more.
- **Options and concerns.** Each candidate design with its trade-offs, and the recommended
  one. Then every conflict with a policy, another requirement or the current code, each as
  `C<n>: <the conflict and its concrete failure case>. Owner: <who decides>. Resolved:
  <decision, by whom, when>`. Leave `Resolved` empty until the owner decides. Number from
  C1 with no gaps.

## Drafting

Draft the whole record from what you know and can probe. Mark every unknown. Then ask all
the questions in one message, each with your recommendation. Do not run a one-question-
at-a-time interview; people answer a list faster than a dialogue, and the record shows them
the context. Update the record from the answers.

## Approval

1. Open a PR containing only the record, with `status: approved`, `approvers` filled in as
   the people who will approve, and the Options and concerns each `Resolved`. This is the
   approval PR; where a repository runs `record-check`, it requires that status.
2. The approvers review the record in that PR. A concern with no `Resolved` line, or a
   requirement nobody can test, is a reason to request changes.
3. Merging the PR is the approval. The merge records that the decision preceded the code.
4. Solo, you are every approver; still open the PR and name yourself, so the history shows
   the record came first.

## Building

Branch from the updated default branch. Each task from the record runs as tier 1 (the loop
in the skill), one PR per task, each PR body carrying `Change: docs/changes/<id>.md`.
The reviewer refuses a code PR whose record is not yet approved on the base commit, and so
does `record-check` where a repository runs it. When the
build departs from the record, update Decisions in the same commit as the departing code;
never diverge silently. The last PR sets `status: done` and fills Outcome.
