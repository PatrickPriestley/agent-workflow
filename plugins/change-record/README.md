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

The plugin also brings a `Stop` and `SessionEnd` hook that keeps transcripts of your sessions,
which does nothing until you set `AGENT_TRANSCRIPTS` and write a scope list: see "Capture in
your other repositories" under Transcripts.

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

### record-review

    plugins/change-record/bin/record-review docs/changes/<id>.md

A tier 2 record is read, before its approval PR, by a fresh session that has no context but
the record and the repository. The reviewer gets a brief on standard input (what to look
for, then the record's text as it is in the working tree), runs from the repository's root
and is given tools that only read: by default `claude -p --tools Read Grep Glob
--output-format json`, or `--agent 'CMD'` for another headless agent. A command that
continues or resumes a session is refused, since a reader who knows the conversation is not
this review. It is asked for findings by severity: what it cannot understand without the
conversation, facts with no evidence or that the repository contradicts, requirements no
test could check, decisions with no rejected alternative, tasks with no test, concerns with
no owner, and a tier the content contradicts.

The review is printed under `Reviewed by: <who>, with no context but the record and the
repository` and kept with the brief in `.git/record-review/<id>/`. Exit 0 is a complete
review; 3 means the answer did not end with the end marker, so run it again; 4 that the
reviewer failed or ran past `--timeout` (default 900 seconds); 5 that it changed the working
tree, in which case its review is not used. The reviewer is the same model family as the
author, and it reviews the record, not the code: it finds what a record leaves out. It is not cheap: the
first real review, of a record of 147 lines, took a fresh Claude session five minutes, 38
turns of reading the repository and 3.62 dollars.

### Transcripts

How the parts fit together, in the order a session passes through them:

1. **Capture**: `archive` (the hook, at every stop) and `import` keep each session in a
   local archive with an index entry; `scope` decides which repositories count.
2. **Store**: `push` sends it, redacted, to the shared store; `messages` fills the readable
   table; `materialize` rebuilds a folder from the store with the read key.
3. **Grade and judge**: `grade` (seven deterministic step graders) and `judge` (a model for
   what no pattern settles, and the claims of `--repeats` and `--review`).
4. **Check the measures against people**: `sheet` builds what a person labels from;
   `accuracy` scores the graders against the labels; `report` puts pass rates per skill
   version beside each grader's error.
5. **Improve the skill**: `propose` drafts an edit from a failure a label confirms; `compare`
   runs it against the skill as it is through the step's eval cases (under `evals/`), and the
   edit is kept only if they score better with it than without.

    transcripts archive [--scoped] [--transcript PATH]
    transcripts import [--claude-home DIR] [--repo URL]... [--evals]
    transcripts import [--claude-home DIR] --scoped
    transcripts scope [DIR]
    transcripts push [--session ID]... [--background]
    transcripts materialize DIR [--session ID]... [--repo-dir DIR]
    transcripts redact < lines
    transcripts grade [DIR] [--session ID]... [--repo-dir DIR] [--store]
    transcripts grade --transcript FILE [--cwd DIR]
    transcripts judge [DIR] [--session ID]... [--repo-dir DIR] [--judge claude|opencode] [--limit N] [--store] [--verbose]
    transcripts judge --transcript FILE --record FILE [--judge claude|opencode]
    transcripts judge --repeats [DIR] (--session ID... | --limit N) [--again]
    transcripts judge --repeats --transcript FILE... --out DIR [--again]
    transcripts judge --review [DIR] (--session ID... | --limit N) [--repo-dir REPO] [--model sonnet|opus] [--again] [--local]
    transcripts report [DIR] [--store] [--labels DIR]
    transcripts sheet [DIR] [--session ID]... [--repo-dir DIR] [--labels DIR]
    transcripts sheet --transcript FILE... --out DIR [--labels DIR]
    transcripts accuracy [DIR] [--labels DIR]
    transcripts accuracy --transcript FILE... [--labels DIR]
    transcripts probe --agent codex|cursor [--out DIR]

`transcripts` keeps agent session transcripts in a local archive, sends them to a shared store
and grades them against the `change` skill's steps (record
`docs/changes/2026-11-09-skill-transcripts.md`). This repository's `.claude/settings.json` runs `transcripts archive`
on `Stop` and `SessionEnd`, in this checkout and in every worktree `dispatch` cuts. It is
opt-in: nothing happens unless `AGENT_TRANSCRIPTS` names an archive directory, for example
in your shell profile or in `.claude/settings.local.json`:

    { "env": { "AGENT_TRANSCRIPTS": "/Users/you/agent-transcripts" } }

