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
  version is a text and whose streams are a list; a session's 278 rows beside an index
  row of its own whose version is 999 and whose streams are a list (none, before the
  ranking asked for both to be readable), and beside one whose version is a text and
  whose streams are the session's own, also when the good row has no version; no row of
  a session whose only index row has a text for a version; the same rows in the same
  order when a
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
  own text names, which is the tool's. An index row it cannot read (streams that are no
  object, or a version that is neither a number nor absent, whatever the other says)
  ranks below every row that can be read, has no stream, and stops nothing; this is by
  this record and is not what `materialize` does today (Decisions).
  Check: the same suite, on made-up rows, one assertion for each clause: two index rows
  that tie are settled as `materialize` settles them; a stream with no chunk; an id
  `.x`; a stream `../x`; a chunk missing; two chunks that name each other, answered in
  under a second; an index row that cannot be read in each of three ways (a text for a
  version and a list for streams; a high number and a list; a text and good streams),
  each beside a good row, one of them with no version, which is still the one shown; a
  session whose only row has a text for a version and good streams, which shows
  nothing; chunk numbers out of order; rows of another
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
is C9's case and the command's to mend. Its third pass found one more, right again: an
index row whose streams were a list kept its version in the ranking, so with a high
number it outranked the good row and the session showed nothing. Its fourth pass found
the other half: a row whose version was a text kept its streams. A row that cannot be
read in either way now ranks below every row that can and has no stream (R2, Appendix
A); each case was run in the probe.

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
         case when r.ok then s.entry->'sent'->'streams' else '{}'::jsonb end as streams
  from public.sessions s
  -- a row can be read when its streams are an object and its version is a number or is not there
  cross join lateral (select coalesce(jsonb_typeof(s.entry->'sent'->'streams') = 'object', false)
                             and coalesce(jsonb_typeof(s.entry->'redaction_version'), 'null') in ('number', 'null') as ok) r
  order by s.session_id,
           r.ok desc,
           case when r.ok and jsonb_typeof(s.entry->'redaction_version') = 'number'
                then (s.entry->>'redaction_version')::numeric else 0 end desc,
           coalesce(s.entry->>'last_timestamp', '') collate "C" desc,
           (select coalesce(sum(case when jsonb_typeof(x.value->'bytes') = 'number' then (x.value->>'bytes')::numeric else 0 end), 0)
              from jsonb_each(case when r.ok then s.entry->'sent'->'streams' else '{}'::jsonb end) x) desc,
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
                      and not exists (select 1 from whole w    -- only a stream named as a transcript is ever whole
                                      where w.session_id = t.session_id and w.stream = t.stream))
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

### Task 1: the table, the view and the gate

Built test first, a suite at a time, each committed red before its code:
`store/schema.test.sh`, 34 assertions failing with no table in `schema.sql`; the probe's
new checks in `bin/transcripts-store.test.sh`, 17; the CI step in
`bin/ci-workflow.test.sh`, 4; the probe against a store that is not all or none, 3. Then
`schema.sql` (Appendix A), `SHAPE` in `bin/transcripts`, the checks in `store/probe`, the
stand-in's `messages`, `transcript` and `--loose`, and the two CI steps. Suites after:
store schema 51, transcripts-store 182, ci-workflow 21, transcripts-judge 422,
transcripts-grade 212, transcripts 364, record-check 117, none failing.

The schema suite starts a PostgreSQL of its own. It gives the three roles what Supabase
grants on a new table or view by default, so that the file's revokes are what refuse
`anon`; it stops any statement at 20 seconds, so that a view that never ends fails its
test; and it inserts the made-up rows of `messages` backwards, so that no order of
insertion can pass for the view's.

