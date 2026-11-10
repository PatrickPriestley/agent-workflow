---
id: 2026-11-09-skill-transcripts
tier: 2
status: approved
requester: Patrick Priestley, in chat on 2026-11-09 and 2026-11-10 ("I want to track skill transcripts so I can evaluate them", "We don't have to use skill doctor as written if creating our own evaluation agent makes more sense", "rewrite the record as capture and evaluate", "How do we register transcripts across multiple sessions and machines", "add it to the record", "Didn't we say database over repo?", "Works for me")
approvers: [Patrick Priestley, 2026-11-10]
plugin: plugins/change-record
tasks:
  - name: capture
    done: true
  - name: store
    after: capture
    done: true
  - name: grade
    after: store
    done: true
  - name: report
    after: grade
---
# Real agent sessions are kept and graded against the change skill's own steps

## Goal

Every agent session that works in this repository, on any machine, cloud and `dispatch`
sessions included, leaves its transcript in one shared database with an index row saying where
it came from. An evaluator of our own then grades each session against the `change` skill's
steps, using the transcript together with the record, the check results and the PR it
produced, and keeps the scores so a change to the skill shows up as a change in how sessions
behave.

## Probed facts

Capture:

- Verified against the real system (Claude Code 2.1.319, 2026-11-09): a project
  `.claude/settings.json` with `Stop` and `SessionEnd` hooks, under `claude -p`, ran both and
  passed each, on stdin, JSON with `session_id`, `cwd`, `hook_event_name` and a
  `transcript_path` to an existing file under `~/.claude/projects/<dir>/<id>.jsonl`.
- Verified against the real system: this cloud container holds this session's transcript
  (12 MB), the two real `dispatch` sessions and 156 eval-runner sessions (23 MB); all are lost
  when the container is reclaimed. A copy was sent to the owner on 2026-11-09. The repository
  is private and has no `.claude/settings.json` today.
