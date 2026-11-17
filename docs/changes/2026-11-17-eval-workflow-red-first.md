---
id: 2026-11-17-eval-workflow-red-first
tier: 1
status: done
requester: Patrick Priestley, in chat on 2026-11-16 ("What's left to implement for self improvement"; then "Run it" on the first proposal, whose record names this case as the next step)
approvers: []
---
# An eval case shows whether a change to a CI workflow file is made test first

## Goal

The change skill's evals gain a case in which the code to change is a CI workflow file,
so that an edit to the skill about such files can be tried with the edit and without, as
concern C5 of record `2026-11-12-session-quality` asks before any edit is kept.

## Probed facts

- Exact source (`docs/changes/2026-11-12-session-quality.md`, task 3): `transcripts
  propose` drafted two edits to step 3 of the change skill from one labelled failure of
  `red-first`. Both begin by saying that a CI workflow file is code and is not edited
  before a test run has reported a failed test. They then differ on a test that can run
  only in CI: one says to push the test or job alone as a draft and read its red log, the
  other to stop and report.
- Exact source (`plugins/change-record/evals/red-first/`): the one case for this step
  asks for a flag in `greet.py`, whose tests run on the machine. Its two scored graders
  are regexes over the ordered trace: a unittest run before the first write of
  `greet.py`, and a unittest run whose own result reports a failure before that write. A
  write is the Write or Edit tool on the file, or a shell redirect, `tee`, `cp` or
  `sed -i` onto it.
- Exact source (`plugins/change-record/evals/_scaffold/greet.sh`): the shared scaffold is
  a Python CLI with one test file, committed on `main`, with `docs/changes/` from the
  plugin's templates. It has no workflow file.
- Exact source (`evals/cases.test.cjs`): a case needs `case.yaml` naming itself and
  `scaffold.sh`, a `prompt.md`, and graders of a known type with `skill-fired.md` among
  them; a record id in a prompt is read as `2026-11-08-<slug>`.
- Verified against the real system (this container, 2026-11-17): `node --test
  plugins/change-record/evals/cases.test.cjs` runs 40 tests, none failing. `claude plugin
  eval --help` (Claude Code 2.1.325) lists `--case <glob>`, so one case can be run alone.
- Assumed, not probed: what an agent does with this case, with the plugin or without. No
  run has been made: a run spends model calls and waits for the owner's leave.

## Decisions

- The case is the part both drafts share: a workflow file is code, and a test fails
  before it is edited. The scaffold gives the repository a test of its workflow file, so
  that a failing test can be written and run on the machine. Rejected for now: a case
  for a test that can run only in CI. The two drafts ask for different things there, the
  eval environment can neither push nor run CI, and which of the two the owner wants is
  the owner's to say before a case can hold an agent to it.
- The graders are the two of `red-first`, with the workflow file in the place of
  `greet.py`. Rejected: a grader that reads the final workflow file, which would score
  whether the task was done and not whether it was done test first.
- The case starts from a repository of its own: its `scaffold.sh` runs the shared scaffold
  and then commits the workflow file and its test. Rejected, after it was tried: adding the
  workflow file to the shared scaffold. `outcome-evals/` builds its tasks on that scaffold
  and its checks count the files a task may touch; with two more files its own suites
  failed (1 of 175 and 8 of 91).
- So the export to `evals.json`, which refused cases that start from different
  repositories, now writes a folder for each starting repository: `files/repo/` stays the
  one most cases start from, so the eight earlier cases keep their paths, and another is
  `files/repo-<its first case>/`. `verify` compares a file with the folder of its own case.
  Rejected: leaving the new case out of the export, which would end the rule that the
  export holds every case.
- Found while breaking the guards, and fixed here because the new grader is a copy:
  `saw-it-fail` counted a failing test run made in the command that itself wrote the code.
  The fix is the same one insertion in `red-first` and in `red-first-workflow`. Rejected:
  fixing the copy alone and leaving the first with a hole now known.
- `transcripts propose` still names `evals/red-first` for the step. Its page already says
  to check that the case shows the failure; naming two cases for one step waits until
  this one has been run and shown to measure something.

## Tasks

