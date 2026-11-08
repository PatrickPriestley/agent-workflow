# Outcome evals: does the change skill improve the code and the tests, not only the record?

Status: plan, not built. Follows `docs/design/2026-11-07-one-record-sdlc.md` and the process
evals under `plugins/change-record/evals/` (eight cases; with the plugin 0.98, without 0.66).

## The question

The process evals show the skill changes what the record holds and the order of work. They do
not show whether the code that comes out is more correct or the tests stronger. This plan
measures that directly: hidden acceptance tests the agent never sees, behaviour probes
against the real program, the mutation score of the agent's own tests, and the other test
quality checks Codex proposed for an AI-written-test framework, each judged on whether it is
worth its cost here.

## Harness

Not the Claude plugin eval runner. Its graders cannot run a command, and its sandbox mounts
the repository read-only for shell commands, which stops an agent at the first `git commit`.
Instead, the shape of `skills/incident-to-eval/scripts/run-eval.sh`, which this repository
already has: snapshot a scaffold into a fresh repository, run the agent with `claude -p`, then
run a check script kept outside the agent's view.

- **Two arms**, chosen by the harness: `claude -p ... --plugin-dir plugins/change-record`
  (verified 2026-11-08 on CLI 2.1.319: a `-p` session with the flag lists the skill, one
  without does not) against the same prompt without it.
  Both arms see the scaffold's `docs/changes/README.md`, as the process evals do, so the
  measure is what the skill adds to a repository that already asks for records.
- **Writable repository.** The agent runs with `--permission-mode acceptEdits` in a scratch
  directory the harness owns, so it can branch and commit and the skill's loop runs as
  written. Hidden tests and probes live beside the scratch directory, not inside it.
- **Per run, the harness records** the agent's `num_turns`, `total_cost_usd` and
  `duration_ms` from `--output-format json`, then runs the checks below and writes one JSON
  line. A small reporter turns the lines into a table per task and arm.
- **Location:** `plugins/change-record/outcome-evals/` with `tasks/<name>/{prompt.md,
  scaffold.sh}`, `checks/<name>/{hidden_test.py, probes.sh}` and `run.sh`. Results under
  `outcome-evals/results/`, ignored like the process results.

## Tasks

Four feature tasks on the greet scaffold, each with traps the prompt does not spell out, and
one injected defect. The traps are where a happy-path implementation and a probed one part.

| Task | Prompt asks for | Hidden tests and probes check |
|---|---|---|
| `names-file` | `--names-file PATH`, one name per line, via `fileinput` | no trailing newline, blank lines skipped, CRLF, a UTF-8 BOM, a missing file gives a clear error and exit 2, `-` reads stdin |
| `names-csv` | `--names Ana,Bo` comma-separated | spaces around names trimmed, an empty item skipped, an all-empty list is an error with exit 2, a single name, unicode names |
| `format-json` | `--format json` printing `{"greeting": ...}` | a name with a quote or backslash produces valid JSON (`json.dumps`, not string formatting), unknown format is an error with exit 2, output ends with one newline |
| `repeat` | repeat the greeting N times | `-n 0` prints nothing and exits 0, a negative or non-integer N is an error with exit 2, N=1 equals the plain output, `-n` combines with `--shout` if present |
| `defect-whitespace` | "greet('  Ada ') prints `Hello,   Ada !`; fix it" | the fix strips in one place so `main` and `greet` agree, a regression test exists that fails on the base, and names that are only whitespace fall back to `world` (the root cause, not the symptom) |