Guards, each broken by hand in a clone of the repository, with the suite named for it: 38
breaks, 32 caught at the first run. Two of the six that survived were code no input can
reach, and are taken out: in the view, `not named` beside `not whole`, since only a
stream named as a transcript is ever whole (Appendix A is changed to match; the view's
rows are the same); and in the probe, a count of the bytes of a row whose size is the
probe's own constant, which the suite reads from the request instead. The other four were
gaps in the tests: the rank by version, whose two rows did not tie the other way; the
order of lines in a chunk, which the order of insertion gave; a store that takes U+0000,
which no stand-in was; and the first request of rows, which could have held one. Each got
an assertion and was broken again. The 36 guards that stand, by the assertion that failed
first for each:

- Caught first by "R1: each check of the table refuses what it is there for": table:
  anyone as who; table: line 0; table: a block below 0; table: shape 0; table: a chunk id
  that is no hash; table: a tool's name of any length; table: a call id of any length.
- Caught first by "R2: the index row is chosen as materialize chooses it: by redaction
  version, then the later, then the larger, then the higher version": view: the redaction
  version does not rank; view: the last timestamp does not rank; view: the bytes sent do
  not rank; view: the version does not rank (survived the first run).
- Caught first by "R2: a session's rows come in the order of the chain, numbered from 1,
  whatever numbers the sender gave its chunks": view: a chain that comes back on itself is
  walked on; view: the rows come in the order from the tip; the tool's shape and the
  view's differ.
- Caught first by "R1: a row the table's checks refuse: a kind that is none of the three,
  a text with no end to it": table: any kind; table: a text of any length.
- Caught first by "R1: row security is on for the table, and the view is granted to the
  read key alone": table: row security is not turned on; view: what Supabase grants by
  default is not revoked.
- Caught first by "R1: the hooks' key (anon) may insert a row, once": table: the hooks'
  key is not granted insert; table: no policy lets the hooks' key insert.
- Caught first by "R1: and nothing else: no select, update or delete of the table, and no
  select of the view": table: what Supabase grants by default is not revoked.
- Caught first by "R1: the view reads as the one who asks where the server can (PostgreSQL
  15 and later)": view: it does not read as the one who asks.
- Caught first by "R2: a session whose only index row cannot be read shows nothing, and
  stops nothing": view: a row that cannot be read keeps its streams.
- Caught first by "R2: a stream with no chunk has no row and hides nothing": view: a
  stream with no chunk is not whole.
- Caught first by "R2: no row of a session one of whose streams is no transcript's": view:
  every stream name is taken for a transcript's.
- Caught first by "R2: no row of a session whose chain does not reach its root": view: a
  chain need not reach its root.
- Caught first by "R2: no row of a session whose id begins with a dot": view: a session
  whose id begins with a dot is shown.
- Caught first by "R2: rows of another shape are not shown": view: rows of every shape are
  shown.
- Caught first by "R2: the same with a text for a version and streams of its own, beside a
  good row that has no version": view: a row that cannot be read is ranked with the
  others.
- Caught first by "R2: two index rows that tie are settled as materialize settles them:
  the first by row_id": view: a tie goes to the last row_id.
- Caught first by "R2: within a chunk the rows go by line and then by block": view: the
  lines of a chunk come in no order (survived the first run).
- Caught first by "against a store that keeps the new row of a refused request and takes a
  text PostgreSQL would not, the probe fails on each and exits 1": probe: an accepted
  U+0000 passes (survived the first run).
- Caught first by "against a store that keeps the new row of a refused request, the probe
  fails on the read-back and exits 1": probe: what the read key reads is not looked at.
- Caught first by "the rows went as the probe says: the first request holds two, and one
  request is at least 3,100,000 bytes": probe: the several rows are sent one by one
  (survived the first run).
- Caught first by "with both keys every check of the probe passes against the stand-in":
  probe: the big row is small.
- Caught first by "without the read key the probe says the read-back was not made, and
  exits 1": probe: without the read key it exits 0.

The commands themselves, on the final code. The file in PostgreSQL 16.15, on the copy of
the real rows (mock only, as in Probed facts), as the database's owner and then as each
role:

