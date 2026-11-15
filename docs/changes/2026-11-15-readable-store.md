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
  the secret key (role `service_role`) reads. No sender ever updates a row.
- Exact source (`bin/transcripts`, `push_session`): a part of the archive is redacted line
  by line, cut into chunks of at most 2,000,000 redacted bytes, and each chunk is one
  insert, keyed by a hash chain over the redacted bytes. A duplicate insert is answered
  409 (23505) and counted as already stored. `REDACTION` is 2; a change of it sends every
  stream again as a new chain.
- Exact source (`bin/transcripts`, `cmd_materialize`): for each session it takes the index
  row that ranks first by redaction version, last timestamp, bytes sent and version, and
  for each stream walks the chain back from that row's `tip`.
- Verified against the real system (the store, read with the read key through the
  environment `agent-workflow-admin`, 2026-11-15): 173 index rows of 17 sessions, 271
  chunks under redaction versions 1 and 2, from four senders. `materialize` rebuilt the 17
  sessions in 15 seconds: 46.6 MB of redacted transcript lines in 37 streams.
- Verified against the real system (the same rows, copied into PostgreSQL 16.15 in this
  container, with roles `anon`, `authenticated` and `service_role` made as Supabase has
  them and `schema.sql` run first): the SQL of Appendix A runs with no error, and a second
  time with none. The rows read from every chunk are 6,199, holding 13.5 MB of text; the
  table takes 10 MB on disk beside 20 MB for `chunks`.
- Verified against the real system (the same): the view returns 5,959 rows for the 17
  sessions. For 35 of the 37 streams its rows are, in order, exactly the rows read from the
  file `materialize` rebuilt. In the other two, 8 rows differ, and each holds the
  character U+0000 in a tool's result, which the probe had to take out to load them.
- Verified against the real system (the same): PostgreSQL refuses a text holding U+0000
  (`unsupported Unicode escape sequence`). Assumed: the store's interface answers such an
  insert with an error and stores nothing.
- Verified against the real system (the same, `set role`): `anon` inserts a row; the same
  row again is `duplicate key value violates unique constraint`; `anon` cannot select,
  update or delete the table and cannot select the view; `authenticated` can do nothing;
  `service_role` reads the view. A view made `with (security_invoker = true)` and granted
  to `anon` as well still answers `anon` with `permission denied for table messages`.
- Verified against the real system (the same): the view answers a count over every row
  in 31 to 50 ms, one session's rows in 11 ms, and a search of every text for a word in
  23 ms.
- Verified against the real system (the same): with a second copy of one session's rows
  inserted under `shape` 2, the view shows that session's 2 rows from shape 2 and none
  from shape 1.
- Verified against the real system (the 17 rebuilt sessions, read as the label sheet reads
  a session): the sheets hold 5,287 entries and 9.3 MB of text; the longest session holds
  6.9 MB of it.
- Documentation claim (Supabase, "Postgres Extensions Overview", read 2026-11-15): the
  page names no extension that unzips. Not verified against the project's own list.
- Assumed, not probed: an insert of several rows in one request is one statement, so it
  stores all of them or none; the dashboard's table editor lists a view beside the tables;
  the project runs PostgreSQL 15 or later, which `security_invoker` needs. The first is
  checked in task 1's real use, the other two when the owner runs the SQL.

## Problem

The store was built for tools: `materialize` rebuilds a session on the owner's machine and
the graders read that. The owner asked three times on 2026-11-15 to read sessions where
they are stored, and cannot: PostgreSQL has no function that unzips `chunks.data`, so no
query and no view can show the text. The only readable form is a sheet written on a
machine that holds the read key.

## Requirements

- R1. `store/schema.sql` gains a table `messages` and a view `transcript`, as in Appendix
  A: one row for each text, tool call and tool result of a transcript line, keyed by the
  chunk it was read from, the line's number in that chunk, the block's place in the line,
  and the version of the rule that read it. `anon` may insert and nothing else;
  `service_role` reads; `authenticated` gets nothing. Running the file again changes
  nothing that is there. Check: the store suite runs the file's statements for the new
  table against the stand-in's rules, and the record's probe is run again on PostgreSQL in
  task 1's real use.
- R2. The rows of a chunk are read from its redacted lines, after redaction and never
  before: a text of a user line is `user`, or `context` when the line is marked as
  injected or as a summary; a text of an assistant line is `assistant`; a tool call is
  `assistant` with the tool's name, its id and its input as JSON; a tool result is `tool`
  with the call's id, whether it failed, and its content as text. A line of another type,
  a block of another kind (thinking, an image) and an empty text give no row. A line of a
  subagent kept inline is marked. U+0000 in a text is written as U+2400, the sign for it.
  Check: `bin/transcripts-store.test.sh`: a made-up transcript with one line of each sort
  gives the expected rows; a text with an address in it is stored redacted; a U+0000 is
  stored as U+2400.
