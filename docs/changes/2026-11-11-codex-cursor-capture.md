---
id: 2026-11-11-codex-cursor-capture
tier: 2
status: approved
requester: Patrick Priestley, in chat on 2026-11-11 ("Is there a way to make this platform agnostic? Using chatgpt, opencodego, cursor etc", "Codex and Cursor, review this solution and draft the record", and "Yes" to capture only after the architecture review)
approvers: [Patrick Priestley, 2026-11-11]
plugin: plugins/change-record
tasks:
  - name: probe
  - name: capture
    after: probe
---
# Codex and Cursor sessions are kept beside Claude Code's

## Goal

Sessions run with Codex or Cursor in this repository leave their transcripts in the same
archive and database as Claude Code sessions, as each agent wrote them and marked with the
agent they came from, so they are not lost while the grading is being checked
(2026-11-11-grading-trust) and can be graded later without having been captured again.

## Probed facts

What exists today (the 2026-11-09-skill-transcripts record, all four tasks merged):

- Exact source (`.claude/settings.json`, `bin/transcripts`): capture is Claude Code's `Stop` and
  `SessionEnd` hooks running `transcripts archive`, which reads hook JSON with `session_id`,
  `transcript_path`, `cwd` and `hook_event_name`.
- Exact source (`grade/fields.py`): the graders read Claude Code's transcript lines directly
  (`tool_use` and `tool_result` blocks, tool names `Bash`, `Write`, `Edit`).
- Exact source (`store/schema.sql`): `session_id` must match `^[A-Za-z0-9._-]{1,100}$`, so an id
  with a colon, such as `codex:<id>`, is refused by the database. The index entry is `jsonb`,
  so a new attribute in it needs no schema change.
- Exact source (PR #44, open on 2026-11-11): a shell command that prints a `SKILL.md` counts as
  using the skill. This is how an agent without the plugin reads it.

Codex:

- Exact source (`openai/codex` at `4dd5f1e`, 2026-11-11, its main branch, not necessarily the
  release the owner runs): Codex has command hooks, with input schemas under
  `codex-rs/hooks/schema/generated/`. The `Stop` hook receives `session_id`, `transcript_path`
  (nullable), `cwd`, `hook_event_name`, `model`, `permission_mode`, `turn_id`,
  `stop_hook_active` and `last_assistant_message`. `SessionEnd` receives `session_id`,
  `transcript_path`, `cwd`, `hook_event_name` and `reason`. The four fields `archive` reads
  have the same names as Claude Code's.
- Exact source (same commit, `hooks/src/engine/discovery.rs`): hooks are declared in a
  `hooks.json` in a config folder, or under `[hooks]` in `config.toml`; a project layer is the
  repository's `.codex/` folder. A hook that is not managed is checked against a trusted hash
  before it runs.
- Exact source (same commit, `rollout/src/recorder.rs`, `rollout/src/compression.rs`): a session
  is a JSONL "rollout" file under `~/.codex/sessions/YYYY/MM/DD/`, named
  `rollout-<timestamp>-<conversation id>.jsonl`. Each line has a `timestamp` and one item:
  session metadata, a response item, a compaction, a turn context or token usage. A revert
  writes a new rollout file for the same thread (`…_<rollout id>.jsonl`). Rollouts can be
  compressed to `.jsonl.zst`.
- Exact source (same commit, `protocol/src/models.rs`, `protocol/src/protocol.rs`): tool calls
  are response items `function_call` (a `name`, and `arguments`), `local_shell_call` and
  `custom_tool_call`, answered by `function_call_output` matched on `call_id`. Session
  metadata carries `cwd`, `cli_version`, `originator`, `source`, git information and, when
  present, `creator_user_id` and `creator_account_id`.
- Assumed: a file edit is a `custom_tool_call` named `apply_patch` whose text names each file;
  a refused command shows only in its output text ("rejected by user"), with no error flag.
  To be checked in task 1 on a real session.
- Assumed: the hook's `transcript_path` is the plain `.jsonl` while the session is live.
- Verified against the real system (this container, 2026-11-11): Python 3.13 has no zstd
  module and there is no `zstd` command, so a `.jsonl.zst` rollout cannot be read here.

Cursor:

- Assumed (Cursor's hooks documentation as quoted in search results on 2026-11-11;
  `cursor.com` cannot be reached from the cloud environment, so the page was not read):
  hooks are declared in `<project>/.cursor/hooks.json` or `~/.cursor/hooks.json` with
  `"version": 1`. Events include `stop`, `sessionEnd`, `afterShellExecution`, `afterFileEdit`
  and `postToolUse`. Every hook receives `conversation_id`, `generation_id`, `model`,
  `hook_event_name`, `cursor_version`, `workspace_roots`, `user_email` and `transcript_path`,
  which is null when transcripts are turned off.
- Assumed (forum posts and a third-party reference, same date): `stop` fires at the end of each
  agent turn, in the CLI too; `sessionEnd` fires when the window or tab closes, not per turn;
  user-level hooks do not run in Cursor's cloud agents; the format of the file at
  `transcript_path` is not documented.
- Not known: where Cursor keeps transcripts, their format, how a refused command appears, and
  whether a hook's output on stdout matters. All to be checked in task 1.

## Problem

The owner works with Codex and Cursor as well as Claude Code, and only Claude Code sessions
are captured. Every Codex or Cursor session that follows the `change` skill is lost to the
archive. The architecture review of 2026-11-11 found the graders not yet trustworthy enough
to extend to other agents, so grading those sessions waits; capture does not have to, and a
session not captured now cannot be graded later.

## Requirements

- R1. With the hook files in place and `AGENT_TRANSCRIPTS` set, a Codex session and a Cursor
  agent session in this repository are archived at each stop. The index entry gains `agent`
  (`claude-code`, `codex` or `cursor`), the agent's version and the transcript's `format`.
  Check: a test feeds each agent's real hook input (task 1's samples) to `archive` and
  compares the entry with a stored one.
