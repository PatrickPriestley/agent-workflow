# Outcome evals: does the change skill improve the code and the tests?

The process evals in `../evals/` show that the `change` skill changes what an agent writes
down and in what order. These evals ask the other question: is the code that comes out more
correct, and are its tests stronger? The plan, its review and every decision are in
`docs/changes/2026-11-08-outcome-evals.md`.

## The answer, 2026-11-14

On five small tasks, with Sonnet 5.5, five runs a task and arm: **no effect shown on any
measure**, by the rule fixed before the runs. The skill's arm took about twice the turns
and one and a half times the money. By the owner's ruling on a tie, the skill's value is
the record and the review, not better code on tasks this small.

What the fifty runs do show:

- **Hidden tests.** The plugin arm is ahead on one task, `names-csv` (0.94 against 0.63):
  the baseline printed `Hello, !` for an empty item and a trailing comma in all five runs,
  the plugin arm in one. On the other four tasks the arms are level. Over all runs the
  means are 0.90 and 0.83.
- **Traps both arms missed.** A UTF-8 byte order mark at the start of a names file: missed
  in 10 of 10 runs. A name of spaces only: `Hello, !` in 9 of 10. Neither arm's "use it as
  its user would" found these.
- **Error paths.** Level, and near full marks: of 50 runs, one did not follow the
  repository's convention (a plugin run of `names-file` that exits with status 1).
- **Test strength.** The agents' tests kill 0.72 of the mutants in the functions they
  changed with the skill (21 runs) and 0.77 without (20 runs). On `repeat` the plugin arm
  is behind, 0.57 against 0.76. On the four tasks that can be scored, no cell's mean reaches
  0.9. That, and not a difference between the arms, is what bears on a mutation check in CI.
- **Red before green.** Every changed test file fails on the base, in both arms, 50 of
  50. For a new feature any test of it does; this measure cannot tell the arms apart here.
- **Cost.** 9.7 cents a run with the skill, 6.3 without; 7.9 turns against 4.2. The whole
  matrix cost 3.98 dollars, and the ten shake-out runs before it 86 cents.

## The report

This block is the output of `report.py results/2026-11-14-matrix.jsonl`; a test in
`run.test.sh` fails if the two differ.

<!-- report:begin -->
Model: claude-sonnet-5-5. 50 of 50 runs count; a run that was cut off, saw a check or had the skill in the wrong arm does not.

### names-file

| Arm | Runs | Hidden tests | Probes | Mutation | Coverage | Red tests | Outside | Weakened | Tests with no assertion | Weak assertions | Flaky | Lines added | Turns | Cost |
|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|
| plugin | 5 of 5 | 0.83 (0.71 to 0.86) | 0.80 (0.00 to 1.00) | 0.68 (0.63 to 0.79) | 0.98 (0.95 to 1.00) | 5 of 5 | 0.0 | 0.0 | 0.0 | 0.2 | 0.0 | 130.4 | 8.0 | 0.11 |
| baseline | 5 of 5 | 0.86 | 1.00 | 0.67 (0.60 to 0.75) | 0.98 (0.95 to 1.00) | 5 of 5 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 122.2 | 4.0 | 0.07 |

### names-csv

| Arm | Runs | Hidden tests | Probes | Mutation | Coverage | Red tests | Outside | Weakened | Tests with no assertion | Weak assertions | Flaky | Lines added | Turns | Cost |
|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|
| plugin | 5 of 5 | 0.94 (0.71 to 1.00) | 1.00 | 0.73 (0.60 to 0.82) | 0.99 (0.94 to 1.00) | 5 of 5 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 92.8 | 8.0 | 0.10 |
| baseline | 5 of 5 | 0.63 (0.57 to 0.71) | 1.00 | 0.88 (0.84 to 0.93) | 0.99 (0.96 to 1.00) | 5 of 5 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 105.6 | 4.4 | 0.07 |

### format-json

| Arm | Runs | Hidden tests | Probes | Mutation | Coverage | Red tests | Outside | Weakened | Tests with no assertion | Weak assertions | Flaky | Lines added | Turns | Cost |
|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|
| plugin | 5 of 5 | 1.00 | 1.00 | 0.84 (0.83 to 0.85) | 1.00 | 5 of 5 | 0.0 | 0.2 | 0.0 | 0.0 | 0.0 | 97.2 | 8.4 | 0.10 |
| baseline | 5 of 5 | 1.00 | 1.00 | 0.76 (0.68 to 0.85) | 0.97 (0.93 to 1.00) | 5 of 5 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 106.2 | 4.2 | 0.06 |

