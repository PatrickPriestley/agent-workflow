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

## Review before approval

The author of a record knows what it leaves out, and so does not see it. Before the approval
PR, have the record read by a fresh session that has only the record and the repository:

    ${CLAUDE_PLUGIN_ROOT}/bin/record-review docs/changes/<id>.md

It starts a headless session with tools that only read, gives it the record, and prints
what that reader could not understand, facts without evidence or that the repository
contradicts, requirements no test could check, decisions with no rejected alternative, tasks
with no test, concerns with no owner, and a tier the record's content contradicts.

- Each finding is a claim (`review-findings.md`): check it against the record and the
  repository, then fix the record or dismiss the finding with your evidence. Fix what the
  reader could not understand by writing it into the record, not by explaining it to
  yourself.
- Run it again after fixes that change what the record decides. At most two rounds.
- Add a `## Review` section to the record, after Checks: the `Reviewed by:` line the tool
  printed, and each critical or important finding in a line with what was done about it.
  Minor findings go there as open items.
- A review that did not finish (no end marker, a timeout) is not a review. Never give the
  record to a session that has seen this conversation and call that a review. Where no
  fresh session can be started, write that in the section and claim no review; the
  approvers then know they are the first readers.

## Approval

1. Open a PR containing only the record, with `status: approved`, `approvers` filled in as
   the people who will approve, and the Options and concerns each `Resolved`. This is the
   approval PR; where a repository runs `record-check`, it requires that status.
2. The approvers review the record in that PR. A concern with no `Resolved` line, a
   requirement nobody can test, or a missing `## Review` section is a reason to request
   changes.
3. Merging the PR is the approval. The merge records that the decision preceded the code.
4. Solo, you are every approver; still open the PR and name yourself, so the history shows
   the record came first.

## Building

Branch from the updated default branch. Each task from the record runs as tier 1 (the loop
in the skill), one PR per task, each PR body carrying `Change: docs/changes/<id>.md`. To
have each task built by a fresh agent session that sees the record and not this conversation,
list the tasks in the record's frontmatter (`plugin:`, `tasks:` with `name`, `branch`,
`after`; see the template) before approval, then run `${CLAUDE_PLUGIN_ROOT}/bin/dispatch
docs/changes/<id>.md` after the approval PR merges: it refuses a record that is not approved
on the base branch, cuts a worktree per task, runs the agent with the plugin loaded, checks
the result with `record-check` and `red-check`, and pushes the branch for the PR. Run it again
after each PR merges to start the next task.
The reviewer refuses a code PR whose record is not yet approved on the base commit, and so
does `record-check` where a repository runs it. When the
build departs from the record, update Decisions in the same commit as the departing code;
never diverge silently. The last PR sets `status: done` and fills Outcome.
