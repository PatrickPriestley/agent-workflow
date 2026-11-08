# One record, three tiers: a redesign of the agent-workflow SDLC

Status: proposal. Written after a review of agent-workflow at commit 3bc8803.

## The problem this solves

agent-workflow today has two loops that share rules but not artifacts. `feature-loop`
produces a design note; `intent`, `spec` and `plan` produce three documents with their
own frontmatter, numbering and approval trailers. The trigger for the heavy loop is file
count, not risk, so a two-file rename gets the same seven steps as a new external
integration. Most of the evidence the rules ask for (red first, mutation results, the
reviewer used, hands-on output) is a sentence the agent writes in a PR body, which the
repo's own `incident-to-eval` skill says is the wrong thing to assert on. And the one
hard gate that exists locally (`commit-gate`) is skipped by GitHub's squash merge.

The redesign keeps what has earned its place (evidence labels, the design note, probe
before assert, cross-model review, incident to eval, hooks over prose) and changes four
things:

1. **One artifact per change** that grows as the change needs it, instead of a note for
   small work and three documents for large.
2. **Tier by risk**, decided by a short checklist, not by how many files change.
3. **Evidence as artifacts CI can check**, not as prose in a description.
4. **Rules short enough to hold**: a 15-line rules file and one skill that loads
   references on demand.

## The change record

Every change above trivial has one markdown file, `docs/changes/<id>.md`, where `<id>` is
`YYYY-MM-DD-<slug>`. It is created by the agent at the start, committed on the feature
branch, and finished when the PR merges. It replaces the design note, intent, spec and
plan. Sections are added when the tier calls for them; nothing is filled in to satisfy a
template.

```markdown
---
id: 2026-11-07-page-up
tier: 1                # 0 trivial, 1 routine, 2 agreed
status: open           # open -> approved (tier 2 only) -> done | abandoned
requester: <name or ticket link>
approvers: []          # tier 2: who agreed, and when
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
How this will be shown to work: the test command, the real-use commands (main path and
one error path), what the independent reviewer should attack.

## Outcome
Filled at the end: what shipped, what did not, open findings, the real-use output.
```

Tier 2 adds three sections before Decisions:

```markdown
## Problem
The evidence that this is a problem: incident, measurement, complaint. No solutions here.

## Requirements
R1, R2, ... Each testable in three lines or fewer.

## Options and concerns
The candidate designs with trade-offs and the recommended one. Each concern as
"C<n>: <conflict>. Owner: <who>. Resolved: <decision, by whom, when>".
```

This maps onto the documents it replaces, and it is worth being plain about that:
Problem and Requirements are the PRD, Probed facts and Decisions are the SDD, Tasks are
the ticket breakdown. The difference is that they are one file, next to the code, written
mostly by the agent from evidence it gathered, read by the agent that builds, and only as
long as the tier requires.

## Tiers

The agent proposes the tier from this checklist at the start and records it. The owner
can override in either direction. The agent must raise the tier mid-work when a later
answer flips.

| Question | If yes |
|---|---|
| Does it change behaviour anyone can observe? | at least tier 1 |
| Can it be undone with `git revert` alone (no data migration, no external state, no published API)? | if no, tier 2 |
| Does another team, system or external consumer depend on what changes? | tier 2 |
| Does it touch auth, money, personal data, or infrastructure? | tier 2 |
| Does anyone other than the requester need to agree before it is built? | tier 2 |
| Will it take more than one PR? | tier 2 |

Tier 0 is a change with no behaviour change, whatever the file count: typos, comments,
formatting, a rename a compiler or test suite fully checks. No record. Commit hooks only.

Tier 1 is the default for feature work: the requester owns the decision, it fits in one
PR, it reverts cleanly. The agent writes the record, builds, and opens the PR. No human
gate before code. The human reads the PR with the record beside it.

Tier 2 has exactly one human gate: the record is approved before code. Approval is a PR
that adds the record to main with `status: approved` and the approvers named. Then each
task runs as tier 1, with the PR body carrying `Change: docs/changes/<id>.md`.

What this drops from the current formal path: the separate intent, spec and plan files
and branches; `Accepted-by` merge trailers; `generated_by` hashes; one-question-at-a-time
interviews. Replace the interview with: draft the record from what is known, mark each
unknown, and ask all questions in one message with a recommendation on each.

## The loop

The same loop runs at tier 1 and for each task of tier 2. Six steps.

1. **Record.** Create or update the change record. Probe anything the change depends on
   and label it. For a new call to another system, send the real request to the real
   version first; until that passes, the work is a prototype and the record says so. If a
   probe shows the request impossible, stop and report; never substitute.
2. **Size.** If the tasks add more than the aim (400 reviewable lines), plan one PR per
   task. `pr-size` is the measure.
3. **Red, then green.** Per task: write the test, see it fail on the missing behaviour,
   commit the test, make it pass, commit. CI checks this (below), so the agent does not
   have to attest to it.
4. **Guards.** Where a mutation tool exists for the language, run it on the changed files
   and fix every survivor or justify it in the record. Where none exists, break each new
   guard by hand, see a test fail, restore it.
5. **Use it.** Run the real thing as its user would, main path and one error path. Paste
   the commands and output into the record's Outcome section.
6. **Push.** Open the PR with the record linked. Independent review runs in CI. Treat each
   finding as a claim: probe it, fix verified ones test first, dismiss with evidence.
   Re-push until no critical or important finding remains.

Stop and wait for a human only when: a probe shows the request impossible; two readings
of the request lead to different work; the tier needs raising; the next action merges,
releases or deletes; another tool shows a trust or login prompt; a check needs hardware
or access only a person has.

## Evidence CI can check

