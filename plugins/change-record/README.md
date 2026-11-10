# change-record

A second plugin in this repository, separate from `agent-workflow`, which it leaves as it is.
It is the design in `docs/design/2026-11-07-one-record-sdlc.md` made concrete:

- **One change record per change**, `docs/changes/<id>.md`, that grows with the change. It
  replaces the design note, intent, spec and plan with one file whose sections depend on the
  tier. Problem and Requirements are the PRD, Probed facts and Decisions the design document,
  Tasks the ticket breakdown: one file, next to the code, as long as the change needs.
- **A tier by risk**, from a six-question checklist, not by how many files change. Tier 0
  (no behaviour change) needs no record. Tier 1 (the requester decides, one PR, reverts
  cleanly) has no human gate before code. Tier 2 (hard to undo, crosses a boundary, needs
  agreement, more than one PR) has exactly one: the record is approved before code.
- **Evidence CI can check**, instead of sentences in a PR body:
  - `bin/red-check`: every test file a PR adds or changes must fail on the base commit.
    Language-agnostic; it needs one line saying how the repository runs named test files.
  - `bin/record-check`: the PR names a record that parses, has its sections, and for tier 2
    is approved on the base before code.
- **Short rules** (`RULES.md`, eight lines) and **one skill** (`skills/change`) that loads
  its references only when a step needs them.

## Install

As a Claude Code plugin, from this repository's marketplace:

    claude plugin marketplace add PatrickPriestley/agent-workflow
    claude plugin install change-record@agent-workflow

The skill then refers to this plugin's files through `${CLAUDE_PLUGIN_ROOT}`. For other
agents, point their instructions file at `RULES.md` and put `skills/change` where they read
skills (`~/.agents/skills/change`), as `install.sh --wire` does for the other plugin.

## Three levels of adoption

The checks are optional. The record and the tiers are the change to how you work; the
scripts and the workflow are enforcement you add when a convention needs to hold without
anyone's cooperation. Start at the first level.

**1. Record only (the default).** Install the plugin and copy `templates/docs-changes/` to
`docs/changes/` in the repository (the tier checklist and the template). The agent writes the
record, sets the tier, and names the record on a `Change:` line in the PR body. The tier is a
judgment you read in the record, not a gate. Tier 2 is a convention: the agent stops after
writing the record and asks, in chat or by opening the record-only PR, and no code PR opens
until you have said yes. Nothing is vendored and no workflow runs. This is enough for one
person or a small team that reads its own records.

**2. Record plus a local red check.** As above, plus the agent runs `bin/red-check` before
pushing. It is one bash script that needs only git and one line saying how the repository
runs a named test file, and it shows whether each changed test really failed on the base
without any CI. Put it on your PATH (link `bin/red-check` into `~/.local/bin`, or call it
as `${CLAUDE_PLUGIN_ROOT}/bin/red-check` from the skill) and, if you like, set
`git config redcheck.run '<command> {files}'` once per repository.

**3. Full CI.** For a team where the gate must hold without cooperation, or where PRs come
from agents nobody watches. Copy `bin/red-check` and `bin/record-check` to
`.github/scripts/change-record/`, and `workflows/change-record.yml` to `.github/workflows/`;
set `TEST_CMD`. The workflow runs the vendored copies from the repository's own checkout and
fetches nothing at run time, so a change in this repository cannot run code in yours; update
by copying again and reviewing the diff. `record-check` then enforces the record and the tier
2 approval gate on every PR, and `red-check` runs with `--require --strict`.

At any level, set the repository's squash-merge message to "pull request title" (Settings,
Pull Requests), so the commit rules the hooks enforce are what land on the default branch,
and consider `commit-gate enable` and `pr-size` from the `agent-workflow` plugin; the skill
uses `pr-size` for sizing when it is installed and says so when it is not.

## The commands

    red-check [BASE..HEAD] --run 'CMD {files}' [--match GLOB]... [--link DIR]... [--red-pattern REGEX] [--require] [--strict] [--github] [--json]
    record-check [BASE..HEAD] [--body FILE] [--github] [--json]
    dispatch RECORD [--task NAME] [--dry-run] [--no-push] [--fresh] [--base REF] [--remote NAME] [--agent CMD] [--red-run CMD] [--red-match GLOB]... [--worktrees DIR]

