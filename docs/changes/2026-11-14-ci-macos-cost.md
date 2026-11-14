---
id: 2026-11-14-ci-macos-cost
tier: 1
status: done
requester: Patrick Priestley, in chat on 2026-11-14 ("Can we fix 3", to "Cut what CI costs. For example, run the macOS jobs only on `main` instead of on every PR push.")
approvers: []
---
# CI runs macOS on every pull request only where it is free

## Goal

Stop the macOS jobs from using up the account's Actions allowance. On 2026-11-13 GitHub
stopped starting any job for this repository; the likely cause is that allowance, and the
macOS jobs are most of what each run costs.

## Probed facts

- Verified against the real system (GitHub's API for this repository, 2026-11-13 and 14):
  since the push of #64 to `main` at 02:02 UTC on 2026-11-13, every job of every workflow
  ends in 2 to 3 seconds with no runner assigned and no log, on `main` and on PR #65, and a
  re-run did the same. `test.yml` has run 171 times in all, macOS jobs included.
- Verified against the real system (the same API): the repository is private.
- Not known: why the jobs are not started. The reason is in the annotation on the run's
  page, which the API does not return. An allowance or spending limit that was reached, or a
  billing problem, is the usual cause; the owner has not confirmed it.
- Assumed, from a web search of GitHub's documentation on 2026-11-14 (the documentation's
  host cannot be reached from this session, so the pages themselves were not read): standard
  GitHub-hosted runners are free for public repositories, macOS included; for private
  repositories a Linux minute is $0.006 and a macOS minute $0.062, about ten times as much.
- Verified against the real system (the jobs of PR #64's run): `test (macos-latest)` took 60
  s and `change-record (macos-latest)` 151 s; the two Linux jobs took 33 s and 111 s. At the
  rates above, and with each job rounded up to a minute, the two macOS jobs are about $0.25
  of a run and every Linux job of the three workflows together about $0.05.
- Exact source (`.github/workflows/test.yml` on `main` at `7f5bc17`): the `test` and
  `change-record` jobs each run on `ubuntu-latest` and `macos-latest`, on every pull request
  event and on every push to `main`. Nothing cancels a run that a newer push to the same pull
  request has replaced. Record `2026-11-11-grading-trust`, R6, asks that every change-record
  suite runs on macOS in CI.
- Assumed, not run: `github.event.repository.private` is in the event of a `pull_request`,
  `push` and `workflow_dispatch` run, and a matrix may be given as `fromJSON` of an
  expression. Both are in common use; neither can be run here while Actions starts no job.

## Decisions

- On a pull request to a private repository the two jobs run on Linux only. On a push to
  `main`, on a run started by hand, and on any event of a public repository, they run on
  Linux and macOS. So R6 still holds on `main`, a macOS failure is seen after the merge and
  not before it, and the day the repository is public the pull requests get macOS back with
  no further change. Rejected: macOS on `main` only whatever the repository is, which gives
  up the check before merge where it costs nothing; and dropping macOS, which is how the
  suites broke there before.
- `workflow_dispatch` is added, so the whole matrix can be run on a branch before a merge
  that might behave differently on macOS.
- A run of a pull request is cancelled when a newer push to that pull request starts one.
  Runs on `main` are never cancelled: each merge keeps its own result.
- A test reads the workflow as text and pins these, as `pr-agent/workflow.test.sh` does for
  its workflow. It does not show that GitHub evaluates the expression as intended; only a
  run does, and the Outcome says whether one has.

## Tasks

1. `.github/workflows/test.yml`, `bin/ci-workflow.test.sh` and its step in the `test` job.
   Test: `bin/ci-workflow.test.sh`; it fails today because the matrix is fixed, there is no
   `workflow_dispatch` and nothing is cancelled.

## Checks

`bash bin/ci-workflow.test.sh`. Real use is the first pull request and the first push to
`main` after Actions starts jobs again: the pull request must show two `test` and
`change-record` jobs on Linux and none on macOS, and the push all four. The reviewer should
attack: a pull request on which no job runs at all, and a required status check named after a
macOS job that now never reports.

## Outcome

Shipped: `.github/workflows/test.yml` takes the runners of its `test` and `change-record`
jobs from one expression, can be started by hand, and cancels a pull request's run when a
newer one starts; `bin/ci-workflow.test.sh` (13 assertions) pins that, and runs as a step
of the `test` job.

Red first: 6 of the 13 assertions failed on the workflow as it was. 9 guards broken by
hand, in the workflow's text; all 9 failed the test. The workflow parses as YAML, and the
suites beside it pass (`commit-gate` 81, `pr-size` 41, `pr-agent/workflow` 61,
`pr-agent` 11).

Verified against the real system (the jobs GitHub made for three runs on 2026-11-14, read
through the GitHub API from this session): the expression gives the lists it was written to
give on this private repository.

- Pull request #66, this change: `test (ubuntu-latest)` and `change-record (ubuntu-latest)`,
  no macOS job.
- The push to `main` that merged it (run 43605788455): `test` and `change-record` on
  `ubuntu-latest` and on `macos-latest`; `pr size` and `conventional PR title` skipped.
- Pull request #67, the first opened from the merged workflow (run 43606174472): the two
  suites on `ubuntu-latest` only, with `pr size` and `conventional PR title`.

Not shown: no job of those runs was started. GitHub has started no job for this repository
since 2026-11-13; each ended within three seconds with no runner and no log. So the
`CI workflow` step has not run on a runner, on Linux or macOS, and the cancelling of an
older run has not been seen. The list for a public repository (both systems on a pull
request) has not been evaluated by GitHub either: the repository is private.

What the reviewer was asked to attack:

- A pull request on which no job runs. On a private repository the list is
  `["ubuntu-latest"]`, never empty.
- A required status check named after a macOS job. If branch protection requires
  `test (macos-latest)` or `change-record (macos-latest)`, a pull request would wait for a
  check that no longer reports. This session cannot read the repository's protection rules;
  the owner has merged with macOS jobs unfinished before, which suggests there is none.

