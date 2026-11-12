---
id: 2026-11-12-push-resend-after-stop
tier: 1
status: done
requester: Patrick Priestley, in chat on 2026-11-12 ("As recommended", to "Fix the redaction bug? I recommend yes, as its own small tier 1 change, test first")
approvers: []
---
# A push that stops after a change of redaction version still sends every stream again

## Goal

Fix the defect the code-quality judge named on its first real run (record
`2026-11-12-session-quality`, Outcome of task 2): after a change of redaction version, a push
that stops part way leaves some of a session's streams in the store only as the old
redaction made them, and never sends them again.

## Probed facts

- Exact source (`plugins/change-record/bin/transcripts` on `main` at `86eeb6d`, `push_session`):
  `fresh` is true when the session's saved `sent.redaction` is another version than
  `REDACTION`. `sent["redaction"]` is set to the new version at once. Each stream's saved
  state is then replaced, one stream at a time, as the loop reaches it, and the whole state
  is written to the index entry after every part that was sent.
- So, read from that code: with two streams, when the first stream's part has been sent and
  the push then stops (the 60-second limit, a store error), the entry on disk says the new
  redaction version, the first stream restarted, and the second stream as it was: complete,
  under the old version. At the next push `fresh` is false, the second stream has nothing new
  to send, and it is not sent again. `unsent` then calls the session sent.
- Exact source (the same file): `materialize` rebuilds a stream from the chunks of the
  generation its index row names. For that second stream the row names the old generation,
  so a reader gets the text as the old redaction left it, in a session whose row says the new
  version.
- Verified against the real system (`bin/transcripts-store.test.sh`, the stand-in store, in
  this container): "a new redaction version sends every stream again, as the next generation"
  passes, with one stream and a push that is not stopped. No test stops a push between two
  streams. The stand-in can refuse a whole table, not an insert after the first.
- `REDACTION` is 1 and has never changed, so no session in the real store is in this state.
  The defect matters the day the redaction is tightened, which is the day the re-send is
  the point.

## Decisions

- Every stream's saved state is restarted before anything is sent, when the redaction version
  has changed, so the first write to the index entry already says that every stream is owed.
  Rejected: saving the old version until the last stream is done, which would restart streams
  already re-sent after every stop, and send their chunks again as yet another generation.
- The stand-in gains `--refuse-after N`: it accepts N inserts into `chunks` and answers 503 to
  the rest, as a store that fails part way through a session would. Rejected: the time limit
  to stop the push, which a test cannot place between two streams.
- What the store already holds under the old redaction stays there: the hooks' key cannot
  delete, and removing old generations is the owner's, with the read key. Not changed here.

## Tasks

1. `bin/transcripts` (`push_session`), `store/stand-in.py` (`--refuse-after`). Test: in
   `bin/transcripts-store.test.sh`, a session with two streams, sent, its redaction version
   set back, pushed to a stand-in that refuses the second chunk, then pushed to one that
   accepts; both streams must be sent again as the next generation. It fails today because
   the second stream stays at its old generation.

## Checks

`bash plugins/change-record/bin/transcripts-store.test.sh` and the other change-record suites.
Real use is the test itself, against the stand-in: the real store's redaction version cannot
be changed to try it. Error path: the push that stops exits 1 and says so. The reviewer should
attack: a stream sent twice as two generations after a stop, and a session with one stream.

## Outcome

Shipped: `push_session` restarts every stream's saved state before it sends anything, when the
saved redaction version is not the current one; `store/stand-in.py` takes `--refuse-after N`.
`transcripts-store.test.sh` goes from 82 assertions to 89; `transcripts`, `transcripts-grade` and
`transcripts-judge` pass unchanged.

Red first: three of the new assertions failed on the old code, with the state Probed facts
predicted from reading it:

    FAIL after the stop, the entry says the stream that was not reached is still owed
         expected [1 main=2/1 subagents/agent-a1=2/0] got [1 main=2/1 subagents/agent-a1=1/1]
    FAIL the next push sends the stream that was not reached, as the next generation, ...
         expected [subagents/agent-a1 2] got []

(`1` is the redaction version the entry claims; `main=2/1` is generation 2, one part sent. The
second stream stayed at generation 1, complete, and the next push sent nothing.)

Use, against the stand-in, which is the test: a session with two streams is sent; its saved
redaction version is set back; a push to a store that refuses the second chunk exits 1 with
the 503; the entry then says `main=2/1 subagents/agent-a1=2/0`; the next push sends one chunk,
`subagents/agent-a1` as generation 2, and `main` is not sent a third time; a push after that
sends nothing.

Guards: five were broken by hand, one at a time. Four failed the suite. The fifth was the
difference between "another version" and "another version, or never sent": for a session
never sent, restarting every stream gives the same first generation, so the two are the same
program. The code now says the simpler one.

Not done: nothing in the real store was touched, and none of it is in this state, since the
redaction version has never changed. Old generations already in the store under an older
redaction stay there until the owner removes them with the read key.
