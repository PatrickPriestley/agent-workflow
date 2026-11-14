---
id: 2026-11-14-record-review
tier: 1
status: done
requester: Patrick Priestley, in chat on 2026-11-14 ("Add the zero-context review for tier 2", to "What I would borrow: a zero-context review of the record before code, for tier 2 changes")
approvers: []
---
# A tier 2 record is read by a session with no context before it goes for approval

## Goal

Before a tier 2 record goes to its approvers, a fresh session that has only the record and
the repository reads it and says what is missing, unproven or unclear. The author knows too
much to see what the record leaves out; a reader who knows nothing sees it at once.

## Probed facts

- Exact source (`plugins/change-record/skills/change/references/tier-2.md` on `main` at
  `bf3901e`): a tier 2 record is drafted, questions are asked in one message, and the
  approval PR is opened. Nobody but the author and the approvers reads it before code. The
  independent review of `references/review-findings.md` runs on the code PR, after the code.
- Exact source (record `2026-11-12-session-quality`, Outcome): blind labellers, each a
  fresh session with a transcript and no conversation, found eleven defects in work that had
  passed the process. That is the evidence here that a reader with no context finds things.
- Verified against the real system (Claude Code 2.1.325 in this container, 2026-11-14):
  `claude -p --tools Read Grep Glob --output-format json`, given a prompt on standard input
  from the repository's root, read a change record and summarised it correctly in 18
  seconds for 0.17 dollars; asked to create a file, it answered that it has no tool to
  write with, and no file was made. Its JSON has `result`, `is_error`, `total_cost_usd` and
  `modelUsage`, whose key names the model.
- Exact source (`plugins/change-record/bin/dispatch`): the plugin already starts fresh
  sessions, with `claude -p` by default or `--agent CMD`, the brief on standard input, and
  `AGENT_TRANSCRIPTS_PARENT` set to the calling session so the capture ties the two.
- Exact source (`bin/agent-review` of the other plugin): `agent-review plan FILE` reviews a
  plan with another model family and refuses a reviewer of the caller's own kind. It needs
  a second provider's account; none has worked since 2026-11-11.
- Assumed (search summaries of pages this session cannot open): Google's Elephant-Goldfish
  model has a long-context session draft a design and fresh sessions with no memory of the
  conversation review it before code, and says the review must stop if no fresh context can
  be had.

## Decisions

- A new tool in this plugin, `bin/record-review RECORD`, and not a change to
  `agent-review`. The two reviews differ in what makes them independent: `agent-review` is
  another model family, this one is no context. Rejected: letting `agent-review` take a
  reviewer of the caller's own kind, which weakens the rule that tool exists for.
- The reviewer gets a brief on standard input: fixed instructions and the record's text.
  It runs from the repository's root and may read the repository. It gets no tool that
  writes or runs a command: by default `claude -p --tools Read Grep Glob --output-format
  json`, or `--agent CMD`.
- The brief asks for findings by severity in seven kinds: what a reader cannot understand
  without the conversation, facts with no evidence or that the repository contradicts,
  requirements no test could check, decisions with no rejected alternative, tasks with no
  test or one that passes today, concerns with no owner or failure case, and a tier the
  record's own content contradicts. It asks for no rewrite and no code.
- The review counts only if its last line is `<<RECORD-REVIEW-END>>`, as `agent-review`
  does it: exit 0 complete, 2 usage, 3 no end marker, 4 the reviewer failed or ran out of
  time, 5 the reviewer changed the working tree.
- An `--agent` command that continues or resumes a session is refused: that is not a fresh
  context. Rejected: trusting the caller, since a resumed session is the one way to get this
  wrong without noticing.
- One reviewer, one run. Rejected: several reviewers at once, until one has been seen to
  miss what another finds.
- The skill asks for it at tier 2 only, between drafting and the approval PR. Findings are
  claims, handled as `references/review-findings.md` says, in at most two rounds. The record
  gets a `## Review` section: who reviewed, and each finding with what was done. Where no
  fresh session can be had, the record says so and claims no review.
- `record-check` does not ask for the section. Rejected for now: a check that a section is
  there shows only that it was written; whether to check more is for after the review has
  been used on real records.
- Concern C5 of record `2026-11-12-session-quality` says an edit proposed from transcripts
  enters the skill only when the eval suite shows it helps. This edit is the owner's request
  and not such a proposal, and it has no eval case: a case would have to start a session
  from inside an isolated eval session. That is said under Not done, for the owner to rule.

## Tasks

