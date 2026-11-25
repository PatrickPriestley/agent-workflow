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
2. **Answer key**: sealed with a `PROBE_KEY` secret (`bin/probe-key seal`) and kept as the
   planter run's `probe-key` artifact; its SHA-256 goes on the planted commit as a
   `provenance` status before the PR exists, so the key cannot change after the loops have
   run. Only the planter's `open-probe` job (after threat detection) and the scorer have
   `PROBE_KEY`; a test checks no agent can.
3. **Running the loops**: the planter's `open-probe` job checks the agent's hand-over
   (`bin/probe-open`), pushes an ordinarily named branch and opens the PR with the owner's
   `PROBE_TOKEN`, so CI and the label-started agents run on it as on any PR, and adds
   `hold`, `verify` and `properties`. gh-aw gives every agent read-only GitHub tools that
   show labels and statuses, so no label, status or branch name says probe;
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
- A `hold` label and a required check (`probe-guard.yml`, "not on hold") that fails while it
  is present; the scorer closes probe PRs, and a weekly sweep closes any left.
- One probe a week; replays only on misses; gh-aw's daily token guardrail.
- A quarter of probes held out from proposals; the regression set replayed monthly; one
  clean PR a month, with no bug, to measure false alarms.

## Store
The ledger, the everyday feedback and the review agents' own sessions go in the transcript
store the change-record plugin already uses (`plugins/change-record/store/schema.sql`,
Supabase), under its rules: senders hold only the publishable key and may INSERT and
nothing else; reading needs the secret key; no row is ever updated, so a correction is a new
row; everything sent is redacted first.

- `probe_runs`: one row per probe (id, pull request, kind, loud, planted commit, the
  planter's run, cost, opened and scored times).
- `probe_verdicts`: one row per loop per probe (verdict, evidence, scorer version), inserted
  by `probe-score`.
- `feedback`: one row per signal on a real pull request (loop, finding or comment, acted on,
  dismissed, a reaction or a `wrong:` reply and its reason, who gave it), inserted by a
  scheduled job that uses no model.
- The review agents' sessions: gh-aw keeps each agent run's Claude output (stream-json,
  `agent-stdio.log`) and prompt in its `agent` artifact. `.github/workflows/agent-sessions.yml`
  (built ahead of Phase 3), for each Claude agent, turns them into a transcript with `bin/agent-session-collect` and
  pushes it through the existing redaction into `chunks` and `sessions`, as source `agent`,
  session `gh-aw-<workflow>-<run>-<attempt>`, so `transcripts grade` and `judge` can read what
  an agent did when it missed, and the improver can see why. The planter is left out: its
  session holds the answer key. The scorer's judge reuses `judge_votes` and its three-vote rule.
- Weekly report and catch-rate views read with the secret key; no agent ever has it.

The publishable key and the store's URL are repository secrets given only to the jobs that
insert (`probe-score`, the feedback job, the collector); `bin/agent-allowlists.test.sh`
refuses them in any agent workflow, as it does `PROBE_KEY`.

## Phases
1. `bin/probe-key`, `bin/probe-score` and their tests, with #37 and #45 as known answers;
   then an evidence collector and the planter and scorer workflows, run by hand.
   Then `probe_runs` and `probe_verdicts` in the store, inserted by `probe-score`.
2. Weekly schedule and a report issue with the measures above, read from the store. The
   `feedback` table and its job start recording everyday feedback: the outcomes on each
   merged pull request and the owner's reactions and `wrong:` replies. No model calls.
3. The review agents' sessions collected into the store; the improver and the replay gate,
   with the regression set, fed by probe misses (with the missing agent's session) and
   everyday feedback.
4. Misses and confirmed wrong outputs filed as labelled failures in the transcript loop, so
   skill edits can come from them too; the scheduled grading job the README lists as not
   built.
Separately, once: rewrite the agent prompts as principles with reasons, keeping every hard
limit, each change checked by the replay like any other.

## Decisions
- Ledger in the transcript store, not the repository: the scorer's token cannot push to
  the default branch, and a row per pull request would be noise. The sealed key stays a run
  artifact.
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