```
$ psql -d store -v ON_ERROR_STOP=1 -q -f plugins/change-record/store/schema.sql
NOTICE:  relation "messages" already exists, skipping      (and one for each older table)
schema.sql: exit 0
$ psql -d store -c "select count(*) as rows, count(distinct session_id) as sessions,
    count(distinct (session_id, stream)) as streams from transcript"
 rows | sessions | streams
 5959 |       17 |      37
$ psql -d store -c "set role anon; select count(*) from transcript"
ERROR:  permission denied for view transcript
$ psql -d store -c "set role service_role; select who, kind, count(*) from transcript group by 1, 2 order by 1, 2"
 assistant | call   |  2448
 assistant | text   |   666
 context   | text   |    57
 tool      | result |  2443
 user      | text   |   345
$ psql -d store -Atc "select session_id, stream, n, who, kind, md5(text) from transcript
    order by session_id, stream, n" | cmp - view-final.txt && echo same
same
```

`view-final.txt` is the plan's probe: the same 5,959 rows in the same order. The probe
against the stand-in (mock only), its new checks and its end, and then the error path,
against a store that is not what the plan needs (`stand-in.py --loose messages`), with
both keys and with the hooks' key alone:

```
$ AGENT_TRANSCRIPTS_URL=http://127.0.0.1:<port> plugins/change-record/store/probe
ok   two rows in one request: stored: HTTP 201
ok   the same request again: refused as a duplicate: HTTP 409
ok   one new row and one stored row: refused as a duplicate: HTTP 409
ok   select messages: refused: HTTP 401
ok   update a message: refused: HTTP 401
ok   delete a message: refused: HTTP 401
ok   select the transcript view: refused: HTTP 401
ok   one row in a request of at least 3,100,000 bytes: stored: HTTP 201
ok   a text holding U+0000: refused: HTTP 400
ok   a text holding a lone surrogate: refused: HTTP 400
ok   read key: the probe chunk still holds its first bytes: HTTP 200
ok   read key: the new row of the refused request is not there: HTTP 200
probe session probe-<id>: 26 passed, 0 failed
exit 0
$ plugins/change-record/store/probe                        (the loose store, both keys)
FAIL a text holding U+0000: refused: HTTP 201
FAIL a text holding a lone surrogate: refused: HTTP 201
FAIL read key: the new row of the refused request is not there: HTTP 200 but [{"line": 3}]
probe session probe-<id>: 23 passed, 3 failed
exit 1
$ plugins/change-record/store/probe                        (the loose store, no read key)
FAIL a text holding U+0000: refused: HTTP 201
FAIL a text holding a lone surrogate: refused: HTTP 201
note: no read key here, so the probe chunk was not read back
the check that a request of several rows stores all or none was not made: no read key here
probe session probe-<id>: 22 passed, 2 failed
exit 1
```

Not done, and it is this task's real use: the gate of R3. The owner runs `schema.sql` in
the project's SQL editor, opens `transcript` in the table editor, and runs `store/probe`
where both keys are; the probe's output goes here, and tasks 2 and 3 are not merged
before it passes. Nothing here has been sent to the real store, and until the probe has
passed there this task is a prototype: what the real store answers to a request of
several rows, to one of 3,100,000 bytes, and to the hooks' key on the new table and view
is known from a PostgreSQL and a stand-in only. It cannot be run from the cloud session:
the table is not in the project until the owner has run the file, and every request from
the session carries the read key, so the checks of what the hooks' key may not do cannot
be made from it. The CI step is verified by this pull request's own run: on the Linux
runner the suite ran with `SCHEMA_TEST_REQUIRED=1` in PostgreSQL 18.6, 51 passed, none
failed; so the file is run in two versions, 16.15 here and 18.6 there. Not verified: the
suite on a Mac, where it runs only if a PostgreSQL is installed.

