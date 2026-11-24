# Probe loop: attack the review loops, score what they miss, keep only fixes that help

## Problem
The review loops (tests, red-check, mutation, properties, Open Code Review, CI diagnosis,
CI fix, Verify PR claims, Property Scout) were each checked once, by hand, with a planted
bug: #37 (loud: a test fails) and #45 (silent: tests stay green). Both probes found bugs in
the loops themselves (#46, #51). Nothing repeats that, nothing records the results, and a
miss never turns into a tested change to the loop that missed.

## Loop
    plant -> run the loops -> score -> ledger + weekly report
                                         -> each miss -> propose a fix -> replay with vs without -> a person merges
    past probes become a regression set for every proposed fix

## Parts
1. **Planter** (gh-aw, weekly and by hand): one subtle bug of a rotating kind (dropped
   alternative, off-by-one at a limit, inverted guard, swallowed error, changed default,
   unescaped value) in a file that has tests, inside a plausible feature PR with one false
   claim. Loud and silent probes alternate. It writes an answer key: file, lines, kind,
   terms, counterexample, false claim.
2. **Answer key**: sealed with a `PROBE_KEY` secret that only the scorer job has
   (`bin/probe-key seal`), kept as a run artifact; the PR carries its SHA-256, so the key
   cannot change after the loops have run. No agent workflow may name `PROBE_KEY` (a test
   checks every workflow).
3. **Running the loops**: the planter opens the PR and adds `verify` and `properties`;
   Open Code Review and, for a loud probe, CI diagnosis start on their own; `ci-fix` is
   added after diagnosis.
4. **Scorer**: `bin/probe-score` turns the key and the PR's evidence (check conclusions,
   inline review comments, each agent's comment) into one verdict per loop: caught, missed,
   not run, no data, n/a, or judge (for a model to decide, then a person). Fixed rules
   first; a Claude judge only for what they leave open, checked against the owner's
   rulings before it is trusted. One ledger row per loop.
5. **Proposer and replay**: for a miss, one drafted change to that loop (a prompt line, an
   Open Code Review rule, a property, a test), replayed on the probe three times with and
   without, and kept only if it catches more and raises no new false alarm on the
   regression set. A person merges.

## Safeguards
- A `probe` label and a required check that fails while it is present; the scorer closes
  probe PRs, and a weekly sweep closes any left.
- One probe a week; replays only on misses; gh-aw's daily token guardrail.
- A quarter of probes held out from proposals; the regression set replayed monthly; one
  clean PR a month, with no bug, to measure false alarms.

## Phases
1. `bin/probe-key`, `bin/probe-score` and their tests, with #37 and #45 as known answers;
   then an evidence collector and the planter and scorer workflows, run by hand.
2. Weekly schedule and a report issue: catch rate per loop and per bug kind, cost, trend.
3. Proposer and replay, with the regression set.
4. Misses filed as labelled failures in the transcript loop, so skill edits can come from
   probes too; the scheduled grading job the README lists as not built.

## Decisions
- Ledger in the repository (`docs/probes/ledger.jsonl`), so results are reviewed like any
  change; the sealed key as a run artifact.
- Targets: agent-workflow first; meal-plan once its Actions budget allows, with its data
  rules in the planter.
- A person merges every proposed fix.