- Exact source (the Claude Code 2.1.321 binary's settings schema, checked in task 1): "Number
  of days to retain chat transcripts before automatic cleanup (default: 30). Minimum 1", and
  "Cleanup deletes data only on this computer". A container records its last cleanup in
  `~/.claude/.last-cleanup`.

Identity, across sessions and machines:

- Verified against the real system (2026-11-10): every line of a transcript carries
  `sessionId` (a UUID), `timestamp`, `cwd`, `gitBranch`, `version` and `entrypoint`; this
  session's lines run from 2026-11-07T23:45 to 2026-11-10T00:05 under one `sessionId`, across a
  compaction and a model switch.
- Verified against the real system: a cloud session's environment carries
  `CLAUDE_CODE_REMOTE`, `CLAUDE_CODE_REMOTE_SESSION_ID` (the claude.ai/code session) and
  `CLAUDE_CODE_CONTAINER_ID`. The hostname is `vm`, so it identifies nothing. The checkout's
  `origin` is `https://github.com/PatrickPriestley/agent-workflow`, while its path is
  `/home/user/agent-workflow`, which differs from a laptop's checkout of the same repository.
- Verified against the real system: the compaction appended a `compact_boundary` record and
  kept every earlier line in the file. Verified against the real system (Claude Code 2.1.321,
  task 1): a `claude -p` session, then `--resume` with a prompt, `--resume` with `/compact`, and
  `--resume` again kept one file and one `session_id`, and each snapshot (22, 30, 48, 63 lines)
  was a byte prefix of the next.
- Verified against the real system (task 1): a cloud session's environment carries
  `CLAUDE_CODE_SESSION_ID`, equal to its transcript's file name and `sessionId`, and `claude -p`
  here records `entrypoint` `remote`. Exact source (the binary): subagent transcripts live at
  `<project dir>/<sessionId>/subagents/[<subdir>/]agent-<id>.jsonl`, and a command hook takes
  `timeout` (seconds) and `async`.
- Exact source: git does not store file modification times, and Skill Doctor's collector
  filters transcripts by modification time, so files taken from a git store need their times
  set from their own timestamps before Skill Doctor reads them.
- Exact source (the `claude-artifacts` tools, 2026-11-10): the artifact database is written
  only through Claude's own tools (`db_write`, at most 50 documents per call, rate-limited), so a
  shell hook cannot write to it.
- Verified against the real system (task 2, 2026-11-10): the owner's Supabase project answers
  PostgREST over HTTPS with the publishable key the cloud proxy injects, whether the request
  carries no `apikey` header or a placeholder one (`GET` and `POST /rest/v1/chunks` before the
  schema existed: 404 `PGRST205`, "Could not find the table 'public.chunks'", not 401); the
  schema root `GET /rest/v1/` answers 401 "Secret API key required". Python's `urllib` reaches
  it through the proxy with no extra setup.
- Verified against the real system (task 2, 2026-11-10, `store/probe` after the owner applied
  `store/schema.sql`): with the publishable key the proxy injects, an insert into `chunks` or
  `sessions` answers 201; the same key again, with other bytes, answers 409 `23505` "duplicate
  key value violates unique constraint"; select, an insert with `return=representation`,
  update, delete and any access to `scores` answer 401 `42501` "permission denied". So the key
  is held to insert-only by the grants alone, and a duplicate cannot change a stored row.
- Verified against the real system (same probe): `Prefer: resolution=ignore-duplicates` answers
  401 `42501` with the hint "GRANT SELECT ON public.chunks TO anon": PostgREST sends `ON CONFLICT
  DO NOTHING`, which needs SELECT. So senders insert one row per request and count a 409 as
  already stored, rather than grant SELECT.
- Verified against the real system: a 4 MB request body is accepted (201).
- Verified against the real system (task 2): a hook under `claude -p` gets that process's own
  proxy (`HTTPS_PROXY=http://127.0.0.1:35135` in the hook, `:34313` in the parent session's
  shell), which closes when the process exits, so the background push started by a `-p`
  session's last stop got "Connection refused". The next stop of any session using the same
  archive sends those lines (Outcome).
- Exact source (`dispatch`): the agent's JSON, saved beside each worktree as
  `<name>.agent.json`, carries the child session's `session_id`.

Contents, for grading:

- Verified against the real system (this session's file, 2026-11-10): every tool call is
  kept with its name, full input and the result the model saw, MCP calls included (185 of 620,
  named `mcp__<server>__<tool>`). Ten results carry the error flag, three of them permission
  denials; 103 results without the flag still report a failure in their text (a test run piped
  through `tail`, CI logs fetched over MCP). MCP servers dropping and reconnecting appear as
  `attachment` records, not as tool errors. Of 309 reasoning blocks, 62 keep their text.
- Verified against the real system: tool calls are compact JSON in the same shape as the eval
  runner's trace (`"type":"tool_use","id":…,"name":…,"input":…`), the plugin skill is recorded
  as `"name":"Skill","input":{"skill":"change-record:change"}`, tool results appear in both key
  orders within one file, and one `attachment` line holds every tool's definition.
- Verified against the real system: the eval suite's red-first graders, run unchanged on the
  two `dispatch` sessions, gave the expected answers, except that the issued-command grader
  passed on a command that was denied and never ran.
- Exact source (`plugins/change-record/evals/*/graders/*.md`): the eval graders name their
  case's code file (`greet.py`) and record id, so they cannot run unchanged on other sessions.
- Exact source (`warpdotdev/common-skills`, `skill-doctor`, cloned 2026-11-09): Skill Doctor
  reads `projects/*/*.jsonl` under `--claude-home`, finds skills only in `.agents`, `.claude`
  and `.codex` skill folders or `--skills-dir`, counts a skill as used only when a tool call
  names its folder name (so `change-record:change` counts as no skill), and grades the
  transcript alone on four generic rubrics with an LLM.

## Problem

Most work on this repository happens in cloud sessions whose transcripts vanish with the
container, including every `dispatch` session, and sessions on a laptop are deleted after a
month. Sessions from different machines name the same repository by different paths, and
nothing ties a `dispatch` child to the session that started it. So there is nothing to grade
the skill on after the fact, and nothing that says which sessions belong together. The tool
built for grading, Skill Doctor, would grade on generic rubrics from the transcript alone, and
would score the `change` skill as unused in the very sessions that used it. Whether real
sessions follow the skill's steps is today an impression, not a number.

## Requirements

Capture and registry:

- R1. When a session in scope (C4) stops or ends, its new transcript lines, and any subagent
  transcripts, are added to a local archive, and the session's index entry is written or
  updated. Check: a test feeds hook JSON twice for a growing fake transcript and finds both
  parts and one index entry.
- R2. Capture is opt-in and never blocks a session: with no archive configured the hook does
  nothing; any failure, including no network, exits 0 with a message and is retried at the next
  stop. Check: tests for unset, unwritable, bad JSON and an unreachable remote.
- R3. A session's index entry, one file per session keyed by `sessionId`, holds: source kind
  (local, cloud, `dispatch` child, eval), machine id (a random id written once per machine; in
  the cloud the container id and the cloud session id), repository by its normalised remote
  URL, branch and commit at first and last stop, first and last timestamp from the transcript,
  skills invoked with each skill file's git blob hash, the record named or written, the parent
  session for a `dispatch` child, the line count and hash of what has been sent, and the
  redaction version. Check: a test compares the entry for a fixture session with a stored one.
- R4. The database receives only lines it does not have, as numbered compressed chunks per
  session; when a transcript is no longer an extension of what was sent, a full copy is sent as
  a new generation and the index row says so. Two machines sending at once both succeed. Check:
  tests against a stand-in for the database's HTTPS interface for growth, a rewrite, and two
  concurrent senders.
- R5. Transcripts reach the database redacted as decided under C2, with a key that can only
  insert; a local archive is never written into a repository's working tree. Check: a test
  finds no unredacted string in what was sent, and refuses an archive inside a repository.
- R6. `transcripts import` registers sessions already in a machine's `~/.claude/projects` once,
  for repositories in scope. Check: a test imports a fixture project directory, then imports it
  again and finds nothing new.
- R7. `transcripts materialize` rebuilds, from the database, a folder in Claude Code's layout with
  each file's time set from its last timestamp, plus a skills folder with plugin-qualified
  names, for the evaluator and for Skill Doctor. Check: a test materialises a fixture store and
  finds the files, times and skill folders expected.

Grading:

- R8. For each registered session the evaluator records, per step of the `change` skill, pass,
  fail or not applicable, from deterministic checks on the transcript and on the record at the
  session's last commit: tier declared, probe before record, record before code, test run and
  seen failing before code, `Change:` line first in the PR body, record passes `record-check`,
  Outcome filled when done. A failure counts from the error flag or from failure text in a
  result, and a denied command counts as not run. Check: fixture sessions in both tool-result
  key orders, with flagged and unflagged failures and a denial, give the expected verdicts.
- R9. The deterministic graders are generalised from the eval graders and run against the eval
  graders' fixtures and against fixtures cut from real sessions. Check: both fixture sets pass
  through the same grader code.
- R10. Two judgments no regex settles, whether Decisions name a rejected alternative and
  whether the Outcome quotes real output, are made by a fresh Claude Haiku session with three
  votes, and the first report measures its agreement with a judge from another model family
  (C3). Check: the judge's prompt and votes are kept per session, a fixture with a known answer
  gets it, and the first report states the agreement rate.
- R11. Scores are kept in the database per session and per skill version, and a report lists each step's pass
  rate over time and, only from failed sessions, proposed skill edits citing the session and
  step. Check: the report from known score rows matches a stored expected report.

## Options and concerns

Options considered:

- A. Skill Doctor as written, on an archive. Rejected as the evaluator: generic rubrics, the
  transcript only, plugin skills missed, an LLM judging its own model family. Kept as an
  optional second opinion through R7.
- B. Our own evaluator: capture by hook into a registry, deterministic graders first, an LLM
  judge for what remains, scores kept. Recommended.
- C. Extend the eval runner to read real sessions. Rejected: its graders run on cases it starts
  itself; it has no input for an existing transcript.

For the store:

- D. A hosted Postgres database with three tables: `sessions` (the index, one row per session),
  `chunks` (one row per session, generation and number) and `scores`. Chosen (C1): rows keyed
  by session and chunk number make concurrent senders skip what exists without retries, nothing
  accumulates copies, and the trend report is a query.
- E. Push the whole transcript at each stop. Rejected: every turn would add a full copy.
- F. A private git repository with one index file per session and chunk files. The fallback if
  a database vendor is not wanted: it works with tools already on every machine, at the cost of
  push retries and a store that only grows.
- G. The artifact database. Rejected for transcripts and scores: a shell hook cannot write to
  it, and a 12 MB transcript would have to pass through an agent's context to reach it.

Concerns:

### C1: where transcripts and scores persist
A cloud container keeps nothing. (a) A new private repository used only for transcripts, such
as `PatrickPriestley/agent-transcripts`, laid out as in F; (b) Google Drive, uploaded by the
agent at the end of a session with one approval each; (c) a hosted database,
as in D; (d) local only, cloud sessions lost. Scores: the private artifact database with a
private page for the trend, or beside the transcripts. Recommended at first: transcripts (a), scores in
the artifact database. (a) uploads transcripts to GitHub, which Skill Doctor's own guidance
avoids, and the owner creates the repository (this session cannot). Owner: Patrick Priestley.
Resolved by: a hosted Postgres database holding the index, the chunks and the scores (D), with
an insert-only key for the hooks and a separate read key for grading, on Supabase; the owner
creates the project before task 2. The private repository (F) stays the fallback. Patrick
Priestley, 2026-11-10.

### C2: personal data and secrets in transcripts
Transcripts hold the owner's email address, file contents, command output and whatever MCP
calls returned. Recommended: before anything leaves the machine, replace the email address and
token-shaped strings (GitHub, Anthropic, AWS, bearer tokens) with placeholders, keep the
unredacted copy local, and record the redaction version in the index. The graders do not read
those strings. Owner: Patrick Priestley.
Resolved by: as recommended. Patrick Priestley, 2026-11-10.

### C3: the judge's model and cost
R10 asks for a model family other than the session's. The repository already reaches two
through OpenCode Go: `agent-review` uses `opencode-go/kimi-k3.1-pro`, and the PR-Agent workflow
uses `glm-5.3`, which has timed out often on this repository's PRs. Three votes on two
judgments is six short calls per session. Recommended: reuse `agent-review`'s reviewer
selection and fallback, and judge only sessions that changed code, capped per report. Owner:
Patrick Priestley.
Resolved by: the two judgments are narrow and close to factual, so a fresh Claude Haiku session
judges them (three votes, sessions that changed code only, at most 20 sessions per report),
as the eval runner's own judge does; the first report also judges 10 sessions with
`opencode-go/kimi-k3.1-pro` and records how often the two agree, and the default moves to the
other family if they disagree often. Open-ended judgments, such as reviewing proposed skill
edits, stay with a model family other than Claude. R10 changes to match. Patrick Priestley,
2026-11-10.

### C4: which sessions are captured
A hook in this repository's `.claude/settings.json` captures only sessions in this repository
and in the worktrees `dispatch` cuts from it. Capturing every repository the owner works in
needs the hook in user settings on each machine and in the cloud environment's setup.
Recommended: this repository only, widened later if the scores prove useful. Owner: Patrick
Priestley.
Resolved by: as recommended, this repository and its `dispatch` worktrees. Patrick
Priestley, 2026-11-10.

## Decisions

- A session is identified by its transcript's `sessionId` everywhere; machine, cloud session
  and source kind are attributes in its index entry, never part of the key. Rejected: hostname
  or path, which are `vm` and machine-specific.
- A repository is identified by its normalised remote URL, not its path. Rejected: the path,
  which differs between a laptop and a cloud checkout of the same repository.
- Times come from the transcript's own timestamps; `materialize` sets file times from them.
  Rejected: file modification times, which git does not keep.
- The store keeps chunks, the evaluator and Skill Doctor read a folder `materialize` rebuilds in
  Claude Code's layout. Rejected: storing that layout directly, which needs whole-file uploads.
- The hook lives in this repository's `.claude/settings.json`, so worktrees `dispatch` cuts carry
  it, and does nothing unless `AGENT_TRANSCRIPTS` names an archive. `dispatch` sets
  `AGENT_TRANSCRIPTS_PARENT` to its own session id for each child. Rejected: user settings only,
  which `dispatch` worktrees and cloud environments would not share (see C4 for widening).
- Field graders generalise the eval graders: any file outside `docs/changes/` and the test
  directories counts as code, the record is the one the session wrote or named on its
  `Change:` line, tool results are matched in either key order, failures are read from result
  text as well as the error flag, and the tool-definitions attachment is skipped. Rejected:
  running the eval grader files unchanged, since they name the case's own file and record.
- A command a session issued but was denied does not count as run: the grader requires the
  call's own result, matched by tool id, to be a result and not a denial.
- Scores are stored with each skill file's git blob hash, so a report compares sessions before
  and after an edit to the skill. Rejected: dates alone, which mix two skill versions.
- The hooks' key can insert rows and nothing else; grading reads with a separate key kept on
  the owner's machine. Rejected: one key everywhere, which would let any environment holding it
  read or delete every transcript.
- In a cloud environment the database host is allowed and the insert key saved through the
  environment's secure credential form, proposed when task 2 starts. Rejected: putting the key
  in an environment variable, which the environment stores in plain text.
- The hook sends in the background with a time limit, so a slow or unreachable database never
  delays a session; unsent lines go at the next stop.
- Skill Doctor stays an optional second opinion on a materialised folder; the README gives its
  flags. Reporting its plugin-name gap upstream is left to the owner.
- All of it lives in the `change-record` plugin (`bin/transcripts`), leaving the
  `agent-workflow` plugin as it is.
- (Task 1.) The local archive is parts plus index files: `parts/<sessionId>/<stream>/g<G>-<N>.jsonl`
  for each run's new complete lines, `sessions/<sessionId>.json`, and a `locks/<sessionId>`
  directory per run, taken over after 60 s. Only complete lines are taken, so a line still
  being written waits; a transcript that stops extending what was archived starts a new
  generation with a full copy. Rejected: copying the whole file at each stop, which is what E
  rejects for the store, and appending to one archive file, which a crash mid-write corrupts.
- (Task 1.) The hooks are synchronous with a 10 s timeout and `|| true`, not `async`: archiving
  is a local copy of the new bytes, about 50 ms, and an async `Stop` hook could still be running
  when `SessionEnd` starts. The background send of the Decision above belongs to task 2.
- (Task 1.) A record is tied to a session only from the session's own acts: a Write or Edit of
  `docs/changes/*.md`, or a `Change:` line in its own text, never in a prompt or a tool result
  (a `dispatch` brief carries a literal `Change:` line). When the written and the named records
  disagree, or there are several, the entry has none. Rejected: the first record mentioned,
  which ties a session that read another record to it.
- (Task 1.) Source is eval (cwd under `/claude-eval-`) before dispatch (a parent set) before
  cloud (`CLAUDE_CODE_REMOTE` or entrypoint `remote`) before local; the parent is taken at the
  first stop only and never equal to the session itself, and `dispatch` unsets it when it has
  no session id of its own, so a stale value is not passed on. A skill counts as invoked through
  the Skill tool or a Read of its `SKILL.md`, since a session without the plugin installed
  reads the file instead.
- (Task 1.) The archive refuses a directory inside any git working tree (R5's local half,
  taken early because task 1 is where the archive is first written).
- (Task 1, review.) `transcripts` runs under umask 077, so every folder and file it creates in
  the archive is open to its owner only, as Claude Code keeps `~/.claude/projects` (0700
  folders, 0600 files). Rejected: the user's umask, under which a common 022 makes unredacted
  transcripts readable by every local user.
- (Task 2.) Senders insert one row per request and count a 409 duplicate as stored. Rejected:
  `Prefer: resolution=ignore-duplicates`, which needs SELECT (probed), and granting SELECT on
  the key columns, which would let the hooks' key list sessions.
- (Task 2.) A chunk's key is a hash chain, `sha256(start ":" sha256(redacted bytes))` from
  `sha256(sessionId "/" stream)`; `generation` and `number` are the sender's, kept as columns.
  Two senders store a shared chunk once, different chunkings never collide, nobody can claim a
  key ahead of the bytes, and `materialize` checks every chunk. Rejected: keys by session,
  generation and number, under which two machines chunking one session differently would
  silently drop each other's bytes on a duplicate.
- (Task 2.) An index row is a new version keyed by the hash of its content, with the sending
  machine (`sender`: the machine id, or `cloud:<container>`); `materialize` takes, per session,
  the row with the latest transcript timestamp, then the most bytes, then the highest version.
  Rejected: updating one row per session, which the insert-only key cannot do.
- (Task 2.) Redaction (version 1) runs on each JSON string after decoding, and a line with
  nothing to redact keeps its exact bytes; it replaces every email-shaped string, not only the
  owner's, plus GitHub, Anthropic, AWS, Supabase, Slack and `sk-` keys, JWTs, bearer and basic
  tokens, URL passwords and private key blocks. Rejected: regexes over the raw line, which can
  cut a JSON escape such as `\n` and break the line, and a list of the owner's addresses, which
  would put them in the repository. A new version resends every stream as a new generation.
- (Task 2.) The insert key comes from `~/.config/agent-transcripts/insert-key` (refused unless
  0600), or from nowhere in the cloud, where the proxy injects it; the read key only from
  `read-key` beside it. Rejected: an environment variable, which every child process inherits
  and settings files keep in plain text. `AGENT_TRANSCRIPTS_URL` must be https (or 127.0.0.1).
- (Task 2.) The hook starts `push --background` detached (its own session, no pipes back to
  the hook) with a 60 s limit, and every push sends every session in the archive with unsent
  lines, so lines a stop could not send, including a `claude -p` session's last ones whose proxy
  is gone, go at the next stop of any session on that archive. Rejected: a foreground push at
  `SessionEnd`, which would delay every `dispatch` child's exit by the store's latency.
- (Task 2.) The cloud environment `agent-workflow` sets `AGENT_TRANSCRIPTS=~/agent-transcripts`
  and `AGENT_TRANSCRIPTS_URL`; its network allows the project's host and its proxy injects the
  publishable key (set up before task 2).

- (Task 3.) Grading runs where the read key is: `transcripts grade` works on a local folder (the
  archive, or a folder `materialize` wrote), reads the record with git at the session's first and
  last commit from a checkout (`--repo-dir`), writes its rows beside the transcripts in
  `scores/<sessionId>.json`, and only `--store`, on the owner's machine, inserts them into
  `scores` with the read key. Rejected: widening the hooks' insert-only key to `scores`, which
  would let any environment write scores, and grading in the cloud against the store, which
  would put the read key there.
- (Task 3.) A score is one row per step, as the `scores` table task 2 created is keyed
  (session, step, grader, graded_at), so "one score row per session" in task 3 is a session's
  seven rows. Each carries the change skill's name and blob from the index entry, and the
  grader `fields/1`, bumped when a rule changes. Rejected: one row with every step in a JSON
  column, which the report would have to unpack per step.
- (Task 3.) A call ran when its own result says so: no result, a denial (a permission prompt
  refused or unanswered, an interruption, a tool error), flagged or not, or a flagged result of
  any tool but Bash, means it did nothing; a flagged Bash result that is not a denial ran and
  failed. Rejected: requiring an `Exit code` prefix on a failed Bash result, which the eval
  traces do not always carry.
- (Task 3.) The record is tied to the session as in task 1, but only from acts that ran, shell
  writes and pull request bodies included; a step a session never reached is not applicable:
  no record (every record step), the record there before the session (probe and record before
  code, judged from its first commit or the session's first act on it, since a record can sit
  uncommitted), no code (red-first, record-before-code), no pull request or description
  (change-line), a record not done (outcome-filled), no commit (the steps that read the record).
  Tier 0, declared or recorded, needs no red-first. Rejected: failing those steps, which would
  score a session for work it was never asked to do.
- (Task 3.) Where the field graders part from the eval graders on the eval fixtures, on purpose
  and listed in `cases.test.cjs`: a code file copied to a new path inside the repository is
  code, and a scratch script that is run is a probe whatever it imports, since no field grader
  knows which dependency a change rests on. The eval fixtures whose code never comes are given
  the same code write on both sides, since a field grader holds a step no code reached as not
  applicable.

## Tasks

One pull request each, in order.

1. **Local capture and registry.** `plugins/change-record/bin/transcripts` with `archive` (hook
   JSON on stdin, or `--transcript PATH`) and `import`; the index entry of R3; the opt-in hook
   in `.claude/settings.json`; the parent variable in `dispatch`; `bin/transcripts.test.sh`; a
   README section. First probe: transcripts are append-only across a resume and a compaction,
   and `cleanupPeriodDays`. Test: the suite asserts R1, R2, R3 and R6; it fails today because
   the command does not exist.
2. **Database store.** The schema for `sessions`, `chunks` and `scores` in the owner's Supabase
   project, with the insert-only and read keys; `transcripts push` (new chunks, a new generation on
   rewrite, redaction per C2) and `materialize`; the network and credential settings that turn
   it on for cloud sessions. Test: a stand-in for the database's HTTPS interface receives
   redacted chunks from two senders without duplicates, a rewrite yields a new generation, and
   `materialize` gives the expected folder (R4, R5, R7); it fails today because the subcommands
   do not exist.
3. **Deterministic grading.** `transcripts grade` with the field graders for R8 and R9, writing
   one score row per session. Test: fixtures cut from the two real `dispatch` sessions and from
   the eval graders' fixtures give the expected verdict per step, the denied-command case
   included; it fails today. (Built: one row per step, see Decisions; rows are local, and
   `--store` sends them from the owner's machine.)
4. **Judge, scores and report.** The R10 judge per C3 with its agreement check, scores written
   to the database, and the R11 report with proposed skill edits from failed sessions. Test:
   known score rows give the stored expected report, and a judge fixture with a known answer
   gets it; it fails today.

## Checks

`bash plugins/change-record/bin/transcripts.test.sh` and `node --test
plugins/change-record/evals/cases.test.cjs`. Real use: a `claude -p` session in this repository
with `AGENT_TRANSCRIPTS` set is archived, sent to the database and graded, and the two archived `dispatch`
sessions grade as the probes expect (the second passes red-first, the first fails it); a second
machine, or a second container, sending at the same time adds its own chunks without conflict.
Error path: an unwritable archive or an unreachable database leaves the session unaffected and is
retried at the next stop, and a session with no record grades every record step as not
applicable rather than failed. The reviewer should attack: whether the hook can ever fail or
slow a session, whether anything leaves the machine unredacted, whether two machines can
overwrite each other's chunks or index rows, whether the hooks' key can read or delete, whether a grader can pass a step on a denied or
never-run command, and whether a session can be tied to the wrong record or parent.

## Outcome

### Task 1: capture (branch `2026-11-09-skill-transcripts/capture`)

Shipped: `plugins/change-record/bin/transcripts` (`archive`, `import`), the opt-in hooks in
`.claude/settings.json`, `AGENT_TRANSCRIPTS_PARENT` in `dispatch`, `bin/transcripts.test.sh`
(78 assertions: R1, R2, R3, R6 and the hook config, four added in review for a transcript cut
below one line and for the archive's permissions) and two new `dispatch` assertions, a README
section, and the suite in `.github/workflows/test.yml`. The tests failed first on their
assertions (62 of 69, exit 127 with no parts and no entry; and `[stale]` where the parent id
was expected). Every guard was broken by hand and a test failed; the two first survivors (a
quoted `Change:` line in a user text block, an eval run inside a checkout) got fixtures.

Not shipped (later tasks): sending to the database, redaction, `materialize`, grading. The
`tool-results/` files beside a transcript (large outputs the model saw a preview of) are not
archived. Imported sessions carry no parent and no commit. Not run for real: a `dispatch`
child with the hook, since that costs a full agent run; the variable is covered by the test.

Real use, in this cloud container. Main path, a `claude -p` session in this repository with
the hook in place:

    $ AGENT_TRANSCRIPTS=$S/archive claude -p --output-format json "Reply with the word ok."
    rc=0  sid=e5ca3179-0aab-45c0-aedb-f6baa498e4a9
    $ find $S/archive -type f
    archive/sessions/e5ca3179-0aab-45c0-aedb-f6baa498e4a9.json
    archive/parts/e5ca3179-0aab-45c0-aedb-f6baa498e4a9/main/g1-000001.jsonl   (Stop)
    archive/parts/e5ca3179-0aab-45c0-aedb-f6baa498e4a9/main/g1-000002.jsonl   (SessionEnd)
    $ cat archive/parts/e5ca3179-.../main/g1-*.jsonl | cmp - ~/.claude/projects/-home-user-agent-workflow/e5ca3179-....jsonl
    parts rejoin to the transcript
    $ cat archive/sessions/e5ca3179-0aab-45c0-aedb-f6baa498e4a9.json   (abridged)
    "source": "cloud",
    "machine": {"id": null, "cloud_container": "container_014ftvxVWFTziN4BpstuEiWF", "cloud_session": "cse_01QoTuvL7MqCiwcVSuPYChLw"},
    "repository": "github.com/patrickpriestley/agent-workflow",
    "first_stop": {"branch": "2026-11-09-skill-transcripts/capture", "commit": "f914002dc75c65074674ee17fb6a385a6a913b73"},
    "first_timestamp": "2026-11-10T01:55:17.886Z", "last_timestamp": "2026-11-10T01:55:22.474Z",
    "streams": {"main": {"generation": 1, "parts": 2, "lines": 24, "bytes": 138909, "sha256": "1219f1ce..."}}

Error path, an unwritable archive: the session is unaffected, and the hook command as
configured, run by hand to see its stderr, exits 0 and the next stop archives the session:

    $ printf x > $S/afile; AGENT_TRANSCRIPTS=$S/afile/archive claude -p --output-format json "Reply with the word ok."
    rc=0  result= ok is_error= False session c3668692-2106-41a7-a9cb-c81c307f606a
    hook command: "$CLAUDE_PROJECT_DIR"/plugins/change-record/bin/transcripts archive || true
    $ (unwritable archive)
    transcripts: [Errno 20] Not a directory: '.../scratchpad/afile/archive'; nothing archived this time, the lines are kept for the next stop
    exit 0
    $ (next stop, archive writable)
    exit 0
    g1-000001.jsonl
    $ (no archive set)
    exit 0
    $ (this session, 4b2c2a9a)
    real	0m0.048s
    cloud github.com/patrickpriestley/agent-workflow 2026-11-10T01:43:56.203Z 2026-11-10T01:55:53.234Z 179

Import, twice, on this container's `~/.claude/projects` (three sessions here, one probe
session in a scratch directory):

    $ AGENT_TRANSCRIPTS=$S/imp plugins/change-record/bin/transcripts import
    transcripts: imported 3, unchanged 0, skipped 1 (not in scope); archive .../scratchpad/imp
    $ AGENT_TRANSCRIPTS=$S/imp plugins/change-record/bin/transcripts import
    transcripts: imported 0, unchanged 3, skipped 1 (not in scope); archive .../scratchpad/imp

### Task 2: store (branch `2026-11-09-skill-transcripts/store`)

Shipped: `store/schema.sql` (applied by the owner on 2026-11-10), `store/probe`,
`transcripts push`, `materialize` and `redact`, the background push from the archive hook,
`store/stand-in.py` and `bin/transcripts-store.test.sh` (82 assertions: R4, R5, R7, the hook's
time limit and error paths; four added in review for a stream or skill name whose first segment
is `.` or `..`, which the guards let through and `materialize` wrote one folder up) in `.github/workflows/test.yml`, a README section, and the cloud
environment's two variables. The suite failed first on its assertions (43 of 69, the usage text
where push and materialize should answer). Every guard was broken by hand and a test failed
(18 mutations); the one survivor, the index row's digest check, was redundant and hid a gap
(a refused index row waited for new lines), which got a test, red first, and a fix.

Not shipped: `materialize` against the real store, which needs the read key on the owner's
machine (run `store/probe` there too, with `read-key` in place, to read the probe chunk back);
it is tested against the stand-in only, and that the secret key is accepted in the `apikey`
header alone is assumed. `tool-results/` files are still not archived or sent. A `claude -p`
session's own last lines are sent at the next stop of a session on the same archive, not at its
own (Probed facts).

Real use, in this cloud container, against the real project. The insert-only probe:

    $ AGENT_TRANSCRIPTS_URL=https://your-project-ref.supabase.co plugins/change-record/store/probe
    ok   insert a chunk: HTTP 201
    ok   insert an index row: HTTP 201
    ok   a duplicate chunk, other bytes: refused as a duplicate: HTTP 409 {"code":"23505",...
    ok   a duplicate index row: refused as a duplicate: HTTP 409 {"code":"23505",...
    ok   ignore-duplicates: refused, since ON CONFLICT needs SELECT: HTTP 401 {"code":"42501",...
    ok   select chunks: refused: HTTP 401 {"code":"42501",...
    ok   select sessions: refused: HTTP 401 {"code":"42501",...
    ok   insert with return=representation: refused: HTTP 401 {"code":"42501",...
    ok   update a chunk: refused: HTTP 401 {"code":"42501",...
    ok   delete a chunk: refused: HTTP 401 {"code":"42501",...
    ok   update an index row: refused: HTTP 401 {"code":"42501",...
    ok   delete an index row: refused: HTTP 401 {"code":"42501",...
    ok   insert a score: refused: HTTP 401 {"code":"42501",...
    ok   select scores: refused: HTTP 401 {"code":"42501",...
    note: no read key here, so the probe chunk was not read back
    probe session probe-74e1e907cd2eb8c5: 14 passed, 0 failed

This session's own transcript (1.3 MB, 274 lines), archived and pushed through a local
forwarder that logs each request body before relaying it to the project, then pushed again:

    $ AGENT_TRANSCRIPTS=$S/real/archive transcripts archive --transcript ~/.claude/projects/-home-user-agent-workflow/659da00f-....jsonl
    exit 0
    $ AGENT_TRANSCRIPTS=$S/real/archive AGENT_TRANSCRIPTS_URL=$FWD transcripts push
    transcripts: pushed 1 new chunks and 1 index rows for 1 sessions to http://127.0.0.1:38051
    real	0m1.952s
    $ (again)
    transcripts: pushed 0 new chunks and 0 index rows for 0 sessions to http://127.0.0.1:38051
    requests: 2 methods: ['POST'] answers: [201] apikey header sent by push: False

The bytes sent, decoded from the forwarder's log, against the unredacted archive:

    pattern         in local archive   in bytes sent
    email                         22               0
    github-token                   7               3   (all three: the pattern's own source, `github_pat_[`)
    anthropic-key                  4               0
    aws-key                        4               0
    supabase-key                   4               0
    every sent line is JSON: True

Two senders at once (two archives of the same session, machine ids `realuse-machine-A` and
`-B`), against the real project:

    A: transcripts: pushed 0 new chunks and 1 index rows for 1 sessions to http://127.0.0.1:38051
    A: exit 0
    B: transcripts: pushed 1 new chunks and 1 index rows for 1 sessions to http://127.0.0.1:38051
    B: exit 0
    POST /rest/v1/chunks   bfc44c23c68c -> 201
    POST /rest/v1/chunks   bfc44c23c68c -> 409 {"code":"23505",...   (the second copy, counted as stored)
    POST /rest/v1/sessions 6562aa05ac24 -> 201
    POST /rest/v1/sessions 047d9bc8fb0c -> 201

Error path, the hook command as configured, with the store unreachable, then the next stop:

    hook command: "$CLAUDE_PROJECT_DIR"/plugins/change-record/bin/transcripts archive || true
    $ (Stop, AGENT_TRANSCRIPTS_URL=http://127.0.0.1:9)
    exit 0 in 0.09 s
    push.log: push stopped: cannot reach http://127.0.0.1:9 ([Errno 111] Connection refused); what was not sent goes at the next stop (sent 0 chunks before)
    $ (next Stop, store reachable)
    exit 0 in 0.09 s
    push.log: pushed 1 new chunks and 1 index rows for 1 sessions to http://127.0.0.1:38051
      POST /rest/v1/chunks generation 1 number 2 lines 26 -> 201
      POST /rest/v1/sessions -> 201

Main path, a `claude -p` session in this repository with the hook sending straight to the
project; its own background pushes found its proxy gone, and this session's next stop sent it:

    $ AGENT_TRANSCRIPTS=$S/cp/archive AGENT_TRANSCRIPTS_URL=https://your-project-ref.supabase.co claude -p --output-format json "Reply with the word ok."
    rc=0  real 0m4.878s  result= ok is_error= False session 883c53c9-01a5-4ca6-b96c-d0c7d43dec50
    push.log: push stopped: cannot reach https://your-project-ref.supabase.co ([Errno 111] Connection refused); ... (Stop and SessionEnd)
    $ (this session's next Stop, same archive)
    exit 0 in 0.1 s
    push.log: pushed 3 new chunks and 2 index rows for 2 sessions to https://your-project-ref.supabase.co
    659da00f cloud sent version 1 main lines 319 of 319 redaction 1
    883c53c9 cloud sent version 1 main lines 24 of 24 redaction 1

### Task 3: grade (branch `2026-11-09-skill-transcripts/grade`)

Shipped: `transcripts grade` and the field graders in `grade/fields.py` (tier-declared,
probe-before-record, record-before-code, red-first, change-line, record-check, outcome-filled),
one row per step in `<folder>/scores/<sessionId>.json`, `--store` for the owner's machine,
`--transcript` for one file; `bin/transcripts-grade.test.sh` (60 assertions: both `dispatch`
fixtures, made-up sessions in both result key orders with flagged and unflagged failures,
denials and unanswered calls, which record, sessions with none, a materialized folder, the
error paths and `--store` against the stand-in) and four R9 tests in `evals/cases.test.cjs`
that run the eval graders' own fixtures through the same code and get their verdicts, two
listed divergences aside (Decisions). Both suites are in `.github/workflows/test.yml`; the
stand-in now keys `scores` as the real table does. The grade suite failed first on its
assertions (51 of 53, the usage text where verdicts should be). Every guard in `fields.py` and
in `grade`'s folder handling was broken by hand (27 mutations); three survived (a test folder
whose files are not named `test_*`, the session's first act as proof the record existed, and
sidechain lines), and each got a test that kills it. Real use found one bug, fixed red first: a
first commit without the record made the grader say the session wrote it, although the session
had read and edited it, so record-before-code failed where it does not apply. Grading this
session found a second, older bug, in `record-check`: under `pipefail` it piped the record into
`grep -q`, which can quit at its first match and kill `printf` with SIGPIPE, so a large record
(this one) was reported missing `## Goal` whenever a Python program ran the check. A test with a
large record, run through Python, failed 5 of 5; `record-check` now uses here-strings.

Not shipped: the judge, the agreement check and the report (task 4). Not run: `--store` and
`materialize` against the real store, which need the read key on the owner's machine (below).
Known limits: a file written by a program the grader cannot read (a Python one-liner, `patch`,
`git apply`) is not seen as a write; a PR description in the last message counts only when it
has a `Change:` line; a hook that blocks a call with wording outside the denial patterns would
count as a failed run, not as not run (it still cannot pass red-first unless its text reports a
failed test).

The read path, for the owner to run on their machine at the start of task 4 (the read key never
comes to this environment). In a checkout of this repository, on `main` with this PR merged:

    umask 077; mkdir -p ~/.config/agent-transcripts
    pbpaste > ~/.config/agent-transcripts/read-key      # the project's secret key (sb_secret_...)
    pbpaste > ~/.config/agent-transcripts/insert-key    # the publishable key, for the probe's inserts
    chmod 600 ~/.config/agent-transcripts/read-key ~/.config/agent-transcripts/insert-key
    export AGENT_TRANSCRIPTS_URL=https://your-project-ref.supabase.co

    plugins/change-record/store/probe
      expect 15 `ok` lines, the last new one
      `ok   read key: the probe chunk still holds its first bytes: HTTP 200 [{"data": "first"}]`,
      then `probe session probe-...: 15 passed, 0 failed`, exit 0. A FAIL on that line with 401
      means the secret key is not accepted in the `apikey` header alone (the assumption task 2
      left open); FAILs on the insert lines mean `insert-key` is missing.

    git fetch origin
    plugins/change-record/bin/transcripts materialize ~/agent-transcripts-store
      expect `transcripts: materialized N sessions into /Users/<you>/agent-transcripts-store`,
      exit 0, and `~/agent-transcripts-store/projects/github-com-patrickpriestley-agent-workflow/<id>.jsonl`
      for each session the hooks sent (659da00f, 883c53c9 and the sessions since).

    plugins/change-record/bin/transcripts grade ~/agent-transcripts-store --store
      expect, per session, `<id8> record <path or none>` and seven `<id8> <step> <verdict> <why>`
      lines, then `transcripts: graded N sessions into .../scores; stored 7N score rows at
      https://your-project-ref.supabase.co`. A session whose commits never reached origin
      (a `claude -p` probe, a scratch repository) is reported as `commit ... is not in <checkout>`,
      its record steps not applicable, and the exit status is then 1; the others are graded and
      stored.

Real use, in this cloud container. The two `dispatch` fixtures as shipped, each graded on its
own (no commits here, so the steps that read the record do not apply):

    $ transcripts grade --transcript plugins/change-record/grade/fixtures/dispatch-1-95e399c5.jsonl.gz
      tier-declared        not_applicable  the record cannot be read: no commit for the session
      probe-before-record  not_applicable  the record was there when the session started
      record-before-code   not_applicable  the record was there when the session started
      red-first            fail            no test ran before the code {'test_runs_before_code': 0, 'denied_test_runs': 6, 'failing_runs': []}
      change-line          pass            the PR description opens with the Change: line
      record-check         not_applicable  no commit for the session
      outcome-filled       not_applicable  the record cannot be read: no commit for the session
    $ transcripts grade --transcript plugins/change-record/grade/fixtures/dispatch-2-da1017af.jsonl.gz
      tier-declared        not_applicable  the record cannot be read: no commit for the session
      probe-before-record  not_applicable  the record was there when the session started
      record-before-code   not_applicable  the record was there when the session started
      red-first            pass            a test run failed before the code (toolu_01Hi1bjGyT1tDD7TMdSnAcSF) {'test_runs_before_code': 1, 'denied_test_runs': 0, 'failing_runs': ['toolu_01Hi1bjGyT1tDD7TMdSnAcSF']}
      change-line          pass            the description in the last message has the Change: line on its own
      record-check         not_applicable  no commit for the session
      outcome-filled       not_applicable  the record cannot be read: no commit for the session

A real session with no record, a `claude -p` question in this repository:

    $ AGENT_TRANSCRIPTS=$S/nr claude -p --output-format json "What does plugins/change-record/bin/red-check do? One sentence."
    rc=0
    session 93793685-1af7-49f1-9225-c4b42e763af7 result: `red-check` verifies test-driven changes: ...
    $ transcripts grade $S/nr
    93793685 record none
    93793685 tier-declared not_applicable no record and no code written
    93793685 probe-before-record not_applicable no record
    93793685 record-before-code not_applicable no record
    93793685 red-first not_applicable no code written
    93793685 change-line not_applicable no record
    93793685 record-check not_applicable no record
    93793685 outcome-filled not_applicable no record
    transcripts: graded 1 sessions into .../scratchpad/nr/scores
    exit 0

Error path: the same archive plus a transcript cut mid-line and dispatch-2 with its commits set
to this repository's HEAD, which has no `shout` record:

    $ transcripts grade $S/err
    transcripts: cut-0001: line 8 of the transcript is not JSON; not graded
    transcripts: da1017af-e406-4505-ade7-a5b331fa0989: docs/changes/2026-11-08-shout.md is not in commit 21c00ba8af
    da1017af record docs/changes/2026-11-08-shout.md
    da1017af tier-declared fail docs/changes/2026-11-08-shout.md is not in the session's last commit
    da1017af probe-before-record not_applicable the record was there when the session started
    da1017af record-before-code not_applicable the record was there when the session started
    da1017af red-first pass a test run failed before the code (toolu_01Hi1bjGyT1tDD7TMdSnAcSF)
    da1017af change-line pass the description in the last message has the Change: line on its own
    da1017af record-check fail docs/changes/2026-11-08-shout.md is named in the PR body but not in the head commit
    da1017af outcome-filled not_applicable the record cannot be read: not in the last commit
    transcripts: graded 2 sessions into .../scratchpad/err/scores, 1 with problems
    exit 1

This session's own transcript, archived into the local archive (`AGENT_TRANSCRIPTS`) by hand,
since its first Stop comes after this, and graded at its commits (before the done marker; it
writes its pull request description afterwards, so change-line does not yet apply):

    $ transcripts archive --transcript ~/.claude/projects/-home-user-agent-workflow/6cc07e5f-8172-530e-9c9a-e23e0a49a446.jsonl
    $ transcripts grade --session 6cc07e5f-8172-530e-9c9a-e23e0a49a446
    6cc07e5f record docs/changes/2026-11-09-skill-transcripts.md
    6cc07e5f tier-declared pass tier 2
    6cc07e5f probe-before-record not_applicable the record was there when the session started
    6cc07e5f record-before-code not_applicable the record was there when the session started
    6cc07e5f red-first pass a test run failed before the code (toolu_019RuRmPuxvNX8KzFekCwQkx)
    6cc07e5f change-line not_applicable the session opened no pull request and wrote no description
    6cc07e5f record-check pass record-check: ok tier=2 mode=code
    6cc07e5f outcome-filled not_applicable the record is approved and no task was marked done
    transcripts: graded 1 sessions into /root/agent-transcripts/scores

Before the `record-check` fix the same run said `record-check fail ... missing section: Goal;
... missing section: Problem`, which is how the bug above was found.

`--store` here, where there is no read key:

    $ transcripts grade --session 6cc07e5f-... --store
    transcripts: the store's read key is needed in /root/.config/agent-transcripts/read-key (mode 0600), on the owner's machine only
    exit 2
