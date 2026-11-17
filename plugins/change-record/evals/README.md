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
| `red-first-workflow` | The same as `red-first` where the code is a CI workflow file: a test of the workflow is seen failing before `.github/workflows/test.yml` changes. Added 2026-11-17 and not yet run, so it has no row in the results below |

The `skill-fired` grader in each case is the activation indicator under with/without ablation,
not part of the score. `evals/cases.test.cjs` checks that every case is well formed and that
the scaffold builds, without running an agent.

`red-first-workflow` starts from a repository of its own: its `scaffold.sh` runs the shared
scaffold and then commits a workflow file and a test that reads it. The workflow is not in
the shared scaffold because `outcome-evals/` builds its tasks on that scaffold too, and its
checks count the files a task may touch.

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

A fourth, on 2026-11-17 and after the numbers above: `saw-it-fail` counted a failing test run
made in the very command that wrote the code (`sed -i ... greet.py && python3 -m unittest`),
because its guard looked at where the tool call begins and not at its command. The other
grader of `red-first` already failed such a run, so it scored half and now scores nothing. No
trace of the runs above is kept, so whether any of them was such a run is not known; with
the plugin the case scored 1.00, which no such run could have given.

## Running them

    claude plugin eval plugins/change-record --scaffold --allow-tools Bash Write Edit --trust-plugin --no-publish --runs 3 -j 4

The runner mounts the scaffold repository read-only for shell commands, so the prompts tell
the agent not to branch or commit; an agent that tries will stop and report the sandbox,
which is the right behaviour and a zero score. The runner needs bubblewrap and socat on
Linux. Results land in `evals/results/`, which is not committed.

## The same cases as an `evals.json`, for tools that are not Claude's

The open Agent Skills guide (agentskills.io, "Evaluating skill output quality") keeps a
skill's test cases in `evals/evals.json` inside the skill's folder: a prompt, a description of
the expected output, input files and plain statements to check. `export-evals-json` writes
that file from the case folders above, into `../skills/change/evals/`:

    plugins/change-record/evals/export-evals-json           # write evals.json, checks.json and the input files
    plugins/change-record/evals/export-evals-json --check   # exit 1 if they have drifted

The case folders are the source. Change a prompt or a grader there, run the first command and
commit both; `cases.test.cjs` runs the second, so CI fails on a file that was edited by hand
or left behind. What each entry holds:

| Field | From |
|---|---|
| `id`, `name` | 1 to 9 in the folders' alphabetical order, and the folder's name (`name` is outside the guide; the tools read so far accept it) |
| `prompt` | `prompt.md`, after one sentence saying which folder of the input files is the repository |
| `expected_output` | the `description` in `case.yaml` |
| `files` | the files the case's `scaffold.sh` commits. Cases that start from the same repository share a folder: `skills/change/evals/files/repo/` for the one most cases start from (the six files of `_scaffold/greet.sh`), and `files/repo-<case>/` for any other, named after the first case that starts from it |
| `assertions` | one per scored grader: the `# assertion:` line in the grader's top block |

Every scored grader carries its statement on that line, so a new grader without one fails the
tests. `skill-fired` has none: it asks whether Claude's Skill tool was called.

What does not carry over, and what to expect from another runner:

- **The graders become statements.** Claude's runner checks 24 of the 31 with a pattern, a
  file test or a count of tool calls; in `evals.json` all 31 are sentences. The guide does not
  say a model must judge them all: for what code can check (a file exists, a line is there) it
  says to use a verification script, as more reliable than a model. `verify`, below, is that
  script. It covers 15 of the 31; a runner that follows only `evals.json` and does not call it
  hands all 31 to its judge.
- **Nine statements are about what the agent did**, and in what order (a test seen failing
  before the code, a probe before the record). They begin "The transcript shows". The guide
  grades a run's outputs and calls an assertion that cannot be checked from the output alone
  one to fix. These nine are kept because the order of work is most of what the skill adds;
  a runner has to give its judge the run's transcript for them, and one that does not cannot
  grade them.
- **Some statements pass with and without the skill.** The guide says to remove those, since
  they show nothing about the skill. In the results above the baseline also wrote its record
  in every run, so the five "The file ... exists" statements, and the two cases that tie at
  full score, are of that kind. They are kept here to match the case folders one for one.
- **The comparison with and without the skill is the runner's to make.** The guide says to
  run each case both ways; the file does not record it.
- **The repository is plain files with no git history**, and where a runner puts input files
  is not defined by the guide. The first sentence of each prompt is there for that.
- **The cases need an agent that edits files and runs commands.** A runner that sends the
  prompt to a chat model with the skill in its context (`agent-skills-eval` 0.1.1 does) can
  produce text for a judge to read, and nothing that the statements about files or the
  transcript could be checked against.
- Nothing here has been run against Codex or Cursor. The file's shape was checked against the
  guide's source and against one third-party loader's source by reading them.

### Checking a run without a model: `verify`

`skills/change/evals/verify` checks the statements code can check against the folder a run
left, and prints what the guide calls `grading.json`. It needs Python 3.8 and the skill's
`evals/` folder, nothing else of this plugin:

    skills/change/evals/verify record-before-code path/to/the/run/repo --final-message final.md

The first argument is a case's name or its number in `evals.json`. The second is the run's
copy of the repository after the agent worked in it. `--final-message` names a file holding
the agent's last message, for runners that keep it. On a real run of that case (2026-11-12):

    {
      "eval": "record-before-code",
      "assertion_results": [
        {"text": "The final message contains the line \"Change: docs/changes/2026-11-08-shout.md\".", "passed": true,
         "evidence": "the final message has: \"Change: docs/changes/2026-11-08-shout.md\""},
        {"text": "The file docs/changes/2026-11-08-shout.md exists.", "passed": true,
         "evidence": "docs/changes/2026-11-08-shout.md is there (1881 bytes)"},
        ...
      ],
      "not_checked": [
        {"text": "The final message reports the --shout flag implemented and the test suite passing.", "why": "needs a judge"},
        {"text": "The transcript shows docs/changes/2026-11-08-shout.md was written before greet.py was first changed.", "why": "needs the run's transcript"}
      ],
      "summary": {"passed": 4, "failed": 0, "total": 4, "pass_rate": 1.0}
    }

It exits 0 when every statement it checked passed, 1 when one failed, 2 when it could not
run. `not_checked` is not in the guide's `grading.json`: it is what is left for a judge.

| Checked from | Statements | How |
|---|---|---|
| the files | 13 | a file is there (5), a file holds the grader's pattern (6), `docs/changes/` holds only what it started with (1), `greet.py` is the input file (1) |
| the final message, if given | 2 | the message holds the grader's pattern |
| not checked | 16 | 7 need a judge, 9 need the transcript |

What it checks is `evals/checks.json`, which `export-evals-json` writes from the graders: the
path of a `file_exists` grader, and the pattern and flags of a `regex` grader that reads a
file or the last message. So a pattern is written once, in the grader. A grader that reads
the trace gets no check, unless its top block says how the same thing shows in the folder:
`# check: unchanged PATH` or `# check: only DIR NAME...`. The generator refuses a grader it
cannot turn into a check faithfully (a pattern that must be absent, a flag or a construct
Python's regular expressions lack) instead of writing a looser one.
