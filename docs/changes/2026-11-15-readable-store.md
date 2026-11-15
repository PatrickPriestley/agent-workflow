---
id: 2026-11-15-readable-store
tier: 2
status: approved
requester: Patrick Priestley, in chat on 2026-11-15 ("Is there a way for me to view these in supabase"; "I just want to see every session"; "Can I see transcriptions in supabase yet"; "Go ahead as recommended"; and on the six concerns the plan and its review raised, "As recommended")
approvers: [Patrick Priestley, 2026-11-15]
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
  revokes from `public, anon, authenticated`, and allows a session id that begins with a
  dot.
- Exact source (`bin/transcripts`, `archive_session` and `push_session`): a stream whose
  file has no finished line yet is recorded with no part, and is sent with its chain's
  root for a tip and no chunk. A part of the archive is redacted line by line and cut
  into chunks; a chunk is closed before the line that would take it past 2,000,000
  redacted bytes, so a single longer line is a chunk of its own, of any size. Each chunk
  is one insert, keyed by a hash chain over the redacted bytes; a duplicate is answered
  409 (23505) and counted as already stored. An insert that raises leaves the part
  unmarked and the session's index row unsent. `REDACTION` is 2; a change of it sends
  every stream again as a new chain.
- Exact source (`bin/transcripts`, `request`, `its_own` and `cmd_push`): a request's body
  is JSON with every non-ASCII character escaped, so such a character is 6 or 12 bytes of
  it. A refusal from 400 to 499 other than 401, 403, 408 and 429 is taken as one
  session's own and the push goes on to the next session; any other stops the push.
- Exact source (`hooks/hooks.json`, `bin/transcripts`): the hook has 10 seconds and only
  starts a push in the background; that push has 60 (`PUSH_LIMIT`) and writes what it
  says to `push.log` in the archive.
- Exact source (`bin/transcripts`, `cmd_materialize`): for each session it takes the index
  row that ranks first by redaction version, last timestamp, bytes sent and version, the
  first by `row_id` on a tie, and for each stream walks the chain back from that row's
  `tip` to the stream's root; a tip that is the root gives an empty file. It refuses a
  session whose id is not a plain name or begins with a dot, a stream whose name is no
  transcript's (`STREAM`), a chunk that is missing, and one whose bytes do not match its
  id. The ranking is outside the part that fails one session: an index row whose
  redaction version is a text, or whose streams are a list, raises and ends the whole
  run for every session.
- Exact source (`grade/labels.py`, `events`; `grade/measures.py`; `bin/transcripts`): a
  transcript line is read by the Claude Code fields `type`, `isMeta`, `isCompactSummary`,
  `isSidechain` and `message.content`. `push` sends what `archive` kept, and `archive`
  keeps Claude Code transcripts only: for Codex and Cursor the tool has `probe` alone
  (record `2026-11-11-codex-cursor-capture`).
- Exact source (`store/stand-in.py`): the stand-in keeps rows in lists by key. It checks
  no type, no `not null` and no check constraint, and takes one row a request.
- Verified against the real system (the store, read with the read key through the
  environment `agent-workflow-admin`, 2026-11-15): 173 index rows of 17 sessions, 271
  chunks under redaction versions 1 and 2, from four senders; the largest chunk is
  1,999,898 bytes; the chunks' `data` is 19,518,000 bytes in all. `materialize` rebuilt
  the 17 sessions in 15 seconds: 46.6 MB of redacted transcript lines in 37 streams.
- Verified against the real system (record `2026-11-09-skill-transcripts`, Probed facts):
  an insert into a table that is not there is answered 404 `PGRST205`; one row is sent in
  a request, and a body of 4 MB was accepted. No request with several rows has been sent
  to the store.
