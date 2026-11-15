---
id: 2026-11-15-suites-on-macos
tier: 1
status: done
requester: Patrick Priestley, in chat on 2026-11-15 ("Continue development work on the public"); the first CI runs in the public repository showed the failures
approvers: []
---
# The plugin's suites pass on macOS again

## Goal

The `change-record (macos-latest)` job is green: the four suites that fail there pass, or
the one failure that may be a fault in the tool is explained.

## Probed facts

- Verified against the real system (GitHub Actions in `PatrickPriestley/agent-workflow`,
  2026-11-15, the `change-record (macos-latest)` job of run 43682153558 on `main` at
  `5469580` and of run 43684023930 on pull request 1): both fail the same 23 assertions
  with the same details, in four suites. The Linux job of both runs passes every suite.
  The runner has bash 3.2.57, Python 3.15.2 and BSD `sed`.
- Verified against the real system (the same logs): `record-check.test.sh` fails 20
  assertions named "<suite>.test.sh stops when it cannot make its temporary folder". The
  suites it starts with `TMPDIR` naming a folder that is not there run to their end and
  print `ok` lines, and the step takes 220 to 300 seconds where Linux takes 5.
- Exact source (`bin/record-check.test.sh`): it starts each suite with
  `TMPDIR="$TMPROOT/no-such-folder"` and expects the suite's `mktemp -d` to fail. Assumed:
  macOS's `mktemp -d` with no template does not fail on a `TMPDIR` it cannot use.
- Verified against the real system (the same logs): `transcripts-judge.test.sh` fails "the
  brief is Appendix A of the record, word for word" after `sed: 1: "1,/./{/^$/d}": extra
  characters at the end of d command`. The expression is from task 1 of record
  `2026-11-15-checkable-judges`.
- Verified against the real system (the same logs): `outcome-evals/run.test.sh` fails
  "OLDPWD is dropped whatever it holds ...; PWD is the scratch repository", `expected
  [True] got [False]`.
- Exact source (`outcome-evals/run.py`, `agent_env` and `run_one`): the agent is given
  `PWD` set to the folder `tempfile.mkdtemp` returned. Assumed: on macOS that is
  `/var/folders/...`, a link to `/private/var/folders/...`, which is what the agent's own
  `os.getcwd()` gives, so the two differ.
- Verified against the real system (the same logs): `transcripts-store.test.sh` fails
  "addresses are redacted exactly as the one pattern redacts them", `expected [same 30012]
  got [differ 11539]`: the address redactor and the single pattern it stands in for
  disagree on 18,473 of 30,012 made-up strings.
- Verified against the real system (this container, Linux, 2026-11-15): the same test
  program under Python 3.12.3, 3.13.18, 3.14.6 and 3.15.0b4 gives no difference, on the
  same 30,000 strings (their hash is the same under each). So the difference is of the
  runner, not of the Python version alone, and is not explained.

## Decisions

- The check that a suite stops is given a `mktemp` that fails, first on `PATH`. Rejected:
  a `TMPDIR` that is not there, which is what fails to fail on macOS; and skipping the
  check on macOS, which would leave the guard untested where the trap it guards against
  was first seen.
- The record's appendices are read with Python, not `sed`. Rejected: a `sed` expression
  both GNU and BSD take; the suite already needs Python and one reader is easier to trust
  than two dialects.
- The harness gives the agent the real path of its scratch folder. Rejected: comparing
  real paths in the test, which would leave an agent on a Mac with a `PWD` that is not
  where it is.
- Decided from the runner's answer: the address redactor is right and is not changed.
  The test's program is moved out of the here-document inside `"$( )"` into a file. Bash
  3.2 expands braces in such a here-document, so the pattern's `{2,}` reached Python as
  `2`. Rejected: writing the pattern without braces, which leaves the trap for the next
  program put there.
- Until that answer came: the address redactor is not changed until the difference is seen. The test now prints
  the first strings on which the two disagree and the Python that ran it; the next macOS
  run shows them, and the fix, in the tool or in the test, follows in this same change.

## Tasks

1. The three fixes whose cause is known, and the test that says which addresses differ.
   Test: the suites themselves, on the macOS runner. Red today: 22 assertions there.
2. The address redactor on macOS, once the run of task 1 shows the strings.

## Checks

`bash plugins/change-record/bin/record-check.test.sh`, `transcripts-judge.test.sh`,
`transcripts-store.test.sh` and `outcome-evals/run.test.sh` on Linux here, and the
`change-record (macos-latest)` job of the pull request, which is the real use: nothing
here can stand in for a Mac.

## Outcome

Task 1, three causes fixed, seen on the macOS runner (run 43712625701, `change-record
(macos-latest)`): `record-check.test.sh` 117 passed and none failed, in 16 seconds where it
had taken 220 to 300; `transcripts-judge.test.sh` 280 and none; `outcome-evals/run.test.sh`
91 and none. One assertion was left, in `transcripts-store.test.sh`.

Task 2, the address test. The first run with the strings printed showed that the
redactor redacts and the test's own pattern leaves every string as it was:

```
input '-.@a.co--.jane.doe@example.org-1b@@é.com' | redactor '<redacted:email>@example.org-1b@@é.com' | pattern '-.@a.co--.jane.doe@example.org-1b@@é.com' | python 3.15.2
```

The second (run 43714085731), with the pattern printed, showed why:

```
the pattern as compiled: '[A-Za-z0-9._%+-]+(?:@|%40)[A-Za-z0-9-]+(?:\\.[A-Za-z0-9-]+)*\\.[A-Za-z]2' | it finds 'jane.doe@example.org': False
  '[A-Za-z0-9._%+-]+(?:@|%40)[A-Za-z0-9-]+' finds: 'jane.doe@example'
```

The test wrote `[A-Za-z]{2,}`; Python was given `[A-Za-z]2`. The program was a
here-document inside `"$( )"`, and bash 3.2 on the runner expanded the braces. So the
difference was in the test, on one shell, and the tool redacts addresses on macOS as on
Linux. The cause was not found by reading: it took two runs on the runner, each made to
say more. That the fix holds there is shown by the macOS job of the pull request that
carries it.

Not done: other here-documents inside `"$( )"` were not searched for a brace word of
that kind; the suites that pass on the runner hold none that changes a result.
