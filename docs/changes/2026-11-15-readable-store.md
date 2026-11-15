---
id: 2026-11-15-readable-store
tier: 2
status: open
requester: Patrick Priestley, in chat on 2026-11-15 ("Is there a way for me to view these in supabase"; "I just want to see every session"; "Can I see transcriptions in supabase yet"; "Go ahead as recommended")
approvers: []
---
# A session's text can be read and searched in the store's dashboard

## Goal

The owner opens the Supabase dashboard and reads any stored session in order, message by
message and tool call by tool call, and searches all of them with plain SQL. Today the
store holds the text gzipped, so the dashboard shows that a session is there and nothing
of what was said.

## Probed facts

- Exact source (`plugins/change-record/store/schema.sql`): the store is four tables.
  `chunks.data` is "base64 of gzip of the lines"; `sessions.entry` is the redacted index
  entry. The publishable key (role `anon`) may only insert into `chunks` and `sessions`;
  the secret key (role `service_role`) reads. No sender ever updates a row. The file
  revokes from `public, anon, authenticated`.
- Exact source (`bin/transcripts`, `push_session`): a part of the archive is redacted line
  by line and cut into chunks. A chunk is closed before the line that would take it past
  2,000,000 redacted bytes, so a single longer line is a chunk of its own, of any size.
  Each chunk is one insert, keyed by a hash chain over the redacted bytes; a duplicate is
  answered 409 (23505) and counted as already stored. An insert that raises leaves the
  part unmarked and the session's index row unsent. `REDACTION` is 2; a change of it sends
  every stream again as a new chain.
- Exact source (`bin/transcripts`, `its_own` and `cmd_push`): a refusal from 400 to 499
  other than 401, 403, 408 and 429 is taken as one session's own, and the push goes on to
  the next session; any other stops the push.
- Exact source (`hooks/hooks.json`, `bin/transcripts`): the hook has 10 seconds and only
  starts a push in the background; that push has 60 (`PUSH_LIMIT`).
- Exact source (`bin/transcripts`, `cmd_materialize`): for each session it takes the index
  row that ranks first by redaction version, last timestamp, bytes sent and version, the
  first by `row_id` on a tie, and for each stream walks the chain back from that row's
  `tip` to the stream's root. A stream whose name is no transcript's (`STREAM`), a chunk
  that is missing, or one whose bytes do not match its id fails the whole session.
- Exact source (`grade/labels.py`, `events`; `bin/transcripts`): a transcript line is read
  by the Claude Code fields `type`, `isMeta`, `isSidechain` and `message.content`. `push`
  sends what `archive` kept, and `archive` keeps Claude Code transcripts only: for Codex
  and Cursor the tool has `probe` alone (record `2026-11-11-codex-cursor-capture`).
- Verified against the real system (the store, read with the read key through the
  environment `agent-workflow-admin`, 2026-11-15): 173 index rows of 17 sessions, 271
  chunks under redaction versions 1 and 2, from four senders; the largest chunk is
  1,999,898 bytes. `materialize` rebuilt the 17 sessions in 15 seconds: 46.6 MB of
  redacted transcript lines in 37 streams.
- Verified against the real system (record `2026-11-09-skill-transcripts`, Probed facts):
  an insert into a table that is not there is answered 404 `PGRST205`; one row is sent in
  a request, and a body of 4 MB was accepted. No request with several rows has been sent
  to the store.