### repeat

| Arm | Runs | Hidden tests | Probes | Mutation | Coverage | Red tests | Outside | Weakened | Tests with no assertion | Weak assertions | Flaky | Lines added | Turns | Cost |
|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|
| plugin | 5 of 5 | 1.00 | 1.00 | 0.57 (0.51 to 0.63) | 0.97 (0.87 to 1.00) | 5 of 5 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 83.0 | 7.8 | 0.10 |
| baseline | 5 of 5 | 1.00 | 1.00 | 0.76 (0.69 to 0.83) | 0.96 (0.92 to 1.00) | 5 of 5 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 112.0 | 4.2 | 0.07 |

### defect-whitespace

| Arm | Runs | Hidden tests | Probes | Mutation | Coverage | Red tests | Outside | Weakened | Tests with no assertion | Weak assertions | Flaky | Lines added | Turns | Cost |
|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|
| plugin | 5 of 5 | 0.73 (0.67 to 1.00) | 1.00 | 1.00 | 1.00 | 5 of 5 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 40.2 | 7.4 | 0.08 |
| baseline | 5 of 5 | 0.67 | 1.00 | none | 1.00 | 5 of 5 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 37.6 | 4.0 | 0.05 |

### What the numbers show

- Hidden tests: no effect shown. The plugin arm is ahead on 1 and behind on 0 of 5 decided tasks; 0 of 5 tasks were not decided.
- Probes: no effect shown. The plugin arm is ahead on 0 and behind on 0 of 5 decided tasks; 0 of 5 tasks were not decided.
- Mutation score: no effect shown. The plugin arm is ahead on 0 and behind on 1 of 4 decided tasks; 1 of 5 tasks were not decided.
- Changed-line coverage: no effect shown. The plugin arm is ahead on 0 and behind on 0 of 5 decided tasks; 0 of 5 tasks were not decided.
- Files outside the task: no effect shown. The plugin arm is ahead on 0 and behind on 0 of 5 decided tasks; 0 of 5 tasks were not decided.
- Tests weakened: no effect shown. The plugin arm is ahead on 0 and behind on 0 of 5 decided tasks; 0 of 5 tasks were not decided.
<!-- report:end -->

Read with the table: "Weakened" counts an assertion line that was rewritten as well as one
that was removed (the one case here is a rewrite). "Red tests" is the count of changed test
files that fail on the base. Mutation has no score for `defect-whitespace`: mutmut makes no
mutant in `greet`, the one function most fixes touch.

## What this does not show

- One model. Nothing here is about another.
- One scaffold of forty lines. A tie here may not hold on larger code, where a probe or a
  record has more to catch. The owner has ruled that a tie closes the question as asked.
- Five runs a cell. The rule asks for a difference larger than the range of either arm,
  so a modest effect reads as none.
- The runs were started from a cloud session, whose environment the agents inherit but for
  this repository's path.
- Two hidden checks were dropped or widened, and one more widened, after the shake-out and
  before the matrix; the record says which and why.

## How it works

- `tasks/<name>/`: the prompt and the scaffold of each task. Both arms get the same prompt
  in the same repository, which already asks for change records.
- `checks/<name>/`: the hidden acceptance tests and probes, with a naive and a reference
  implementation they are proven against (`checks/selftest.sh`). No agent can reach them.
- `run.sh`: runs an agent on each task in each arm and writes one JSON line a run. The
  plugin arm gets a copy of the plugin; neither arm loads anything installed for the user.
- `measures.py`: what is measured in what the agent committed.
- `report.py`: the table and the answer by the rule.

To run it again (it spends money on agent runs; `--max-cost` stops it):

    plugins/change-record/outcome-evals/run.sh --runs 5 --max-cost 15 --out results/<date>-matrix.jsonl
    python3 plugins/change-record/outcome-evals/report.py results/<date>-matrix.jsonl

Tests, with no model and nothing installed:

    bash plugins/change-record/outcome-evals/checks/selftest.sh
    bash plugins/change-record/outcome-evals/run.test.sh