`red-check` checks out the base commit in a temporary worktree, copies in each changed test
file at the head's version one at a time, runs the command, and gives each file one of three
verdicts. **Red**: the run failed with an assertion marker in its output, so the test shows
the change is needed. (A changed file under a test directory in which the runner finds no
tests, such as a conftest, a fixture or a helper, is reported as **no tests** and not judged
at all; if every changed file is like that, the run counts as no test files changed.) **Green**: the run passed on the base, so the test proves nothing;
this fails the check. **Inconclusive**: the run failed without reaching an assertion (an
import, compile or collection error, or no marker this script recognises), so the test did
not run and shows nothing either way; it is a warning when another changed file is red, and
fails the check with `--strict`. When every changed file is inconclusive the check fails
whatever the flags, since nothing was shown: a pass would be vacuous, as when the test
dependencies were not installed or the command cannot run. The assertion marker is `--red-pattern` or `git config redcheck.redPattern`,
with a default that covers pytest, unittest, Vitest and Jest, Go and TAP. A file that existed
on the base is first run there as it was: if it already fails, its verdict is inconclusive,
since a failure after the change proves nothing. A new file is run once with the file absent:
if the suite already fails on an assertion without it, the file's failure cannot be
attributed to it and is inconclusive too. Each file is judged on its own and the base checkout
is restored between files. The command should still run only the named file; a runner that
ignores `{files}` and runs the whole suite costs a suite run per changed file. `--link` symlinks an untracked directory
(`node_modules`, `.venv`, `target`) into the worktree; the runner then shares that directory
and may write caches or build output into it, as it would in a normal run. A tracked
directory is refused, since the runs would then see the working tree instead of the base. `--run` and
`--match` fall back to `git config redcheck.run` and `redcheck.match`. Tracked files, HEAD
and the branch are never touched. Exit 0 when every changed test is red (or none changed), 1 when one passes on the
base, `--strict` meets an inconclusive one, or `--require` finds no test changed, 2 for a
usage problem. `--json` prints one document instead of lines: `status` is pass, fail, warn
(inconclusive files) or skip (no test files), with a verdict, exit code and detail per file.
A run that could not execute never reads as a pass. `--json` and `--github` cannot be
combined, since both write to stdout.

`record-check` finds the record from a `Change: docs/changes/<id>.md` line in the PR body,
else the first record path the body mentions at a path boundary, else the one record changed
in the range, reads it at the head commit, and checks frontmatter (`id` equal
to the file name, `tier` 0, 1 or 2, `status` open, approved, done or abandoned), the section
headings (Goal, Probed facts, Decisions, Tasks, Checks, Outcome; tier 2 adds Problem,
Requirements, Options and concerns), a filled Outcome when done, and the tier 2 rule: a PR
that changes only the record (mode `approval`) must set `status: approved`; a PR that
changes anything else (mode `code`) must find the record on the base at tier 2 and approved,
so a record cannot be raised to tier 2 in the same PR as the code, nor born `done`; a
record-only PR may also set `abandoned`, at any tier. A code PR may not lower
the tier the base recorded either; that takes a record-only PR. A body line `Tier: 0`
passes with no record. It prints `tier=N record=PATH mode=approval|code`, and with
`--github` writes all three to `$GITHUB_OUTPUT`; the workflow skips the red check for an
approval PR, which has no tests to judge. `--json` prints status, tier, record, mode and the
problems as one document.

`dispatch` is for a record whose frontmatter lists its tasks (`plugin:` and `tasks:` with
`name`, `branch` and `after`, as the template shows): it hands each task to a fresh agent
session that gets the record and not the conversation that wrote it. It reads the record on
the base branch (`origin/main` after a fetch) and refuses one that is not there, not approved
(tier 2) or open (tier 1), already done or abandoned, without tasks, without a `plugin:`
line when the default agent command is to be used, with a task name that is not a plain slug
(it names a worktree directory under `<worktrees>/<id>/`), or with an `after:` that names no
task or a later one. Then, task by task in order: a task
whose branch is already on the remote is in flight and skipped; a task whose `after` task is
not yet `done: true` in the record on the base stops the run; otherwise it cuts a worktree on
the task's branch from the base, writes a brief from the record (title, Goal, Probed facts,
Decisions, the task's own numbered item, Checks, and the fixed instructions: use this record,
do not change its tier or status, commit but do not push, end with the PR description whose
first line is the `Change:` line), and runs `claude -p --permission-mode acceptEdits
--allowedTools Bash --output-format json --plugin-dir <plugin>` in the worktree with the brief
on stdin (nobody is there to answer a prompt, and with edits alone every test run and commit
is denied; the summary line reports any command that was still denied). It keeps
the agent's JSON and PR description beside the worktree, commits `done: true` under the task
in the record (so the record on the base says so once the branch merges, which squash merges
would otherwise hide), runs `record-check` and, given a run command, `red-check`, and pushes
the branch only when both pass, and fails the task loudly when the marker cannot be written
(an agent that renamed the task) rather than pushing without it. The worktree stays for
inspection either way, and a later run leaves a kept worktree, or a local task branch with
commits beyond the base, alone unless `--fresh` says to discard it and start that task again
from the base. A task with no numbered item of its own under Tasks fails before any agent
runs, since the brief would otherwise carry every task. Opening the PR
is left to whoever runs it, with the saved description. `--agent CMD` replaces the agent
command, which is how its tests drive a fake agent. The agent runs on your credential with
edit permission and shell access in that worktree, the same trust as running the skill
yourself with those tools allowed. Each agent runs with `AGENT_TRANSCRIPTS_PARENT` set to the
session running `dispatch` (`CLAUDE_CODE_SESSION_ID`), or unset when there is none, so the
child's transcript entry names its parent.