- Mock only (PostgreSQL 16.15 in this container, the real rows above copied in, the roles
  `anon`, `authenticated` and `service_role` made by hand, `schema.sql` run first; this is
  not the store's own interface): the SQL of Appendix A runs with no error, and a second
  time with none. The rows read from all 271 chunks are 6,199, holding 13.5 MB of text;
  as request bodies they are 16,113,157 bytes, the largest row 114,388. The longest text
  is 112,819 characters. The table takes 10 MB on disk beside 20 MB for `chunks`.
- Mock only (the same): the view returns 5,959 rows for the 17 sessions. For 35 of the 37
  streams its rows are, in order, exactly the rows read from the file `materialize`
  rebuilt. In the other two, 8 rows differ, and each holds the character U+0000 in a
  tool's result, which the probe had to take out to load them: PostgreSQL refuses a text
  holding it (`unsupported Unicode escape sequence`).
- Mock only (the same, `set role`): `anon` inserts a row; the same row again is
  `duplicate key value violates unique constraint`; `anon` cannot select, update or
  delete the table and cannot select the view; `authenticated` can do nothing;
  `service_role` reads the view. After the last statement of Appendix A the view has
  `security_invoker=true`, and still refuses `anon` and answers `service_role`.
- Mock only (the same, each in a transaction rolled back): the view shows no row of a
  session, and every row of the 16 others, when a chunk of its chain is deleted, when its
  best row names a stream `../x`, and when two planted chunks name each other as their
  start (that query took 16 ms). It shows no row of a copy of a session under the id `.x`.
  It shows a session's 278 rows as before when its best row gains a stream with no chunk,
  whose tip is its root; all 17 sessions as before beside an index row whose redaction
  version is a text and whose streams are a list; the same rows in the same order when a
  chain's chunk numbers are reversed; and a session's own rows when others are planted
  under `shape` 999.
- Mock only (the same): the view answers a count over every row in 77 to 83 ms.
- Mock only (the same, option B2 below): with every chunk's lines as plain text in a
  table (27 MB), a query that splits them and reads each line as JSON fails on the first
  line that holds `\u0000`; with those lines left out, counting the user and assistant
  lines takes 869 ms, before any block is read.
- Assumed (Supabase, "Postgres Extensions Overview", read 2026-11-15): the page names no
  extension that unzips. Not checked against the project's own list.
- Assumed, not probed: a request with several rows is one statement, so it stores all of
  them or none, and a duplicate among them is answered 409 with none stored; the store's
  interface answers a text holding U+0000, or a lone surrogate, with an error; a body of
  3,100,000 bytes of rows is accepted; the dashboard reads as a role that may read the
  view, and its table editor lists a view beside the tables; the project runs PostgreSQL
  15 or later. Task 1 sends the first three for real, and has the owner open the view,
  before anything is built on them; Appendix A runs on an older PostgreSQL too.

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
  Check: a new suite, `store/schema.test.sh`. It starts a PostgreSQL of its own in a
  temporary folder, makes the three roles (`service_role` with `bypassrls`), runs
  `schema.sql` twice and asserts, by role, each line of the sentence above. Where no
  PostgreSQL is installed it prints that it did not run and exits 0, unless
  `SCHEMA_TEST_REQUIRED=1`, which the Linux CI job sets after installing one: then it
  exits 1.
- R2. The view shows, for each session `materialize` writes, each stream's rows in the
  order of the chain, numbered from 1; a stream with no chunk has none and hides nothing.
  It shows no row of a session `materialize` refuses for a reason SQL can see: an id that
  begins with a dot, a stream name that is no transcript's, a chain that does not reach
  its root, a chain that comes back on itself. It reads the rows of the one `shape` its
  own text names, which is the tool's. An index row it cannot read (a version that is no
  number, streams that are no object) counts as version 0 with no stream and stops
  nothing; this is by this record and is not what `materialize` does today (Decisions).
  Check: the same suite, on made-up rows, one assertion for each clause: two index rows
  that tie are settled as `materialize` settles them; a stream with no chunk; an id
  `.x`; a stream `../x`; a chunk missing; two chunks that name each other, answered in
  under a second; a malformed index row; chunk numbers out of order; rows of another
  shape; and the number after `m.shape =` in `schema.sql` is the tool's `SHAPE`.
