---
id: 2026-11-09-skill-transcripts
tier: 2
status: done
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
    done: true
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
- Verified against the real system (task 4, Claude Code 2.1.322, 2026-11-10): `claude -p --model
  haiku --output-format json --tools "" --no-session-persistence --setting-sources ""
  --system-prompt ...`, prompt on stdin, from a scratch directory, answers exit 0 with one JSON
  object whose `result` is the answer text, `stop_reason` `end_turn`, `is_error` false, and
  `modelUsage` keyed by the model served (`claude-haiku-5-5`), in about 5 s. A refusal answers
  exit 1 with `is_error` true, `stop_reason` `refusal`, `terminal_reason` `api_error` and a
  `result` of "API Error: Haiku 5.5 can't help with this. ...". An unknown model answers exit 1,
  `terminal_reason` `api_error`, empty `modelUsage`, and `[claude-code:unrecognized_model]` on
  stderr.
- Verified against the real system (task 4): asked for `{"verdict", "reason"}` in that order,
  Haiku sometimes voted `pass` while its own reason said the Decisions gave no reason for the
  rejected alternative ("strictly, this is a fail"); asked for the reason first, its verdicts
  followed its reasons in every run (Outcome).
- Exact source (`bin/agent-review`): `opencode run --agent <name> -m <model> "<prompt>"` prints
  the answer on stdout, with the agent defined in `OPENCODE_CONFIG_CONTENT` and project config
  disabled by `OPENCODE_DISABLE_PROJECT_CONFIG=1`. Assumed, not probed here (no OpenCode Go key in
  this environment): that a Kimi answer through it carries nothing but the answer text, and how
  a refusal looks there.
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
  reads the file instead; and (follow-up, 2026-11-11) a Bash command that prints it with `cat`,
  `head`, `tail`, `sed`, `less`, `more`, `nl` or `bat`, which is how the cloud sessions read it.
  A command that only names the file (`git log -- …/SKILL.md`, `echo`) does not count.
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