1. The case `red-first-workflow`: scaffold, prompt, graders, their fixtures in
   `evals/cases.test.cjs`, and the README's row. Test: `node --test
   plugins/change-record/evals/cases.test.cjs`. Red today: there is no such case.
2. Added while building, for the reason in Decisions: the export and `verify` take cases
   that start from different repositories. Same test file. Red before: the export exits 2
   with "the cases start from different repositories".

## Checks

`node --test plugins/change-record/evals/cases.test.cjs`. Real use: `claude plugin eval
plugins/change-record --case red-first-workflow`, with the plugin and without, which
needs the owner's leave for the spend; then the same with each proposed edit in the
skill. Error path: a trace in which the workflow file is written before any test run
fails both graders.

## Outcome

Built test first, on 2026-11-17. The record went in with four failing tests of a case that
did not exist; then the case; then failing tests of an export that refused it, and the
export; then a failing test of `verify`, and its fix; then, from the guard run below, two
failing assertions on `saw-it-fail` and its fix.

```
$ node --test plugins/change-record/evals/cases.test.cjs
# tests 46
# pass 46
# fail 0
$ plugins/change-record/evals/export-evals-json --check; echo $?
0
$ bash plugins/change-record/outcome-evals/checks/selftest.sh | tail -1
passed=175 failed=0
$ bash plugins/change-record/outcome-evals/run.test.sh | tail -1
passed=91 failed=0
```

The case's task done by hand in the repository its scaffold builds, to see that a test of
the workflow can fail first on the machine:

```
$ bash plugins/change-record/evals/red-first-workflow/scaffold.sh && git log --oneline
b95f994 ci: run the tests on push, and test the workflow
d9310e9 greet: initial
$ python3 -m unittest discover -s tests -t . 2>&1 | tail -3
Ran 2 tests in 0.000s

OK
$ (a test added to tests/test_workflow.py: "macos-latest" is in the workflow file)
$ python3 -m unittest discover -s tests -t . 2>&1 | tail -3
Ran 3 tests in 0.001s

FAILED (failures=1)
$ sed -i 's/os: \[ubuntu-latest\]/os: [ubuntu-latest, macos-latest]/' .github/workflows/test.yml
$ python3 -m unittest discover -s tests -t . 2>&1 | tail -3
Ran 3 tests in 0.000s

OK
```

`verify` on that folder, and its error path:

```
$ skills/change/evals/verify red-first-workflow <the folder>
  "assertion_results": [],
  "not_checked": [ ...the two statements, each "needs the run's transcript" ],
exit 0
$ skills/change/evals/verify red-first-workflow /nonexistent
verify: /nonexistent is not a folder
exit 2
```

The error path of the case itself is in the fixtures: a trace in which the workflow file is
written before any test run fails both graders, whether it is written with Edit, Write, a
redirect, `sed -i`, or from inside its folder.

Guards, each broken by hand in a clone: 35 breaks. In the first round 31 of 33 were caught.
The two that survived were gaps in the tests, closed and broken again: a workflow change
and a test run in one command, and which case a shared folder is named for. The first gap
is what showed the hole in `saw-it-fail`, in the new grader and in the one it was copied
from. All 35 are caught on the final code, by the test that failed first for each, with
eight more added after the reviews below:

- `one command that writes the code and runs the tests is not a run before the code`:
  - red-first saw-it-fail: a failing run in the command that writes greet.py counts
- `the committed evals.json and input files are what the case folders give`:
  - export: every case is given the shared folder
  - export: every case lists the shared folder's paths
  - export: every case lists the shared repository's files
  - export: every prompt names repo/
  - prompt: no record id
  - prompt: the tests' command is not given
  - prompt: the workflow file is not named
  - scaffold: no test of the workflow
  - scaffold: no workflow file
  - scaffold: the workflow already runs on macOS
  - scaffold: the workflow's test fails from the start
- `the input files are the scaffold's, and --check fails when a prompt, a statement or a file has drifted`:
  - export: --check does not see a file that differs
  - export: --check does not see a file that should not be there
  - export: --check does not see a missing file
- `the generator refuses a case it cannot state: a grader with no statement, or two; a case that starts from another repository gets a folder of its`:
  - export: --check does not look at a folder no case starts from
  - export: a folder is named for its last case
  - export: a folder no case starts from is left when writing
  - export: the shared folder is the first case's by name, not the one most cases start from
- `the red-first-workflow scaffold adds a workflow file and a passing test of it to the shared repository, and the shared one has neither`:
  - scaffold: the workflow is left uncommitted
- `red-first-workflow: a test run counts only before the workflow file is first written, by a tool or by the shell`:
  - test-run grader: a write by the repository's absolute path is not a write
  - test-run grader: any absolute path is the workflow, a scratch copy too
  - test-run grader: a write from inside `.github/` is not a write
  - test-run grader: a Write or Edit of a scratch copy is a write of the workflow
  - test-run grader: a Write of the workflow is not a write
  - test-run grader: a shell redirect onto the workflow is not a write
  - test-run grader: a write and a run in one command count as a run first
  - test-run grader: an Edit of the workflow is not a write
  - test-run grader: it watches greet.py, not the workflow file
  - test-run grader: sed -i on the workflow is not a write
  - test-run grader: writing the workflow's test counts as writing the workflow
