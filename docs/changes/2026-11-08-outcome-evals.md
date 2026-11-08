---
id: 2026-11-08-outcome-evals
tier: 2
status: open
requester: Patrick Priestley, in chat on 2026-11-08 ("Is there a way to measure whether this skill improves the actual implementation and quality?")
approvers: []
---
# Measure whether the change skill improves the code and the tests, not only the record

## Goal

Know, with numbers, whether an agent using the `change` skill produces more correct code and
stronger tests than the same agent without it, on tasks with traps the prompt does not spell
out, and at what cost in turns and money. Then decide from those numbers whether to build the
mutation CI job and whether the skill's step 5 needs to be stronger.

## Probed facts

- Verified against the real system (Claude Code 2.1.319, this session, 2026-11-08):
  `claude -p ... --output-format json` returns `num_turns`, `total_cost_usd`, `duration_ms`,
  `is_error` and `subtype`, so the harness can take turns and cost from the agent itself.
- Verified against the real system: the Claude plugin eval runner mounts the scaffold
  repository read-only for shell commands; in the second process-eval run every plugin-arm
  agent stopped at `git checkout -b` or `git commit` with "Read-only file system" (traces).
- Verified against the real system: `red-check` and `pr-size` run on a commit range here;
  `pr-size origin/main..HEAD` reports 701 reviewable lines on this branch.
- Verified reachable, not yet run: PyPI serves mutmut 3.8.1, coverage 7.17.2 and hypothesis
  6.170.15 through this environment. That mutmut runs on a 40-line module here is assumed
  until task 2's shake-out.
- Exact source: `skills/incident-to-eval/scripts/run-eval.sh` snapshots a commit into a fresh
  repository, runs `claude -p` with `--permission-mode acceptEdits`, then runs
  `evals/checks/<id>/check.sh` from outside the case directory; its contract is the one
  this harness copies.
- Verified against the real system, CLI 2.1.319 on 2026-11-08: `claude -p --max-turns 1
  --plugin-dir plugins/change-record` asked for its skill list named `change-record:change`;
  the same call without the flag did not. That the loaded skill fires under `-p` is what the
  process evals' `skill-fired` grader showed on every plugin-arm run (the runner uses `-p`).

## Problem

The process evals (`plugins/change-record/evals/`, 2026-11-08) show the skill changes what the
record holds and the order of work: 0.98 with the plugin against 0.66 without. Nothing
measures whether the code that comes out is more correct or the tests stronger, and the
plugin README labels that claim assumed. Two decisions wait on it: the mutation CI job in the
design, and the Outcome error path, which the process evals put at one run in three on the
first run and three in three on the second, so they cannot settle it.

## Requirements

- R1. Each of five tasks has hidden acceptance tests and behaviour probes the agent cannot
  see, and each fails against a naive implementation before any agent runs.
  Check: `checks/selftest.sh` applies the naive implementation and expects every check to fail.
- R2. The harness runs both arms (`--plugin-dir plugins/change-record` present or absent) N
  times per task in writable scratch repositories, and writes one JSON line per run with:
  hidden tests passed, probes passed, mutation score, red-check verdicts, changed-line
  coverage, files touched outside the task, tests weakened, turns, cost, duration, and a
  status of pass, fail, warn, skip or error, so a check that could not run never reads as a
  pass. Check: `run.test.sh` drives the harness with a fake agent that applies a canned patch
  and asserts the fields and statuses.
- R3. A reporter turns the lines into a table per task and arm with mean, spread and cost.
  Check: `run.test.sh` feeds it known lines and compares the table.
- R4. The assertion heuristic and the flakiness repeats are reported as counts, never as pass
  or fail. Check: the reporter's columns for them carry numbers only.
- R5. The report goes into `outcome-evals/README.md` and the plugin README cites it; raw
  results are not committed. Check: `.gitignore` covers `outcome-evals/results/`.
- R6. The harness does not change the skill. Any change to the skill follows from the report,
  as its own change record.

## Options and concerns

Options considered:

- A. The Claude plugin eval runner. Rejected: its graders cannot run a command, so hidden tests
  cannot run; and its sandbox mounts the repository read-only for shell commands, which
  stopped the skill at `git commit` in the first process-eval run (verified).