Each task's checks are written before any agent runs, and run once by hand against a
deliberately naive implementation to confirm they fail (the check's own red step).

## Measures

Per run, deterministic unless noted:

1. **Hidden acceptance tests**: fraction passing. The primary correctness measure.
2. **Behaviour probes**: a shell script runs the program on each trap input and compares exit
   code and a message pattern; fraction passing. Separates "a test exists" from "the error
   path is right".
3. **Mutation score of the agent's tests**: `mutmut run` over the lines the agent changed in
   `greet.py`, killed over total. Direct test-strength measure. Mutmut 3.8.1 installs here.
4. **Red before green**: `red-check` from this plugin, run by the harness over the agent's
   commits (named-file runner, `--strict`): red, green, inconclusive, no-tests per changed
   test file. The skill's rule 3, measured rather than attested.
5. **Changed-line coverage**: `coverage.py` over the agent's tests, restricted to the lines
   the agent changed; fraction covered. Cheap, and a weak proxy that the mutation score
   corrects.
6. **Scope and collateral**: files changed outside `greet.py`, `tests/` and `docs/changes/`;
   tests deleted or assertions removed relative to the base; diff size in added lines.
7. **Turns, cost and wall time**, so quality is reported against what it cost.

Judged by an LLM, only where nothing deterministic exists:

8. **Error message quality**: does the message name the input and what to do, without a
   traceback. Haiku judge on the probe output, three votes.

## Codex's methods, and whether to include them

- **Red/green verification**: included (measure 4); it is `red-check`, already built.
- **Mutation testing, narrow and on changed code**: included (measure 3), run by hand per task
  through `mutmut`; this doubles as the hand-run that decides whether the mutation CI job in
  the design is worth building.
- **Coverage of changed code**: included (measure 5) because it is nearly free, with the
  caveat written into the report that it says a line ran, not that a test would notice it
  breaking.
- **Static assertion analysis**: included as one heuristic, not a framework: a 30-line Python
  AST check that counts test functions with no assertion and assertions of the
  `assertTrue(x)`, `assertIsNotNone(x)` and `assertEqual(x, x)` shapes. Reported as a count,
  never as a pass or fail, because `toBeDefined`-style assertions are sometimes right. The
  ESLint-plugin approach is for a Vitest repository and does not apply here.
- **Flakiness and isolation**: included cheaply: the agent's tests run three more times and
  once in reverse file order; any difference is reported. The full "shuffled order, repeated
  execution, historical regression" profile is deferred; this scaffold has no history.
- **Property-based testing**: not a measure. It is a capability the skill could ask for when
  the record's Requirements state an invariant. Deferred until the record has a Requirements
  section in tier 1, which it does not; noted for the skill, not for this harness.
- **Historical bug corpus**: deferred. It needs a real repository with fixed bugs; the
  `incident-to-eval` skill is the path to it, one incident at a time.
- **Structured JSON findings with pass, fail, warn, skip, error**: adopted for the harness's
  own per-run record, so a check that could not run never reads as a pass; the same
  distinction `red-check` makes.
- **Capped repair loop**: not a measure; already in the skill.

## Runs and cost

Five tasks, two arms, five runs each: fifty agent runs. The process evals cost about 0.12 USD
a run on this scaffold; the skill arm takes more turns, so budget 8 to 10 USD for the agent
runs. Mutmut on a 40-line module with a handful of tests is seconds per run. Total under
15 USD and about two hours of wall time at four runs in parallel.

Five runs per arm is the minimum at which a difference of one hidden test in five means
something; the report shows the spread, not only the mean.

## What counts as an answer

The skill improves implementation quality if, across the five tasks, the plugin arm passes
more hidden tests and probes and its tests kill more mutants, by margins larger than the
run-to-run spread, and does so without touching files outside the task. If it passes more
tests at two to three times the cost, that is a trade-off to report, not a win to claim. If
the arms tie on hidden tests and differ only on the record, the skill's value is in the
record and review, and the README should say so.

A tie on this scaffold is a real possibility: the tasks are small and the model may get the
traps right either way. The traps are chosen to need a probe or a real-use run, which is what
the skill adds; if the baseline gets them anyway, that is also an answer.

## Order of work

1. Write the five tasks' hidden tests and probes; run each against a naive implementation and
   see it fail. Half a day.
2. The harness: snapshot, two arms, checks, JSON lines, reporter; the AST heuristic and the
   flakiness repeats. Half a day.
3. One task, one run per arm, to shake out the harness. Then the full matrix.
4. Report: a table per task and arm with all eight measures, the spread, and the cost, written
   into `plugins/change-record/outcome-evals/README.md`; the plugin README's verified section
   cites it.
5. Decide from the mutation scores whether to build the mutation CI job; from the hidden
   tests and probes whether the skill's step 5 needs to be stronger or the Outcome error path
   needs its own check.

## Not in scope

Running this against a real repository of yours; that is the quarter-long measurement in the
design document. Changing the skill from these results before they exist. A TypeScript or
Vitest port of the harness.