- R2. The archive and the database keep each transcript as its agent wrote it, redacted on
  send as today. Check: the archived parts rejoin byte for byte to the fixture, and
  `materialize` returns the native file under a folder per agent.
- R3. A session's key stays its own id and the database schema does not change. Check:
  `store/schema.sql` is untouched, and a test pushes a Codex and a Cursor session to the
  stand-in under it.
- R4. The hook never fails or slows a session of any agent: exit 0, a bounded time, and
  output each agent's hook contract accepts. Check: tests run the hook command as each agent
  runs it, with an unwritable archive and with no archive set.
- R5. `transcripts import --agent codex|cursor` registers sessions already on a machine once.
  Check: a test imports a fixture session folder twice and the second run adds nothing.
- R6. What the new agents add is redacted before it leaves the machine: Cursor's `user_email`,
  and Codex's user and account ids. Check: a test finds none of them in the bytes sent.
- R7. `grade`, `judge` and `report` leave a session from another agent alone: every step not
  applicable, with the reason "not graded yet: <agent>", and no row in a pass rate. Check: a
  test grades a folder holding one session per agent.

## Options and concerns

**A. Each agent's own stop hook, transcripts stored as the agent wrote them (recommended).**
The repository gains `.codex/hooks.json` and `.cursor/hooks.json` beside
`.claude/settings.json`, all running `transcripts archive`. The archive and the database keep
the native file, and the index entry says which agent and which format it is. Nothing reads
the content yet beyond what the entry needs. Trade-offs: three hook files to keep in step, and
an agent's update can change what its hook passes. What is stored stays usable either way,
because it was never converted.

**B. Convert to Claude Code's format at capture.** One format in the store. Rejected: the
conversion is lossy and cannot be redone when it turns out wrong, and the stored file would
claim to be something it is not.

**C. Our own event log from per-tool hooks** (`PostToolUse`, `afterShellExecution`,
`afterFileEdit`), ignoring transcripts. The hook inputs are documented where Cursor's
transcript is not. Rejected for this change: a process per tool call, no record of the agent's
own text (the `Change:` line, the tier), and only what hooks cover. Whether it is worth
building for an agent that gives no transcript is a question for the later grading change
(see C1).

