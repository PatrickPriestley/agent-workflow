# The change record

One file per change at `docs/changes/<YYYY-MM-DD>-<slug>.md`, created on the feature branch
before code, finished when the last PR merges. Copy the template below (also at
`${CLAUDE_PLUGIN_ROOT}/templates/docs-changes/TEMPLATE.md`); a repository may keep its own
copy at `docs/changes/TEMPLATE.md`. Sections are added when the tier calls for them; nothing
is filled in to satisfy the template. Keep the headings exactly as written: a reviewer scans
for them, and `record-check`, where a repository runs it, verifies the frontmatter and them.

```markdown
---
id: 2026-11-07-page-up          # equals the file name without .md
tier: 1                         # 0 trivial, 1 routine, 2 agreed
status: open                    # open -> approved (tier 2) -> done | abandoned
requester: <name, or the issue link>
approvers: []                   # tier 2: who agreed, and when
plugin: plugins/change-record   # optional, for dispatch: the plugin each task's agent loads
tasks:                          # optional, for dispatch: one entry per numbered item in Tasks
  - name: first-task            #   branch defaults to <id>/<name>
  - name: second-task
    after: first-task           #   runs once first-task is done on the base branch
---
# <title: the outcome, in one sentence>

## Goal
What will be true afterwards, in the requester's words. One paragraph.

## Probed facts
Each fact labelled: verified against the real system, exact source, mock only, assumed.
Version and date on anything about another system.

## Decisions
One per bullet: the decision, the alternative rejected, why.

## Tasks
Numbered. Each names the files, the test and why that test fails today. One PR per task
when the total passes the size limit.

## Checks
How this will be shown to work: the test command, the real-use commands (main path and one
error path), what a reviewer should attack.

## Outcome
Filled at the end: what shipped, what did not, open findings, the real-use output.
```

Tier 2 adds these three sections before Decisions, and Review after Checks:

```markdown
## Problem
The evidence that this is a problem: incident, measurement, complaint. No solutions here.

## Requirements
R1, R2, ... Each testable in three lines or fewer.

## Options and concerns
The candidate designs with trade-offs and the recommended one. Each concern as
"C<n>: <conflict>. Owner: <who>. Resolved: <decision, by whom, when>".

## Review
The "Reviewed by:" line that record-review printed. Then each critical or important finding
of that reader, with what was done about it; minor ones as open items.
```

## What goes where

- **Goal** is the requester's outcome, not the implementation. If you cannot state it in a
  sentence, the request is ambiguous: ask.
- **Probed facts** hold what you tried and saw, with the label. "The docs say" is `exact
  source` at best, and only if you read the receiver's own validation code.
- **Decisions** are what a reader six months on needs: why this way, what else was
  considered. One line each is fine.
- **Tasks** are the plan the build follows. Each has the test that proves it and why that
  test fails today, which `red-check` confirms where it runs.
- **Checks** is the contract with the reviewer: what should be attacked, what commands show
  the change working.
- **Review**, at tier 2, is what a reader with no context found in the record before it
  went for approval (`tier-2.md`), and what became of each finding.
- **Outcome** is written at the end and is the only prose evidence the process keeps. Paste
  real output, main path and one error path, from the final code.
- **plugin and tasks** in the frontmatter are read by `${CLAUDE_PLUGIN_ROOT}/bin/dispatch`,
  which hands each task to a fresh agent session in its own worktree with that plugin loaded,
  in order, each behind its `after` gate. The tasks map by position to the numbered items
  under Tasks; leave both keys out when the tasks will be built by hand.

## Commits

The record is committed with `docs(change): <id>` on the feature branch, and updated in the
same commits as the work it describes when a decision changes. Tier 2 approval is its own PR
containing only the record.
