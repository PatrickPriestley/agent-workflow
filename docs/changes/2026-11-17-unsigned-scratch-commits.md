---
id: 2026-11-17-unsigned-scratch-commits
tier: 1
status: open
requester: Patrick Priestley, in chat on 2026-11-17, after a run of the mutation checks in a cloud container exhausted its signing service
approvers: []
---
# No scaffold or test signs a commit in a scratch repository

## Goal

Every commit, merge and tag that an eval scaffold or a test suite makes in a scratch
repository is made with signing off, whatever the machine's git configuration says. The
suites pass with a signing program that always fails configured globally, and that program
is never called. Commits made in the real repository are signed as before.

## Probed facts

- Reported (the requester, 2026-11-17): a run of the mutation checks in a cloud container
  made several thousand signed commits; the container's signing service ran out of file
  handles, and from then on every test that commits failed with `fatal: failed to write
  commit object`.
- Verified against the real system (this container, git 2.43, 2026-11-17): the global
  configuration sets `commit.gpgsign=true`, `gpg.format=ssh` and `gpg.ssh.program`. Every
  scaffold and suite commits with whatever that configuration says: none sets signing.
- Verified against the real system (this container): with `GIT_CONFIG_GLOBAL` naming a
  configuration whose `gpg.program` and `gpg.ssh.program` are a script that records its call
  and exits 1, `git commit` fails with `fatal: failed to write commit object`, the same
  message as the incident. Run that way, 18 of the 21 suites fail (between 1 and 165
  assertions each), `export-evals-json --check` exits 2, and the script is called 454 times
  in one pass over the suites. The same suites with signing off all pass, except the one
  below.
- Verified against the real system (this container): with `tag.gpgsign=true`, a lightweight
  `git tag NAME` fails with `fatal: no tag message?` before any signing program is called.
  So a tag needs `-c tag.gpgsign=false` even when it is not annotated.
- Verified against the real system (this container): `skills/plan/scripts/test-pre-commit-green-phase.sh`
  fails "an unreadable marker fails closed" with signing off too. The container runs as root,
  which reads a file whatever its mode. It is not part of this change.
- Verified against the real system (this container): the container's environment sets
  `GIT_CONFIG_COUNT` and three `GIT_CONFIG_KEY_n` entries (credentials and URL rewriting), so
  a suite that set signing through those variables would replace them.
- Exact source (`plugins/change-record/bin/dispatch`, `run_task`): dispatch commits the done
  marker itself, in a worktree of the repository it runs in. `pr-agent/scratch.sh` commits in
  a worktree of the repository it runs in. `skills/incident-to-eval/scripts/run-eval.sh` tags
  a worktree of the real repository (`new_sandbox`) and commits and tags a fresh repository
  (`new_snapshot`). In use each of the first three is the real repository; in the suites it is
  a scratch one.

## Decisions

- Each command a scaffold or test runs in a scratch repository passes the setting itself:
  `git -c commit.gpgsign=false commit`, and the same for `merge` (a merge can make a commit),
  and `-c tag.gpgsign=false` for `tag`. Where a suite wraps git in a helper (`commit`, `at`,
  `commit_main`), the helper carries it. Rejected: `GIT_CONFIG_COUNT` set at the top of a
  suite, which would replace the entries the environment already sets; and setting it in each
  scratch repository's own configuration, which is less visible at the commit and would also
  switch off signing for the agent an eval runs there.
- Where the commit is made by the tool under test (dispatch's done marker, `scratch.sh`'s two
  branches), the tool is not changed: it commits in the real repository in use, and that
  commit is signed as the user's configuration asks. The suite sets `commit.gpgsign false` in
  the scratch repository it runs the tool in instead.
- `run-eval.sh`'s `new_snapshot` builds a scratch repository, so its commit and tag pass the
  settings. `new_sandbox` tags a worktree of the real repository and is left as it is.
- Text that only quotes a git command (a transcript fixture, an expected denial such as
  `git commit -m x`) is data, not a command, and is not changed.
- CI configures a signing program that always fails, with `commit.gpgsign` and `tag.gpgsign`
  on, before the suites of both test jobs. A suite or scaffold that later commits or tags
  without the settings then fails in CI the first time, rather than in the next container
  whose signing service runs dry. Rejected: relying on this record and review alone.

## Tasks

1. The failing test, then the settings on every commit, merge and tag in a scratch
   repository, and the CI step. Test: `evals/cases.test.cjs` runs every scaffold of the plugin
   (the eval cases, the outcome-eval tasks and `ci/scratch.sh`) with a failing signing program
   configured globally, and checks each succeeds and the program is not called;
   `bin/ci-workflow.test.sh` checks the CI step comes before the suites. Red today: the
   scaffolds fail with `failed to write commit object`, and the workflow has no such step.

## Checks

With `GIT_CONFIG_GLOBAL` naming a configuration whose signing program records its call and
exits 1: every suite CI runs, `node --test plugins/change-record/evals/cases.test.cjs`,
`bash plugins/change-record/outcome-evals/checks/selftest.sh`,
`bash plugins/change-record/outcome-evals/run.test.sh` and the `bin/*.test.sh` suites pass,
and the program is called 0 times. `plugins/change-record/evals/export-evals-json --check`
exits 0. CI on the pull request runs the suites with its own failing signer.

## Outcome