The review of this task's pull request, by another model family (pr-agent, 2026-11-16,
on the first push): three findings. No line naming the reviewer, since the review is the
pull request's own job: added with what it found. No commands with their output, only
counts: right of the record, which had none, and they are above. And the one it calls
blocking: the requests to the real store are not verified against it, and the probe
should pass there before this is merged, not after. The fact is as it says, and it is
what R3 says; the order is the owner's to rule, since only the owner can run either
step. The file can be run from this branch as well as from main, and it is the better
order: a probe that fails is then mended here, before anything is merged.

Changed after approval, each from a review and each run in the probe's PostgreSQL: an
index row that cannot be read ranks last and has no stream (the review of the approval
pull request, pushed after its merge); and the unreachable clause above.

#### The gate: the probe on the real store, 2026-11-16

The owner merged task 1, ran `schema.sql` in the project's SQL editor, and ran the probe
on a laptop that holds the hooks' key and not the read key. Verified against the real
system; each answer is cut here after its code:

```
$ AGENT_TRANSCRIPTS_URL=https://<project>.supabase.co plugins/change-record/store/probe
ok   insert a chunk: HTTP 201
ok   insert an index row: HTTP 201
ok   a duplicate chunk, other bytes: refused as a duplicate: HTTP 409 {"code":"23505"
ok   a duplicate index row: refused as a duplicate: HTTP 409 {"code":"23505"
ok   ignore-duplicates: refused, since ON CONFLICT needs SELECT: HTTP 401 {"code":"42501"
ok   select chunks: refused: HTTP 401 {"code":"42501"
ok   select sessions: refused: HTTP 401 {"code":"42501"
ok   insert with return=representation: refused: HTTP 401 {"code":"42501"
ok   update a chunk: refused: HTTP 401 {"code":"42501"
ok   delete a chunk: refused: HTTP 401 {"code":"42501"
ok   update an index row: refused: HTTP 401 {"code":"42501"
ok   delete an index row: refused: HTTP 401 {"code":"42501"
ok   insert a score: refused: HTTP 401 {"code":"42501"
ok   select scores: refused: HTTP 401 {"code":"42501"
ok   two rows in one request: stored: HTTP 201
ok   the same request again: refused as a duplicate: HTTP 409 {"code":"23505" [...] "messages_pkey\""}
ok   one new row and one stored row: refused as a duplicate: HTTP 409 {"code":"23505" [...] "messages_pkey\""}
ok   select messages: refused: HTTP 401 {"code":"42501"
ok   update a message: refused: HTTP 401 {"code":"42501"
ok   delete a message: refused: HTTP 401 {"code":"42501"
ok   select the transcript view: refused: HTTP 401 {"code":"42501" [...] "permission denied for view transcript"}
ok   one row in a request of at least 3,100,000 bytes: stored: HTTP 201
ok   a text holding U+0000: refused: HTTP 400 {"code":"22P05","details":"\\u0000 cannot be converted to text." [...]
ok   a text holding a lone surrogate: refused: HTTP 400 {"code":"PGRST102","details":null,"hint":null,"message":"Empty or invalid json"}
note: no read key here, so the probe chunk was not read back
the check that a request of several rows stores all or none was not made: no read key here
probe session probe-13cf8033e629eddb: 24 passed, 0 failed
```

Its last two checks need the read key, which that laptop does not hold, so the probe's
exit status there was 1. They were made for that probe session from the cloud session,
whose every request carries the read key, by the probe's own two requests:

```
GET /rest/v1/chunks?session_id=eq.probe-13cf8033e629eddb&select=data
[{"data":"first"}] HTTP 200          the duplicate with other bytes changed nothing
GET /rest/v1/messages?session_id=eq.probe-13cf8033e629eddb&line=eq.3&select=line
[] HTTP 200                          the new row of the refused request is not there
GET /rest/v1/messages?session_id=eq.probe-13cf8033e629eddb&select=line&order=line
lines 1, 2 and 4, and line 4's text is its 1,550,000 double quotes
GET /rest/v1/transcript?session_id=eq.probe-13cf8033e629eddb&select=n
[] HTTP 200                          the view shows nothing of the probe
```