**D. A git hook or a timed import as the trigger** (the first proposal in chat). Rejected as
the main path: both agents have stop hooks, so the same mechanism as today works. `import`
stays for sessions made before the hooks existed.

**E. A proxy that logs each agent's API traffic.** Rejected: it sits in the path of the
owner's credentials and breaks when an agent changes its transport.

**F. Capture and grade together** (the six-task draft of this change: an event model, an
adapter per agent and a report split by agent). Rejected for now: it widens the graders to two
more formats before their error rate on one agent is known, so a wrong rule would be copied
three times. Grading waits for 2026-11-11-grading-trust; capture does not depend on it.

### C1: Cursor's transcript may be missing or unusable
Its format is undocumented, and `transcript_path` is null when transcripts are off. Failure
case: a Cursor session ends and nothing is archived, with no sign of why. Recommended: store
whatever file the agent gives, whatever its shape. When it gives none, say so once in the
hook's log and archive nothing. Building a log from per-tool hooks (C above) is left to the
later grading change. Owner: Patrick Priestley.
Resolved: as recommended: capture stores whatever file the agent gives; when it gives none, the hook
says so once in its log and archives nothing; a log built from per-tool hooks is left to the
later grading change. Patrick Priestley, 2026-11-11.

### C2: where the probes run
Codex and Cursor need the owner's logins, and `cursor.com` is not reachable from the cloud
environment. Failure case: capture is built on the assumed hook inputs and fails on the real
ones. Recommended: task 1 ships `transcripts probe`, the owner runs one short session per
agent on their machine with it hooked in, and it writes a redacted sample of the hook input
and the transcript's shape, which becomes the fixture. Alternative: allow the hosts and save
an OpenAI key and a Cursor login in a cloud environment, which puts two more credentials in
the cloud. Owner: Patrick Priestley.
Resolved: as recommended: task 1 ships `transcripts probe` and the owner runs one short session
per agent on his machine; no Codex or Cursor credential goes into a cloud environment. Patrick
Priestley, 2026-11-11.

### C3: compressed Codex rollouts
Older rollouts are `.jsonl.zst`, and Python before 3.14 cannot read zstd. Failure case:
`import` silently misses old Codex sessions. Recommended: `import` uses the `zstd` command
when it is installed and otherwise lists what it skipped; live capture is unaffected if the
assumption about the live file holds, which task 1 checks. Owner: Patrick Priestley.
Resolved: as recommended: `import` uses the `zstd` command when it is installed and otherwise
lists what it skipped. Patrick Priestley, 2026-11-11.

### C4: which sessions the hooks reach
Codex checks a project hook against a trusted hash, so the owner approves it once and again
whenever the hook command changes; an agent must never answer that prompt. Cursor's
user-level hooks do not run in its cloud agents, and its `sessionEnd` is tied to the window.
Failure case: a hook that was never approved, or a cloud agent's session, is not captured and
nobody notices. Recommended: project-level hook files in this repository, `stop` alone for
Cursor, the owner approves Codex's prompt, and both vendors' cloud agents stay out of scope
until asked for. Owner: Patrick Priestley.
Resolved: as recommended: project-level hook files in this repository, `stop` alone for Cursor,
the owner approves Codex's trust prompt, and both vendors' cloud agents are out of scope.
Patrick Priestley, 2026-11-11.

### C5: new personal data, and re-sending what is stored
Cursor's hook input carries `user_email`; Codex's session metadata carries user and account
ids. Redacting them means new patterns, which raises the redaction version, which re-sends
every stored stream as a new generation (51 chunks today). Failure case without them: an
email address and two account ids reach the database in clear. Recommended: add the patterns
and accept the one-off re-send, since the alternative leaves two redaction rule sets in one
database. Owner: Patrick Priestley.
Resolved: as recommended: the patterns are added to the one rule set and the one-off re-send of
every stored stream is accepted. Patrick Priestley, 2026-11-11.

## Decisions