- R3. `transcripts push` sends, after each chunk it sends, that chunk's rows in one
  request. A 409 is counted as already stored. A push that stops between the two sends
  both again at the next push. A failure to store the rows does not undo the chunk and is
  reported as the chunk's failure is: the part is not marked sent. Check: the same suite,
  against the stand-in: the rows are there after a push; a second push sends nothing; with
  the stand-in refusing `messages`, the push fails, and the next push, not refused, leaves
  the rows there once.
- R4. `transcripts messages [--session ID]...` fills the table for what the store already
  holds: with the read key it reads each chunk, reads its rows as R2 says, and inserts
  them, one request a chunk, counting a 409 as already stored. It prints how many chunks
  it read, how many it filled and how many were already filled. Check: the same suite: a
  store with chunks and no rows is filled; a second run fills nothing; without the read
  key it refuses.
- R5. The view `transcript` gives, for each session and stream, the rows of the copy
  `materialize` would rebuild, numbered in order. Check: task 2's real use: on the real
  store, for every stream, the view's rows are the rows read from the file `materialize`
  rebuilds, in the same order; and the probe of this record, run again in PostgreSQL
  with the final SQL.
- R6. The README says how to read a session and how to search all sessions in the
  dashboard, with the SQL, and what the table does not hold. Check: the text is there and
  its two queries are the ones run in task 2's real use.

## Options and concerns

Options considered:

- A. A view that unzips the chunks. Not possible: PostgreSQL has no such function and the
  extensions page names none.
- B. Keep the chunks as plain text instead of gzip. Rejected: a chunk is up to 2 MB of JSON
  lines in one cell, which the dashboard shows as one unreadable cell, and it would triple
  what every push sends.
- C. A table of rows read from the chunks, written beside them. Recommended: each row is a
  message a person can read, the dashboard filters and sorts it, and the chunks stay the
  one thing the graders trust.
- D. A page outside Supabase that rebuilds and shows sessions. Rejected: it needs the read
  key somewhere new, and the owner asked to read them where they are.
- E. Rows cut to a length. Rejected by the owner's ruling on C1: the whole text of all 17
  sessions is 13.5 MB.

Concerns, each ruled by the owner on 2026-11-15 ("Go ahead as recommended"):

### C1: the whole text is stored, uncut
Recommended and ruled: whole. A cut would make the dashboard's search miss what was cut.
What it costs: the table is about half the size of `chunks` again (10 MB beside 20 MB
today).

### C2: the 17 sessions already stored are filled in
Recommended and ruled: yes, with `transcripts messages`, run from the cloud session
through the environment `agent-workflow-admin`, where the proxy adds the read key.

### C3: the chunks stay
Recommended and ruled: yes. `materialize` and every grader keep reading the chunks; the
rows are for people. If the two ever disagree, the chunks are right.

### C4: who can read is not changed
Recommended and ruled: machines can only insert; reading is the dashboard or the read
key. A reader of the table sees the same redacted text a reader of the chunks could
already rebuild.

Raised by this plan, not yet put to the owner:

### C5: thinking and images are left out
A transcript line can hold the model's thinking and images. Recommended: no row for
either, as the label sheet shows neither; a thinking block is often long and sometimes
only a signature. What it costs: the dashboard does not show why the agent did something
where only its thinking said so.

### C6: the store grows faster
Each push sends each chunk's text twice, once zipped and once as rows. Recommended:
accept it. The longest session so far is 6.9 MB of text; the free plan's database holds
500 MB (not probed), and removing old sessions is the owner's to do in the dashboard.

## Decisions

- The key of a row is the chunk it was read from, the line in that chunk and the block in
  that line. Rejected: a line's number in the whole stream, which two senders or two
  redaction versions number alike for different text; the chunk's id is a hash of its
  bytes and cannot be claimed twice.
- The rule that reads rows has a version, `shape`, in the key, 1 at first. A later rule
  (rows for images, say) writes new rows beside the old and the view reads the newest
  shape a chunk has. Rejected: no version, which leaves a changed rule unable to replace
  what an insert-only table already holds.
- A chunk's rows go in one request, after the chunk. Rejected: a request a row, which is
  thousands of requests for a long session inside a hook's 60 seconds; and before the
  chunk, which could leave rows for a chunk the store does not have.
- The view repeats `materialize`'s choice in SQL, the same ranking and the same walk of
  the chain, so that the two cannot show different copies. Rejected: the newest rows by
  time, which mixes two redaction versions of one session.
- The view is `security_invoker` and is also granted to `service_role` alone. Either
  would do; the first keeps Supabase's own advice on views quiet and the second does not
  depend on it.