So every check of the probe has passed on the real store, in two parts on two machines
and not in one run where both keys are, which is what R3's words ask; the reviewer may
hold that against it. What Probed facts had as assumed is now verified against the real
system: a request of several rows stores all of them or none, and a duplicate among
them is 409 with none stored; a body of 3,100,000 bytes of rows is accepted; a text
holding U+0000 is refused, 400 with PostgreSQL's 22P05; the hooks' key reads neither the
table nor the view. One answer was not what the stand-in gave: half of a surrogate pair
is refused by the interface before PostgreSQL sees it, 400 with `PGRST102`, "Empty or
invalid json"; the stand-in now answers the same. And before the owner ran the file the
store answered a request for `messages` 404 with `PGRST205`, as the stand-in's
`--without` does. Not yet confirmed here: that the owner has opened `transcript` in the
dashboard's table editor.

### Task 2: filling in and checking

Built test first, each step committed red before its code: the fixture, the rule, the
command and its check in `bin/transcripts-store.test.sh`, 73 assertions failing with no
such command; then `message_rows`, `row_requests` and `cmd_messages` in `bin/transcripts`;
the README's two queries in `store/schema.test.sh`, 3 failing with no query in the README;
and a store with no such table yet, 3 failing, then the message for it. Two expectations
of the first tests were wrong and were corrected with the code, each said in its commit:
the order of two rows in a sorted list, and the number of rows in a chunk's request.
Suites after: transcripts-store 330, store schema 58, transcripts 364, transcripts-grade
212, transcripts-judge 422, ci-workflow 21, none failing.

The fixture is `store/fixtures/shape-1.jsonl`, 21 made-up lines with one for each clause
of R4, and `shape-1.rows.jsonl`, its 16 rows, written by hand from R4 before the function
was; the function gave them at its first run. `store/schema.test.sh` puts those rows into
the real table as the store's interface does (`json_populate_recordset`), reads them back
as the interface gives rows, and has the tool's own comparison find each the same: the
time `2026-11-15T10:00:00.250Z` comes back as `2026-11-15T10:00:00.25+00:00`, and one
with nine digits of fraction comes back rounded to six.

Where R4 to R6 left a choice, what was built:

- A row's own fields are read by `message_rows`; the session, stream and chunk are put
  before them by the command. A request is always a list, of one row too.
- A chunk's lines are cut at each newline and at nothing else, as its `lines` are counted.
- A result's content that is neither a string, a list nor absent is JSON with its keys
  sorted, as a call's input is. In a list, a block with no type is left out.
- A time is kept only when it is a real date and its offset is at most 15:59; else null.
- A cut text ends with the line `[cut here: N more characters of this text are in the
  chunk]`, and the limit of 3,000,000 bytes counts that line.
- The command inserts with the read key. It first asks for the table, and where the
  store has none it says to run `schema.sql` and exits 1 with nothing sent.
- A request refused whole because another hand wrote one of its rows meanwhile has its
  rows sent one at a time, a duplicate counted as there.
- A chunk whose insert gets no answer is named as one that could not be filled, and the
  others are still tried.
- The check compares a time as the moment it names, to the microsecond the table keeps.

Not built in this task: R5's last check, that the command's requests are body for body
the ones `push` sends. `push` sends none until task 3, which adds it; here the cutting
rule is tested by itself. The stand-in gained three things for these tests:
`/__admin/forget`, `/__admin/after-read` and `--without TABLE`.

Guards, each broken by hand in a clone of the repository: 92 breaks, 88 caught at the
first run. Of the four that survived, three were gaps in the tests, each closed and
broken again: the fraction of a second, the microsecond the check allows, and a chunk
left out that was read as an empty one. The fourth was a guard that did less than it
cost and is taken out: it ended the whole fill when one insert got no answer, and a
store that cannot be reached still ends the run at the next reading. The 91 guards that
stand, by the assertion that failed first for each:

- Caught first by "the fixture named for the tool's shape gives its rows, compared whole":
  rows: U+0000 is left as it is; rows: an offset of any size is kept; rows: a result's
  list is given as JSON; rows: a result's object keeps its keys' order; rows: a line of
  any type gives rows; rows: a time is kept whatever it is; rows: any truthy isSidechain
  makes a side line; rows: a text that is no string is read; rows: isCompactSummary makes
  no context; rows: a result on an assistant line gives a row; rows: no result is a
  failure; rows: half of a surrogate pair is left as it is; rows: a time that is no string
  is read; rows: a text block of a result whose text is no string is taken for text; rows:
  a result's object has its non-ASCII escaped; rows: a line that is no object is read;
  rows: a name or an id that is no string is kept; rows: no line is a side line; rows: a
  blank text gives a row; rows: any truthy isMeta makes context; rows: a call's input
  keeps its keys' order; rows: the lines are counted from 0; rows: a time of any form is
  kept; rows: an offset of 16 hours is kept; rows: a block of a result with no type is
  read; rows: a line that is no JSON stops the reading; rows: a message that is no object
  is read; rows: a name of any length is kept; rows: a content that is no list is read;
  rows: an assistant's text is the user's; rows: any truthy isCompactSummary makes
  context; rows: a call's input has its non-ASCII escaped; rows: a date that is none is
  kept; rows: a result with no content reads null; rows: a block of a result that is no
  object is read; rows: a content that is a string gives no row; rows: a name's U+0000 is
  kept; rows: a block that is no object is read; rows: isMeta makes no context; rows: a
  call on a user line gives a row; rows: any truthy is_error is a failure.
- Caught first by "a chunk whose bytes do not match its id is named and left out, the
  others are filled, and the exit status is 1": command: a chunk left out is filled all
  the same (survived the first run); command: the fill exits 0 with a chunk left out;
  command: a chunk is not checked against its id; command: a chunk that cannot be opened
  stops it.
- Caught first by "a row planted before the fill under a key the chunk does not give, and
  one planted under a key it does with another text, are each reported": command: the
  check reports no row that is not the chunk's; command: the check reports no row that
  differs; command: the check exits 0 with a row to report; command: the check does not
  compare the text.
- Caught first by "R5: two rows whose request is exactly 1,000,000 bytes go together, one
  byte more and they part, and a first row that is over gives no empty request": requests:
  the comma between rows is not counted; requests: a first row that is over leaves an
  empty request; requests: cut at exactly the limit.
- Caught first by "a row whose chunk the store does not hold is reported too, by its chunk
  and with how many, whatever its shape": check: a row with no chunk behind it is not
  reported; check: the fill reports rows with no chunk too; check: rows with no chunk do
  not count against a clean check.
- Caught first by "a text whose form in a request would be over 3,000,000 bytes is cut to
  the longest beginning that is not, and its last line says how many characters are left
  in the chunk": rows: no text is ever cut; rows: the cut is not the longest; rows: the
  cut is counted in characters.
- Caught first by "only the probe's own chunk is passed over: another chunk in a session
  named like the probe's is read, and left out if it is not what its id says": command: a
  chunk like the probe's is passed over in any session; command: any sender's chunk is
  passed over in a probe's session; command: a chunk that starts anywhere is passed over
  in a probe's session.
- Caught first by "R6: two times are one moment whatever the offset or the fraction they
  are written with, and an hour apart they are not": rows: an offset is added the wrong
  way; check: two times an hour apart are one.
- Caught first by "a chunk the store will not take rows for is named with the store's
  answer, and the exit status is 1": command: a chunk that could not be filled is not
  counted; command: the fill exits 0 with a chunk it could not fill.
