---
name: intent
description: Capture a problem or idea as a version-controlled intent.md (AI-native SDLC Stage 1 Plan), in the originator's own words. Use when someone describes a problem, feature idea, ticket or anomaly and wants it recorded, or says "write an intent" or "capture this as intent".
---

Produce the intent file (path per Conventions) in the current repo. Intent is a proto-spec: what is
wanted, why, and under which constraints, in the originator's terms. It is not a design.

## Conventions (shared by the SDLC skills)

- **Where artifacts live** depends on the repo's local git config
  (`git config sdlc.artifacts`), which is never committed:
  - `repo` or unset: in the product repo. `<root>` is `docs/` when the repo has a
    `docs/` directory, otherwise the repo root. Artifacts live at
    `<root>intent/<change_id>.md`, `<root>specs/<change_id>.md` and
    `<root>plans/<change_id>.md`. Never create a top-level `intent/`, `specs/` or
    `plans/` in a repo that has `docs/`.
  - `external`: for repos that do not allow these files to be committed. Artifacts live
    in a shared store, a git repo at `git config sdlc.store` (default `~/.sdlc`), in a
    folder per product repo: `<root>` is `<store>/<key>/`, where `<key>` is
    `git config sdlc.key` or else the main repo's directory name (the parent of
    `git rev-parse --path-format=absolute --git-common-dir`, not the toplevel, which in
    a worktree is named after the branch). Nothing is written or committed in the
    product repo; `git status` there must be unchanged. Branches for drafts live in the
    store and are named `<stage>/<key>/<change_id>`. If the store is not a git repo,
    stop and ask the user to create it (`git init ~/.sdlc`).
- `change_id` is `NNNN-short-name`: the next free four-digit number among the
  `NNNN-*.md` files in `<root>intent/` (ignore files not named that way) plus a
  kebab-case name of three words or fewer. Fixed here; everything later keys on it.
- **Agent instructions file** means the repo's `AGENTS.md`, or failing that `CLAUDE.md` or
  `GEMINI.md`, whichever exists (read all that exist; they are often symlinks to one
  file). Add new content to `AGENTS.md`, creating it if none exists.
- **Accepting an artifact** means getting it onto the default branch of the repo that
  holds it: the product repo in `repo` mode, the store in `external` mode.
  - With a GitHub remote and `gh`: open a PR; merge is accept, close is reject.
  - Without a remote, when the artifact is on its own branch (spec, plan): the owner
    approves it on that branch, then merge it into the default branch with
    `git merge --no-ff` and an `Accepted-by: <name>` trailer in the merge commit.
    Delete the branch after.
  - Without a remote and no branch (intent): commit straight on the default branch with
    an `Accepted-by: <name>` trailer.
- **Committing an artifact:** stage only the artifact file by path, never `git add -A`
  or `.`; the working tree may hold unrelated uncommitted work. Switching branches or
  rebasing may autostash that work; afterwards confirm `git stash list` holds nothing of
  yours and the working tree is as before. Follow the user's own commit rules (e.g. an
  agent instructions file that forbids co-author or AI attribution lines) over any default
  trailer, whichever agent you are.

## Template

Use `<root>intent/TEMPLATE.md` if the repo has one; otherwise this:

```markdown
---
change_id: <change_id>
author: <originator>
created: <YYYY-MM-DD>
status: draft
tracker: <ticket id or null>
size: null             # small, only when the owner declares one behaviour (see Size)
---
# Intent: <title>

## Problem
## Proposed outcome
## Affected users and systems
## Constraints
## Open questions
```

## Size

A change is **small** when it asks for one behaviour and the owner expects it to touch at
most about 3 files and 50 lines. The owner declares it; you never infer it. A small change
skips the spec stage and goes straight to plan, where its single requirement is `R1`, this
intent's Proposed outcome, and the plan gate measures the files and planned lines and
offers the spec stage when they are exceeded (the owner can override). Record the
declaration as `size: small` in the frontmatter; otherwise leave `size: null`. Anything
else in that field is refused downstream.

## Interactive (a person is present)

Run this as an interview. Every message you send contains exactly one question and
nothing else: no lists of prompts, no preamble about what comes next. Wait for the
answer before asking the next question.

1. Open with one short question: what's the problem or idea? Let the originator
   answer in their own words.
2. Then ask one question at a time, in whatever order follows from what they said,
   until each of these is specific: What can't they do today? Who has the problem,
   and how do you know? What does "fixed" look like? Which users and systems are
   affected? What must not change? What is out of scope? Is there a deadline or
   tracker record? Skip any the answers have already covered. Follow up on vague
   answers before moving on.
   Always ask for evidence, even when the rest is covered: how do you know this is a
   problem (an incident, a failed run, a complaint, a measurement)? If there is none,
   record "no evidence given" in Problem rather than skipping it.
   Last, when the Proposed outcome reads as one behaviour, ask whether this is a small
   change that should skip the spec stage (Size above). Record `size: small` only on a yes.
3. Draft. Keep each section under 6 lines. Unknowns go in Open questions.
4. Show the draft; the originator corrects it. Repeat once.
5. Commit (below).

## Non-interactive (a monitor, scan or ticket trigger)

Draft from the evidence given. Problem states the anomaly and its evidence, Proposed
outcome states back-to-baseline, and every question you would have asked goes in Open
questions. `author` is the triggering identity. Commit; a human triages it.

## Commit

With a remote: `git fetch`, branch `intent/<change_id>` from the latest default
branch, commit `intent: <change_id>`, and open a PR. Without a remote: once the
originator has approved the draft, commit `intent: <change_id>` straight on the default
branch with the `Accepted-by:` trailer; no branch. Either way the product owner (which
may be you) is the one who accepts or rejects.

Do not propose solutions, estimate effort, or name technology unless it is a constraint.