- (Task 4.) `transcripts judge` runs after `grade` and reads its rows: the record from their
  evidence, and whether the Outcome is due from `outcome-filled` (not done: not applicable;
  empty: fail; filled: judged). An empty section fails without a judge. It judges only sessions
  that wrote code (by `fields.code_written`, the graders' own rule) and have a record, newest
  first, at most `--limit` (20) per run, and skips a session already judged on the same record
  text. Rejected: judging every session, which C3 caps, and re-judging at every run, which pays
  again for the same answer.
- (Task 4.) A vote is an answer that is exactly one JSON object with the keys `reason` and
  `verdict` (`pass` or `fail`) and nothing else, alone or in one code fence. A refusal (claude's
  `stop_reason` `refusal`, or declining text), an error (non-zero exit, `is_error`, no answer in
  180 s), an answer served by a model that is not Haiku, and any other answer are kept with
  their text and status (`refused`, `error`, `malformed`) and never counted. Two counted votes
  that agree make the verdict; else it is `undecided` and writes no score row. Rejected: reading
  a verdict out of prose, or a majority of whatever answers parse, under which one vote among
  two refusals would decide.
- (Task 4.) Each judge prompt is redacted with `push`'s redaction before it is sent, and the
  judge runs in an empty scratch directory, with no `AGENT_TRANSCRIPTS*` or `CLAUDE_PROJECT_DIR`,
  no tools, no settings and no saved session, so its own session is neither captured nor kept.
  The Outcome prompt also lists the first line of each shell command the session ran (the last
  60), so the judge can tell a quoted run from an invented one. Rejected: giving the judge the
  transcript, which is large and mostly beside these two questions.
- (Task 4.) Votes, prompts and verdicts are kept per session in
  `judges/<sid>.<claude|opencode>.json`; the Haiku judge's verdicts are score rows in
  `scores/<sid>.judge.json` (grader `judge/1:haiku`), beside `grade`'s own file, which it leaves
  alone. `--store` sends the rows to `scores` and every answer to a new `judge_votes` table with
  the read key, on the owner's machine, as task 3's rows go. Rejected: one row per vote in
  `scores`, whose verdict column cannot hold a refusal.
- (Task 4.) The agreement judge is `opencode run -m opencode-go/kimi-k3.1-pro` with an inline
  agent that denies every tool and project config disabled, as `agent-review` runs OpenCode, on
  the same prompts, only for sessions the Haiku judge judged on the same record, at most 10 per
  run; it writes votes and no score rows. Agreement counts only questions both judges were asked
  and both decided; below 80% the report says the default should move to the other family
  (C3). Rejected: calling the OpenCode Go endpoint directly from Python, which would make
  `transcripts` hold an API key, where `opencode` keeps its own login.
- (Follow-up, 2026-11-11.) The grader's shell reading does not place a write whose target holds
  an expansion it cannot resolve (`$VAR`, `${VAR}`, `$(…)`, backticks), nor a relative write after
  a `cd` into one, until a `cd` to a known path; such a write is outside the tree for every step.
  The cost, accepted: a real code write made only through a variable (`echo … > "$REPO/x.py"`) is
  missed. Rejected: guessing a variable's value from earlier commands, which the transcript does
  not show reliably; and failing the step as unknown, which turned scratch-folder probes into
  red-first failures (task 4's own session).
- (Task 4.) The report groups rows by the skill's name and blob and never adds two versions
  together; within a version it counts the latest row per session, step and grader. "Over time"
  is a table of each step's rate across versions, in the order of their first session. Proposed
  edits are fixed per step (the skill's section and what to tighten) and are listed only for a
  (session, step) whose latest row, across graders, is a fail, under the version that failed.
  Rejected: calendar weeks, which mix versions, and asking a model to write the edits, which C3
  leaves to a model family other than Claude and which no stored expected report could check.

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
   gets it; it fails today. (Built: `transcripts judge` and `report`, `bin/transcripts-judge.test.sh`
   against stand-ins for `claude` and `opencode`, with a live block for the real Haiku judge; the
   agreement run is the owner's, see Outcome.)

## Checks

`bash plugins/change-record/bin/transcripts.test.sh`, `transcripts-store.test.sh`,
`transcripts-grade.test.sh`, `transcripts-judge.test.sh` and `node --test
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

### Task 4: report (branch `2026-11-09-skill-transcripts/report`)

Shipped: `transcripts judge` (the Haiku judge, three votes per question, and `--judge opencode`,
the agreement check with `opencode-go/kimi-k3.1-pro`), `transcripts report`, `grade/judge.py`,
`grade/report.py`, the `judge_votes` table in `store/schema.sql` (the stand-in keeps it as the
real table would), `bin/transcripts-judge.test.sh` (68 assertions: votes counted only from
well-formed answers, refusals, errors, a model that is not Haiku, sessions that wrote no code or
have no record, the limit, redaction of what each judge sees, prompts and votes kept per session,
scores and votes to the stand-in store with the read key only, the agreement judge against a
stand-in for `opencode`, and the report from the known rows in `grade/fixtures/report/` against
its stored `expected.md`; `TRANSCRIPTS_LIVE_JUDGE=1` adds three known answers from the real
Haiku judge) in `.github/workflows/test.yml`, and a README section. The suite failed first on its
assertions (45 of 56, the usage text where `judge` and `report` should answer). Every guard in
`judge.py`, `report.py` and `judge` was broken by hand (27 mutations); eleven survived at first
(extra keys in an answer, a failed run with a well-formed answer, the archive variable reaching
the judge, a record not done, no record, the agreement judge on a session the Haiku judge had
not judged, its score rows, the latest row by time, two judges on different records, a newer
grader's pass, the one-step-per-session rule for edits), and each got a test that kills it.
Two later bugs were fixed red first: agreement counted questions decided without a judge, and
an agreement run whose answers all failed to count read as "not run yet". `--transcript` named
the session after its file, fixed red first.

Real use found the judge's prompt too loose: on the two `dispatch` records, whose only Decision
is "Rejected: argparse." with no reason, Haiku voted pass three times out of three, its reasons
saying "gives no reason for rejecting it" and once "strictly, this is a fail". With the rule made
explicit (a bare alternative does not count) it voted fail 2 to 1, one vote still contradicting
its reason; with the reason asked for before the verdict, every vote followed its reason (below,
and the live test). The live test's made-up bare alternative failed under the old prompt too,
so it guards the case rather than proving the fix; the fixtures' runs are the evidence.

Not shipped: the agreement run and the first agreement rate, which need an OpenCode Go key on the
owner's machine (below); until it runs, the report says "The agreement check has not run yet".
`--store` for `judge` and `report` is tested against the stand-in only, as task 3's was.

Requirements: R1 to R9 as tasks 1 to 3 report. R10: the judge, its prompt and votes kept per
session, and the known answers are met here; the agreement rate is left to the owner's run. R11
is met locally and against the stand-in; reading and writing the real store with the read key is
left to the owner's machine, as task 3 left `--store`.

For the owner. First re-run `plugins/change-record/store/schema.sql` in the Supabase SQL editor
(it adds `judge_votes` and is safe to run again). Then, on your machine, in a checkout of this
repository on `main` with this PR merged, with `read-key` in place as task 3 describes and
`opencode` installed and logged in to OpenCode Go (`opencode auth login`):

    export AGENT_TRANSCRIPTS_URL=https://your-project-ref.supabase.co
    T=plugins/change-record/bin/transcripts
    $T materialize ~/agent-transcripts-store
    $T grade ~/agent-transcripts-store --store
    $T judge ~/agent-transcripts-store --store
      expect, per session that wrote code and has a record, two lines such as
      `<id8> decisions-alternative pass (vote vote vote) 3 of 3 votes pass: ...`, others
      `<id8> not judged: no code written` (or no record), then
      `transcripts: claude judge (haiku) judged N sessions into .../judges; ...; stored M rows at https://...`
    $T judge ~/agent-transcripts-store --judge opencode --store
      expect the same lines for up to 10 of those sessions, then
      `transcripts: opencode judge (opencode-go/kimi-k3.1-pro) judged N sessions into .../judges; ...`
      Votes shown as `malformed` on every line mean OpenCode prints more than the answer (the
      assumption under Probed facts): send `judges/<id>.opencode.json` back and the reader is fixed.
    $T report ~/agent-transcripts-store --store
      expect the report, whose "Judge agreement" section now reads
      `The Haiku judge and opencode-go/kimi-k3.1-pro agree on A of N judgments (P%), over S sessions judged by both.`
      Below 80%, it adds that per C3 the default judge should move to the other model family.

Real use, in this cloud container. The suite as committed, and red at the test commit:

    $ bash plugins/change-record/bin/transcripts-judge.test.sh | tail -1
    transcripts judge and report: 68 passed, 0 failed
    $ (at 5f753c5, the test alone)
    transcripts judge and report: 11 passed, 45 failed
    $ bin/red-check origin/main..HEAD --run 'bash {files}' --red-pattern '^  FAIL '
    red-check: red: plugins/change-record/bin/transcripts-judge.test.sh (exit 1 on the base)
    red-check: every changed test file (1) fails on the base commit with an assertion

`red-check` first called the suite inconclusive: on the base, where it copies the test file
alone, its helpers printed tracebacks and `No such file` for the files the missing commands
never wrote. They now read quietly, and each missing file is a failed assertion.

Found while running the checks, outside this task: `bin/transcripts.test.sh` (task 1) did not
unset `AGENT_TRANSCRIPTS_URL`, which this cloud environment sets, so its archive hook started a
background push of the suite's made-up sessions to the real store, and its entry check failed
whenever that push won the race (4 runs of 4 here, after earlier runs that passed). CI does not
set the variable. Fixed by unsetting it, as the other three suites do (5 runs of 5 pass). The
store therefore holds made-up rows from runs of that suite in cloud containers, sender
`cloud:<container>`, session ids such as `11111111-2222-3333-4444-555555555555` and
`77777777-0000-0000-0000-000000000000`: the insert key cannot delete them, and they are left
for the owner to remove with the read key if wanted.

The real Haiku judge on the two `dispatch` fixtures, each with its record rebuilt from the text
the session printed with `cat` and its own Edits (dispatch-1 could not run anything, dispatch-2
pasted real runs). Each prompt, its three votes and the verdict:

    $ transcripts judge --transcript grade/fixtures/dispatch-1-95e399c5.jsonl.gz --record $S/shout-1-95e399c5.md
    95e399c5 decisions-alternative fail (vote vote vote) 3 of 3 votes fail: The Decisions section names argparse as a rejected alternative for parsing the flag, but gives no reason for rejecting it, so per the rules this does not count and the record fails.
      prompt:
        You judge one question about a software change record. Answer with one line of JSON and nothing else: {"reason": "<one sentence>", "verdict": "pass" or "fail"}.

        Question: does the record's Decisions section name, for at least one decision, an alternative that was considered and rejected, with a reason?
        PASS if at least one decision names a rejected alternative and why (for example "Rejected: X, because Y", or "rather than X, since Y"). FAIL if the section is empty, holds only placeholders, or lists decisions with no rejected alternative. A rejected alternative named without any reason for rejecting it does not count: if that is all the section has, FAIL.

        The record: docs/changes/shout-1-95e399c5.md

        <decisions>
        - Parse the flag by hand in `main`, keep `greet()` pure and add `shout(text)`. Rejected: argparse.
        </decisions>

        Answer with one line of JSON: {"reason": "<one sentence>", "verdict": "pass" or "fail"}.
      vote 1: fail: The Decisions section names argparse as a rejected alternative for parsing the flag, but gives no reason for rejecting it, so per the rules this does not count and the record fails.
      vote 2: fail: The decision names a rejected alternative (argparse) but gives no reason for rejecting it, and the section has no other decisions with a stated rationale, so per the rules it fails.
      vote 3: fail: The single decision names a rejected alternative (argparse) but gives no reason for rejecting it, and the rule says a rejected alternative without a reason does not count.
      verdict: fail
    95e399c5 outcome-real-output fail (vote vote vote) 3 of 3 votes fail: The Outcome quotes no command runs or printed output; it only describes expected results and states that the test, run, and commit commands were denied and remain to be done.
      prompt:
        You judge one question about a software change record. Answer with one line of JSON and nothing else: {"reason": "<one sentence>", "verdict": "pass" or "fail"}.

        Question: does the record's Outcome quote real runs of what the change built: the commands run and the output they printed, rather than only describing the result or reporting test counts?
        PASS if the Outcome quotes at least one command and the output it printed. FAIL if it only describes behaviour, only reports unit-test results, or holds no output.

        The record: docs/changes/shout-1-95e399c5.md

        <outcome>
        - Task 1 built on `shout/flag`: `greet.py` gains `shout(text)` and `main` strips `--shout`
          from the arguments wherever it appears; `tests/test_greet.py` covers `shout()`, the flag
          before and after the name, the flag alone, and the unchanged default with and without a name.
        - Not verified in the building session: every command that runs Python or writes to git
          (`python3 -m unittest …`, `python3 greet.py …`, `git add`, `git commit`) was denied by the
          session's permission mode, so the red run, the green run, the real-use runs and the commits
          are still to be done by whoever picks the branch up. Expected output: `python3 greet.py
          --shout Ada` → `HELLO, ADA!`; `python3 greet.py Ada` → `Hello, Ada!`.
        </outcome>

        Commands the session ran, for reference (a command the Outcome quotes should be among them):
        <commands>
        $ git status --short && git log --oneline -3 && ls -R . | grep -v '^\.git' | head -30 && cat docs/changes/2026-11-08-shout.md && echo ---- && cat greet.py && echo ---- && cat tests/test_greet.py && ls t
        $ python3 --version
        $ rm /tmp/claude-0/-home-user-agent-workflow/5ac54a69-3ba4-5369-bb2d-6980aeb1a0d6/scratchpad/realuse/worktrees/shout/PR.md
        $ git status --short && git diff --stat
        </commands>

        Answer with one line of JSON: {"reason": "<one sentence>", "verdict": "pass" or "fail"}.
      vote 1: fail: The Outcome quotes no command runs or printed output; it only describes expected results and states that the test, run, and commit commands were denied and remain to be done.
      vote 2: fail: The Outcome quotes no command run and no output printed; it only describes expected output and states that every Python and git command was denied, so no real runs are shown.
      vote 3: fail: The Outcome quotes no executed command and printed output; it states that every run was denied and gives only expected output, with the test and real-use runs still to be done.
      verdict: fail
    exit 0
    $ transcripts judge --transcript grade/fixtures/dispatch-2-da1017af.jsonl.gz --record $S/shout-2-da1017af.md
    da1017af decisions-alternative fail (vote vote vote) 3 of 3 votes fail: The Decisions section names argparse as a rejected alternative but gives no reason for rejecting it, which the criteria say does not count.
      prompt:
        You judge one question about a software change record. Answer with one line of JSON and nothing else: {"reason": "<one sentence>", "verdict": "pass" or "fail"}.

        Question: does the record's Decisions section name, for at least one decision, an alternative that was considered and rejected, with a reason?
        PASS if at least one decision names a rejected alternative and why (for example "Rejected: X, because Y", or "rather than X, since Y"). FAIL if the section is empty, holds only placeholders, or lists decisions with no rejected alternative. A rejected alternative named without any reason for rejecting it does not count: if that is all the section has, FAIL.

        The record: docs/changes/shout-2-da1017af.md

        <decisions>
        - Parse the flag by hand in `main`, keep `greet()` pure and add `shout(text)`. Rejected: argparse.
        </decisions>

        Answer with one line of JSON: {"reason": "<one sentence>", "verdict": "pass" or "fail"}.
      vote 1: fail: The Decisions section names argparse as a rejected alternative but gives no reason for rejecting it, which the criteria say does not count.
      vote 2: fail: The Decisions section names a rejected alternative (argparse) but gives no reason for rejecting it, and the criteria explicitly say a rejected alternative without a reason does not count.
      vote 3: fail: The single decision names a rejected alternative (argparse) but gives no reason for rejecting it, and the question says a rejected alternative without a reason does not count.
      verdict: fail
    da1017af outcome-real-output pass (vote vote vote) 3 of 3 votes pass: The Outcome quotes real command runs with their printed output, including the unittest suite run and the `python3 greet.py` invocations showing their results.
      prompt:
        You judge one question about a software change record. Answer with one line of JSON and nothing else: {"reason": "<one sentence>", "verdict": "pass" or "fail"}.

        Question: does the record's Outcome quote real runs of what the change built: the commands run and the output they printed, rather than only describing the result or reporting test counts?
        PASS if the Outcome quotes at least one command and the output it printed. FAIL if it only describes behaviour, only reports unit-test results, or holds no output.

        The record: docs/changes/shout-2-da1017af.md

        <outcome>
        Task 1 (branch `shout/flag`), 2026-11-08.

        Red: `tests/test_greet.py` gained tests for `--shout` (first, last, alone) and for the unchanged
        default; the three flag tests failed on assertions before the code (`'Hello, --shout!\n' !=
        'HELLO, ADA!\n'`), the default tests passed. Green: `greet.py` strips `--shout` from the
        arguments and passes the greeting through a new `shout(text)`; `greet()` is unchanged.

        Suite:

        ```
        $ python3 -m unittest discover -s tests -t .
        Ran 7 tests in 0.000s

        OK
        ```

        Used as a user would:

        ```
        $ python3 greet.py --shout Ada
        HELLO, ADA!
        $ python3 greet.py Ada
        Hello, Ada!
        $ python3 greet.py Ada --shout
        HELLO, ADA!
        $ python3 greet.py
        Hello, world!
        ```

        Guards: no Python mutation tool is installed, so each new guard was broken by hand and
        restored; every mutant failed the suite: `shout()` returning its input (4 failures), the
        upper-casing never applied (3), `--shout` not removed from the name arguments (2), the flag
        test inverted (5). No survivors.
        </outcome>

        Commands the session ran, for reference (a command the Outcome quotes should be among them):
        <commands>
        $ git status --short && git log --oneline -3 && ls -R . | grep -v '^\.git' | head -30 && cat docs/changes/2026-11-08-shout.md && echo ---- && cat greet.py && echo ---- && cat tests/test_greet.py && ls t
        $ python3 -m unittest discover -s tests -t . 2>&1 | tail -30
        $ git add tests/test_greet.py && git commit -q -m "test(greet): --shout flag upper-cases the greeting; default unchanged
        $ python3 -m unittest discover -s tests -t . 2>&1 | tail -4; echo "--- shout:"; python3 greet.py --shout Ada; echo "--- default:"; python3 greet.py Ada; echo "--- trailing flag:"; python3 greet.py Ada -
        $ (python3 -m mutmut --version 2>/dev/null || echo "no mutmut") && cp greet.py /tmp/greet.py.bak
        $ rm -rf __pycache__ tests/__pycache__ && python3 -m unittest discover -s tests -t . 2>&1 | tail -1 && rm -rf __pycache__ tests/__pycache__ && git add greet.py tests/test_greet.py docs/changes/2026-11-0
        </commands>

        Answer with one line of JSON: {"reason": "<one sentence>", "verdict": "pass" or "fail"}.
      vote 1: pass: The Outcome quotes real command runs with their printed output, including the unittest suite run and the `python3 greet.py` invocations showing their results.
      vote 2: pass: The Outcome quotes real commands with their printed output, including the `python3 -m unittest discover` run and the `python3 greet.py --shout Ada` usage runs, and those commands appear in the session's command list.
      vote 3: pass: The Outcome quotes real commands with their printed output, including the unittest run and the `python3 greet.py` invocations, and those commands appear in the session's command list.
      verdict: pass
    exit 0

Error path: answers that are not votes, from the real Haiku judge and from the refusal the probe
got, read by the judge's own code (`judge.ask` and `judge.read_claude`):

    the refusal the probe got, read by the judge: {"status": "refused", "verdict": null, "detail": "stop_reason refusal"} answer: API Error: Haiku 5.5 can't help with this. Start a new sessi...
    answer 1: {"status": "malformed", "verdict": null, "served_model": "claude-haiku-5-5"} answer: 'A change record is a documented entry describing a modification to a software project, typically inc'
    answer 2: {"status": "malformed", "verdict": null, "served_model": "claude-haiku-5-5"} answer: 'A change record is a documented account of a modification to a software system, typically capturing '
    answer 3: {"status": "vote", "verdict": "pass", "served_model": "claude-haiku-5-5"} answer: '{"reason": "Two plus two is four, which is a correct arithmetic statement.", "verdict": "pass"}'
    decide: ('undecided', '1 of 3 answers counted as votes, and no two agree')


This session's own transcript, archived by hand into the local archive (`AGENT_TRANSCRIPTS`),
since it has had no stop yet, with its first stop set to `236a403`, the `main` commit it started
from (a hand archive records the current commit as both, and the done marker would then look
already set), graded at `8b43906` (the done marker) and judged for real. Its prompts are
abridged here where they quote this record; each is kept whole in
`~/agent-transcripts/judges/dd2defdb-d4db-5066-b961-2838a0b29d84.claude.json` with its sha256 (`a50eebae...`, 154 lines;
`99283c69...`, 259 lines), and every vote was served by `claude-haiku-5-5`:

    $ transcripts archive --transcript ~/.claude/projects/-home-user-agent-workflow/dd2defdb-d4db-5066-b961-2838a0b29d84.jsonl
    exit 0
    $ transcripts grade --session dd2defdb-d4db-5066-b961-2838a0b29d84
    dd2defdb record docs/changes/2026-11-09-skill-transcripts.md
    dd2defdb tier-declared pass tier 2
    dd2defdb probe-before-record not_applicable the record was there when the session started
    dd2defdb record-before-code not_applicable the record was there when the session started
    dd2defdb red-first fail no test ran before the code
    dd2defdb change-line not_applicable the session opened no pull request and wrote no description
    dd2defdb record-check pass record-check: ok tier=2 mode=code
    dd2defdb outcome-filled pass Outcome has 434 lines
    transcripts: graded 1 sessions into /root/agent-transcripts/scores
    exit 0
    $ transcripts judge --session dd2defdb-d4db-5066-b961-2838a0b29d84 --verbose
    dd2defdb decisions-alternative pass (vote vote vote) 3 of 3 votes pass: Many decisions name a rejected alternative with a stated reason, such as the hostname or path rejected because they are machine-specific, so the section passes.
      prompt:
        You judge one question about a software change record. Answer with one line of JSON and nothing else: {"reason": "<one sentence>", "verdict": "pass" or "fail"}.

        Question: does the record's Decisions section name, for at least one decision, an alternative that was considered and rejected, with a reason?
        PASS if at least one decision names a rejected alternative and why (for example "Rejected: X, because Y", or "rather than X, since Y"). FAIL if the section is empty, holds only placeholders, or lists decisions with no rejected alternative. A rejected alternative named without any reason for rejecting it does not count: if that is all the section has, FAIL.

        The record: docs/changes/2026-11-09-skill-transcripts.md

        <decisions>
        [... the record's Decisions as committed at 8b43906, 143 lines ...]
        </decisions>

        Answer with one line of JSON: {"reason": "<one sentence>", "verdict": "pass" or "fail"}.
      vote 1: pass: Many decisions name a rejected alternative with a stated reason, such as the hostname or path rejected because they are machine-specific, so the section passes.
      vote 2: pass: The Decisions section names rejected alternatives with reasons in many entries, such as "Rejected: hostname or path, which are `vm` and machine-specific."
      vote 3: pass: Many decisions name a rejected alternative with its reason, such as "Rejected: hostname or path, which are `vm` and machine-specific."
      verdict: pass
    dd2defdb outcome-real-output pass (vote vote vote) 3 of 3 votes pass: The Outcome quotes many real command invocations and their printed output (e.g., the `import` runs, the `cmp` check, the probe results, and the `push` output), so it satisfies the pass condition.
      prompt:
        You judge one question about a software change record. Answer with one line of JSON and nothing else: {"reason": "<one sentence>", "verdict": "pass" or "fail"}.

        Question: does the record's Outcome quote real runs of what the change built: the commands run and the output they printed, rather than only describing the result or reporting test counts?
        PASS if the Outcome quotes at least one command and the output it printed. FAIL if it only describes behaviour, only reports unit-test results, or holds no output.

        The record: docs/changes/2026-11-09-skill-transcripts.md

        <outcome>
        [... the record's Outcome as committed at 8b43906, 184 lines ...]
        </outcome>

        Commands the session ran, for reference (a command the Outcome quotes should be among them):
        <commands>
        $ cd /home/user/agent-workflow && grep -n "opencode" bin/agent-review | sed -n '1,60p' | tail -30; grep -n "opencode\|zen/go" -A3 .github/workflows/pr-agent.yml | head -40
        $ cd /home/user/agent-workflow/plugins/change-record && sed -n 1,80p bin/transcripts; grep -n "^def \|^    sub\|add_parser\|^[A-Z_]* = " bin/transcripts
        $ sed -n 513,640p bin/transcripts; sed -n 920,1145p bin/transcripts
        [... 54 more commands ...]
        $ S=$S; cd /home/user/agent-workflow && cat $S/ru/outcome4.md >> docs/changes/2026-11-09-skill-transcripts.md && grep
        $ python3 -c "
        $ git add docs/changes/2026-11-09-skill-transcripts.md && git commit -qm "docs(change): 2026-11-09-skill-transcripts, task report done" && git log --oneline -1
        </commands>

        Answer with one line of JSON: {"reason": "<one sentence>", "verdict": "pass" or "fail"}.
      vote 1: pass: The Outcome quotes many real command invocations and their printed output (e.g., the `import` runs, the `cmp` check, the probe results, and the `push` output), so it satisfies the pass condition.
      vote 2: pass: The Outcome quotes many real command runs and their printed output (e.g., the `claude -p` session transcripts, the `find`/`cmp` checks, the import runs, and the insert-only probe results), so it passes the requirement of at least one command with its output.
      vote 3: pass: The Outcome quotes multiple real command invocations with their printed output (e.g., the `claude -p` archive session, the import runs, the insert-only probe output, and the push/forwarder logs), satisfying the requirement for at least one command and its output.
      verdict: pass
    transcripts: claude judge (haiku) judged 1 sessions into /root/agent-transcripts/judges
    exit 0
    $ transcripts judge --session dd2defdb-d4db-5066-b961-2838a0b29d84
    transcripts: claude judge (haiku) judged 0 sessions into /root/agent-transcripts/judges; 1 already judged
    exit 0

The red-first fail is the grader's, not the session's: this session ran the judge suite and saw
it fail (45 of 56) before any code, but `fields/1` took the probe's `cd $S/probe && claude -p
... > out.json`, a redirect under an unexpanded variable into a scratch folder, for a code file
written inside the repository (`first_code_write` `$S/probe/out.json`). That is a limit of task
3's shell reading, left as found (this task does not change the field graders): a redirect
target that starts with a variable should not count as a write in the working tree. The skill's
blob is unknown because this session read `SKILL.md` with `cat`, which task 1's rule (the Skill
tool, or a Read of the file) does not count.

The report from the local score rows (this session's), so its one proposed edit comes from the
false red-first fail above:

    $ transcripts report
    # Change skill report

    Score rows from 1 sessions, grouped by skill version (the git blob of the skill file), oldest first; two versions are never counted together. A pass rate is pass / (pass + fail), with not applicable counted apart. Each step keeps the latest row per session and grader.

    ## change-record:change, blob unknown

    Sessions: 1, from 2026-11-10 to 2026-11-10.

    | Step | Grader | Pass | Fail | N/A | Pass rate |
    |---|---|---|---|---|---|
    | tier-declared | fields/1 | 1 | 0 | 0 | 100% |
    | probe-before-record | fields/1 | 0 | 0 | 1 | - |
    | record-before-code | fields/1 | 0 | 0 | 1 | - |
    | red-first | fields/1 | 0 | 1 | 0 | 0% |
    | change-line | fields/1 | 0 | 0 | 1 | - |
    | record-check | fields/1 | 1 | 0 | 0 | 100% |
    | outcome-filled | fields/1 | 1 | 0 | 0 | 100% |
    | decisions-alternative | judge/1:haiku | 1 | 0 | 0 | 100% |
    | outcome-real-output | judge/1:haiku | 1 | 0 | 0 | 100% |

    ## Pass rate over time

    Passes of graded sessions, per skill version, oldest first (the date is the version's first session).

    | Step | Grader | unknown (2026-11-10) |
    |---|---|---|
    | tier-declared | fields/1 | 1 of 1 |
    | probe-before-record | fields/1 | - |
    | record-before-code | fields/1 | - |
    | red-first | fields/1 | 0 of 1 |
    | change-line | fields/1 | - |
    | record-check | fields/1 | 1 of 1 |
    | outcome-filled | fields/1 | 1 of 1 |
    | decisions-alternative | judge/1:haiku | 1 of 1 |
    | outcome-real-output | judge/1:haiku | 1 of 1 |

    ## Judge agreement

    The agreement check has not run yet: no session here has been judged by both the Haiku judge and opencode-go/kimi-k3.1-pro. On the owner's machine, run `transcripts judge DIR --judge opencode`, then this report again.

    ## Proposed skill edits

    From failed sessions only, citing each session and step, per skill version, newest first.

    ### change-record:change, blob unknown

    - red-first, in "3. Loop", step 3 (Red, then green): require the failing test run's output to be seen before the first code edit, and say that a denied or skipped test run does not count. Failed in:
      - dd2defdb (dd2defdb-d4db-5066-b961-2838a0b29d84): no test ran before the code
    exit 0

### The owner's read check, against the real store (2026-11-11)

Run from a cloud session, not the owner's machine: a one-off departure from the Decision that
the read key stays on the owner's machine, agreed by the owner in chat. A separate personal
environment (`agent-workflow-admin`) allowed only the Supabase host and held the secret key as a
network secret, so the proxy added it to requests and the session never saw it. The session
moved onto it for the check and back afterwards; the owner deletes that key or environment.
The schema was re-run by the owner first ("Success. No rows returned").

- The secret key is accepted in the `apikey` header alone (the assumption under task 2):
  `GET /rest/v1/sessions?select=session_id&limit=3` answered 200 with rows.
- Test rows removed by exact id: 116 chunks and 90 index rows of 10 sessions
  (`11111111-…` to `66666666-…`, `probe-…`, `probe-size-…`). Left: 5 real sessions, 51 chunks,
  22 index rows. `store/probe` was not run, since its insert-only checks fail by design with
  the secret key; the read above stands for its read-back.
- `transcripts materialize ~/agent-transcripts-store`: `materialized 5 sessions`, exit 0.
- `transcripts grade ~/agent-transcripts-store --store`: `graded 5 sessions …; stored 35 score
  rows`, exit 0. Task 3's session (`6cc07e5f`) passes every step that applies.
- `transcripts judge ~/agent-transcripts-store --store`: Haiku judged the 2 sessions with a
  record and code (`6cc07e5f`, `dd2defdb`), 3 of 3 votes pass on both questions for each;
  `stored 16 rows` (12 in `judge_votes`, 4 verdicts in `scores`).
- `transcripts report ~/agent-transcripts-store --store`: written, exit 0. The agreement
  check has not run (OpenCode Go has no balance).

What the real report shows, and why its three proposed edits are not yet evidence about the
skill:

- `659da00f` (task 2) fails tier-declared and red-first because the store holds only its first
  319 lines (to 13:34; the session ran to about 13:45). That session's own hook never ran: the
  environment's `AGENT_TRANSCRIPTS` variables were set at 13:34, during it, and take effect only
  when a session starts. Its 319 lines are the ones it archived and pushed by hand for its real
  use. Not a capture gap: tasks 3 and 4, which started with the variables set, are stored to
  their last message (`6cc07e5f` to 18:17:07, `dd2defdb` to 20:33:42).
- `dd2defdb` (task 4) fails red-first from the known limit of task 3's shell reading: a redirect
  under an unexpanded variable counted as a code write in the tree.
- Every row's skill blob is `unknown`: the sessions read `SKILL.md` with `cat`, which task 1's
  rule does not count, so the report cannot split skill versions yet.
- The task 1 session is not in the store: it ran before the hook and environment existed.

### Follow-up: the two grading gaps the real report showed (branch `ccr-f30b758a-i1j9v1`)

Both found by the real report above, each fixed red first:

- Skill blob `unknown`: `bin/transcripts.test.sh` gains three assertions (a `sed -n` and a `cat`
  of the skill file record the skill with `how` `Bash` and its blob; `git log --` and `echo` of
  the path do not). Red: `got [none]` twice, 79 passed, 2 failed. Green: 81 passed. Mutation:
  dropping `sed` from the verbs fails one.
- False red-first fail on a write under a variable: `bin/transcripts-grade.test.sh` gains a
  session that probes with `cd $S/probe && … > out.json` and `echo … > $TMPDIR/probe.py` before
  a failing test run and the code (now red-first pass), and one whose `cd $S/probe && cd <repo>`
  then writes `greet.py` (still fail). Red: `expected [pass] got [fail]`, 61 passed, 1 failed.
  Green: 62 passed. Mutation: removing either the target filter or the unknown `cd` fails one.

The earlier note that a cloud session's final lines are lost was wrong; it is corrected above.
All suites: transcripts 81/0, transcripts-store 82/0, transcripts-grade 62/0, transcripts-judge
68/0, red-check 107/0, record-check 85/0, dispatch 218/0, `cases.test.cjs` 25/0.

### Closed (2026-11-11)

All four tasks and the follow-up are merged (PRs #40 to #44). Requirements R1 to R9 and R11
are met, and the read path is verified against the real store. One part of R10 is still
open and is the owner's to run: the agreement check with `opencode-go/kimi-k3.1-pro`
(`transcripts judge DIR --judge opencode`), which waits on OpenCode Go balance; until then the
report says the agreement rate has not been measured. The secret key saved on the temporary
`agent-workflow-admin` environment is the owner's to delete. Capturing and grading Codex and
Cursor sessions is a separate change, drafted as 2026-11-11-agent-neutral-transcripts.