- The agent is an attribute of the index entry, never part of the session's key. Rejected: a
  prefixed id such as `codex:<id>`, which the database's check on `session_id` refuses and
  which would change every key already stored.
- Transcripts are stored native, and nothing is converted before it is stored. Rejected: B
  above.
- Capture uses each agent's own stop hook, with the hook file committed in the repository so
  a worktree carries it. Rejected: D above, and user-level hook files, which the 2026-11-09
  record's C4 already held back.
- `archive` learns the agent from an `--agent` flag in each hook file's command, not by
  guessing from the input's field names. Without the flag it is `claude-code`, so the existing
  hook and its entries do not change. Rejected: guessing, which breaks the day two agents share
  a field name; Codex's input already shares four with Claude Code's.
- Capture does not read a transcript's content to decide whether to keep it. A file whose
  shape the probe did not see is archived all the same, and its entry's `format` says what was
  recognised. Rejected: refusing an unrecognised file, which loses the session an update to
  the agent produced.
- `materialize` rebuilds each agent's sessions under a folder of its own, with Claude Code's
  layout left where it is. Rejected: one folder for all, in which the existing graders and
  Skill Doctor would meet files they cannot read.
- Grading other agents' sessions waits for 2026-11-11-grading-trust. Until then `grade`, `judge`
  and `report` skip a session whose entry names another agent and give the reason (R7).
  Rejected: F above, and reading those sessions with Claude Code's reader, which would turn
  every step into a false failure or a silent not applicable.
- The new redaction patterns go into the one rule set, with its version raised. Rejected: a
  rule set per agent, which leaves two versions of redacted bytes in one database (C5).
- `dispatch`, which starts `claude -p`, is left as it is; running tasks with another agent is
  a separate change.

## Tasks

One pull request each, in order.

1. **Probe.** `bin/transcripts` gains `probe --agent codex|cursor`: a hook command that writes
   the hook input and a redacted summary of the transcript's shape (keys, item types, tool
   names, whether a file was given; no content) to a file. The owner runs one short session
   per agent with it and commits the samples under `grade/fixtures/agents/`. The Probed facts
   change label from what the samples show, in the same pull request. Test, in
   `bin/transcripts.test.sh`: `probe` on made-up Codex and Cursor files gives the stored
   summaries; it fails today because the command does not exist.
2. **Capture.** `.codex/hooks.json`, `.cursor/hooks.json`, and in `bin/transcripts`:
   `archive --agent`, the entry's `agent`, version and `format`, `import --agent`,
   `materialize` per agent, the redaction patterns of R6, and the skip with its reason in
   `grade`, `judge` and `report` (R7). The README says how to turn each hook on, and the record
   is closed. Tests, in `bin/transcripts.test.sh`, `transcripts-store.test.sh` and
   `transcripts-grade.test.sh`: R1 to R7 against task 1's samples. They fail today because
   `archive` rejects the flag, `import` knows one agent, the two ids and the email address
   pass redaction, and no entry names an agent for `grade` to give as its reason.

## Checks

`bash plugins/change-record/bin/transcripts.test.sh`, `transcripts-store.test.sh`,
`transcripts-grade.test.sh`, `transcripts-judge.test.sh` and `node --test
plugins/change-record/evals/cases.test.cjs`. Real use, on the owner's machine: one Codex
session and one Cursor session in this repository are archived at their stops, sent to the
database, and rebuilt with `materialize` into their agents' folders, byte for byte what each
agent wrote apart from the redactions; `grade` on the rebuilt folder then leaves both ungraded
with the reason and grades the Claude Code sessions as before. Error path: with
`AGENT_TRANSCRIPTS` not set, the hook exits 0 in each agent and the session goes on. The
reviewer should attack: whether a hook can fail or slow a Codex or Cursor session, whether
anything of the new agents leaves the machine unredacted, whether a stored transcript can
differ from what its agent wrote, whether a Claude Code entry or verdict changes, whether a
session from another agent can reach a pass rate, and whether any step has an agent answer
Codex's trust prompt.

## Outcome