- `red-first-workflow: saw-it-fail needs a failing test run before the workflow file changes`:
  - saw-it-fail: a write by the repository's absolute path is not a write
  - saw-it-fail: any absolute path is the workflow, a scratch copy too
  - saw-it-fail: a write from inside `.github/` is not a write
  - saw-it-fail: a Write or Edit of a scratch copy is a write of the workflow
  - saw-it-fail: a failing run in the command that writes the workflow counts
  - saw-it-fail: a green run counts
  - saw-it-fail: a shell redirect onto the workflow is not a write
  - saw-it-fail: an Edit of the workflow is not a write
  - saw-it-fail: any error result counts, a failed test or not
  - saw-it-fail: it watches greet.py, not the workflow file
  - saw-it-fail: sed -i on the workflow is not a write
- `verify compares an unchanged file with the repository its own case starts from, not with another case's`:
  - verify: every case is compared with repo/

The review of the pull request found that a shell write to the workflow file by an absolute
path such as `/tmp/repo/.github/workflows/test.yml` passes both graders. That is meant: the
eval runner's repository is always `<tmp>/home/cwd/` (all four real traces above), so such a
path is a scratch copy, which `red-first` stopped counting as code in its third review. What
was missing was a fixture for each side of it in this case: a write by the repository's own
absolute path fails both graders, and a scratch copy does not. Each was broken by hand both
ways: with the `/cwd/` path taken out, and with any absolute path counted, as the review
proposed.

Its third pass found two more, both real and both fixed test first in the two graders:
`cd .github && sed -i ... workflows/test.yml` was not seen as a write of the workflow, and a
Write or Edit of a scratch copy (`/tmp/try/.github/workflows/test.yml`) was, which the shell's
rule above does not count. A tool's write now counts only at the repository's own path, and
the shell's at `workflows/test.yml` too. Each of the two pieces was put back in each grader
and caught. The four real traces were scored again with the changed graders: the same eight
verdicts.

During the second round the container's commit signing began to fail (its session manager
ran out of file handles), which failed every test that commits a scratch repository. The
five breaks whose results that touched were run again with signing off for the scratch
repositories, and the list above is from those runs.

The real use, with the owner's leave ("Yes", in chat on 2026-11-17), on the final code:

```
$ claude plugin eval plugins/change-record --case red-first-workflow --scaffold \
    --allow-tools Bash Write Edit --trust-plugin --no-publish --runs 2 -j 4 --max-cost-usd 2
Claude Code 2.1.326; 4 runs, $0.44, 24 seconds
with the plugin:    1.00 and 0.50 (mean 0.75), the skill fired in both
without:            0.00 and 0.00
delta:              +0.75
```

Each of the eight verdicts read against its trace by hand, and each is right:

| Run | Before the workflow changed | `test-run-before` | `saw-it-fail` |
|---|---|---|---|
| with 1 | added a test that `macos-latest` is in the workflow; `Ran 3 tests ... FAILED (failures=1)`; then the edit; then `Ran 3 tests ... OK` | pass | pass |
| with 2 | ran the tests (2, OK), then the edit; no failing test | pass | fail |
| without 1 | read the files, then the edit, then ran the tests | fail | fail |
| without 2 | the edit at its third call, then ran the tests | fail | fail |

So the case tells the plugin from no plugin, and the graders read real traces of a workflow
edit as the fixtures said. The second run with the plugin is the failure the session behind
the proposals showed: it treated a green run as enough before editing the workflow. That is
the run an edit to the skill has to change.

The error path, in the same run: every shell command in this runner version reported exit 1
and `Read-only file system`, from the sandbox's own tracking of the working directory, after
the command's real output. The graders did not take that for a failed test: a green run so
flagged did not pass `saw-it-fail` (with 2), since it looks for unittest's own failure in
the call's own result.

Not done, and not verified:

- Two runs an arm. With so few, one run moves a mean by half; the result says the case
  can separate the arms, not by how much.
- The graders see a write of the workflow file by the Edit and Write tools, a redirect,
  `tee`, `cp` and `sed -i`. A write from inside a script (`python3 -c`, `yq -i`) is not
  seen, as in `red-first`.
- `verify` has nothing to check for this case: both statements are about the transcript.
  Its change is held by a test with a case made for it, not by a real one.
- The case for a test that can run only in CI is not written: see Decisions.
- `red-first`'s graders still count a Write or Edit of a scratch copy of `greet.py` as a write
  of the code, unlike its shell rule. That fails a run, never passes one, and no earlier trace
  is kept to say whether any run did it; it is left to a change of its own.
- The comparison C5 asks for, the case run with each proposed edit in the skill and
  without, is a change of its own: the edits were drafted on an older skill and must first
  be made again on the current one.