- R3. `store/probe` gains the checks of the new table with the hooks' key, on the real
  store: a request of two rows is stored; the same request again is 409; a request of one
  new row and one stored row is 409 and the new row, read back, is not there; select,
  update and delete are refused, on the table and on the view; a request whose body is
  at least 3,100,000 bytes (one row whose text is 1,550,000 double quotes) is stored; a
  text holding U+0000 and one holding a lone surrogate are each refused. The read-back
  needs the read key: without one the probe says that check was not made and exits 1.
  Check: in the store suite the probe passes against the stand-in, which is given the
  same answers; and the gate is its exit status on the real store, run where both keys
  are (the owner's machine) after the owner has run `schema.sql`, with the owner also
  opening `transcript` in the dashboard's table editor. Its output goes in Outcome.
  Nothing of tasks 2 and 3 is merged before it passes.
- R4. The rows of a chunk are read from its redacted lines, after redaction and never
  before, by one function that both senders of rows use. `line` is the line's number in
  the chunk, from 1, counting every line. For each line that is a JSON object whose
  `type` is `user` or `assistant`, and each block of its `message.content` (a content
  that is a string is one text block, block 0; `block` is the block's index in the list):
  - a `text` block whose text is a string and not blank: `kind` `text`; `who` is
    `assistant` on an assistant line, else `context` when the line's `isMeta` or
    `isCompactSummary` is true, else `user`;
  - a `tool_use` block of an assistant line: `kind` `call`, `who` `assistant`, `tool` the
    block's `name`, `call_id` its `id`, `text` its `input` as JSON with keys sorted,
    non-ASCII characters as they are, and Python's default separators;
  - a `tool_result` block of a user line: `kind` `result`, `who` `tool`, `call_id` the
    block's `tool_use_id`, `failed` true only when its `is_error` is true, `text` its
    `content`: a string as it is; a list as its text blocks joined by a newline, each
    other block as its type in square brackets; nothing as an empty text; anything else
    as JSON.
  Any other line or block gives no row (thinking and images among them, C5). `side` is
  true only when the line's `isSidechain` is true. `at` is the line's `timestamp` when it
  is a string of the form `2026-11-15T10:00:00Z`, with or without a fraction and with `Z`
  or an offset, else null. `tool` and `call_id` are the value when it is a string, else
  null, cut to 200 characters. In `text`, `tool` and `call_id`, U+0000 becomes U+2400 and
  a lone surrogate becomes U+FFFD. A text whose form in a request's body would be over
  3,000,000 bytes is cut to the longest beginning that is not, and ends with a line
  saying how many characters were left in the chunk (C8). `shape` is `SHAPE`, a constant
  beside the function, 1. Check: `bin/transcripts-store.test.sh`: a made-up transcript
  with a line for each clause above gives the rows kept beside it in a fixture named for
  the shape, compared whole; an address in a text is stored redacted. And
  `store/schema.test.sh` inserts that fixture's rows through the real table, so its types
  and checks take what the function writes.
- R5. `transcripts messages [--session ID]...` fills the table from what the store holds.
  With the read key it reads every chunk (of the named sessions, or all), leaves out and
  names one whose bytes do not match its id, reads its rows as R4 says, reads the keys of
  the rows the table has for that chunk and `SHAPE`, and inserts the rows that are
  missing. A chunk's rows are cut into requests by one rule that `push` shares: in order,
  each request's body at most 1,000,000 bytes, a row that is more alone; so the requests
  of a chunk are the same whoever sends them. A request none of whose rows is there is
  sent whole; one some of whose rows are there has its missing rows sent one at a time,
  so that the command never leaves a request half there by its own doing. It prints the
  chunks read, the rows inserted, the chunks that needed none, and
  each chunk it could not fill with the store's answer, and exits 1 if there is one or a
  chunk was left out. After a change of `SHAPE` the same command writes the new shape's
  rows for every chunk. Check: the store suite against the stand-in: a store with chunks
  and no rows is filled; a second run inserts nothing; a chunk whose lines give no row is
  counted as needing none both times; a chunk with one row already there gets the
  others, one at a time; a tampered chunk is named and left out; without the read key it
  refuses; and the requests it sends for a chunk are, body for body, the ones `push`
  sends for it.
- R6. `transcripts messages --check` changes nothing: for each chunk as in R5 it compares
  the rows the table holds with the rows the chunk gives and prints each row that is
  missing, each that is there and should not be, and each whose text or fields differ,
  and exits 1 if there is one. Check: the same suite: a filled store is clean; a row
  planted before the fill, a row planted under the same key with another text, and a row
  left out are each reported.
- R7. `transcripts push` sends a chunk's rows after the chunk, in the requests of R5,
  each request whether or not the store already had the chunk. Rows never hold back a
  chunk, a part or the index row. When a request of rows is refused, whatever the
  answer, or gets no answer, the push goes on to the next chunk, and the request is kept
  in the session's sent state as owed: its part, its chunk's place in the part, and its
  own place among the chunk's requests. A session that owes a request counts as unsent,
  and each later push sends its owed requests again, cut from the part as they first
  were, and strikes each off when it is stored. A request is all or none (R3) and both
  senders write whole requests, so a 409 means the request is there, unless another hand
  wrote some of its rows (C9, or the command filling single rows). The push cannot read,
  so it goes by what it knows it has not stored: a 409 on a request of a chunk it has
  just stored, or on an owed request, is followed by that request's rows one at a time,
  each 409 counted as stored, and an owed request is struck off only when every row was
  stored or 409. A 409 on a request of a part that is being sent again after a stopped
  push is taken as there: the push may have stored it itself, and what another hand left
  missing in it is for `transcripts messages`, which can read. The push's last line says
  how many requests are owed; its exit status is what it would have been. The push's own
  time limit ends it as today, wherever it falls; the part it was in is sent again, rows
  and all. Check: the store suite: after a push the rows are there and `--check` is
  clean; a second push sends nothing; with one row of a new chunk's request planted
  before the push, the push sends that request's rows one at a time and the others are
  there; with the stand-in answering 404 to `messages` (the SQL not yet run) the chunks
  and the index row are stored, `materialize` rebuilds the session, the exit status is
  0, the last line names the requests owed, and a push after the stand-in takes rows
  stores them and `--check` is clean; the same with 503 on the second of a chunk's two
  requests, where only that one is owed and sent again; with one row of an owed request
  stored by another hand before the retry, the retry sends the request's rows one at a
  time, strikes it off, and `--check` is clean; and with a part sent again after a
  stopped push, one row of one request planted and the rest of that request missing,
  the push takes the 409, `--check` names the missing rows and `transcripts messages`
  fills them.
- R8. `plugins/change-record/README.md` says how to read one session and how to search
  every session in the dashboard, with the SQL for each, what the table leaves out, that
  rows can be missing until `transcripts messages` or the owing machine's next push, and
  that the chunks are what the graders read. Check: task 2 adds to `store/schema.test.sh`
  an assertion that takes the two queries out of the README and runs them on the suite's
  made-up rows: each returns the rows the test expects.

## Options and concerns

Options considered:

- A. A view that unzips the chunks. Not possible: PostgreSQL has no such function and the
  extensions page names none.
- B. Keep the chunks as plain text instead of gzip, read in the dashboard as they are.
  Rejected: a chunk is up to 2 MB of JSON lines in one cell.
- B2. Plain-text chunks and a view that splits the lines and blocks in SQL (raised by the
  review: it would need no second kind of row, no fill and no check). Rejected on the
  probe: one line holding `\u0000` fails the whole query, splitting alone takes 869 ms
  where the table answers in 83, the rule that reads a line would live in SQL where only
  the new suite can test it, and the chunks already stored are gzip and cannot be
  changed, so they would need a second table and a fill all the same.
- C. A table of rows read from the chunks, written beside them by `push` and by a command
  that fills gaps. Recommended: each row is a message a person can read, the dashboard
  filters and sorts it, and the chunks stay the one thing the graders trust.
- D. A page outside Supabase that rebuilds and shows sessions. Rejected: it needs the read
  key somewhere new, and the owner asked to read them where they are.
- E. Rows cut to a length. Rejected by the owner's ruling on C1, but for one text over
  3,000,000 bytes (C8).
- F. As C, but rows written only by the command, never by `push` (raised by the review).
  Not recommended, and put to the owner as C7.

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

Raised by the plan and its review, and ruled by the owner on 2026-11-15 after the second
round ("As recommended"), each as recommended:

### C5: thinking and images are left out
A transcript line can hold the model's thinking and images. Recommended and ruled: no row for
either, as the label sheet shows neither. What it costs: the dashboard does not show why
the agent did something where only its thinking said so.

### C6: a push sends more, and the store grows faster
For the chunks stored today the rows' request bodies are 16.1 MB beside 19.5 MB of
chunks, so a push sends about 1.8 times the bytes inside the same 60 seconds; a part
that does not finish is sent again at the next push, as today. Recommended and ruled: accept it,
and time a push of the longest session in task 3's real use, with rows and without. If
that push does not finish in its 60 seconds with rows and does without, rows come out of
`push` (option F) in that same task. The free plan's database is said to hold 500 MB
(not probed); removing old sessions is the owner's to do in the dashboard.

### C7: `push` writes rows as well as the command (raised by the review)
Recommended and ruled: both, with R7's rule that rows never hold anything back and that a part
whose rows were not stored is tried again at every later push. What it costs: more code
in the path a hook starts; and between a failed request and the owing machine's next
push, or a run of `transcripts messages` by someone with the read key, the dashboard
shows that session without those rows and nothing in the dashboard says so. A machine
that never pushes again leaves the gap until the command is run. The other way, rows
from the command only: nothing in the hook's path changes, and no new session can be
read in the dashboard until someone with the read key runs the command.

### C8: one text over 3,000,000 bytes is cut
The largest request the store has been seen to take is 4 MB, and a single transcript line
can be longer than that. Recommended and ruled: a text whose form in a request would be over
3,000,000 bytes is stored cut, with a last line saying so; the chunk still holds all of
it. The largest row in the store today is 114,388 bytes, so this cuts nothing that
exists. It is the one place where C1's "whole" does not hold.

### C9: whoever holds the hooks' key can write what the owner reads
The hooks' key can already insert a made-up session. With this table it can also insert a
row that the chunk does not bear out, before the honest sender does. The honest sender's
request is then answered 409: for a chunk it has just stored, or a request it owes, it
sends the rows one at a time, so only the planted row stands; for a part being sent
again after a stopped push, the request's other rows wait for `transcripts messages`
(R7).
Recommended and ruled: accept it, as for sessions: the key is on the owner's machines only, the
view reads one named shape, so rows under another are not shown, and `transcripts
messages --check` (R6) reports every row the chunks do not bear out. What it costs:
until someone runs the check, a planted row is read as the session's.

### C10: `materialize` stops for every session on one malformed index row
Found by the review, true today and not caused by this change (Probed facts): the hooks'
key, or a fault, can write an index row that ends every `materialize` run. Recommended and ruled:
its own tier 1 change, next after this record's tasks; this record only makes sure the
view does not share the fault.

## Decisions

- The key of a row is the chunk it was read from, the shape, the line in that chunk and
  the block in that line. Rejected: a line's number in the whole stream, which two
  senders or two redaction versions number alike for different text; the chunk's id is a
  hash of its bytes.
- The rule that reads rows has a version, `shape`, 1 at first. The view names the one
  shape it reads, and a test holds that number to the tool's (R2). A change of the rule
  changes the constant, adds a fixture named for the new shape, and changes the view's
  text; the owner runs `schema.sql` again and `transcripts messages` writes the new rows
  for what is stored (R5). Rejected: the view reading the highest shape a chunk has,
  which lets anyone with the hooks' key replace what is shown (found by the review).
  Nothing can stop a change of the rule that also rewrites the old fixture and leaves
  the number; the fixture's name is there so that a reviewer sees it.
- Rows never decide whether a chunk, a part or an index row is sent (R7). Rejected: the
  first draft's "a failure to store the rows is reported as the chunk's failure is", by
  which a table meant for people could have stopped `materialize` from seeing a session,
  for every session until the owner had run the SQL (found by the review).
- A sender remembers which requests of rows it owes and tries them again; the command
  finds what is missing from the store itself. Rejected: the command alone, which leaves a gap until
  someone with the read key acts (found by the review); and the sender's memory alone,
  which another machine's gap, or a planted row, would escape.
- Every request of rows is sent whether or not the chunk was new. The requests of a
  chunk are cut by one rule for `push` and `transcripts messages`, and the command sends
  either a whole request or single rows, so that nothing the tool does leaves a request
  half there. A sender keeps what it owes request by request, and a 409 on a request it
  knows it has not stored (a chunk just stored, or an owed request) is followed by the
  rows one at a time; on a part sent again after a stop it is taken as there. Rejected: sending only the first request
  for a chunk the store had, which loses the second request of a stopped push (found by
  the record's review); rows one at a time after every 409, which is thousands of
  requests each time a stopped part is sent again; and a 409 always taken as there,
  under which a push whose request shared one row with what was there would strike its
  part off with the other rows missing (found by the review of the approval pull
  request).
- Limits are counted in the bytes of a request's body, as `request` writes it: 1,000,000
  for a request of several rows, 3,000,000 for one text. Rejected: characters, of which
  one can be 12 bytes (found by the review); one request a chunk, which a single long
  line makes unbounded; and smaller requests, which are more of them in 60 seconds.
- `tool` and `call_id` are cut to 200 characters. Rejected: refusing the row, which
  loses its text for an id.
- The order of a session's rows is the order of the chain, counted from the tip.
  Rejected: `chunks.number`, which is what a sender says (found by the review).
- The view repeats `materialize`'s choice in SQL, the same ranking with the same
  tie-break and the same walk, and shows nothing of a session `materialize` refuses for a
  reason SQL can see. Two things differ by intent: SQL cannot see a chunk whose bytes do
  not match its id, which R5 and R6 read; and an index row that cannot be read is passed
  over, where `materialize` stops (C10). Rejected: the newest rows by time, which mixes
  two redaction versions of one session.
- A chain that comes back on itself is stopped by remembering the chunks walked.
  Rejected: a limit on the depth alone, which makes every query walk to the limit once
  two such chunks are planted (found by the review).
- The view is revoked from `public`, `anon` and `authenticated` and granted to
  `service_role`, and is made `security_invoker` where the server is PostgreSQL 15 or
  later, by a statement that asks the server's version. Rejected: `security_invoker`
  alone, which fails on an older server; and the revoke alone, which Supabase's advisor
  is said to flag (not probed).
- U+0000 becomes U+2400 and a lone surrogate U+FFFD in a row. Rejected: dropping them,
  which hides that they were there; and leaving the chunk's rows out, which loses a
  chunk's text for one character.
- The rows are read by code in `bin/transcripts`, beside the push. Rejected: the label
  sheet's reader in `grade/labels.py`, which joins a call to its result, so that a row
  would change when the result arrives, and an insert-only table cannot change a row.
- Only Claude Code transcripts give rows. Rejected: rules for Codex and Cursor lines,
  which nothing archives or stores yet.

## Tasks

1. **The table, the view and the gate.** `schema.sql`; `store/schema.test.sh` and the CI
   step that installs PostgreSQL and requires it; the stand-in's `messages` table, with
   the answers the probes gave PostgreSQL; the new checks in `store/probe`. Tests:
   `store/schema.test.sh`, and the probe against the stand-in in
   `bin/transcripts-store.test.sh`. Red today: there is no table, and the probe has no
   such check. Then the owner runs `schema.sql` in the project's SQL editor, opens
   `transcript` in the table editor, and runs the probe on the real store with both
   keys; that output is this task's real use, and tasks 2 and 3 wait for it.
2. **Filling in and checking.** The rows read from a chunk and their fixture,
   `transcripts messages` and `--check`, and the README with its assertion. Test:
   `bin/transcripts-store.test.sh`. Red today: the command is unknown. Real use: the 17
   sessions filled through `agent-workflow-admin`; `--check` clean; for every stream the
   view's rows, read from the real store, are the rows read from the file `materialize`
   rebuilds, in order; and the owner reads a session in the dashboard.
3. **The push.** `transcripts push` sends rows and remembers parts that owe them. Test:
   `bin/transcripts-store.test.sh`. Red today: a push stores no row, says nothing of
   rows, and keeps no request as owed. Real use: a push of a real session from a machine
   with the hooks' key, timed with rows and without (C6), then `--check` clean on it; and
   the error path of Checks.

## Checks

`bash plugins/change-record/store/schema.test.sh`,
`bash plugins/change-record/bin/transcripts-store.test.sh` and the other change-record
suites. The review of each pull request by another model family is the pr-agent job.
Real use: each task's, above. Error path: a push while the store answers 404 for the new
table, as it does before the owner has run the SQL: the session's chunks and index row
are stored, `materialize` rebuilds it, the push says what it owes, and the next push
after the SQL is run stores it. The independent reviewer should attack: a row that holds
text the chunk does not, or text not redacted; a way for the hooks' key to read; a push
that holds anything back for its rows; and the view showing a copy `materialize` would
not rebuild.

## Review

Two rounds, each by a fresh session with no context but the record and the repository
(`plugins/change-record/bin/record-review`), on 2026-11-15. Each finding was checked
against the repository, and each change to the view was run in the probe's PostgreSQL.

Round one: 1 critical, 6 important, 7 minor; all fixed. Critical: a failed insert of rows
would have left the part unmarked and the index row unsent, so a table meant for people
could have stopped `materialize`, for every session until the owner had run the SQL; rows
now never hold anything back (R7). Important: a chunk has no largest size, so requests
are batched; the PostgreSQL facts were labelled as the real system and are now mock only,
with a gate on the real store before anything is built on them (R3); a 409 on several
rows proved nothing and the view read the highest shape, which the hooks' key could
plant: the view reads one named shape, and a check compares rows with chunks (R6, C9);
three checks could not be carried out as written: there is a suite that runs the SQL
(R1); the view differed from `materialize` in four ways: it now walks the chain itself,
breaks ties the same way, hides what `materialize` refuses and survives a malformed row
(R2); and R2's terms were left to guess: R4 names each field and form.

Round two: 1 critical, 9 important, 7 minor; all fixed but one, which was put to the owner.
Critical: a stream with no chunk yet hid its whole session from the view; such a stream
is whole (R2), shown in the probe. Important: the rule for a chunk the store already had
lost the second request of a stopped push: every request is sent (R7); limits were in
characters where a request is bytes (R3, R4, R5, C8); there was no Outcome section; the
stand-in checks no type, so the rows are also put through the real table (R4); the view
did not refuse an id beginning with a dot (R2); nothing held the view's shape to the
tool's (R2); rows a push could not send had no one to send them: the part is remembered
and tried again (R7, C7); the dashboard's own reading of the view was checked last and is
now part of the gate (R3); and an option was not weighed, plain-text chunks split by a
view, which the probe then ran and which is rejected (B2). One finding is true of the
code as it is and is not fixed here: `materialize` ends its whole run on one malformed
index row (C10).

Not fixed, and why: nothing can stop someone changing the rule that reads rows together
with its fixture and leaving `shape` as it was (Decisions).

The review of the approval pull request, by another model family (pr-agent, 2026-11-15):
one finding, right. R7 took every 409 on a request of rows as the request being there,
and the command filled missing rows in requests of its own cutting, so a push could
strike a part off with rows missing. The two senders now cut a chunk's rows by one rule,
the command sends whole requests or single rows, what is owed is kept request by
request, and a 409 on a request the sender knows it has not stored (a chunk just stored,
or an owed request) is followed by the rows one at a time (R5, R7, Decisions). The first
answer left the owed case trusting the 409; the reviewer's second pass held the finding,
rightly. What is left is a part sent again after a stopped push whose request another
hand has half written, which the sender cannot tell from its own earlier request; that
is C9's case and the command's to mend.

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
  text       text    not null check (length(text) <= 3000000),      -- redacted, as the chunk holds it
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
-- name is no transcript's, or whose chain does not reach its root, or a session whose id begins with a dot)
-- is not shown at all. A stream with no chunk yet has its root for a tip, and is whole.
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
         encode(sha256(convert_to(b.session_id || '/' || x.key, 'UTF8')), 'hex') as root,
         x.key ~ '^(?:main|subagents/(?!(?:.*/)?\.\.?(?:/|$))[A-Za-z0-9._/-]+)$' as named
  from best b cross join lateral jsonb_each(b.streams) x
), chain as (
  select t.session_id, t.stream, t.root, c.chunk_id, c.start_id, 1 as depth, array[c.chunk_id] as seen
  from tips t
  join public.chunks c on c.session_id = t.session_id and c.stream = t.stream and c.chunk_id = t.tip
  where t.named
  union all
  select c.session_id, c.stream, h.root, c.chunk_id, c.start_id, h.depth + 1, h.seen || c.chunk_id
  from chain h
  join public.chunks c on c.session_id = h.session_id and c.stream = h.stream and c.chunk_id = h.start_id
  where c.chunk_id <> all (h.seen)          -- a chain that comes back on itself stops, and never reaches its root
), whole as (
  select session_id, stream from chain where start_id = root
  union
  select session_id, stream from tips where named and tip = root
), written as (
  select b.session_id from best b
  where b.session_id !~ '^\.'
    and not exists (select 1 from tips t
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
-- From PostgreSQL 15 a view can read as the one who asks, which is what Supabase's advisor wants of a view.
do $$ begin
  if current_setting('server_version_num')::int >= 150000 then
    execute 'alter view public.transcript set (security_invoker = true)';
  end if;
end $$;
```

## Outcome

Nothing is built yet. This record is the plan.
