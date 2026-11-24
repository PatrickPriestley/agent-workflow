# Probe loop: attack the review loops, score what they miss, keep only fixes that help

## Problem
The review loops (tests, red-check, mutation, properties, Open Code Review, CI diagnosis,
CI fix, Verify PR claims, Property Scout) were each checked once, by hand, with a planted
bug: #37 (loud: a test fails) and #45 (silent: tests stay green). Both probes found bugs in
the loops themselves (#46, #51). Nothing repeats that, nothing records the results, and a
miss never turns into a tested change to the loop that missed.

## Loop
    plant -> run the loops -> score ------------------+
    every pull request -> the owner's feedback -------+-> ledger + weekly report
                                                      +-> improver -> one small edit -> replay with vs without -> a person merges
    past probes become a regression set for every proposed edit

Two signal sources feed one improver: probes (planted bugs, scored against a sealed key)
and everyday feedback (what the owner does with each agent's output on real pull
requests). Probes are rare and artificial but measurable; everyday feedback is plentiful
but noisy. An edit is kept only when the replay measures it.

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
   not run, no data, or judge (for a model to decide, then a person). Fixed rules
   first; a Claude judge only for what they leave open, checked against the owner's
   rulings before it is trusted. One ledger row per loop.
5. **Everyday feedback**: kept where the work happens, with no extra step. For each merged
   pull request, without a model: which Open Code Review findings were acted on (a later
   commit touched the lines, or the thread was resolved with a fix) and which were
   dismissed; whether each property Property Scout pushed held, or needed fixing (#50);
   claims-check verdicts later shown wrong. And the owner's own marks on an agent's
   comment: a thumbs-up or thumbs-down reaction, or a reply starting `wrong:` with the
   reason. Only the owner's feedback counts (others' is recorded, not used), and it is
   assumed to be wrong sometimes: the improver reads the agent's output, the reply and
   the code before acting on it.
6. **Improver** (one, shared by every loop): reads the ledger's misses and the owner's
   feedback, and drafts the smallest edit that captures one signal, to whichever loop it
   concerns: Open Code Review's `.opencodereview/rule.json`, a gh-aw prompt (verify,
   property-scout, ci-fix, ci-diagnose), a property or a test. Each draft is replayed three
   times with and without it, on the probe or pull request it came from, and on the
   regression set; it becomes a pull request only if it does better there and raises no new
   false alarm. The pull request says which signals prompted it and what the replay
   showed. A person merges. One improver with a small layer per loop, not one per loop.

## Writing the loops' prompts
Principles with their reasons, not lists of rules: an agent that knows why it re-runs a
property before pushing generalises; one told only to do it does not (#50). The hard
limits stay as they are and stay enforced outside the prompt (allowlists, `allowed-files`,
threat-detection guards). Edits from the improver follow the same style: one principle
and its reason, not a special case for the one bug that prompted it.

## Measures
Per loop and per bug kind: catch rate on probes, false-alarm rate on clean probes, findings
acted on versus dismissed on real pull requests. For the whole system, numbers already
watched: time from opening to merge, cost per run (gh-aw reports it), and how many
improver edits were kept or dropped. All of them go in the weekly report.

## Safeguards
- A `probe` label and a required check that fails while it is present; the scorer closes
  probe PRs, and a weekly sweep closes any left.
- One probe a week; replays only on misses; gh-aw's daily token guardrail.
- A quarter of probes held out from proposals; the regression set replayed monthly; one
  clean PR a month, with no bug, to measure false alarms.

## Phases
1. `bin/probe-key`, `bin/probe-score` and their tests, with #37 and #45 as known answers;
   then an evidence collector and the planter and scorer workflows, run by hand.
2. Weekly schedule and a report issue with the measures above. The ledger also starts
   recording everyday feedback: the outcomes on each merged pull request and the owner's
   reactions and `wrong:` replies. No model calls.
3. The improver and the replay gate, with the regression set, fed by probe misses and
   everyday feedback.
4. Misses and confirmed wrong outputs filed as labelled failures in the transcript loop, so
   skill edits can come from them too; the scheduled grading job the README lists as not
   built.
Separately, once: rewrite the agent prompts as principles with reasons, keeping every hard
limit, each change checked by the replay like any other.

## Decisions
- Ledger in the repository (`docs/probes/ledger.jsonl`), so results are reviewed like any
  change; the sealed key as a run artifact.
- Targets: agent-workflow first; meal-plan once its Actions budget allows, with its data
  rules in the planter.
- A person merges every proposed edit.
- Only the owner's feedback is used.

## Borrowed
From Warp's account of its self-improving agents (claude.com, "How Warp builds
self-improving agents on Claude"): feedback captured where the work happens, a scheduled
improver that opens small edits for review, one shared improver, principles over rules,
filtering whose feedback counts, and tracking whole-system numbers. Where this plan
differs: every edit must win a measured replay before it is proposed (the article
describes human review only, and no regression set), and probes supply failures that
everyday feedback would never surface.