- Caught first by "a second run inserts nothing: every chunk needs none, the one whose
  lines give no row among them both times": command: a request with a row there is sent
  whole; command: rows that are there are sent again.
- Caught first by "the limit is in the bytes of the request and not in characters: 600,000
  characters of 6 bytes each are cut, and 2,999,998 of one byte are not": rows: a text of
  exactly the limit is cut; rows: the cut text may be one byte over.
- Caught first by "the rows store/probe leaves behind are passed over and said: its chunk
  is no transcript's, and it fails neither the fill nor the check": command: the probe's
  chunk is read like any other; check: no chunk is known to be held.
- Caught first by "R4, R6: read back as the interface gives rows, each is the row that
  went in by the tool's own comparison, the time of a line among them": check: a time is
  compared as it is written.
- Caught first by "R4: a line nested deeper than the reader goes gives no row and stops
  nothing: the next line's row is there": rows: a line nested too deep stops the reading.
- Caught first by "R4: a time is kept only when it names a moment: the form, a real date,
  and an offset a clock can have": rows: an offset of 60 minutes is kept.
- Caught first by "R5: a chunk's rows are cut into requests in order, each body at most
  1,000,000 bytes, and a row that is more goes alone": requests: never cut.
- Caught first by "R6: a microsecond apart is still one moment, since the table rounds a
  longer fraction its own way, and two apart is not": check: a time rounded by the table
  differs (survived the first run).
- Caught first by "R6: two times are one moment whatever the offset or the fraction they
  are written with; an hour apart, or half a second, they are not": rows: the fraction of
  a second is dropped (survived the first run).
- Caught first by "a chunk whose bytes do not match its id is named by the check too, and
  the exit status is 1": command: the check exits 0 with a chunk left out.
- Caught first by "a filled store is clean, and the check sends nothing but reads":
  command: the check fills.
- Caught first by "a row left out is reported as missing, the check does not put it there,
  and the command then does, alone": command: the check reports no missing row.
- Caught first by "a row under another shape does not count as there": command: rows of
  every shape count as there.
- Caught first by "a store with chunks and no rows is filled: it says the chunks read, the
  rows inserted and the chunks that needed none": command: a chunk that got rows is
  counted as needing none.
- Caught first by "an unknown argument is a usage error, and nothing is asked of the
  store": command: an unknown argument is taken.
- Caught first by "and the same moment written another way is no difference": command: the
  check compares the text alone.
- Caught first by "each chunk's rows went in one request, a list, and a chunk with no row
  sent none": command: every row goes alone.
- Caught first by "the rows are each line's texts, calls and results, in the chunk they
  were read from, under the tool's shape": command: a row with no text of the session is
  keyed to another chunk.
- Caught first by "where the store has no such table yet it says to run schema.sql, sends
  nothing, and exits 1": command: a store with no table is not said.
- Caught first by "with --session only that session's chunks are read": command: --session
  reads every session.
- Caught first by "with --session only that session's rows are looked at, and a store with
  rows and no chunk at all is not clean": check: rows outside the sessions named are
  looked at.
- Caught first by "with no store named, or one that cannot be reached, it says so: exit 2
  and exit 1": command: with no store named it goes on.
- Caught first by "without the read key it refuses before any request": command: the read
  key is not required.

A rehearsal of the real use on the copy of the real rows (mock only: the stand-in for
the interface, then a real PostgreSQL 16.15 for the table and the view), on the final
code:

```
$ transcripts messages
transcripts: messages: read 271 chunks of 17 sessions, inserted 6199 rows, 42 chunks needed none
$ transcripts messages --check
transcripts: messages --check: 271 chunks, 6199 rows, each as its chunk gives it
$ transcripts messages
transcripts: messages: read 271 chunks of 17 sessions, inserted 0 rows, 271 chunks needed none
```