- Mock only (PostgreSQL 16.15 in this container, the real rows above copied in, the roles
  `anon`, `authenticated` and `service_role` made by hand, `schema.sql` run first; this is
  not the store's own interface): the SQL of Appendix A runs with no error, and a second
  time with none. The rows read from every chunk are 6,199, holding 13.5 MB of text; the
  longest text is 112,819 characters; the table takes 10 MB on disk beside 20 MB for
  `chunks`.
- Mock only (the same): the view returns 5,959 rows for the 17 sessions. For 35 of the 37
  streams its rows are, in order, exactly the rows read from the file `materialize`
  rebuilt. In the other two, 8 rows differ, and each holds the character U+0000 in a
  tool's result, which the probe had to take out to load them: PostgreSQL refuses a text
  holding it (`unsupported Unicode escape sequence`).
- Mock only (the same, `set role`): `anon` inserts a row; the same row again is
  `duplicate key value violates unique constraint`; `anon` cannot select, update or
  delete the table and cannot select the view; `authenticated` can do nothing;
  `service_role` reads the view.
- Mock only (the same, each in a transaction rolled back): with a chunk of a session's
  chain deleted the view shows no row of that session and all 16 others; with an index
  row whose redaction version is a text and whose streams are a list it shows all 17 as
  before; with a stream named `../x` in a session's best row it shows no row of that
  session; with a chain's chunk numbers reversed it shows the same rows in the same order;
  with rows planted under `shape` 999 beside a session's own it shows the session's own.
- Mock only (the same): the view answers a count over every row in 18 ms.
- Verified against the real system (the 17 rebuilt sessions, read as the label sheet reads
  a session): the sheets hold 5,287 entries and 9.3 MB of text; the longest session holds
  6.9 MB of it.
- Assumed (Supabase, "Postgres Extensions Overview", read 2026-11-15): the page names no
  extension that unzips. Not checked against the project's own list.
- Assumed, not probed: a request with several rows is one statement, so it stores all of
  them or none, and a duplicate among them is answered 409 with none stored; the store's
  interface answers a text holding U+0000, or a lone surrogate, with an error; the
  dashboard reads as a role that may read the view, and its table editor lists a view
  beside the tables. Task 1 sends the first two for real before anything is built on
  them; the owner sees the last when they open the dashboard.

## Problem

The store was built for tools: `materialize` rebuilds a session on the owner's machine and
the graders read that. The owner asked three times on 2026-11-15 to read sessions where
they are stored, and cannot: PostgreSQL has no function that unzips `chunks.data`, so no
query and no view can show the text. The only readable form is a sheet written on a
machine that holds the read key.

## Requirements

- R1. `store/schema.sql` gains the table `messages` and the view `transcript` of Appendix
  A. `anon` may insert into the table and nothing else; `service_role` reads; `public` and
  `authenticated` get nothing. Running the file again changes nothing that is there.
  Check: a new suite, `store/schema.test.sh`, runs `schema.sql` in a PostgreSQL it starts
  where one is installed (the Linux CI job installs it; elsewhere the suite says that it
  cannot run and passes nothing off as checked) and asserts, by role, each line of the
  sentence above.
- R2. The view shows, for each session `materialize` would write, each stream's rows in
  the order of the chain, numbered from 1, and no row of a session `materialize` would
  not write for a reason SQL can see: a stream name that is no transcript's, or a chain
  that does not reach its root. It reads the rows of the one `shape` its own text names.
  A malformed index row does not stop it for the other sessions. Check: the same suite,
  on made-up rows: two index rows that tie are settled as `materialize` settles them; a
  chain with a chunk missing, and a stream named `../x`, hide their session and no other;
  an index row with a text for a version and a list for streams changes nothing; chunk
  numbers out of order do not change the order; rows of another shape are not shown.
- R3. `store/probe` gains the checks of the new table with the hooks' key, on the real
  store: a request of two rows is stored; the same request again is 409; a request of one
  new row and one stored row is 409 and, read back with the read key where there is one,
  the new row is not there; select, update and delete are refused, on the table and on the
  view; a request whose body is 3,500,000 bytes is stored; a text holding U+0000 is
  refused. Check: the probe's own exit status on the real store, run by the owner or in a
  cloud environment that holds the hooks' key, after the owner has run `schema.sql`; its
  output goes in Outcome. Nothing in tasks 2 and 3 is built before it passes.
- R4. The rows of a chunk are read from its redacted lines, after redaction and never
  before, by one function that both senders of rows use. For each line whose `type` is
  `user` or `assistant`, and each block of its `message.content` (a content that is a
  string is one text block, block 0):
  - a `text` block that is not blank: `kind` `text`; `who` is `assistant` on an assistant
    line, else `context` when the line has `isMeta` or `isCompactSummary`, else `user`;
  - a `tool_use` block of an assistant line: `kind` `call`, `who` `assistant`, `tool` the
    block's `name`, `call_id` its `id`, `text` its `input` as JSON with keys sorted,
    non-ASCII characters as they are, and Python's default separators;
  - a `tool_result` block of a user line: `kind` `result`, `who` `tool`, `call_id` the
    block's `tool_use_id`, `failed` its `is_error`, `text` its `content`: a string as it
    is; a list as its text blocks joined by a newline, each other block as its type in
    square brackets; anything else as JSON.
  Any other line or block gives no row (thinking and images among them, C5). `side` is the
  line's `isSidechain`; `at` is the line's `timestamp` when it reads as a date and time,
  else empty. `tool` and `call_id` are cut to 200 characters. In `text`, U+0000 becomes
  U+2400 and a lone surrogate becomes U+FFFD. A text over 3,000,000 characters is cut
  there and ends with a line saying how many characters were left in the chunk (C8).
  `shape` is 1, a constant beside the function. Check: `bin/transcripts-store.test.sh`: a
  made-up transcript with a line of each sort gives the rows stored beside it as a
  fixture, compared whole; the same test fails if the rows change and `shape` does not;
  an address in a text is stored redacted.
- R5. `transcripts messages [--session ID]...` fills the table from what the store holds.
  With the read key it walks the chunks the view would walk, reads each chunk's rows as
  R4 says, reads the keys of the rows the table has for that chunk and shape, and inserts
  the rows that are missing, in requests of at most 1,000,000 bytes of text (a longer text
  goes alone). It prints the chunks read, the rows inserted, the chunks that needed none,
  and each chunk it could not fill with the store's answer, and exits 1 if there is one.
  Check: the same suite against the stand-in: a store with chunks and no rows is filled;
  a second run inserts nothing; a chunk whose lines give no row is counted as needing
  none both times; a chunk with one row already there gets the others; without the read
  key it refuses.
- R6. `transcripts messages --check` changes nothing: for each chunk as in R5 it compares
  the rows the table holds with the rows the chunk gives and prints each row that is
  missing, each that is there and should not be, and each whose text or fields differ,
  and exits 1 if there is one. Check: the same suite: a filled store is clean; a row
  planted before the fill, a row planted under the same key with another text, and a row
  left out are each reported.
- R7. `transcripts push` sends a chunk's rows after the chunk, as R5 batches them. It
  never holds back a chunk, a part or the index row for them: when the store refuses a
  request of rows, whatever the answer, the push goes on, says at its end how many chunks
  it could not send rows for and that `transcripts messages` fills them, and its exit
  status is what it would have been. For a chunk the store already had, it sends the
  first request only and takes a 409 to mean the rows are there. For a chunk that is new,
  a 409 on a request is followed by that request's rows one by one, each 409 counted as
  stored. Check: the same suite: after a push the rows are there and `--check` is clean;
  a second push sends no row request for a part already sent; with the stand-in answering
  404 to `messages` (the SQL not yet run) and then 503, the chunks and the index row are
  stored, `materialize` rebuilds the session, the exit status is 0 and the message is
  printed; a later `transcripts messages` fills them.
- R8. `plugins/change-record/README.md` says how to read one session and how to search
  every session in the dashboard, with the SQL for each, what the table leaves out, and
  that the chunks are what the graders read. Check: `store/schema.test.sh` takes the two
  queries out of the README and runs them on its made-up rows: each returns the rows the
  test expects.

## Options and concerns

Options considered:

- A. A view that unzips the chunks. Not possible: PostgreSQL has no such function and the
  extensions page names none.
- B. Keep the chunks as plain text instead of gzip. Rejected: a chunk is up to 2 MB of JSON
  lines in one cell, which the dashboard shows as one unreadable cell.
- C. A table of rows read from the chunks, written beside them by `push` and by a command
  that fills gaps. Recommended: each row is a message a person can read, the dashboard
  filters and sorts it, and the chunks stay the one thing the graders trust.
- D. A page outside Supabase that rebuilds and shows sessions. Rejected: it needs the read
  key somewhere new, and the owner asked to read them where they are.
- E. Rows cut to a length. Rejected by the owner's ruling on C1, but for one text over
  3,000,000 characters (C8).
- F. As C, but rows written only by the command, never by `push` (raised by the review).
  Not recommended, and put to the owner as C7: nothing in a hook's path changes, but a new
  session cannot be read until someone with the read key runs the command.

Concerns ruled by the owner on 2026-11-15. The message they answered with "Go ahead as
recommended" proposed: "A `messages` table: one row per message or tool call";
"Written at push time, alongside the compressed chunks, which stay as they are for the
graders"; "Same access as now: machines can only insert; reading is through the
dashboard or the read key"; "Backfill of the 17 existing sessions from this session,
through the admin environment"; and, above them, "I would store the whole text rather
than cut anything."

### C1: the whole text is stored, uncut
Ruled: whole. A cut would make the dashboard's search miss what was cut. What it costs:
the table is about half the size of `chunks` again (10 MB beside 20 MB today).

### C2: the 17 sessions already stored are filled in
Ruled: yes, with `transcripts messages`, run from the cloud session through the
environment `agent-workflow-admin`, where the proxy adds the read key.

### C3: the chunks stay
Ruled: yes. `materialize` and every grader keep reading the chunks; the rows are for
people. If the two ever disagree, the chunks are right, and R6 is how that is seen.

### C4: who can read is not changed
Ruled: machines can only insert; reading is the dashboard or the read key. A reader of
the table sees the same redacted text a reader of the chunks could already rebuild.

Not yet put to the owner:

### C5: thinking and images are left out
A transcript line can hold the model's thinking and images. Recommended: no row for
either, as the label sheet shows neither. What it costs: the dashboard does not show why
the agent did something where only its thinking said so.

### C6: the store grows faster, and a push sends more
Each chunk's text goes twice, once zipped and once as rows, so a push sends roughly three
times the bytes inside the same 60 seconds; a part that does not finish is sent again at
the next push, as today. Recommended: accept it, and measure a push of the longest
session in task 3's real use. The free plan's database is said to hold 500 MB (not
probed); removing old sessions is the owner's to do in the dashboard.

### C7: `push` writes rows as well as the command (raised by the review)
The review asked whether rows should come only from `transcripts messages`. Recommended:
both, with R7's rule that rows never hold back a chunk. What it costs: more code in the
path a hook starts, and rows that are missing until the command is run when a push could
not send them. What the other way costs: no new session is readable in the dashboard
until someone with the read key runs the command.

### C8: one text over 3,000,000 characters is cut
The largest request the store has been seen to take is 4 MB, and a single transcript line
can be longer than that. Recommended: a text over 3,000,000 characters is stored cut,
with a last line saying so; the chunk still holds all of it. The longest text in the
store today is 112,819 characters, so this cuts nothing that exists. It is the one place
where C1's "whole" does not hold.

### C9: whoever holds the hooks' key can write what the owner reads
The hooks' key can already insert a made-up session. With this table it can also insert a
row that the chunk does not bear out, before the honest sender does. Recommended: accept
it, as for sessions: the key is on the owner's machines only, the view reads one named
shape, so rows under another are not shown, and `transcripts messages --check` (R6)
reports every row the chunks do not bear out. What it costs: until someone runs the
check, a planted row is read as the session's.

## Decisions

- The key of a row is the chunk it was read from, the shape, the line in that chunk and
  the block in that line. Rejected: a line's number in the whole stream, which two
  senders or two redaction versions number alike for different text; the chunk's id is a
  hash of its bytes.
- The rule that reads rows has a version, `shape`, 1 at first. The view names the one
  shape it reads, and a change of the rule changes the constant, the fixture and the
  view's text together; the owner runs `schema.sql` again. Rejected: the view reading the
  highest shape a chunk has, which lets anyone with the hooks' key replace what is shown
  by inserting under a higher one (found by the review).
- Rows never decide whether a chunk, a part or an index row is sent (R7). Rejected: the
  first draft's "a failure to store the rows is reported as the chunk's failure is", by
  which a table meant for people could have stopped `materialize` from seeing a session,
  for every session until the owner had run the SQL (found by the review).
- What is missing is found from the store, not remembered by the sender: `transcripts
  messages` reads the keys that are there. Rejected: a mark in the sender's archive for
  rows owed, which another machine's fill would not see.
- The order of a session's rows is the order of the chain, counted from the tip.
  Rejected: `chunks.number`, which is what a sender says (found by the review).
- The view repeats `materialize`'s choice in SQL, the same ranking with the same
  tie-break and the same walk, and shows nothing of a session `materialize` would refuse
  for a reason SQL can see. What SQL cannot see is a chunk whose bytes do not match its
  id; R6 reads the bytes. Rejected: the newest rows by time, which mixes two redaction
  versions of one session.
- The view is an ordinary view, revoked from `public`, `anon` and `authenticated` and
  granted to `service_role`. Rejected: `security_invoker`, which needs PostgreSQL 15 and
  adds nothing the revoke does not do; the probe showed both refuse `anon`.
- U+0000 becomes U+2400 and a lone surrogate U+FFFD in a row. Rejected: dropping them,
  which hides that they were there; and leaving the chunk's rows out, which loses a
  chunk's text for one character.
- The rows are read by code in `bin/transcripts`, beside the push. Rejected: the label
  sheet's reader in `grade/labels.py`, which joins a call to its result, so that a row
  would change when the result arrives, and an insert-only table cannot change a row.
- Only Claude Code transcripts give rows, since only they are stored. A line in another
  agent's format gives none.

## Tasks

1. **The table, the view and the gate.** `schema.sql`, `store/schema.test.sh` and its CI
   step, and the new checks in `store/probe`. Test: `store/schema.test.sh`. Red today:
   there is no table. Then the owner runs `schema.sql` in the project's SQL editor and
   the probe is run on the real store with the hooks' key; its output is this task's real
   use, and tasks 2 and 3 wait for it.
2. **Filling in and checking.** The rows read from a chunk, the stand-in's new table,
   `transcripts messages` and `--check`, and the README. Test:
   `bin/transcripts-store.test.sh`. Red today: the command is unknown. Real use: the 17
   sessions filled through `agent-workflow-admin`; `--check` clean; for every stream the
   view's rows, read from the real store, are the rows read from the file `materialize`
   rebuilds, in order; and the owner reads a session in the dashboard.
3. **The push.** `transcripts push` sends rows. Test: `bin/transcripts-store.test.sh`.
   Red today: a push stores no row. Real use: a push of a real session from a machine
   with the hooks' key, timed with and without rows, then `--check` clean on it; and the
   error path of Checks.

## Checks

`bash plugins/change-record/store/schema.test.sh`,
`bash plugins/change-record/bin/transcripts-store.test.sh` and the other change-record
suites. The review of each pull request by another model family is the pr-agent job.
Real use: each task's, above. Error path: a push while the store answers 404 for the new
table, as it does before the owner has run the SQL: the session's chunks and index row
are stored, `materialize` rebuilds it, and the push says the rows are owed. The
independent reviewer should attack: a row that holds text the chunk does not, or text not
redacted; a way for the hooks' key to read; a push that holds anything back for its rows;
and the view showing a copy `materialize` would not rebuild.

## Appendix A: the table and the view, as run in the probe

```sql
create table if not exists public.messages (
  session_id text    not null check (session_id ~ '^[A-Za-z0-9._-]{1,100}$'),
  stream     text    not null check (length(stream) between 1 and 300),
  chunk_id   text    not null check (chunk_id ~ '^[0-9a-f]{64}$'),  -- the chunk the row was read from
  shape      integer not null check (shape >= 1),                   -- the version of the rule that read it
  line       integer not null check (line >= 1),                    -- the line's number in that chunk
  block      integer not null check (block >= 0),                   -- the block's place in the line
  at         timestamptz,                                           -- the line's own timestamp
  who        text    not null check (who in ('user', 'assistant', 'tool', 'context')),
  kind       text    not null check (kind in ('text', 'call', 'result')),
  tool       text    check (length(tool) <= 200),                   -- the tool called, on a call
  call_id    text    check (length(call_id) <= 200),                -- ties a result to its call
  failed     boolean not null default false,                        -- a result the tool marked an error
  side       boolean not null default false,                        -- a subagent's line kept inline
  text       text    not null check (length(text) <= 3100000),      -- redacted, as the chunk holds it
  created_at timestamptz not null default now(),
  primary key (session_id, stream, chunk_id, shape, line, block)
);

alter table public.messages enable row level security;
revoke all on public.messages from public, anon, authenticated;
grant insert on public.messages to anon;
grant all on public.messages to service_role;
drop policy if exists messages_insert on public.messages;
create policy messages_insert on public.messages for insert to anon with check (true);

-- Each session's text in order, from the copy `materialize` rebuilds: the index row it ranks first, and for
-- each stream the chain of chunks that row's tip ends. A session `materialize` would not write (a stream whose
-- name is no transcript's, or whose chain does not reach its root) is not shown at all.
create or replace view public.transcript as
with recursive best as (
  select distinct on (s.session_id) s.session_id,
         case when jsonb_typeof(s.entry->'sent'->'streams') = 'object' then s.entry->'sent'->'streams' else '{}'::jsonb end as streams
  from public.sessions s
  order by s.session_id,
           case when jsonb_typeof(s.entry->'redaction_version') = 'number' then (s.entry->>'redaction_version')::numeric else 0 end desc,
           coalesce(s.entry->>'last_timestamp', '') collate "C" desc,
           (select coalesce(sum(case when jsonb_typeof(x.value->'bytes') = 'number' then (x.value->>'bytes')::numeric else 0 end), 0)
              from jsonb_each(case when jsonb_typeof(s.entry->'sent'->'streams') = 'object'
                                   then s.entry->'sent'->'streams' else '{}'::jsonb end) x) desc,
           s.version desc,
           s.row_id collate "C"
), tips as (
  select b.session_id, x.key as stream, x.value->>'tip' as tip,
         x.key ~ '^(?:main|subagents/(?!(?:.*/)?\.\.?(?:/|$))[A-Za-z0-9._/-]+)$' as named
  from best b cross join lateral jsonb_each(b.streams) x
), chain as (
  select t.session_id, t.stream, c.chunk_id, c.start_id, 1 as depth
  from tips t
  join public.chunks c on c.session_id = t.session_id and c.stream = t.stream and c.chunk_id = t.tip
  where t.named
  union all
  select c.session_id, c.stream, c.chunk_id, c.start_id, h.depth + 1
  from chain h
  join public.chunks c on c.session_id = h.session_id and c.stream = h.stream and c.chunk_id = h.start_id
  where h.depth < 100000
), whole as (
  select session_id, stream from chain
  where start_id = encode(sha256(convert_to(session_id || '/' || stream, 'UTF8')), 'hex')
), written as (
  select b.session_id from best b
  where not exists (select 1 from tips t
                    where t.session_id = b.session_id
                      and (not t.named or not exists (select 1 from whole w
                                                      where w.session_id = t.session_id and w.stream = t.stream)))
)
select m.session_id, m.stream,
       row_number() over (partition by m.session_id, m.stream order by h.depth desc, m.line, m.block) as n,
       m.at, m.who, m.kind, m.tool, m.failed, m.side, m.text, m.call_id
from chain h
join written s on s.session_id = h.session_id
join public.messages m on m.session_id = h.session_id and m.stream = h.stream and m.chunk_id = h.chunk_id
where m.shape = 1;

revoke all on public.transcript from public, anon, authenticated;
grant select on public.transcript to service_role;
```