- U+0000 becomes U+2400 in a row. Rejected: dropping it, which hides that it was there;
  and refusing the chunk's rows, which loses a whole chunk's text for one character.
- The rows are read by code in `bin/transcripts`, beside the push. Rejected: the label
  sheet's reader in `grade/labels.py`, which joins a call to its result, so that a row
  would change when the result arrives, and an insert-only table cannot change a row.

## Tasks

1. **The table, the view and the push.** `schema.sql`, the stand-in, the rows read from a
   chunk, and `push`. Test: `bin/transcripts-store.test.sh`. Red today: no row is stored.
   Then the owner runs `schema.sql` in the project's SQL editor.
2. **Filling in, and the words.** `transcripts messages`, the README. Test: the same
   suite. Red today: the command is unknown. Real use: the 17 sessions filled through
   `agent-workflow-admin`, the view checked against `materialize` stream by stream, and
   the owner reading a session in the dashboard.

## Checks

`bash plugins/change-record/bin/transcripts-store.test.sh` and the other change-record
suites. The review of each pull request by another model family is the pr-agent job.
Real use: task 2's, on the real store. Error path: a push while the store refuses the new
table (before the owner has run the SQL: the hook must not fail the session, and the
chunk must not be lost). The independent reviewer should attack: a row that holds text
the chunk does not, or text not redacted; a way for the publishable key to read; a push
that marks a part sent with its rows not stored; and the view showing a copy `materialize`
would not rebuild.

## Appendix A: the table and the view, as probed

```sql
create table if not exists public.messages (
  session_id text    not null check (session_id ~ '^[A-Za-z0-9._-]{1,100}$'),
  stream     text    not null check (length(stream) between 1 and 300),
  chunk_id   text    not null check (chunk_id ~ '^[0-9a-f]{64}$'),  -- the chunk the row was read from
  line       integer not null check (line >= 1),                    -- the line's number in that chunk
  block      integer not null check (block >= 0),                   -- the block's place in the line
  shape      integer not null check (shape >= 1),                   -- the version of the rule that read it
  at         timestamptz,                                           -- the line's own timestamp
  who        text    not null check (who in ('user', 'assistant', 'tool', 'context')),
  kind       text    not null check (kind in ('text', 'call', 'result')),
  tool       text    check (length(tool) <= 200),                   -- the tool called, on a call
  call_id    text    check (length(call_id) <= 200),                -- ties a result to its call
  failed     boolean not null default false,                        -- a result the tool marked an error
  side       boolean not null default false,                        -- a subagent's line kept inline
  text       text    not null check (length(text) <= 8000000),      -- redacted, as the chunk holds it
  created_at timestamptz not null default now(),
  primary key (session_id, stream, chunk_id, shape, line, block)
);

alter table public.messages enable row level security;
revoke all on public.messages from anon, authenticated;
grant insert on public.messages to anon;
grant all on public.messages to service_role;
drop policy if exists messages_insert on public.messages;
create policy messages_insert on public.messages for insert to anon with check (true);

create or replace view public.transcript with (security_invoker = true) as
with recursive best as (
  select distinct on (s.session_id) s.session_id, s.entry
  from public.sessions s
  order by s.session_id,
           coalesce((s.entry->>'redaction_version')::int, 0) desc,
           coalesce(s.entry->>'last_timestamp', '') desc,
           (select coalesce(sum((x.value->>'bytes')::bigint), 0)
              from jsonb_each(coalesce(s.entry->'sent'->'streams', '{}'::jsonb)) x) desc,
           s.version desc
), chain as (
  select b.session_id, x.key as stream, c.chunk_id, c.start_id, c.number
  from best b
  cross join lateral jsonb_each(coalesce(b.entry->'sent'->'streams', '{}'::jsonb)) x
  join public.chunks c on c.session_id = b.session_id and c.stream = x.key
                      and c.chunk_id = x.value->>'tip'
  union all
  select c.session_id, c.stream, c.chunk_id, c.start_id, c.number
  from chain h
  join public.chunks c on c.session_id = h.session_id and c.stream = h.stream
                      and c.chunk_id = h.start_id
)
select m.session_id, m.stream,
       row_number() over (partition by m.session_id, m.stream
                          order by h.number, m.line, m.block) as n,
       m.at, m.who, m.kind, m.tool, m.failed, m.side, m.text, m.call_id
from chain h
join public.messages m on m.session_id = h.session_id and m.stream = h.stream
                      and m.chunk_id = h.chunk_id
where m.shape = (select max(m2.shape) from public.messages m2
                 where m2.session_id = m.session_id and m2.stream = m.stream
                   and m2.chunk_id = m.chunk_id);

revoke all on public.transcript from anon, authenticated;
grant select on public.transcript to service_role;
```

This is the text the probe ran, extracted from this record into a file.