The 6,199 rows went in 230 requests, 16,121,104 bytes in all, the largest 978,277, each
run in about 2 seconds against the stand-in. Read back and put through the real table,
every row was taken, and the view shows 5,959 rows, the number of the plan's probe. Row
for row against that probe, 5,189 are the same; 762 are calls whose input is the same
JSON with its keys now sorted, as R4 has had it since the review; and 8 are results
holding U+2400 where the probe's copy had dropped U+0000.

The error paths, on the same copy:

```
$ transcripts messages      (a store where schema.sql has not been run)
transcripts: the store has no table `messages` yet: run plugins/change-record/store/schema.sql in the project's SQL editor, then this again
exit 1
$ transcripts messages      (one chunk changed in the store)
transcripts: <session> main: chunk 43e8fb7aa642 does not match its chain id; left out
transcripts: messages: read 271 chunks of 17 sessions, inserted 6197 rows, 42 chunks needed none, 1 chunk left out
exit 1
$ transcripts messages --check      (11 rows taken out of the table since)
transcripts: <session> main: chunk 43e8fb7aa642 does not match its chain id; left out
missing: <session> main chunk 14b538649e46 line 3 block 0
[...]
transcripts: messages --check: 271 chunks; 11 rows missing, 1 chunk left out
exit 1
```

The real use, on the real store through `agent-workflow-admin`, once the gate had
passed (verified against the real system, 2026-11-16, with this task's code before its
merge):

```
$ transcripts messages --check
[6,199 lines, each a row that is missing]
transcripts: messages --check: 271 chunks; 6199 rows missing, 1 chunk of store/probe's passed over
exit 1, in 71 seconds
$ transcripts messages
transcripts: messages: read 271 chunks of 17 sessions, inserted 6199 rows, 42 chunks needed none, 1 chunk of store/probe's passed over
exit 0, in 79 seconds
$ transcripts messages --check
transcripts: messages --check: 271 chunks, 6199 rows, each as its chunk gives it, 1 chunk of store/probe's passed over
exit 0, in 55 seconds
$ transcripts messages
transcripts: messages: read 271 chunks of 17 sessions, inserted 0 rows, 271 chunks needed none, 1 chunk of store/probe's passed over
exit 0, in 55 seconds
```

Then `materialize` rebuilt the store's sessions, and for each of its 37 streams the rows
of the view `transcript`, read from the real store in order of `n`, were compared with
the rows `message_rows` reads from the rebuilt file: 5,959 rows in the view, 37 streams
the same row for row and in order, none that differs.

Found in that use, and changed after approval: the chunk `store/probe` leaves behind is
no transcript's (its data is the word `first`), so the command named it as left out and
would have exited 1 at every run from the gate on. R5 has the command read every chunk;
it now passes over the probe's own chunk and says how many: one in a session whose id
begins `probe-`, sent by `probe`, whose start is 64 zeros, which no chain the view shows
can hold. A chunk that is like it in two of the three is still read, and left out.
Tested first, 7 assertions failing, and its four guards are among those above.

The review of this task's pull request, by another model family (pr-agent, 2026-11-16,
on the first push): two findings. No line naming the reviewer, as for task 1: added
with what it found. And one that is right: the check looked only at the rows of chunks
the store holds, so a row whose chunk is not there was never seen, and a store with
such rows and no chunk at all passed for clean. R6 has the check print each row that is
there and should not be. It now reads the keys of every row in the sessions it was asked
about, of any shape, and reports by chunk the rows whose chunk the store does not hold;
the rows the probe leaves are under its own chunk, which is held. Tested first, 8
assertions failing, and its five guards are among those above. On the real store after
it: `messages --check: 271 chunks, 6199 rows, each as its chunk gives it, 1 chunk of
store/probe's passed over`, exit 0, in 73 seconds: it holds no such row.

Not done: the owner reading a session in the dashboard, with the README's query. Not
verified: the command where the hooks' key is the only key (it refuses, by the suite);
and a fill of a session pushed after this one, which waits for one to be pushed.