### Transcripts

    transcripts archive [--transcript PATH]
    transcripts import [--claude-home DIR] [--repo URL]... [--evals]
    transcripts push [--session ID]... [--background]
    transcripts materialize DIR [--session ID]... [--repo-dir DIR]
    transcripts redact < lines
    transcripts grade [DIR] [--session ID]... [--repo-dir DIR] [--store]
    transcripts grade --transcript FILE [--cwd DIR]

`transcripts` keeps agent session transcripts in a local archive, sends them to a shared store
and grades them against the `change` skill's steps (record
`docs/changes/2026-11-09-skill-transcripts.md`; the judge and the report are a later task of it). This repository's `.claude/settings.json` runs `transcripts archive`
on `Stop` and `SessionEnd`, in this checkout and in every worktree `dispatch` cuts. It is
opt-in: nothing happens unless `AGENT_TRANSCRIPTS` names an archive directory, for example
in your shell profile or in `.claude/settings.local.json`:

    { "env": { "AGENT_TRANSCRIPTS": "/Users/you/agent-transcripts" } }

The archive must be outside every git working tree (it is refused otherwise, so transcripts
are never committed); it is not redacted, so `transcripts` creates it open to you only
(umask 077), as Claude Code keeps its own transcripts. At each stop the hook adds the
transcript's new complete lines, and those of the session's subagents, as numbered parts under
`parts/<sessionId>/`, and writes `sessions/<sessionId>.json`: source (local, cloud, dispatch,
eval), machine (a random id kept in `~/.config/agent-transcripts/machine-id`; in the cloud the
container and cloud session ids), repository (the origin URL, normalised, so a laptop and a
cloud checkout agree), branch and commit at the first and last stop, the first and last
timestamp in the transcript, the skills invoked with each skill file's git blob hash, the
record the session wrote or named on its `Change:` line (none when they disagree), the
parent session for a `dispatch` child, and per transcript the lines, bytes and sha256
archived. The script's header lists every field. The hook never fails or holds up a session:
any problem is a line on stderr and exit 0 (Claude Code does not show it under `claude -p`;
run the command by hand to see it), it runs in about 50 ms on a 180-line transcript and times
out after 10 s, and what it could not archive is archived at the next stop.

`transcripts import` registers the sessions already under `~/.claude/projects` (Claude Code
deletes them after `cleanupPeriodDays`, 30 by default) whose working directory is a checkout
of this repository, or of each `--repo URL`; `--evals` adds eval-runner sessions. Running it
again adds only what is new. Imported sessions have no `dispatch` parent and no commit, since
no stop was seen.

**The store.** The owner's Supabase project holds `sessions` (index rows), `chunks` and
`scores`; `store/schema.sql` creates them, and `store/probe` checks against the real project
that the hooks' key can insert and nothing else (no select, update or delete; a duplicate is
refused with 409 and changes nothing). Set `AGENT_TRANSCRIPTS_URL` to the project's URL beside
`AGENT_TRANSCRIPTS`, and every stop also starts `transcripts push --background`, detached from
the hook so the session never waits: it sends what the store does not have, stops after
`AGENT_TRANSCRIPTS_PUSH_LIMIT` seconds (60), logs to `<archive>/push.log`, and leaves the rest
for the next stop. Before anything leaves the machine, every string in every line is redacted:
email addresses, GitHub, Anthropic, AWS, Supabase, Slack and `sk-` keys, JWTs, bearer and basic
tokens, URL passwords and private key blocks become `<redacted:kind>`; the local archive keeps
the original. `transcripts redact` shows what would be sent. Each stream goes as gzip chunks
keyed by a hash chain over the redacted bytes, so two machines sending the same session store
each chunk once, and a rewritten transcript or a new redaction version starts a new generation;
the session's index entry follows as a new row version, never an update.

