# Evals for the change skill

Each case runs the same task with and without the plugin in an isolated session
(`claude plugin eval plugins/change-record --scaffold --allow-tools Bash Write Edit`), on a
tiny Python CLI whose repository has adopted change records (`_scaffold/greet.sh` copies the
plugin's `docs/changes/` templates in). The prompts name the record id to use, so the graders
can check the record file deterministically; the baseline arm sees the same prompt and the
same `docs/changes/README.md`, so what the plugin adds is measured, not whether the agent can
guess a file name.

| Case | What it measures |
|---|---|
| `record-before-code` | A tier 1 record with every section exists, was written before the first code edit, and the PR body names it |
| `tier-0-no-record` | A typo fix writes no record and declares `Tier: 0` |
| `tier-2-stops-before-code` | A cross-team, hard-to-undo change gets a tier 2 record with Problem, Requirements and Options, and the agent stops for approval without touching the code |
| `probed-facts-labelled` | The module the feature depends on is probed before the record is written, and every probed fact carries an evidence label |
| `decisions-record-alternatives` | The Decisions section names a rejected alternative |
| `outcome-has-real-output` | The Outcome quotes real runs, main path and error path |
| `red-first` | The agent still sees the test fail before changing the code (the `agent-workflow` case, against this skill) |
| `no-routine-questions` | Routine choices are decided and recorded, not asked |

The `skill-fired` grader in each case is the activation indicator under with/without ablation,
not part of the score. `evals/cases.test.cjs` checks that every case is well formed and that
the scaffold builds, without running an agent.

## Results

Run on 2026-11-08 with Claude Code 2.1.319, three runs per case and arm, concurrency 4, the
default Haiku judge for `llm` graders, 4.62 USD and seven minutes for the eight cases. Scores are
the mean over three runs of the fraction of scored graders passed; `skill-fired` is excluded.
All eight cases are from one run, made after the grader review described below.

| Case | With plugin | Without | Delta |
|---|---|---|---|
| `record-before-code` | 0.94 | 1.00 | -0.06 |
| `tier-0-no-record` | 1.00 | 0.75 | +0.25 |
| `tier-2-stops-before-code` | 1.00 | 1.00 | +0.00 |
| `probed-facts-labelled` | 0.89 | 0.33 | +0.56 |
| `decisions-record-alternatives` | 1.00 | 0.50 | +0.50 |
| `outcome-has-real-output` | 1.00 | 0.33 | +0.67 |
| `red-first` | 1.00 | 0.33 | +0.67 |
| `no-routine-questions` | 1.00 | 1.00 | +0.00 |
| **Mean** | **0.98** | **0.66** | **+0.32** |

What the numbers say:

- **The record itself is not the plugin's contribution.** The baseline wrote a record at the
  right path in every run of every case, because the scaffold repository carries the
  `docs/changes/` convention and the prompt names the id. That is by design: it isolates
  what the skill adds on top of a repository that already asks for records.
- **What the skill adds is the content and the order.** Decisions that name a rejected
  alternative: 3 of 3 with the plugin, 0 of 3 without. An Outcome that quotes a real run,
  main path and error path: 3 of 3 with the plugin, 0 of 3 without. Probed facts carrying
  an evidence label: 2 of 3 with the plugin, 0 of 3 without; the probe run before the record
  was written: 3 of 3 with the plugin, 0 of 3 without. A test run, and a failing one, before
  the code changed: 3 of 3 with the plugin, 1 of 3 without. A typo fix declaring `Tier: 0`:
  3 of 3 with the plugin, 0 of 3 without.
- **Two cases tie at full score.** A cross-team change stopped for approval in both arms, and
  routine choices were decided without asking in both arms; the repository's own
  `docs/changes/README.md` was enough for those.
- **The misses with the plugin are each one run in three**: a probed fact written without
  its evidence label, and a PR body without the `Change:` line (which is why the baseline
  edges ahead on `record-before-code`). The error path in Outcome, one in three in the first
  run, was three in three in both reruns. With three runs an arm a single case moves by a
  third between runs, so read deltas under about 0.3 as noise and the pattern across cases
  as the result.
- **Earlier runs read 0.94 against 0.69, then 0.97 against 0.61.** The first run's
  `red-first` graders credited the baseline with two runs that never saw a test fail (a green
  check run, then a failure after the code); with the ordering enforced the baseline fell to
  zero there, and in this run to one in three, a run that did write the test and see it fail
  first.

What the evals changed in the plugin before these numbers: the skill wrote the record, with
Probed facts, before its probing step (runs showed the probe after the record), so step 2 now
probes first; the skill excluded trivial changes and so never fired for a typo, leaving
nothing to say `Tier: 0`, so it now fires for every change and clears tier 0 in one line; and
agents wrote the record path in prose, so the `Change:` line is now the first line of the PR
body. Three graders were wrong before they were right: a tier regex used a POSIX class that
JavaScript reads literally, ordering graders on `Edit` missed `greet.py` written with `Write`
or a shell heredoc and matched `tests/test_greet.py`, and the probe grader could not step
over the quotes inside a JSON-encoded command. Review of the first run found more, and the
numbers above are from a rerun after they were fixed: the record-side graders recognised a
record only when the Write tool wrote it, so an agent that wrote it with a shell heredoc
(which the traces show agents do) failed the ordering grader or slipped past the tempered one;
the greet.py guard in the ordering graders was not JSON-aware, matched `tests/test_greet.py`
and missed `> ./greet.py`; a command that wrote the code and ran the tests in one line counted
as a run before the code; `saw-it-fail` accepted any failure anywhere, so a green check run and
a later red one passed `red-first` without the test ever failing first; and the tier regex did
not read `**Tier:** 0`. A third round found that the guard counted a same-named copy of
greet.py in a scratch directory as a write of the code, that the failing result `saw-it-fail`
looked for could belong to any later command rather than the unittest call (it is now tied to
the call by tool id), and that the probe grader knew only `python -c` and a heredoc (it now
also reads pydoc, `-m`, piped stdin and a scratch script that is written and then run). Every
regex grader runs against fixtures in the trace's own encoding in `cases.test.cjs`, with the
shell forms, the one-command cases and the orderings that must fail.

## Running them

    claude plugin eval plugins/change-record --scaffold --allow-tools Bash Write Edit --trust-plugin --no-publish --runs 3 -j 4

The runner mounts the scaffold repository read-only for shell commands, so the prompts tell
the agent not to branch or commit; an agent that tries will stop and report the sandbox,
which is the right behaviour and a zero score. The runner needs bubblewrap and socat on
Linux. Results land in `evals/results/`, which is not committed.