1. `plugins/change-record/bin/record-review`. Test: `bin/record-review.test.sh`, with a
   stand-in agent: the brief, the default command, a complete review, no end marker, a
   failed and a slow reviewer, a reviewer that changes the tree, a resumed session. The
   tool does not exist, so the first assertion fails on a missing command; the suite is
   therefore run red against a stub that prints nothing and exits 0.
2. The skill: `references/tier-2.md`, the record template, one clause in `SKILL.md`, the
   plugin README, and the new suite in `.github/workflows/test.yml`.

## Checks

`bash plugins/change-record/bin/record-review.test.sh` and the other change-record suites.
Real use: the tool on a tier 2 record of this repository, with a real fresh session, and
what it found. Error path: a reviewer that does not finish. The reviewer should attack: a
reviewer that is not fresh, and a review that reads as complete and is not.

## Outcome

Shipped: `plugins/change-record/bin/record-review` and its suite of 81 assertions; the
review step in `references/tier-2.md`, the `## Review` section in the record template, one
clause in `SKILL.md`; the plugin README; the suite in `.github/workflows/test.yml` and in
the list of suites `record-check.test.sh` starts with no temporary folder (117 assertions,
from 113). `dispatch` 218, `red-check` 107 and the eval cases (40) pass unchanged.
`agent-review` is not touched.

Red first: with no tool, 65 of the first 75 assertions failed; against a stub that prints
nothing and exits 0, which is the run that shows the assertions and not a missing command,
59 failed, among them

    FAIL no record, an unknown option and a second record are usage errors
         expected [2] got [0]
    FAIL the reviewer is given the record's whole text and its path, on standard input
    FAIL a reviewer that adds a file exits 5 and names it; the review is not printed

Sixteen passed against the stub: they assert that something is absent from the output.

Use, with a real fresh session, on `docs/changes/2026-11-08-outcome-evals.md`, a tier 2
record of 147 lines that is not yet approved:

    $ plugins/change-record/bin/record-review docs/changes/2026-11-08-outcome-evals.md --timeout 600
    Reviewed by: claude <model>, with no context but the record and the repository
    ...
    exit 0 in 299 s; 38 turns; 3.62 dollars; the working tree as it was

It reported 2 critical, 12 important and 13 minor findings. The two critical ones were
checked against the record and the repository, and hold:

- The record copies the eval runner's call with `--permission-mode acceptEdits` alone
  (its line 31). `bin/dispatch` says in its header that with that alone every test run and
  commit is denied. All fifty runs would have had an agent that cannot run a test.
- The hidden tests are to live under the plugin's folder, which is the folder the plugin
  arm is given with `--plugin-dir` and the other arm is not. That arm could read them.

Neither was seen by the author of that record or in the conversation that produced it. The
record itself is not changed here: its findings are the owner's to act on before approval.

Error path, the real reviewer with five seconds:

    $ plugins/change-record/bin/record-review docs/changes/2026-11-08-outcome-evals.md --timeout 5
    record-review: the reviewer (claude) did not finish in 5 s; nothing was reviewed
    exit 4 in 5 s

Guards: 22 broken by hand. 21 failed the suite. One survived, a parent session left in the
environment and passed on to the reviewer: it now has a test, which the broken guard fails.

A fault of the guard run itself, and what it changed. The first run broke the refusal of a
resumed session, and the test for it then started what the command named: the real
`claude` twice and the real `codex` once, in the suite's scratch repository, with the
brief of the made-up record. Nothing of this repository was touched; two short sessions
were made. The test now puts stand-ins for both agents first on `PATH`, so that a broken
refusal fails the test and starts nothing.

What the reviewer was asked to attack:

- A reviewer that is not fresh. The tool refuses `--continue`, `--resume` and `resume` in
  an `--agent` command, and `-c` and `-r` for `claude`. It cannot know that another
  agent's command resumes a session by some other word, or that a caller pasted the
  conversation into the record. The skill's text says never to call that a review.
- A review that reads as complete and is not. The end marker shows the reviewer finished
  its answer, not that it read the record well. The first real review named files and
  lines it had read, which is what a reader can check; a review with no such detail
  deserves a second run.

Not done:

- No eval case. The eval suite does not show that the step helps with the plugin and not
  without: a case would have to start a session from inside an isolated eval session. One
  real review found two critical faults; that is one record.
- `record-check` does not ask for the `## Review` section.
- The reviewer is the author's own model family. A second family's review of the code is
  still what `references/review-findings.md` asks for, and still has not run since
  2026-11-11.
- The cost. 3.62 dollars and five minutes for 147 lines; the largest record here is eight
  times as long. Nothing limits what the reviewer reads.