The archive must be outside every git working tree (it is refused otherwise, so transcripts
are never committed); it is not redacted, so `transcripts` creates it open to you only
(umask 077), as Claude Code keeps its own transcripts. At each stop the hook adds the
transcript's new complete lines, and those of the session's subagents, as numbered parts under
`parts/<sessionId>/`, and writes `sessions/<sessionId>.json`: source (local, cloud, dispatch,
eval, or agent: a GitHub agent's run that `bin/agent-session-collect` collected), machine (a random id kept in `~/.config/agent-transcripts/machine-id`; in the cloud the
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

**Capture in your other repositories** (record
`docs/changes/2026-11-15-user-level-capture.md`). The plugin ships the same hook
(`hooks/hooks.json`) as `transcripts archive --scoped`, so once the plugin is installed for
your user it runs at every stop of every session, in every repository. It keeps a session
only when the repository is on your scope list, `~/.config/agent-transcripts/scope`, which
you write yourself and which is in no repository:

    # one pattern a line, against github.com/owner/name; case does not matter
    github.com/YourName/*
    github.com/your-org/one-project
    !github.com/YourName/private-*

`*` crosses `/`, so `github.com/YourName/*` is every repository of that owner; a line with no
wildcard is one whole repository; `!` excludes, and an exclusion wins over any match wherever
it stands. Nothing is in scope until a line names it. With no list, an empty one, no matching
line or an excluding one, and for a session outside any repository, in one with no `origin`,
or one whose `origin` is a path on the machine, the hook archives nothing, starts no push,
prints nothing and exits 0, in about 60 ms. Both the folder a session is in at the stop and
the folder it began in must be in scope. A transcript holds the code and command output of
the repository it ran in, and redaction takes out keys, addresses and account ids, not code:
name repositories you hold the rights to, not `*`. To set a machine up:

    claude plugin install change-record@agent-workflow     # for your user, the default scope
    export AGENT_TRANSCRIPTS=~/agent-transcripts           # and AGENT_TRANSCRIPTS_URL, to send
    $EDITOR ~/.config/agent-transcripts/scope
    alias transcripts=/path/to/agent-workflow/plugins/change-record/bin/transcripts   # a checkout of this repository
    transcripts scope                                      # in a repository: in scope, and by which line?
    transcripts import --scoped                            # the sessions already on this machine

`transcripts scope [DIR]` says whether the repository at DIR is in scope and by which line, or
which reason keeps it out, then how much the archive on this machine holds; it exits 0 in
scope and 1 not. `transcripts report --store` says under its title how many sessions and MB
of redacted text the store holds, by redaction version, which is the only place the store's
size shows (only the read key can see it). If you install the plugin and set neither
`AGENT_TRANSCRIPTS` nor a scope list, the hook does nothing but take those 60 ms, and nothing
can reach the owner's store without the owner's key. This repository's own hook stays,
unscoped, so in this checkout and in `dispatch`'s worktrees both run; the second finds
nothing new. This covers your own machines only: a cloud session in another repository does
not have the plugin, and how it would get it is not worked out.

**The store.** The owner's Supabase project holds `sessions` (index rows), `chunks` and
`scores`; `store/schema.sql` creates them, and `store/probe` checks against the real project
that the hooks' key can insert and nothing else (no select, update or delete; a duplicate is
refused with 409 and changes nothing). Set `AGENT_TRANSCRIPTS_URL` to the project's URL beside
`AGENT_TRANSCRIPTS`, and every stop also starts `transcripts push --background`, detached from
the hook so the session never waits: it sends what the store does not have, stops after
`AGENT_TRANSCRIPTS_PUSH_LIMIT` seconds (60), logs to `<archive>/push.log`, and leaves the rest
for the next stop. A session whose own data cannot be sent (its archived files cannot be
read, or the store refuses its rows) is passed over and named, the others still go, and it is
tried again at the next push; a store that cannot be reached or fails as a whole stops the
push at once. Before anything leaves the machine, every string in every line is redacted:
email addresses, GitHub, Anthropic, AWS, Supabase, Slack and `sk-` keys, JWTs, bearer and basic
tokens, URL passwords and private key blocks become `<redacted:kind>`; the local archive keeps
the original. The ids of the account are taken out too: a value under `organizationUuid`,
`accountUuid`, `userID`, `organization_uuid` or `account_uuid` becomes `<redacted:account-id>`,
and so does the same value wherever else it stands, in a URL or a folder name, and a UUID
joined to it by `_`. `transcripts redact` shows what would be sent; it reads all its input
before it writes. Each stream goes as gzip chunks
keyed by a hash chain over the redacted bytes, so two machines sending the same session store
each chunk once, and a rewritten transcript or a new redaction version starts a new generation;
the session's index entry follows as a new row version, never an update.

Keys: on a laptop, put the publishable (insert-only) key in
`~/.config/agent-transcripts/insert-key`, mode 0600 (refused otherwise). In a cloud environment
leave the file out: allow the project's host and save the key as a network secret for the
`apikey` header, and the proxy adds it.

To set up a new machine from a password manager, keep the publishable key there and put these
lines in your dotfiles (1Password's `op` shown; `bw get password ...` works the same way with
Bitwarden). The key never sits in git or in your shell history:

    umask 077; mkdir -p ~/.config/agent-transcripts
    op read "op://Private/Supabase transcripts/insert-key" > ~/.config/agent-transcripts/insert-key
    export AGENT_TRANSCRIPTS=~/agent-transcripts
    export AGENT_TRANSCRIPTS_URL=https://<project>.supabase.co

A machine with no key still archives locally; its sessions are sent at the first stop or
`transcripts push` after the key is in place.

The secret key is the read key: keep it only on your own
machine, in `~/.config/agent-transcripts/read-key` (0600), for `materialize`, which rebuilds a
folder in Claude Code's layout (`projects/<repository>/<id>.jsonl` and subagents, each file's
time from its last timestamp, `sessions/<id>.json`, and `skills/<plugin:skill>/SKILL.md` at the
blob each session recorded, read from the checkout you run it in). It checks every chunk
against its chain id. Where the store holds a session more than once, it takes the copy with
the newest redaction version, then the latest and longest. For Skill Doctor, point `--claude-home` at that folder and `--skills-dir`
at its `skills/`.

**The store's text, for reading** (record `docs/changes/2026-11-15-readable-store.md`).
`chunks` holds each transcript gzipped, which no query can open, so the dashboard shows that a
session is stored and nothing of what was said. `store/schema.sql` also creates `messages`, one
row for each text, tool call and tool result of a transcript line, and the view `transcript`,
which shows each session's rows in the order of the copy `materialize` rebuilds. Run the file
in the project's SQL editor to get them; running it again changes nothing that is there. The
text in a row is the redacted text of the chunk it was read from, never the original.

To read one session, in the dashboard's SQL editor (or filter the view `transcript` by
`session_id` in the table editor); a subagent's lines are under its own `stream`:

```sql
select n, at, who, kind, tool, text
from transcript
where session_id = '<session id>' and stream = 'main'
order by n;
```

To search every session for some words, whatever their case:

```sql
select session_id, stream, n, who, kind, left(text, 300) as text
from transcript
where text ilike '%<words>%'
order by session_id, stream, n;
```

`who` is `user`, `assistant`, `tool` (a tool's result) or `context` (what the harness put in:
reminders and summaries); `kind` is `text`, `call` (the tool's input as JSON, its name in
`tool`) or `result` (`failed` when the tool marked an error); `call_id` ties a result to its
call. Left out: thinking, images, and every line that is no user's or assistant's. One text
longer than 3,000,000 bytes in a request is stored cut, and its last line says so.

`transcripts messages [--session ID]...`, run where the read key is, fills the table from the
chunks the store holds and inserts only the rows that are missing; `transcripts messages
--check` changes nothing and prints each row that is missing, that is there and is not its
chunk's, that differs, or whose chunk the store does not hold, and exits 1 if there is one.

`transcripts push` writes the rows too: after each chunk it sends that chunk's rows, in the same
requests the command would. Rows never hold a transcript back. A request of rows the store
refuses, or does not answer, is kept in the session's sent state as owed; the push's last line
says how many are, its exit status is what it would have been, and the next push sends them
again. Where the store has no `messages` table yet (the SQL not run), the chunks and the index
row are stored as before and every request of rows is owed until it has. So rows can be
missing for a while: until the owing machine's next push, or until `transcripts messages` is
run where the read key is, which also fills what a push could not know was missing. If the
table and the chunks ever disagree the chunks are right: they are what `materialize` and the
graders read, and each is checked against its chain id.

The hooks' key can insert into `messages` and nothing else, and `store/probe` checks that too.
Its check that a request of several rows is stored whole or not at all needs the read key, so
it exits 1 where there is none: run it where both keys are. The probe's rows stay in the
store under a session id that begins `probe-`, one of them 3 MB; `transcripts messages` passes
over its chunk and says so, and the view shows nothing of it. To clear them, in the SQL
editor: `delete from messages where session_id like 'probe-%'`, and the same for `chunks` and
`sessions`. `store/schema.test.sh` runs the
file in a PostgreSQL of its own and tests the grants, each rule of the view, the rows of the
tool's fixture through the real table, and the two queries above as they are printed here; it
says so and passes nothing off where none is installed.

**Grading.** `transcripts grade` scores every session in a folder (the local archive by
default, or a folder `materialize` wrote) with the field graders in `grade/fields.py`, one
verdict per step, pass, fail or not applicable, with its evidence:

| Step | Passes when |
|---|---|
| `tier-declared` | the record at the session's last commit has tier 0, 1 or 2, or, with no record, the session declares `Tier: 0` (it fails when code was written with neither) |
| `probe-before-record` | a probe (inline code, a module, a scratch script, `--help`, a request to another system, a run of the tests, a look at the real environment) ran before the session first wrote its record |
| `record-before-code` | the record was written before the first code |
| `red-first` | a test run, before the first code, ran and reported a failed test |
| `change-line` | the pull request it opened, or the description in its last message, opens with `Change: <record>`, bold or not |
| `record-check` | `record-check` passes on the session's first to last commit |
| `outcome-filled` | a record that is done, or a task the session marked done (`done: true`, or `[x]` under Tasks), has an Outcome |

A call counts only when its own result shows it ran: a denied, refused or unanswered call did
nothing, and a shell write the shell refused (a read-only file system, a permission) wrote
nothing. A failure counts from the error flag or from the result's text. Code is any file in
the session's working tree outside `docs/`, documentation, tests, fixtures and backups. The
record is the one the session wrote and named, from its own acts, never from a prompt. Steps a
session never reached (no record, no code, no pull request) are not applicable, and a session
with no record grades every record step so. The record is read with git from `--repo-dir` (the
current directory by default), which must hold the session's commits. Rows go to
`<DIR>/scores/<sessionId>.json`; on your own machine `--store` also inserts them into `scores`
with the read key. `--transcript FILE` grades one file without commits and prints the rows,
as `evals/cases.test.cjs` does to run the eval graders' fixtures through the same code.

The rules above are the owner's rulings of 2026-11-12 (record
`docs/changes/2026-11-12-grader-fixes.md`), which made the graders `fields/2`. They are
`fields/3` since `docs/changes/2026-11-12-grader-faults.md`: a session starts at the newest
commit made before its first line, not at its first stop, and comment lines, `env -u`, a
script run after a `cd` and a quote that never closes are read as the shell reads them. Rows
of each version are kept apart in the report. Where a rule needs a line drawn: `--version`
alone is no probe, and listing or reading files is none. A look at the environment is
`printenv`, `env` alone, `echo` of a variable in capitals the command did not set itself, or
`ls`, `stat`, `test`, `find` and the like on an absolute path outside the working tree,
temporary folders and a plugin's or skill's own folder. In a last message the description
starts at the line that names it (a heading, a bold line or a line ending in a colon that says
pull request or PR, and description or body); only blank lines, a rule, a code fence and a
`Title:` line may stand before the `Change:` line. A message that names no description and
does not open with the line is not applicable. `tier-declared`, `record-check` and
`outcome-filled` need the session's last commit; without it the row is not applicable with an
`error`, which `accuracy` and the report list as "could not grade" and count nowhere.

**The judge.** Two steps no regex settles are judged by a model, after `grade`: whether the
record's Decisions name a rejected alternative (`decisions-alternative`) and whether its
Outcome quotes real output (`outcome-real-output`). `transcripts judge` asks a fresh Claude
Haiku session each question three times (`claude -p --model haiku --output-format json --tools
"" --no-session-persistence --setting-sources ""`, in an empty scratch directory with no
`AGENT_TRANSCRIPTS`, so the judge's own session is neither saved nor captured), only for
sessions that wrote code and have a record, at most `--limit` (20) per run, newest first. The
judge sees the record's section, and for the Outcome the commands the session ran, redacted as
`push` redacts. An answer is a vote only when it is one JSON object, `{"verdict": "pass" or
"fail", "reason": "..."}`, alone or in one code fence; a refusal, an error, an answer from a
model that is not Haiku, or anything else is kept with its text and not counted. Two counted
votes that agree make the verdict; otherwise it is `undecided` and no score row is written. An
empty section fails, and the Outcome of a record that is not done is not applicable, without
asking. Every prompt, answer and verdict is kept in `<DIR>/judges/<sessionId>.claude.json`, the
score rows in `<DIR>/scores/<sessionId>.judge.json` (grader `judge/1:haiku`); `--store` also
inserts the rows into `scores` and each answer into `judge_votes`, with the read key.
A session is judged once per record text. A question left `undecided` is asked again at the
next run, and the questions that have a verdict are kept, with the time they were judged. A
run in which an answer was an error (no `claude`, no answer in time, another model) says so
and exits 1; answers the model gave that are not votes do not change the exit status. `--store`
also sends the rows of sessions judged at an earlier run that did not store them, or could
not: a judge file is marked `stored_at` when all of its rows went.
`--verbose` prints each prompt and vote. `--transcript FILE --record FILE` judges one record and
prints everything, writing nothing.

**Said twice.** `transcripts judge --repeats` measures the prose a session ended on (record
`docs/changes/2026-11-15-checkable-judges.md`; it replaces the `verbosity` rubric, which gave a
label no judge could match). It sends each chosen session's closing message, redacted as for
the store, to Claude Sonnet once, with no tools, with the brief in `grade/briefs/repeats.md`:
list the points the message makes, each with a quote of where it is first said and, when it is
told a second time, a quote of where. Nothing in the answer is taken on trust. A point counts
only if its quote is in the message that was sent, a pair only if both quotes are and differ
(compared with backticks and asterisks removed, white space run together and case lowered). It
keeps, in `<DIR>/repeats/<sessionId>.json`: the points, the pairs, each with an id made from
its two quotes, the quotes that were not found, and the share of points said again. It gives
a number, not a verdict: what share is too much is the reader's call. It makes no call until
you choose the sessions, with `--session ID` or `--limit N` (the newest N not yet answered),
and it prints the sessions, the calls and the most they can cost (25 cents each; a call
has cost about 1.5 cents) before the first. A kept answer is for the message it was given and is
not asked for again without `--again`; an answer that did not count (not JSON, a refusal, an
error, another model) is kept as what it is and asked for again at the next run.
`--transcript FILE... --out DIR` does the same for transcript files.

**Defects shown.** `transcripts judge --review` measures the code a session left (the same
record; it replaces the `code-quality` rubric, whose judge could not run anything and approved
what a reviewer who ran the code blocked). For each chosen session's own commits in
`--repo-dir`, a fresh Claude session (Sonnet, or `--model opus`) with a shell, `Read`, `Grep`
and `Glob` is given the brief in `grade/briefs/review.md`. The brief demands a method: read
every changed file, write down each guarantee the change states, try to break each with inputs
the tests do not use, at least fifteen experiments. The reviewer leaves each defect it
reproduced as a script, `.review/<name>.sh`, that exits 0 only when it shows the defect.

Nothing the reviewer says is taken on trust. The tool copies the scripts out and runs each
one itself, from the root of a clean clone, at the session's last commit and at its base. A
defect is **shown** only if its script exits 0 at the last commit and not at the base, within
two minutes, and leaves the clone as it was. A script that passes everywhere, or shows
something the session inherited, is counted under its reason and not as a defect. The answer
is kept in `<DIR>/reviews/<sessionId>/<model>/`: `review.json` (each defect with an id made
from its script, its kind, what the reviewer said of it, and its status), the scripts, what
each printed at each commit, and the reviewer's event stream. The count is a floor, not a
verdict: a reviewer finds different defects on different runs, so none shown is weak evidence
of none.

What the reviewer and its scripts can reach:

- The reviewer works in a scratch clone that holds the history up to the session's last commit
  and nothing else: no remote, no ref, no later commit, so a later fix cannot be read from it.
- It runs in Claude Code's sandbox, with no leave to ask for a command outside it and with
  reading the repository and the archive denied. Before
  the first review of a run, one Haiku call checks that the sandbox holds: a write beside the
  reviewer's folder and a read of the repository must both fail, or nothing is reviewed. In the
  sandbox it has no network and can write only in its clone and in the sandbox's own temporary
  area (`/tmp/claude-<uid>`), which other Claude Code sessions on the machine also use.
- A review whose commands name the repository's path is kept, marked as having looked outside
  its clone, and its defects are not counted.
- The scripts are shell commands a model wrote, so the tool runs them in a box (`bwrap`): no
  network, the file system read-only but for the clone and an empty `/tmp`, the repository,
  the archive and your home folder hidden, the environment cleared. Where no box can be
  started (a Mac has no `bwrap`) it refuses, unless you pass `--local`: the scripts then run
  with your own access.
- The tool runs no git in a folder a script has been in (a script could plant a command in the
  clone's git configuration): each script gets a copy of the clean clone, compared by reading
  its files and thrown away. Only the end of what a script prints is kept.
- The reviewer reads the clone's files as they are, and what it reads goes to the model
  unredacted. Run it on sessions in repositories you already work in with Claude Code.

It makes no call until you choose the sessions, with `--session ID` or `--limit N` (at most ten
a run), and prints the sessions, the calls and the most they can cost first ($1.50 a review;
the probes cost $0.21 to $0.56). A kept review is for its model, its brief and the session's
last commit, and is not made again without `--again`; one that did not finish (no answer, an
error, past twenty minutes, looked outside) is kept as what it is and made again at the next
run.

**Checking the two measures.** Neither gives a verdict, so neither has a pass rate to be wrong
about: what can be wrong is a claim. Each pair and each shown defect has an id made from its
content, and a session's sheet (below) lists them under "Claims to rule". A person rules them
in the session's label file:

    said-again: wrong 4c9a82 | right 10fc48
    defects: right e623ab

The report gives each measure's error as the claims ruled wrong over the claims ruled, once
ten are ruled; under ten it is "not yet checked". A ruling applies to whichever counted answer
of the session holds the id, a review's from either model. One on an id no counted answer
holds (the session was asked again and answered differently, the review looked outside its
clone, the id is mistyped) is listed as stale and counted for nothing. An id that is not six
hex digits, a word that is neither `wrong` nor `right`, an id ruled both ways, or a ruling
with no name after `labelled-by:` rejects the label file, with the reason.

**The agreement check.** `transcripts judge --judge opencode` asks `opencode-go/kimi-k3.1-pro`
the same prompts through `opencode run`, with an agent that may use no tool and project config
disabled (as `agent-review` runs it), for up to 10 sessions the Haiku judge judged on the same
record. It writes `<DIR>/judges/<sessionId>.opencode.json` and no score rows. It needs
`opencode` installed and logged in to OpenCode Go.

**The report.** `transcripts report [DIR] [--store] [--labels DIR]` prints, in Markdown, every
step's pass rate per skill version (the skill's git blob, so two versions are never counted
together), oldest first, with the grader's measured error beside it; a table of each step's
rate across versions; the agreement between the two judges (or that the check has not run
yet); the graders' error against the label files (below), with every known false verdict and
what was not counted and why; and, for each session and step whose latest row is a fail, what
the session did: the grader's reason, the rest of its evidence, and the calls it cites, each
with a short excerpt from the transcript, redacted as `push` redacts. It proposes no edit. A
step's error is printed once five labelled sessions cover it, a session covering a step when
its label or the grader says pass or fail; until then the step is "not yet checked", which says
nothing for or against its verdicts. It reads `<DIR>/scores/`, `<DIR>/judges/`, the transcripts
in `<DIR>` and the labels in `grade/labels/` (or `--labels DIR`); `--store` adds the store's
`scores`, `judge_votes` and `sessions` rows, with the read key, and those sessions have no
excerpt and no measured error unless their transcripts are in `<DIR>`. A rejected label file is
listed, not counted, and makes the exit status 1.

The report also has a section for each of the two measures, from `<DIR>/repeats/` and
`<DIR>/reviews/`, per session and per skill version. **Said again**: points, pairs, and the
share of points said again. **Defects shown**: per reviewer, the lines the session changed
(added plus removed between its base and its last commit, binary files left out; "unknown"
for a review kept from before they were counted), the defects shown, how many per 1,000
changed lines, and their kinds. Neither has a label or a pass rate. An answer that was not
counted is named with its reason. Under each stands the measure's error from the rulings,
the claims ruled wrong, and the stale rulings.

**What a session took, and which skills were used** (record
`docs/changes/2026-11-12-session-quality.md`). The report also counts, from the transcripts in
`<DIR>` and with no grader or model: output tokens, tool calls, calls that failed or were
refused, messages written and their characters, the last message's characters, turns from a
person after the first, and the minutes from a session's first line to its last. Per skill
version it prints the middle (the median), the least and the most with their session, then a
row per session. Nothing is stored and no threshold is applied: the numbers are there to be
read, not to pass or fail. How each is counted:

- Output tokens once per message. Claude Code writes one message on several lines, each with
  the same usage, so adding line by line counts a message several times. A transcript with no
  usage shows `-`.
- A turn from a person is a message someone typed. A line the harness wrote, a compaction
  summary and a notification or command wrapped in a tag are not. Whether a turn was a
  correction is not judged.
- Minutes include waiting: a session left overnight is long, not slow.
- A subagent's lines kept inline are left out, as the graders leave them out.

Skill coverage is how many sessions used each skill, and how many used none. A session used a
skill when its index entry lists it or its transcript shows it, by the capture hook's own rule
(the Skill tool, or the skill's file read or printed), so sessions captured before that rule
knew a shell read are counted too. One skill can appear under two names, with and without its
plugin. A folder with transcripts and no `scores/` still gives both sections.

**Two rubric judges were tried and taken out** (the same record, task 2 and its concern C2).
The record allows a judge one wrong in five against a person's labels, and says one over
that is taken out and not tuned. Both were:

| Rubric | Asked of | Model | Labelled | Wrong |
|---|---|---|---|---|
| `verbosity` | the messages the session wrote | Claude Haiku | 14 | 3: it answered `proportionate` every time |
| `code-quality` | the diff of what the session committed | Claude Sonnet, no tools | 7 | 4: each an `approve` where the label blocks |

Each was asked three times in a fresh session with no tools. The code-quality judge's two
blocks both named a real defect, so a block was worth reading; its approvals were not, since
the four it missed were defects a labeller found by running the code. `transcripts judge
--rubrics` now says so and exits 2, and the report drops any rows either judge left in a
folder or the store. The rubric texts stay in `grade/rubrics/` (adapted from Skill Doctor's
scorers, MIT; the notice is beside them), and the label files keep their `code-quality:` and
`verbosity:` lines, which still load and are still checked: they are what each judge was
measured against, and what a later attempt would have to beat.

What the code-quality work left behind is how a session's own commits are found, which the
label sheet prints for a labeller. The last commit is the one at the session's last stop.
The base is the newest commit on that commit's own line (first parents) made before the
session's first line; the commit at the first stop is no base, since it already holds the
first turn's work. A session whose last commit was made before it began made none.

**Checking the graders against a person** (record `docs/changes/2026-11-11-grading-trust.md`).
The graders can be wrong, so a set of sessions is labelled by hand and the graders are scored
against it. The labels are in `grade/labels/<sessionId>.txt`, one file per session:

    session: 4c14e156-58e9-4138-8bc2-a3e13e9b00fa
    transcript: sha256:<64 hex> lines:56
    labelled-by: Your Name, 2026-11-12
    tier-declared: pass | the record it wrote has tier 1
    red-first: fail | the only test run before greet.py changed was denied
    outcome-filled: na | the record is not done
    ...one line for each of the seven steps

A verdict is `pass`, `fail` or `na`, then `|`, then a one-line reason. A step with nothing
before the `|` is not labelled yet. A file with a missing step, an unknown verdict, a verdict
without a reason, or verdicts with no name after `labelled-by:` is rejected. The verdicts are a
person's: a model may fill in a reason for the person to correct, never a verdict.

To label, as the owner:

1. Build the sheets. For the fifteen sessions kept as fixtures (their label files are already
   in `grade/labels/`, empty), from the repository's root:

       transcripts sheet --transcript plugins/change-record/grade/fixtures/*.jsonl.gz \
           plugins/change-record/grade/fixtures/evals/*.jsonl.gz --out ~/label-sheets

   For the sessions in the store, rebuild a folder and grade it first, then build its sheets,
   which go to `<folder>/sheets/` and also show the record at each session's last commit:

       transcripts materialize ~/transcripts-rebuilt
       transcripts grade ~/transcripts-rebuilt
       transcripts sheet ~/transcripts-rebuilt

   Sheets hold transcript text (redacted), so they are written outside every working tree.
   Each run leaves `grade/labels/<sessionId>.txt` for a session that has none, with the hash of
   the transcript and the seven steps to fill in. A file you have written in is never replaced.
2. Read a sheet: `<sessionId>.md`. It opens with the seven steps, each with its question, when
   to answer `na`, and the numbers of the calls worth looking at; then the session in order,
   every call with its input and what came back. It shows nothing a grader concluded, so judge
   from the calls: a call did something only if its own result shows it ran. Label what the
   session did, not what a grader could know. Where the sheet does not show enough to decide
   (the record at the last commit, for a fixture, which has no commit), answer `na` and say so.
3. Write the verdicts in the session's label file, your name and the date after
   `labelled-by:`, and commit the label files. Where the sheet ends with "Claims to rule" (the
   folder holds answers of `judge --repeats` or `judge --review` for the session), rule the
   claims you checked on a `said-again:` and a `defects:` line. That section is the one part
   of a sheet that shows what a model concluded, so it comes last: read the session first.
4. Measure:

       transcripts accuracy --transcript plugins/change-record/grade/fixtures/*.jsonl.gz \
           plugins/change-record/grade/fixtures/evals/*.jsonl.gz
       transcripts accuracy ~/transcripts-rebuilt

   The first grades the fixture files as `grade --transcript` does (`bin/transcripts-grade.test.sh`
   runs it, so CI fails on a label file that is malformed or no longer matches its fixture); the
   second reads the folder's `scores/`. Each prints, per step, the sessions labelled, the
   agreements, the false fails (the grader says fail, the label does not), the false passes and
   the false n/a (the grader says not applicable, the label says pass or fail), then every
   disagreement with its session id and both reasons, then what was not counted: a session with
   no label, a label with no transcript in that folder, a step the grader could not grade, and
   a stale label. A label is stale when the transcript's hash is no longer the one in its
   `transcript:` line, because the session went on after it was labelled or was only partly
   captured then; its verdicts are left out until the session is labelled again from a new
   sheet. Label and measure from the same kind of folder: the local archive is not redacted, so
   its hashes differ from the store's.

**Proposing an edit to the skill** (record `docs/changes/2026-11-12-session-quality.md`, task 3).
`transcripts propose [DIR] --session ID --step STEP` drafts an edit to the skill a session used,
from one failure, and only from one a person has confirmed: the session's label file must say
`fail` for that step, carry a name after `labelled-by:`, and be of this version of the
transcript. Otherwise it exits 1 with nothing sent and nothing written, since the graders have
been wrong too often for an edit to be drafted on a grader's word. It makes one call to Claude
Sonnet, with no tools, holding what a label sheet shows, redacted as for the store: the skill
file as the session used it, the step and its rule, the labeller's reason and the session's
calls. It writes to `DIR/proposals/<session>/<step>/`:

- `SKILL.md`, the proposed file, and `SKILL.diff`, its difference from the file the session used;
- `proposal.md`, which cites the session, the skill file's blob, the step, the label and the
  calls that show the failure, and names the eval cases of the step with the graders that test
  its rule (below), or says that there is none. The cases are chosen by the step, so whether they
  show this session's failure is for you to check.

| Step | Eval cases, and the graders that test the step |
|---|---|
| `tier-declared` | `tier-0-no-record` (`declares-tier-0`), `tier-2-stops-before-code` (`record-is-tier-2`) |
| `probe-before-record` | `probed-facts-labelled` (`probed-before-record`) |
| `record-before-code` | `record-before-code` (`record-before-code`) |
| `red-first` | `red-first` and `red-first-workflow` (`saw-it-fail` and the test-run grader of each) |
| `change-line` | `record-before-code` (`pr-body-names-record`) |
| `outcome-filled` | `outcome-has-real-output` (`outcome-quotes-main-path`, which asks more: an Outcome that quotes a run) |
| `record-check` | none: it runs on commits, which the eval runner cannot make |

The skill file is the version the session used, found by its blob in the repository (or the
folder's own copy when that is the same blob), never a later one. A session that did not load
the skill gets no proposal: an edit would not have reached it.

It never writes to the skill. An edit enters the skill as a change of its own, with its record,
and is kept only if the eval case improves when run with the edit and not without; for a step
with no eval case, write the case first (the `incident-to-eval` skill). `transcripts report`
lists the proposals a folder holds.

**Comparing a proposal** (record `docs/changes/2026-11-17-compare-proposals.md`).
`transcripts compare [DIR] --session ID --step STEP [--repo-dir DIR] [--runs N] [--max-cost USD] [--run]`
makes that comparison. It puts the edit on the skill as it is in `--repo-dir` (the current
directory by default): the proposal's file when the skill is still the version the session
used, otherwise each part of `SKILL.diff`, which must stand once, unchanged, in the current file.
When one does not, it says so and runs nothing: make the edit again by hand. For each eval case
of the step it runs `claude plugin eval` twice, with the plugin as it is and with a copy under
`DIR/compare/<session>/<step>/` whose skill file has the edit, `--ablation none`, 6 runs and at
most $2 an arm unless `--runs` and `--max-cost` say otherwise. Without `--run` it prints what it
would run and the most it could spend, and runs nothing:

    transcripts compare: the edit to change-record:change proposed from session bf01bd72... at step red-first, the edit put on the skill as it is now.
    It would run, with no arm without the plugin:
      plugins/change-record/evals/red-first (graders saw-it-fail, test-run-before-code-change): 6 runs with the skill as it is and 6 with the edit
      plugins/change-record/evals/red-first-workflow (graders saw-it-fail, test-run-before-workflow-change): 6 runs with the skill as it is and 6 with the edit
    Each arm of each case stops at $2.00, so at most $8.00 in all.
    Nothing was run: add --run to run it.

The edit is **kept** when the step's graders pass more often with it, summed over its cases,
and no case's mean over its scored graders is lower with it; it is **dropped** otherwise, a tie
included. `skill-fired`, the runner's sign that the skill was loaded, is not counted. A run that
errored, a result the ceiling cut short, or a runner that exits other than 0 or 1 gives no
verdict and exit 1. The counts and the verdict go to `compare.json` and `compare.md` beside the
proposal. It never writes the skill: a kept edit still enters it as a change of its own.

**Probing Codex and Cursor (the owner's steps).** Capture of Codex and Cursor sessions (record
`docs/changes/2026-11-11-codex-cursor-capture.md`) is built on what those agents' hooks really
pass, and neither agent runs in the cloud environment. `transcripts probe --agent codex|cursor`
is a hook command that writes a sample of it: `<agent>-<event>.json`, in
`plugins/change-record/grade/fixtures/agents/` unless `--out DIR` names another folder. A
sample holds structure and no content: the hook input's keys and value types; the transcript
path with every part replaced by its class (`~/.codex/sessions/<n>/<n>/<n>/rollout-<timestamp>-<uuid>.jsonl`);
the transcript's format, line count and, per kind of line, its key paths and types; the values
of the few fields that name a kind of thing (`type`, `role`, `status`, `model`, the version
fields, and `name` inside a tool call) when they look like an identifier or a version number;
how often fixed phrases occur (`*** Update File:`, `rejected by user`, `Change: docs/changes/`);
and the names, never the values, of `CODEX_*` and `CURSOR_*` environment variables. A key that
does not look like a field name is written `<key>`. A string that is itself JSON (a prompt, a
file a command printed) is content: it is opened one level, for its types, and its keys are
written `<key>`, except the parameter names of a tool call's argument string and the words an
agent's own wrapper around a result uses (`output`, `metadata`, `exit_code`); none of its
values is kept. It holds no prompt, answer, command, path, address or id. Read each sample
before you commit it all the same: a plain object's key names are kept when they look like
field names. `probe` never fails the session: every problem is a line on stderr and exit 0,
it prints nothing on stdout, and it reads at most 20 MB of the transcript. The list of what a
sample may hold is at the top of `probe/agent_sample.py`.

Nothing below has run against the real agents. Each step marked *unverified* rests on an
assumption in the record's Probed facts; if one turns out wrong, say what you saw instead and
that is itself the finding. Do the steps yourself: no agent may answer a trust, permission or
login prompt, and no Codex or Cursor login goes into a cloud environment (the record's C2, C4).

1. In your checkout of this repository, on a branch cut from `main`, write the two hook files.
   They hold your checkout's absolute path, so they are for this probe only: do not commit
   them (the capture task adds the real ones).

       root="$(git rev-parse --show-toplevel)"
       mkdir -p "$root/.codex" "$root/.cursor"
       cat > "$root/.codex/hooks.json" <<EOF
       {"hooks": {"Stop":       [{"hooks": [{"type": "command", "command": "$root/plugins/change-record/bin/transcripts probe --agent codex", "timeout": 10}]}],
                  "SessionEnd": [{"hooks": [{"type": "command", "command": "$root/plugins/change-record/bin/transcripts probe --agent codex", "timeout": 10}]}]}}
       EOF
       cat > "$root/.cursor/hooks.json" <<EOF
       {"version": 1, "hooks": {"stop":       [{"command": "$root/plugins/change-record/bin/transcripts probe --agent cursor"}],
                                "sessionEnd": [{"command": "$root/plugins/change-record/bin/transcripts probe --agent cursor"}]}}
       EOF

   *Unverified:* the layout of both files (Codex's is taken to be Claude Code's; Cursor's is
   from its documentation as quoted in search results), that Codex reads a project's
   `.codex/hooks.json` without a feature being switched on in `config.toml`, and that either
   agent runs the command through a shell. The command has no `|| true` and no variable so
   that it works either way; a checkout path with a space in it may still break it.
2. **Codex.** Start `codex` in the checkout, in a mode that asks before it runs a command.
   *Unverified:* Codex asks once whether to trust this project's hooks, because the hook is
   new (and again whenever the command changes); it may also ask whether to trust the folder.
   The wording is not known. Only you answer it. Then give it one short task that makes one
   of each thing the record assumes about: "Run `git status`. Create the file
   `probe-scratch.txt` holding one line. Then run `touch probe-scratch-2.txt`. End your answer
   with the line `Change: docs/changes/probe.md`." Approve the first command and the edit and
   refuse the last command. Let the turn end, then quit Codex. *Unverified:* `Stop` fires at
   the end of the turn and `SessionEnd` on quitting, so two files appear:
   `plugins/change-record/grade/fixtures/agents/codex-stop.json` and `codex-sessionend.json`.
3. **Cursor.** Open the checkout in Cursor (or run its CLI agent there), give the agent the same
   task in a mode that asks before running commands, refuse the last command, let the turn end,
   then close the window. *Unverified:* project hooks need no approval in Cursor, `stop` fires
   at the end of the turn and `sessionEnd` when the window closes, so `cursor-stop.json` and
   perhaps `cursor-sessionend.json` appear in the same folder. If transcripts are turned off in
   Cursor, the sample says `"given": false`, which is worth knowing too: commit it, then turn
   them on and run once more with `--out` naming another folder to keep both.
4. If no file appears, the hook did not run or could not write. Run the command from the hook
   file by hand with `echo '{}' |` in front: it should print `transcripts probe: wrote ...` and
   leave `<agent>-unknown.json`, which you delete. If that works, the agent is not running the
   hook, and what it showed (or did not) is the finding.
5. Check each sample before it leaves your machine. This should print nothing:

       cd "$root/plugins/change-record/grade/fixtures/agents"
       grep -nE "@|$HOME|/Users/|/home/|[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-|probe-scratch|git status" *.json

   Then read the files. Copied strings can only be in three places: under `"values"` (expect
   type names, tool names, model names and version numbers), under `"variables"` (names of
   environment variables) and as key names in the paths. Anything else is counts and classes.
   If something that is yours shows up, do not commit it; say which field it was.
6. Remove the scratch files and the two hook files, and commit only the samples, on your branch:

       rm -f "$root"/probe-scratch.txt "$root"/probe-scratch-2.txt "$root/.codex/hooks.json" "$root/.cursor/hooks.json"
       git add plugins/change-record/grade/fixtures/agents/codex-*.json plugins/change-record/grade/fixtures/agents/cursor-*.json
       git commit -m "test(transcripts): samples of what Codex's and Cursor's hooks pass"

   Open the pull request with `Change: docs/changes/2026-11-11-codex-cursor-capture.md` as the
   first line of its body. The record's Probed facts change label from what the samples show in
   that pull request, which completes the record's task 1.

`grade/fixtures/agents/made-up/` holds the invented Codex and Cursor files the tests run `probe`
on, and the samples it must give for them. They are shaped like the record's assumptions, not
like anything a real agent wrote.

## What is not here yet

- **A code review as a CI check** of its own. Use `agent-review` locally before the push, or
  a reviewer in CI (Open Code Review, or the `agent-workflow` PR-Agent workflow); the skill
  treats findings from any of them the same way. A `review-check` that fails the PR on a critical finding until the
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

Whether the code that comes out is better was measured separately, on 2026-11-14
(`outcome-evals/README.md`): five small tasks with hidden tests, with and without the
plugin, five runs each on Sonnet 5.5. No effect was shown on hidden tests, error paths,
mutation score, coverage or scope; the plugin's arm took about twice the turns. On tasks
that small the skill's value is the record and the review, not better code.

The plugin's capture hook was run for real on 2026-11-15 (Claude Code 2.1.325): the plugin
installed for the user from this repository as a local marketplace, then sessions with no
`--plugin-dir`. A session in a scratch repository on a scratch scope list was archived; one in
a repository off the list, and one with no list, were not. In this checkout, where the
repository's own hook also runs, the two left one index entry and the transcript's lines once.

## Tests

    bash plugins/change-record/bin/red-check.test.sh
    bash plugins/change-record/bin/record-check.test.sh
    bash plugins/change-record/bin/dispatch.test.sh
    bash plugins/change-record/bin/record-review.test.sh
    bash plugins/change-record/bin/transcripts.test.sh
    bash plugins/change-record/bin/transcripts-store.test.sh
    bash plugins/change-record/bin/transcripts-grade.test.sh
    bash plugins/change-record/bin/transcripts-judge.test.sh   # TRANSCRIPTS_LIVE_JUDGE=1 also runs the real Haiku judge
    bash plugins/change-record/outcome-evals/checks/selftest.sh
    bash plugins/change-record/outcome-evals/run.test.sh
    node --test plugins/change-record/evals/cases.test.cjs

They build real git repositories in a scratch directory and need bash, git and python3 (the
`--json` assertions parse the documents with it; the scripts themselves fall back to a shell
encoder when python3 is absent). Every guard in these scripts was mutation-checked: each was
broken in turn and a test failed.
