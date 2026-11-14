---
id: 2026-11-08-outcome-evals
tier: 2
status: approved
requester: Patrick Priestley, in chat on 2026-11-08 ("Is there a way to measure whether this skill improves the actual implementation and quality?")
approvers: [Patrick Priestley, 2026-11-14]
---
# Measure whether the change skill improves the code and the tests, not only the record

## Goal

Know, with numbers, whether an agent using the `change` skill produces more correct code and
stronger tests than the same agent without it, on tasks with traps the prompt does not spell
out, and at what cost in turns and money. Both arms work in a repository that already asks
for change records (the scaffold's `docs/changes/README.md`), so what is measured is what the
skill adds to that, not a skill against a bare repository. Then decide, by the rule in R7,
whether to build the mutation CI job and whether the skill's step 5 needs to be stronger.

## Probed facts

- Verified against the real system (Claude Code 2.1.319, 2026-11-08, and 2.1.325,
  2026-11-14): `claude -p ... --output-format json` returns `num_turns`, `total_cost_usd`,
  `duration_ms`, `is_error`, `subtype` and `modelUsage`, whose key names the model, so the
  harness can take turns, cost and the model from the agent itself.
- Verified against the real system (the process-eval runs of 2026-11-08, summed up in
  `plugins/change-record/evals/README.md`): the Claude plugin eval runner mounts the scaffold
  repository read-only for shell commands, so an agent that branches or commits stops there.
- Exact source (the grader files under `plugins/change-record/evals/*/graders/`): the
  runner's graders are of four types, `llm`, `file_exists`, `tool_used` and `regex`. None
  runs a command.
- Exact source (`skills/incident-to-eval/scripts/run-eval.sh`, lines 47 to 51, 81 and 82):
  it snapshots a commit into a fresh repository, changes into it and runs `claude -p` with
  `--permission-mode acceptEdits` and no tool allowance, then runs
  `evals/checks/<id>/check.sh`, a script kept outside the snapshot, with the snapshot as its
  working folder. A shell that changes folder exports the one it left as `OLDPWD`.
- Verified against the real system (`plugins/change-record/bin/dispatch`, whose header
  records it, and the archived session `grade/fixtures/dispatch-1-95e399c5.jsonl.gz`): under
  `-p` with `acceptEdits` alone every shell command is denied, test runs and commits
  included. `dispatch` therefore runs `claude -p --permission-mode acceptEdits --allowedTools
  Bash`.
- Verified against the real system, CLI 2.1.319 on 2026-11-08: `claude -p --max-turns 1
  --plugin-dir plugins/change-record` asked for its skill list named `change-record:change`;
  the same call without the flag did not. That the loaded skill fires under `-p` is what the
  process evals' `skill-fired` grader showed on every plugin-arm run (the runner uses `-p`).
- Exact source (`skills/change/SKILL.md`): the skill tells the agent to read `RULES.md` and
  its references from `${CLAUDE_PLUGIN_ROOT}`, which is the folder given to `--plugin-dir`.
  An agent with a shell can list that folder and walk up from it.
- Verified against the real system (a scratch copy of the scaffold, 2026-11-14, mutmut
  3.8.1, pytest 9.2.0, coverage 7.17.3 from PyPI in a virtual environment):
  - mutmut runs the tests through pytest only; pytest collects the scaffold's `unittest`
    suite as it is.
  - On the scaffold as it stands, `mutmut run` makes 10 mutants, all in `main` and none in
    `greet`, and stops with "could not find any test case for any mutant": the one test calls
    `greet` only. Every mutant is `not checked`. There is no score to report.
  - With one more test that calls `main`, the same run takes one second and gives 7 killed
    and 3 survived.
  - Mutants are named by function (`greet.x_main__mutmut_3`), and `mutmut show` prints a
    diff relative to the function. mutmut has no option to mutate a range of lines.
- Exact source (`plugins/change-record/bin/red-check`, its header): the default test-file
  patterns include `**/*_test.py`, `**/test_*.py` and `**/tests/**`. It copies each changed
  test file onto the base and runs it there; a file that cannot run is inconclusive, and a
  range whose every file is inconclusive fails.
- Verified against the real system (Claude Code 2.1.325, a scratch repository, 2026-11-14):
  `claude -p --permission-mode acceptEdits --allowedTools Bash --setting-sources ""
  --output-format stream-json --verbose` ran a shell command and printed one event a line:
  a `system` event of subtype `init` with `model` (the session's own), `plugins` and
  `skills`; an `assistant` event for each tool call, with the tool's name and input; and a
  `result` event with `num_turns`, `total_cost_usd`, `duration_ms` and `is_error`. With no
  setting sources and no `--plugin-dir`, `plugins` held built-in ones only and no `change`
  skill was listed. `--max-budget-usd` is in the CLI's help, for `-p` only. `--max-turns`
  is not in the help of 2.1.325; whether it still limits anything was not probed.
- Exact source (`plugins/change-record/evals/results/run6/aggregate-result.json`, as the
  reviewer of 2026-11-14 read it; not read again here): the process evals ran with at most
  40 turns and 600 seconds a run.
- Verified against the real system (`claude -p` on this account, 2026-11-14): a fresh
  session with no `--model` ran on the account's default model; a review of 38 turns cost
  3.62 dollars. The process evals of 2026-11-08 cost about 0.12 dollars a run. The default
  has changed, or differs between the runner and `-p`; which was not looked into.
- Exact source (record `2026-11-12-session-quality`, Outcome): the two model judges built
  for transcripts were measured against labels and taken out; one was wrong on 3 of 14
  sessions, the other on 4 of 7.

## Problem

The process evals (`plugins/change-record/evals/`, 2026-11-08) show the skill changes what the
record holds and the order of work: 0.98 with the plugin against 0.66 without. Nothing
measures whether the code that comes out is more correct or the tests stronger, and the
plugin README makes no claim about it. Two decisions wait on it: the mutation CI job in the
design, and the Outcome error path, which the process evals put at one run in three with the
plugin in the first full run and three in three in both reruns (`evals/README.md`), so
they cannot settle it.

## Requirements

- R1. Each of five tasks has hidden acceptance tests and behaviour probes. Each check is
  marked as a trap or as plain. Before any agent runs, a naive implementation fails every
  trap check and passes every plain one, and a reference implementation passes all; both
  are kept with the checks. Check: `checks/selftest.sh` applies each and expects exactly
  that.
- R2. The harness runs both arms five times per task (`--runs`, default 5) in writable
  scratch repositories, each with the same pinned model, and writes one JSON line per run
  with: task, arm, the model of the session's `init` event, whether the `change` skill was
  listed and whether the Skill tool was called, turns, cost, duration, the agent's own
  status (ok, or error with the reason: failed, out of time, over budget, saw a check), and
  one entry per measure with a value and a status of its own, pass, fail, warn, skip or
  error, so a measure that could not run never reads as a pass. The measures are: hidden
  tests passed, probes passed, mutation score, red-check verdicts, changed-line coverage,
  files touched outside the task, tests weakened, lines added. "Outside the task" is any
  file but `greet.py`, `README.md` and those under `tests/` and `docs/changes/`. "Tests
  weakened" is the count of test functions deleted and of assertions removed, against the
  base. Check: `run.test.sh` drives the harness with a fake agent that applies a canned
  patch and asserts the fields and statuses.
- R3. A reporter turns the lines into a table per task and arm with mean, spread and cost.
  Check: `run.test.sh` feeds it known lines and compares the table.
- R4. The assertion heuristic and the flakiness repeats are reported as counts, never as pass
  or fail. Check: the reporter's columns for them carry numbers only.
- R5. The report goes into `outcome-evals/README.md`, and the plugin README's section "What
  is verified against the real system" gets a sentence that cites it. The JSON lines of the
  matrix are committed under `outcome-evals/results/`; they hold numbers and no transcript.
  Everything else a run leaves is not committed. Check: `run.test.sh` runs the reporter over
  the committed lines and compares its table with the one in the README.
- R6. The harness does not change the skill. Any change to the skill follows from the report,
  as its own change record. Check: `git diff --stat <base>..<head> --
  plugins/change-record/skills` is empty for each of the three pull requests.
- R7. The report answers by one rule, written before any run. Better is higher for hidden
  tests, probes, mutation score and coverage, and lower for files outside the task and
  tests weakened. A task is decided on a measure only when both arms have five runs whose
  entry for it has a value; the spread of an arm is then the range over those five, and an
  arm is ahead when its mean is better by more than the larger of the two spreads. The
  skill is said to improve a measure when the plugin arm is ahead on at least three decided
  tasks and behind on none; otherwise the report says no effect was shown, and how many
  tasks were decided. Where the plugin arm's mean cost per run on a task is more than
  twice the baseline's, a gain there is reported as a trade-off. Check: `run.test.sh` feeds
  the reporter lines for a win, a tie, a mixed result, a trade-off and a task with a short
  cell, and compares its sentence.
- R8. No agent can reach the checks. They are not in the scratch repository, not beside it,
  and not in or above the folder given to `--plugin-dir`; and no variable or argument of
  the agent's process holds this repository's path. Check: `run.test.sh` runs a fake agent
  that searches upward from its working folder and from the folder its `--plugin-dir`
  argument names, and looks through its environment and arguments for this repository's
  path, and finds nothing; and a run in which any tool call's input names a check file or
  the checks' folder has the agent status error, "saw a check".
- R9. Neither arm has the skill unless the harness gave it. Both run with no setting
  sources, so nothing installed for the user is loaded. Check: `run.test.sh` asserts
  `--setting-sources ""` in both arms' calls, and that a baseline run whose `init` event
  lists the `change` skill, or that calls the Skill tool for it, has the agent status
  error; a plugin run in which the skill is not listed has it too.
- R10. One prompt per task, the same for both arms. It names the record id to use, says the
  repository has no remote and that the work ends at a commit on a branch with the PR body
  as the last message, and names the test command. Check: `selftest.sh` asserts those four
  things of each `prompt.md`.

## Options and concerns

Options considered:

- A. The Claude plugin eval runner. Rejected: none of its grader types runs a command, so
  hidden tests cannot run; and its sandbox mounts the repository read-only for shell
  commands, which stops the skill at its first commit (both under Probed facts).
- B. Extend `skills/incident-to-eval/scripts/run-eval.sh`. Considered: its `check.sh` contract
  outside the agent's view is the shape needed, but it has no notion of arms, it gives the
  agent no shell, and it belongs to the other plugin, which this work leaves as it is.
- C. A new harness under `plugins/change-record/outcome-evals/` in the `run-eval.sh` shape.
  Recommended.
- D. A third arm in a repository with no `docs/changes/README.md`, to show what the
  convention alone adds. Not now: it is twenty-five more runs for a question the process
  evals already answer in part, and it can be added without changing the other two arms.

Concerns:

### C1: the scaffold is small and a tie is plausible
A greet CLI may get the traps right in both arms, and a tie would read as "no quality effect"
when the effect might show only on larger code. Owner: Patrick Priestley (decides whether a
tie closes the question or motivates a larger scaffold; the plan proposes reading a tie as
"the skill's value is the record and the review", and saying so in the README).
Resolved: a tie closes it. The README then says the skill's value is the record and the
review, and the mutation CI job is decided on the mutation scores alone. Patrick Priestley,
in chat, 2026-11-14.

### C2: fifty agent runs on the owner's credential
Five tasks, two arms, five runs. At the process evals' rate that is 8 to 15 dollars and two
hours in parallel. At the rate `claude -p` charged on 2026-11-14 with the account's default
model it could be ten times that. Failure case: the matrix runs on the default model and
costs over a hundred dollars; or the credential is rate-limited half way and the table mixes
finished and unfinished cells; or one agent loops in the skill's repair step and spends the
whole budget before the sum is looked at. Proposed: pin the model (C5); give each run
`--max-budget-usd 1` and ten minutes, after which it has the agent status error; stop
starting runs once the summed cost passes `--max-cost` (default 15 dollars); and R7 does not
decide a task whose cell is short. Owner: Patrick Priestley.
Resolved: 15 dollars in all and 1 dollar and ten minutes a run, as proposed. Patrick
Priestley, in chat, 2026-11-14.

### C3: this branch already carries 701 reviewable lines
That was so on 2026-11-08. The process evals, their fixes and this record merged as pull
request 37 that day, so the tasks are cut from `main`. Owner: Patrick Priestley.
Resolved: moot; the pull request merged on 2026-11-08.

### C4: what counts as an answer
The design says the plugin arm must be ahead "by margins larger than the run-to-run spread".
Failure case: the plugin arm kills 0.80 of mutants against 0.70 with a spread of 0.15, and
two readers decide the mutation CI job opposite ways from one table. Proposed: R7. Five runs
are too few for a significance test, so the rule is a plain one about means and ranges.
Owner: Patrick Priestley.
Resolved: R7 as proposed, ahead on at least three of five tasks and behind on none. Patrick
Priestley, in chat, 2026-11-14.

### C5: which model, and that it is the same in both arms
`claude -p` takes the account's default model unless `--model` is given, and that default
is not what it was on 2026-11-08. Failure case: one arm runs before a change of default and
the other after, and the difference is put down to the skill. Proposed: the harness always
passes `--model`, the same for both arms, default `claude-sonnet-5-5` to stay near the
budget; each JSON line carries the model of the session's `init` event, which is one name
whatever helper models a run also used, and the reporter refuses a table whose lines name
more than one. Owner: Patrick Priestley (which model).
Resolved: Sonnet 5.5, pinned as `claude-sonnet-5-5`, for both arms. The report says its
result is for that model. Patrick Priestley, in chat, 2026-11-14.

## Decisions

- Harness in the `run-eval.sh` shape, not the eval runner. Rejected: the runner, for the two
  reasons under option A.
- The agent is run with a shell, as `dispatch` runs it, and cut off from the user's own
  setup: `claude -p --permission-mode acceptEdits --allowedTools Bash --setting-sources ""
  --model <model> --max-budget-usd 1 --output-format stream-json --verbose`, started by the
  harness with the scratch repository as its working folder and an environment that holds
  no path of this repository (no `OLDPWD`, no `PWD` of the caller). Rejected: `run-eval.sh`'s
  call as it is, under which the agent could not run a test or commit; and its `cd` in a
  subshell, which leaves the caller's folder in `OLDPWD`.
- The harness reads the stream of events: the `init` event for the model and for whether
  the skill is listed, each tool call for the Skill tool and for any mention of a check, the
  `result` event for turns, cost and duration. Rejected: `--output-format json`, which has
  none of the calls; and reading the session file under `~/.claude/projects`, whose place
  and form are the CLI's own business.
- Arms by presence of `--plugin-dir` on the same call. Rejected: installing and removing the
  plugin between runs, which is slower and leaves state behind.
- The plugin arm is given a copy of the plugin made by the harness in a temporary folder:
  `.claude-plugin/`, `skills/`, `RULES.md`, `bin/` and `templates/`, nothing else. Rejected:
  `--plugin-dir plugins/change-record`, which would hand that arm the folder the checks live
  in, and through it the path of this repository.
- Checks stay in this repository, under `outcome-evals/checks/`, and their path is in no
  variable and no argument the agent's process gets; the scratch repository is made in a
  temporary folder of its own. Rejected: beside the scratch repository, where an agent with
  a shell finds them with `ls ..`; and a dot directory inside it.
- The scaffold's README states the repository's conventions: a usage error names the input
  on standard error and exits with status 2, with no traceback; `-` is standard input; one
  greeting a line. The prompts do not repeat them. Rejected: traps that neither the prompt
  nor the repository lets an agent find out, which would measure guessing and not care.
  (Added while building task 1.)
- A hidden check must follow from the prompt or from the scaffold's README. Two things
  changed on that ground after the shake-out of task 2, before any run of the matrix: the
  check that `-n 0` prints nothing is gone, since the prompt leaves open whether a count of
  0 is valid and both arms' agents refused it; and a probe accepts a refusal that names the
  option or the value, since a message such as "argument -n: must be at least 1" has named
  the input. Rejected: keeping them, which would count one reasonable reading against both
  arms alike and add noise to every cell of that task.
- The measures are one module, `measures.py`, called by `run.py` behind `run.sh`, and not
  the five scripts task 2 listed. They share the diff of the agent's commits and the clone
  they run in. Rejected: five scripts that each work those out again.
- Task 2 goes up as two pull requests, the harness with its measures and then the
  reporter. Together they are 1,098 reviewable lines, over the plugin's stop of 1,000.
  Rejected: one pull request, as the task list has it.
- A measure's status says what became of the measuring, not how well the agent did: pass
  when it ran and has a value, skip when there was nothing to measure, error when it could
  not run; `red-check` keeps its own pass, fail or warn. How well the agent did is the
  value. Rejected: fail for a low value, which would make a count read as a verdict (R4).
- The agent inherits the caller's environment but for this repository's path. Started from
  a cloud session, it therefore knows that session's id, and one agent of the shake-out put
  it into a commit message. It is the same for both arms. Rejected for now: an empty
  environment, which would also drop what the CLI signs in with.
- The hidden tests are named `acceptance.py`, not `hidden_test.py`. Rejected: a name that
  `red-check` and pytest take for a test of this repository.
- Deterministic measures only. Rejected: the Haiku judge of error-message wording that the
  design proposed. The two model judges built since were wrong too often to keep, and the
  probes already compare each error's exit code and a message pattern.
- The mutation score is over the functions the agent changed, taken from mutmut's results
  for the whole file by the function in each mutant's name. A run with no mutant in those
  functions, or none that a test reaches, has the status skip and no score. Rejected:
  "the lines the agent changed", which mutmut cannot select and its results do not name.
- The measures need pytest, mutmut and coverage, installed by the harness into a virtual
  environment of its own. They run on a copy of the scratch repository made after the agent
  has finished and after the scope measure has read the agent's commits, so mutmut's
  configuration file and its `mutants/` folder are never counted as the agent's.
- The three tasks are built by hand in this order, not by `dispatch`: the record's
  frontmatter lists no tasks. Rejected: `dispatch`, for a harness whose own suite must be
  watched while it is written.
- From the test-quality methods Codex (OpenAI's coding agent) proposed in the session of
  2026-11-08, listed in the design document: include red/green (it is `red-check`), mutation
  testing with mutmut, changed-line coverage with its weakness stated, a 30-line assertion
  heuristic as a count, and three repeat runs plus reverse order for flakiness. Defer
  property-based testing (a skill capability, not a measure), a bug corpus (needs a real
  repository) and the ESLint rules (a Vitest codebase). Reasons in
  `docs/design/2026-11-08-outcome-evals.md`.

## Tasks

One pull request each, cut from `main`.

1. **Checks.** `outcome-evals/tasks/<name>/{prompt.md,scaffold.sh}` and
   `outcome-evals/checks/<name>/{acceptance.py,probes.sh,naive.patch,reference.patch}` for
   `names-file`, `names-csv`, `format-json`, `repeat` and `defect-whitespace`, plus
   `checks/selftest.sh`. Test: `selftest.sh`, committed first with stub checks that pass
   whatever they are given: its first assertion, that `names-file`'s trap checks fail on
   the naive patch, then fails on a check that passed.
2. **Harness and measures.** `outcome-evals/run.sh` (snapshot, the plugin's copy, two arms,
   five runs, the pinned model, the cost stop, JSON lines), `measures/mutation.sh`,
   `measures/coverage.sh`, `measures/assertions.py`, `measures/flaky.sh`,
   `measures/scope.sh`, `report.py`, and `run.test.sh` with fake agents. Test:
   `run.test.sh` asserts each JSON field, the error status of a measure that cannot run, the
   skip status when mutmut has nothing to score, what the searching fake agent finds (R8),
   both arms' calls and the two contaminated runs (R9), the reporter's table and its
   sentence (R7). It stands a fake `mutmut` and a fake `claude` on `PATH`, so it needs
   neither PyPI nor a model, and both suites are added to `.github/workflows/test.yml`.
3. **The run and the report.** One shake-out run of one task, then the full matrix with five
   runs; the JSON lines committed; `outcome-evals/README.md` with the table, spread and cost;
   the plugin README cites it. Test: `run.test.sh` compares the README's table with the
   reporter's output over the committed lines, and looks for the report's path in the
   plugin README; both fail until the README holds them.

## Checks

`bash outcome-evals/checks/selftest.sh`; `bash outcome-evals/run.test.sh`; the full matrix
with `--runs 5`; R6's command, pasted with its empty output into each pull request's
Outcome. `red-check` is not run on these three pull requests: copied onto the base, each
suite finds no harness to run, which `red-check` calls inconclusive and fails. Red first is
shown by the order of commits, the suite before the code, and the suite's failing output in
Outcome. Inside each scratch repository the harness does run `red-check <base>..HEAD --run
'python3 -m unittest {files}' --strict` over the agent's commits. The independent
reviewer should attack: whether an agent can reach the checks from the scratch repository or
from the plugin's copy; whether any measure that could not run reads as a pass; whether the
mutation score is really over the functions the agent changed; and whether the fake agents
in `run.test.sh` exercise the same code path as a real one.

## Review

Two rounds, the most the skill allows, each by a fresh session with no context but the
record and the repository (`plugins/change-record/bin/record-review`), on 2026-11-14. Each finding was checked against the repository before
anything was changed.

Round 1, on the record of 2026-11-08: 2 critical, 12 important, 13 minor.

- Critical, fixed. The agent would have had no shell: Probed facts now say what `run-eval.sh`
  and `dispatch` each pass, and Decisions give the agent a shell.
- Critical, fixed. The checks would have sat in the folder only the plugin arm is given: that
  arm now gets a copy with no checks in it, and R8 tests that no agent can reach them.
- Important, fixed: the Goal now says both arms see the record convention; R7 and C4 give
  the rule for an answer; R2 defines "outside the task" and "tests weakened"; the README
  was said to label a claim it does not make; mutmut is probed (it needs pytest, has nothing
  to score on the untouched scaffold, names mutants by function); C3 was stale; the judge
  had no task, field or budget and is dropped; the model is pinned (C5); R5 commits the JSON
  lines so task 3's test can run anywhere; C2 has a failure case.
- Added while fixing, not from the review: R1 asks that each check also passes against a
  reference implementation.

Round 2, on the revised record: 1 critical, 10 important, 9 minor.

- Critical, fixed. Nothing kept a plugin installed for the user out of the baseline arm:
  both arms now run with no setting sources, and R9 makes a contaminated run an error.
- Important, fixed: the caller's folder leaked through `OLDPWD` (R8 and Decisions); "every
  check fails" against the naive patch could not hold for plain checks (R1); R8 named a
  transcript the harness did not have (the event stream, Decisions); `modelUsage` can name
  several models (the `init` event's one, C5); R7 had no rule for a short cell; one status
  for a run with several measures (R2); `red-check` would have failed these pull requests
  (Checks); no cap on one run (C2); no requirement on the prompts (R10); task 1's red step
  was the wrong way round.
- Minor, fixed: `run-eval.sh`'s check runs inside the snapshot; directions and cost in R7;
  the suites in CI; where mutmut writes; a check for the README's sentence and for R6; the
  tasks are built by hand; lines added is back in R2; how the fake agent learns the
  plugin's folder.

Open:

- A third arm with no record convention is option D, not built.
- The reviewer's remark that both arms edited `README.md` in the process-eval traces was
  not checked; `README.md` counts as inside the task either way.
- `--max-turns` is not relied on: it is missing from the CLI's help and was not probed.
- No third round was run, so the fixes of round 2 have not been read by a fresh session.

## Outcome

### Task 1, the checks (2026-11-14)

Shipped under `plugins/change-record/outcome-evals/`: `tasks/<name>/{prompt.md,scaffold.sh}`
and `checks/<name>/{acceptance.py,probes.sh,naive.patch,reference.patch}` for the five
tasks, and `checks/selftest.sh`. Beside what the task listed: `tasks/scaffold-base.sh`, the
one scaffold all five start from; `checks/run-checks.sh TASK REPO`, which prints one line a
check and is what the harness will call; and the two small libraries the checks are written
with, `checks/cli.py` with `checks/acceptance_runner.py`, and `checks/probes.lib.sh`.

Forty checks, 25 traps and 15 plain:

    task               traps  plain
    names-file             7      3
    names-csv              6      4
    format-json            5      3
    repeat                 4      3
    defect-whitespace      3      2

One trap of the design is a plain check here: a file with CRLF line ends. Python reads it
right in text mode, so the naive implementation passes it.

Red first, with stub checks that pass whatever they are given: 10 of 126 assertions
failed, two a task, as the task said they would:

    FAIL names-file: the naive implementation: acceptance, trap, stub: fail
         expected [fail] got [pass]
    FAIL names-file: the naive implementation: probe, trap, stub: fail
         expected [fail] got [pass]

With the real checks `selftest.sh` has 177 assertions and passes: against each naive
implementation every trap fails and every plain check passes, against each reference
implementation all pass, and each prompt holds to R10 and gives no trap away.

Use, on implementations written another way than the reference (with `argparse` and
`fileinput`), to see that the checks ask for the behaviour and not for one way of writing
it: `repeat` 7 of 7, `format-json` 8 of 8, `names-file` 10 of 10. `argparse`'s own two-line
refusal passes the probes: they ask for status 2, the input named, and no traceback.

    $ python3 greet.py --names-file nope.txt
    usage: greet [-h] [--names-file NAMES_FILE] [name]
    greet: error: cannot read nope.txt: No such file or directory
    exit 2

Guards in the libraries and in `run-checks.sh`: 16 broken by hand. 13 failed the self-test
at once. Three survived because another guard behind each gave the same exit status; each
of their tests now tells the two apart, and all 16 fail it.

R6: `git diff --stat origin/main..HEAD -- plugins/change-record/skills` prints nothing.

Not done in this task: no agent has run against the checks; `selftest.sh` is not yet in
CI, which task 2 adds with its own suite.

### Task 2, part one: the harness and its measures (2026-11-14)

Shipped under `plugins/change-record/outcome-evals/`: `run.sh` with `run.py` (the scratch
repository, the plugin's copy, the two arms, the pinned model, the budget and time of a
run, the cost stop, one JSON line a run), `measures.py` (the ten measures), `run.test.sh`,
and both suites in `.github/workflows/test.yml`. `.gitignore` there keeps everything a run
leaves but the JSON lines out of the repository. The reporter is part two.

Red first, against a harness that does nothing: 49 of 58 assertions failed. `run.test.sh`
passes with 58, with a fake `claude`, `mutmut` and `coverage` first on `PATH`: no model,
nothing installed. `checks/selftest.sh` passes with 175.

Guards: 39 broken by hand in `run.py` and `measures.py`. 34 failed the suite at once. Five
survived, each for want of a test and not of the guard: two of the environment's cleaning
(the test's own `PATH` and `OLDPWD` never reached the harness; bash drops an `OLDPWD` that
names no folder), two skips that another skip behind them hid, and `README.md` counting as
inside the task. Each has a test now, and all 39 fail the suite.

Use: the shake-out, one real run an arm of `repeat` on Sonnet 5.5, with the real mutmut
3.8.1 and coverage from a virtual environment the harness made. 21 cents in all.

    $ outcome-evals/run.sh --tasks repeat --runs 1 --keep ... --out ...
    outcome-evals: repeat plugin 1: ok, 0.15 dollars, 0.15 in all
    outcome-evals: repeat baseline 1: ok, 0.06 dollars, 0.21 in all

    plugin:   model claude-sonnet-5-5, the skill listed and called, 14 turns
              hidden 2 of 3, probes 3 of 4, mutation 29 of 45 in main and positive_int,
              coverage 12 of 12 changed lines, red-check: 1 file, red on the base
    baseline: model claude-sonnet-5-5, no skill, 4 turns
              hidden 2 of 3, probes 4 of 4, mutation 40 of 46 in main and usage_error,
              coverage 18 of 18 changed lines, red-check: 1 file, red on the base

What it showed that the fakes could not: the event stream is read right (model, skill,
turns, cost); `--setting-sources ""` with `--plugin-dir` gives the skill to one arm only;
mutmut and coverage give real numbers on what a real agent wrote. And two checks that were
not fair, changed as Decisions say: with them both arms pass 2 of 2 and 4 of 4 on this
task. The checks are now 39, 25 traps and 14 plain.

Error path, by the fakes only: an agent that fails, runs out of time, is stopped at its
budget, looks at a check, or has the skill in the wrong arm; a tool that cannot run; the
cost stop. None of these happened in the shake-out.

R6: `git diff --stat origin/main..HEAD -- plugins/change-record/skills` prints nothing.

Not done here: the reporter, which is part two, and the matrix. One run an arm says nothing
about the skill; at the shake-out's price the fifty runs would cost about five dollars.

### Task 2, part two: the reporter (2026-11-14)

Shipped: `outcome-evals/report.py FILE.jsonl... [--runs 5]`, which prints a table a task
with one row an arm (the mean and the range of each measure over the runs that count, the
two counts as numbers only) and then one sentence a measure by R7's rule; and its tests in
`run.test.sh`.

Red first, against a reporter that prints nothing: 16 of 75 assertions failed, all of them
the reporter's. `run.test.sh` passes with 75.

Guards: 9 broken by hand in `report.py`; all 9 failed the suite.

Use, on the two lines of the shake-out (`--runs 1`, since one run an arm is all there is):

    Model: claude-sonnet-5-5. 2 of 2 runs count; a run that was cut off, saw a check or had
    the skill in the wrong arm does not.

    | Arm | Runs | Hidden tests | Probes | Mutation | Coverage | Red tests | ... | Turns | Cost |
    | plugin | 1 of 1 | 0.67 | 0.75 | 0.64 | 1.00 | 1 of 1 | ... | 14.0 | 0.15 |
    | baseline | 1 of 1 | 0.67 | 1.00 | 0.87 | 1.00 | 1 of 1 | ... | 4.0 | 0.06 |

    - Probes: no effect shown. The plugin arm is ahead on 0 and behind on 1 of 1 decided
      tasks; 0 of 1 tasks were not decided.

Those lines were measured before the two checks were made fair, and one run an arm has a
range of nothing, so any difference reads as ahead or behind: it shows the reporter, not
the skill. Error path: lines that name two models give no table and exit 2.

R6: `git diff --stat origin/main..HEAD -- plugins/change-record/skills` prints nothing.

Not done: the matrix and its report, which are task 3.
