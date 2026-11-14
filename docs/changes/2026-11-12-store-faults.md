---
id: 2026-11-12-store-faults
tier: 1
status: done
requester: Patrick Priestley, in chat on 2026-11-12 ("Privacy and capture first", to the order of fixing the defects the labellers found: "2. The store faults (starved pushes, older copy returned, slow pattern)")
approvers: []
---
# Three faults in push, materialize and redaction

## Goal

Fix three defects a blind labeller found in the store code when reading session `659da00f`
for code quality (record `2026-11-12-session-quality`), each of which loses or exposes
transcripts without saying so: one session that cannot be sent keeps every other session
from being sent; after a new redaction, `materialize` can return the older, less redacted
copy; and one redaction pattern takes a time that grows with the square of its input.

## Probed facts

- Exact source (`plugins/change-record/bin/transcripts` on `main` at `5a815dc`, `cmd_push`):
  every session is sent inside one `try`. Any error ends the push, and the sessions are
  taken in name order at every push, so a session that fails every time stops the ones
  after it for ever.
- Verified against the real system (`bin/transcripts-store.test.sh` with this record's tests,
  the stand-in store, in this container): with two archived sessions and the first one's
  part files moved away, the push stops on `No such file or directory`, the store gets no
  chunk of the second, and its `sent` stays empty; the same at the next push. With a store
  that answers 400 to the first session's rows, the same.
- Exact source (the same file, `cmd_materialize`): of a session's index rows the one kept is
  the greatest by (last timestamp, bytes sent, version). The redaction version is not
  compared.
- Verified against the real system (the same suite): a session sent once, then sent again
  by a copy of the tool with `REDACTION = 2` and a pattern that removes a 409-character
  word, has two rows; `materialize` writes the text with the word in it and an entry with
  `redaction_version` 1.
- Verified against the real system (the email pattern of `PATTERNS`, in this container):
  5,000 letters take 0.12 s, 10,000 take 0.47 s, 20,000 take 1.9 s. `transcripts redact` on
  one line with 60,000 hex digits and 60,000 characters of `a.` is not done in 5 s. The
  background push has 60 s for everything.
- Exact source (`store/schema.sql`): `chunks.data` is checked to be at most 8,000,000
  characters, and a chunk is cut only between lines, so one very long line makes a chunk
  the store refuses. That refusal is a 400 for that session's rows; it is the case the
  stand-in's `--refuse-session` stands for, and it was not run against the real store.
- `REDACTION` is 1 and has never changed, so no session in the real store has two copies.

## Decisions

- A session whose own data cannot be sent is passed over, said by name, and tried again at
  the next push; the others are sent. Its own data means: its archived files cannot be
  read, or the store refuses its rows with a 4xx that is not about who is asking or how
  often (401, 403, 408, 429). Anything else still stops the push at once: a store that
  cannot be reached, a 5xx, the time limit, the lock. Rejected: passing over every error,
  which would hammer a store that is down once per session.
- A push in which a session was passed over exits 1 (0 in the background, as every
  background push does) and says how many.
- `materialize` prefers the row with the newest redaction version, then as before. A reader
  gets the most redacted copy even where an older one is longer. Rejected: leaving the
  order and deleting old rows, which the hooks' key cannot do.
- Addresses are found in one pass over the text, by a function that gives exactly what the
  pattern gives: it goes from one `@` or `%40` to the next and looks at the run of
  local-part characters around each once. Rejected: a lookbehind that lets the pattern
  start only where such a run starts. It was tried first and is not the same: where one
  address follows another with nothing between, the second is no longer found (12,094 of
  200,000 made-up strings came out different). Rejected too: a length limit on the text,
  which would leave long lines unredacted.
- Not changed: the `bearer|token|basic` pattern, which rewrites prose such as "the token
  expiration is checked". The labeller listed it; it errs on the safe side, and narrowing it
  risks letting a real token through. The owner's list for this change did not have it.
- Not changed: a line longer than the store's limit still cannot be sent. It no longer
  holds anything else back, and the push names the session.

## Tasks

1. `bin/transcripts` (`cmd_push`, `StoreError`, `cmd_materialize`, `PATTERNS`),
   `store/stand-in.py` (`--refuse-session`). Test: in `bin/transcripts-store.test.sh`, the
   three cases of Probed facts; they fail today as stated there.

## Checks

`bash plugins/change-record/bin/transcripts-store.test.sh` and the other change-record
suites. Real use is the stand-in: nothing in the real store is in any of these states.
Error path: a store that fails as a whole must still stop the push. The reviewer should
attack: a session passed over for ever without anyone seeing it, and an address the email
pattern no longer finds.

## Outcome

Shipped: in `bin/transcripts`, `cmd_push` passes over a session whose own data cannot be sent
(`its_own`, `StoreError.status`), `cmd_materialize` ranks by redaction version first, and
`redact_emails` replaces the email pattern; `store/stand-in.py` takes `--refuse-session` and
`--refuse-status`; the README. `transcripts-store.test.sh` goes from 89 assertions to 112;
the other suites pass unchanged (279, 168, 224).

Red first: 11 of the first 17 new assertions failed on the old code:

    FAIL a session whose archived lines cannot be read does not keep the next one from being sent
         expected [1 0 1] got [1 0 0]
    FAIL after a new redaction that shortens the text, materialize returns the newer copy, not the longer one
         unexpected [SHORTENME] in: ...
         expected [2] got [1]
    FAIL redaction of a long run of letters, digits and dots takes well under a second, ...
         expected [done 1] got [not done in 5 s]

A wrong fix on the way. The email pattern was first given a lookbehind, so that it could
only start where a run of its characters starts. The suite passed. A comparison with the
old pattern on 200,000 made-up strings did not: 12,094 came out different, among them a
second address that follows the first with nothing between, which was left in. That fix
was dropped for `redact_emails`, which was compared the same way on 400,000 strings with no
difference, and a comparison on 30,012 strings is now in the suite.

Use, against the stand-in:

- two sessions, the first unreadable: exit 1, `10000000 (...) could not be sent: [Errno 2]
  No such file or directory`, `pushed 1 new chunks ...; 1 session could not be sent and will
  be tried again at the next push`; the second session is in the store;
- the first refused with 400: the same, and once a store takes it, the next push sends it
  and nothing of the second again;
- a store that answers 503, 401 or 429 to every chunk: `push stopped`, one request made;
- a session sent under redaction 1 and again under redaction 2, which takes a 409-character
  word out: `materialize` writes the text without the word and `redaction_version` 2;
- one line with 60,000 hex digits, 60,000 characters of `a.` and 20,000 `%40`: redacted in
  under 5 s, where the old pattern was not done in 5 s on the first two alone. In this
  container the whole of `redact_text` takes 21 ms for 200,000 letters; the old email
  pattern alone took 1.9 s for 20,000.

Guards: 20 broken by hand, 17 failed the suite. The three that survived each have a test
now: a 401 must stop the push (and a 429, a guard broken once its test was there), a session
passed over must be tried once in a push and not at each of its three passes, and a long
run of `%40` must not be scanned again from each of them.

What the reviewer was asked to attack:

- A session passed over for ever. It is named at every push, on stderr or in
  `<archive>/push.log`, and a foreground push exits 1. Nothing else reports it: the report
  does not read the archive. A line longer than the store's limit is such a session.
- An address the scan no longer finds. The scan is compared with the pattern on made-up
  strings, 30,012 in the suite; that is evidence for those strings and their kind, not a
  proof.

Not done: the `bearer|token|basic` pattern still rewrites prose, as the Decisions say.
Nothing in the real store was touched or was in any of these states.