The principle: anything a rule asks for should be a check run, a committed file or a git
fact, never a sentence. The current repo checks for the string "Reviewed by:" in a PR
body; the agent writes that string. These replace it.

| Rule | Today | Proposed check |
|---|---|---|
| Record exists | none | `record-check`: PR body names `docs/changes/<id>.md`, the file exists in the PR, frontmatter parses, tier is set. Tier 2: the record is on main with `status: approved` before the code PR can merge. |
| Red before green | agent says so | `red-check`: for each test file the PR adds or changes, check out the base commit, apply only the test changes, run those tests. They must fail. A PR whose new tests pass on the base has tests that prove nothing. |
| Mutation | agent says so | Where a tool exists: run it on changed files, post survivors as a check. Otherwise the record's Checks section lists the guards broken by hand. |
| Independent review | pre-push, locally, string in PR body | `review-check`: CI runs a model of a different family from the team's authoring agents over the diff and the record, posts findings as a review, and the check fails on a critical finding until the author replies with evidence. The local `agent-review` stays for authors who want findings before pushing. |
| Size | warning | Keep as a warning. A PR over the stop limit needs one line in the record saying why it cannot split. |
| Conventional commits | local hook plus title check | Keep. Set the repository's squash-merge message to "pull request title", so the hook's rule is what lands on main. |
| No AI attribution | local hook, defeated by squash | Either drop the rule or enforce it where it leaks: the squash setting above, plus `commit-gate` on the merge commit via a CI check on the PR body. A rule that is visibly broken on main costs every other rule credibility. |
| Real use | prose in PR body | Prose in the record's Outcome section. Where the repo has a smoke script, CI runs it. This stays the one soft check, and it is marked as such. |

`red-check` is the important new piece. It is language-agnostic (it needs only "run these
test files" per repo, declared once in the repo's agent instructions), deterministic, and
it removes the one attestation agents most often fake.

## Rules file and skill

The rules file every agent loads at session start:

```markdown
# Working rules
1. Every change has a tier (docs/changes/README.md). Trivial changes need no record;
   everything else gets a change record before code, and tier 2 gets it approved first.
2. Probe before you assert. Label every claim about another system by its evidence:
   verified, exact source, mock only, assumed. Until a real call succeeds, it is a prototype.
3. Red before green. CI checks that new tests fail on the base commit.
4. Guards get mutation-checked, by tool where one exists.
5. Use what you built as its user would, main path and one error path, and paste the output.
6. An independent review runs on every PR. Findings are claims: probe, then fix or dismiss with evidence.
7. Ask before merging to main, releasing or deleting. Pushing and opening a PR need no approval.
8. Commits are Conventional Commits.
```

One skill, `change`, about 300 words: when it applies (any change above trivial), the
tier checklist, the six steps, when to stop, and links to reference files it loads only
when needed: `references/record-template.md`, `references/probing.md` (the real-contract
gate and evidence labels), `references/splitting.md`, `references/review-findings.md`,
`references/tier-2.md` (Problem, Requirements, Options, approval). The rationalization
table moves to `references/rationalizations.md`. The agent reads it when it notices it is
about to skip a step, not on every change.

`agent-review`, `commit-gate` and `pr-size` stay as commands. The plugin ships them or
says plainly that it is incomplete without the installer.

## Humans

Tier 0: nobody reads it before merge beyond the normal PR glance.

Tier 1: one human reads the PR with the record open. They read Goal, Decisions and
Outcome, spot-check the diff, and look at the review check. They do not re-review line by
line; the independent reviewer did that, and the record says what to spot-check.

Tier 2: the approvers read the record before code, in a PR on the record alone. That is
the one meeting-equivalent, and it is where competing options are argued. After approval,
each task PR is tier 1.

## Tracking

Issues (GitHub, Jira, whatever the team has) are an inbox: a place to say "this is wanted"
and to see what is open. The change record is the source of truth for anything in
progress, and the PR is the unit of work. The record's frontmatter `requester` field holds
the issue link, so a tracker can be queried from git, not the other way around. Do not try
to kill the tracker; demote it.

## Incident to eval

Keep the skill. Unify the eval layout with the plugin's own `evals/` so one runner and
one format exist. Each incident adds a case that replays the decision point, with a check
that asserts on behaviour. Run the suite whenever the rules file, the skill or the hooks
change, and publish the pass rates in the repo. The plugin's own adoption claim should be
a number from these runs.

## What is deliberately not here

- Separate intent, spec and plan documents. Tier 2 sections of one record cover them.
- One-question interviews. Draft, mark unknowns, ask once.
- The green-phase marker and its hooks. `red-check` in CI covers the same risk without
  per-step markers a person has to clear by hand.
- A file-count trigger. Behaviour and risk decide.
- "Never a local model" as a rule. It becomes a configuration of `review-check`: the team
  names the reviewer family, and local models are not in the list.

## Rollout

1. Set squash-merge messages to "pull request title" and turn on `commit-gate`. One
   afternoon, closes the visible gap.
2. Add `docs/changes/README.md` with the tier checklist and the template. Start writing
   records for tier 1 work with the current `feature-loop`; nothing else changes yet.
3. Build `red-check` and `record-check` as CI jobs. Both are small shell plus one
   per-repo line saying how to run named test files.
4. Move the independent review into CI as `review-check`, keep `agent-review` local.
5. Rewrite the skill as `change` with references. Run the evals with and without, record
   the numbers, and only then ask the team to adopt the skill.
6. Retire `intent`, `spec` and `plan` once two tier 2 changes have gone through the
   single record and the approvers say it was enough.

## Measures

Three numbers, kept in the repo, so the process is judged by evidence: lead time from
record created to merged; reverts and hotfixes per merged PR; and the share of
independent-review findings the author confirmed rather than dismissed. If the third
falls below a third for a reviewer, change the reviewer.