- B. Extend `skills/incident-to-eval/scripts/run-eval.sh`. Considered: its `check.sh` contract
  outside the agent's view is exactly the shape needed, but it has no notion of arms, and it
  belongs to the other plugin, which this work leaves as it is.
- C. A new harness under `plugins/change-record/outcome-evals/` in the `run-eval.sh` shape.
  Recommended.

Concerns:

### C1: the scaffold is small and a tie is plausible
A greet CLI may get the traps right in both arms, and a tie would read as "no quality effect"
when the effect might show only on larger code. Owner: Patrick Priestley (decides whether a
tie closes the question or motivates a larger scaffold; the plan proposes reading a tie as
"the skill's value is the record and the review", and saying so in the README).
Resolved by:

### C2: fifty agent runs on the owner's credential
Five tasks, two arms, five runs: about 8 to 15 USD at the process evals' rate, two hours in
parallel. Owner: Patrick Priestley.
Resolved by:

### C3: this branch already carries 701 reviewable lines
The process evals, their fixes and two design documents are on `ccr-f30b758a-i1j9v1`,
unmerged, above the plugin's 400-line aim. The skill's splitting rule puts this work in its
own pull requests, cut after that one merges. Owner: Patrick Priestley (open the process-evals
pull request first, or accept one large one).
Resolved by:

## Decisions

- Harness in the `run-eval.sh` shape, not the eval runner. Rejected: the runner, for the two
  reasons under option A.
- Arms by presence of `--plugin-dir` on the same `claude -p` call. Rejected: installing and
  removing the plugin between runs, which is slower and leaves state behind.
- Deterministic measures first; one LLM judge, three votes, for error-message wording only.
  Rejected: judging correctness by LLM, since hidden tests are exact and cheaper.
- Hidden tests and probes beside the scratch repository, never inside it. Rejected: a dot
  directory inside the repository, which an agent listing files would find.
- From Codex's framework: include red/green (it is `red-check`), narrow mutation testing with
  mutmut, changed-line coverage with its weakness stated, a 30-line assertion heuristic as a
  count, and three repeat runs plus reverse order for flakiness. Defer property-based
  testing (a skill capability, not a measure), a bug corpus (needs a real repository) and the
  ESLint rules (a Vitest codebase). Reasons in `docs/design/2026-11-08-outcome-evals.md`.

## Tasks

One pull request each, cut after the process-evals pull request merges (C3).

1. **Checks.** `outcome-evals/tasks/<name>/{prompt.md,scaffold.sh}` and
   `outcome-evals/checks/<name>/{hidden_test.py,probes.sh}` for `names-file`, `names-csv`,
   `format-json`, `repeat` and `defect-whitespace`, plus `checks/selftest.sh`. Test:
   `selftest.sh` against a naive implementation of each task fails every check; it fails today
   because none of it exists.
2. **Harness and measures.** `outcome-evals/run.sh` (snapshot, two arms, N runs, JSON lines),
   `measures/mutation.sh`, `measures/coverage.sh`, `measures/assertions.py`,
   `measures/flaky.sh`, `measures/scope.sh`, `report.py`, and `run.test.sh` with a fake agent.
   Test: `run.test.sh` asserts each JSON field, the error status when a measure cannot run,
   and the reporter's table; it fails today because none of it exists.
3. **The run and the report.** One shake-out run of one task, then the full matrix with five
   runs; `outcome-evals/README.md` with the table, spread and cost; the plugin README cites
   it. Test: the README numbers match `results/*.jsonl` through `report.py`.

## Checks

`bash outcome-evals/checks/selftest.sh`; `bash outcome-evals/run.test.sh`; the full matrix
with `--runs 5`; `red-check` over each pull request's changed tests. The independent reviewer
should attack: whether an agent can reach the hidden tests from inside the scratch
repository; whether any measure that could not run reads as a pass; whether the mutation
target is really the lines the agent changed and not the whole module; and whether the fake
agent in `run.test.sh` exercises the same code path as a real one.

## Outcome