Keys: on a laptop, put the publishable (insert-only) key in
`~/.config/agent-transcripts/insert-key`, mode 0600 (refused otherwise). In a cloud environment
leave the file out: allow the project's host and save the key as a network secret for the
`apikey` header, and the proxy adds it. The secret key is the read key: keep it only on your own
machine, in `~/.config/agent-transcripts/read-key` (0600), for `materialize`, which rebuilds a
folder in Claude Code's layout (`projects/<repository>/<id>.jsonl` and subagents, each file's
time from its last timestamp, `sessions/<id>.json`, and `skills/<plugin:skill>/SKILL.md` at the
blob each session recorded, read from the checkout you run it in). It checks every chunk
against its chain id. For Skill Doctor, point `--claude-home` at that folder and `--skills-dir`
at its `skills/`.

**Grading.** `transcripts grade` scores every session in a folder (the local archive by
default, or a folder `materialize` wrote) with the field graders in `grade/fields.py`, one
verdict per step, pass, fail or not applicable, with its evidence:

| Step | Passes when |
|---|---|
| `tier-declared` | the record at the session's last commit has tier 0, 1 or 2, or, with no record, the session declares `Tier: 0` (it fails when code was written with neither) |
| `probe-before-record` | a probe (inline code, a module, a scratch script, `--help`, a request to another system) ran before the session first wrote its record |
| `record-before-code` | the record was written before the first code |
| `red-first` | a test run, before the first code, ran and reported a failed test |
| `change-line` | the pull request it opened, or the description it wrote, opens with `Change: <record>` |
| `record-check` | `record-check` passes on the session's first to last commit |
| `outcome-filled` | a record that is done, or a task the session marked done, has an Outcome |

A call counts only when its own result shows it ran: a denied, refused or unanswered call did
nothing. A failure counts from the error flag or from the result's text. Code is any file in
the session's working tree outside `docs/`, documentation, tests, fixtures and backups. The
record is the one the session wrote and named, from its own acts, never from a prompt. Steps a
session never reached (no record, no code, no pull request) are not applicable, and a session
with no record grades every record step so. The record is read with git from `--repo-dir` (the
current directory by default), which must hold the session's commits. Rows go to
`<DIR>/scores/<sessionId>.json`; on your own machine `--store` also inserts them into `scores`
with the read key. `--transcript FILE` grades one file without commits and prints the rows,
as `evals/cases.test.cjs` does to run the eval graders' fixtures through the same code.

## What is not here yet

- **The independent review as a CI check** of its own. Use `agent-review` locally before the
  push, or the `agent-workflow` PR-Agent workflow in CI; the skill treats findings from
  either the same way. A `review-check` that fails the PR on a critical finding until the
  author replies with evidence is the next piece.
- **Mutation testing as a CI check.** The skill says to run the language's tool where one
  exists; wiring each tool's output into a check is per-language work.
- **Evals in CI.** The eval suite under `evals/` runs with a live agent, not in this
  repository's CI; `evals/cases.test.cjs` only checks the cases are well formed.

## What is verified against the real system

The suites run the scripts against real git repositories, but they stand a file in for
`$GITHUB_OUTPUT` and capture the `::error` and `::warning` lines as text. The Actions side
is probed on every CI run of this repository by `.github/workflows/change-record-protocol.yml`:
it builds a scratch repository on the runner (`ci/scratch.sh`), runs both scripts with
`--github`, and a second job asserts that the job outputs carry the tier, record and mode
the scripts wrote; a third job runs only if the template's own gate condition evaluates true
on those outputs. The annotations appear on the run. That is the evidence for the claims
about the runner; the template workflow itself has not yet run in an adopting repository.

The skill's effect on an agent is measured by the eval suite in `evals/` (see its README for
the numbers): eight cases run with and without the plugin, three runs each. With the plugin
the mean score was 0.98 against 0.66 without. The plugin did not change whether a record
gets written, since a repository that asks for records gets one either way; it changed what
the record holds and the order of work: decisions with rejected alternatives, probed facts
with evidence labels after a real probe, an Outcome with real output, tests run before the
code changes, and a tier 0 declaration for trivial changes.

## Tests

    bash plugins/change-record/bin/red-check.test.sh
    bash plugins/change-record/bin/record-check.test.sh
    bash plugins/change-record/bin/dispatch.test.sh
    bash plugins/change-record/bin/transcripts.test.sh
    bash plugins/change-record/bin/transcripts-store.test.sh
    bash plugins/change-record/bin/transcripts-grade.test.sh
    node --test plugins/change-record/evals/cases.test.cjs

They build real git repositories in a scratch directory and need bash, git and python3 (the
`--json` assertions parse the documents with it; the scripts themselves fall back to a shell
encoder when python3 is absent). Every guard in these scripts was mutation-checked: each was
broken in turn and a test failed.
