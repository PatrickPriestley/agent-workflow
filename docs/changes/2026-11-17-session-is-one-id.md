---
id: 2026-11-17-session-is-one-id
tier: 1
status: open
requester: Patrick Priestley, in chat on 2026-11-17 (every command that takes `--session` gets the check `transcripts compare` got in PR 17)
approvers: []
---
# Every transcripts command that takes `--session` refuses a value that is not one session id, before it reads or writes anything

## Goal

PR 17 (record `2026-11-17-compare-proposals`) made `transcripts compare` refuse a `--session`
that is not one id, because `os.path.join(d, "compare", sid, step)` starts over at an absolute
`sid` and `--run` then read a proposal there and deleted the folder. `transcripts propose` has
the same shape: it reads `DIR/sessions/<sid>.json` and writes `DIR/proposals/<sid>/<step>/`,
so `--session /tmp/x` or `../x` reads and writes outside the transcripts folder (it also needs
a label file of that id, which makes it harder to reach, not closed). Every other command that
takes `--session` gets the same check, so no command builds a path from it.

## Probed facts

- Exact source (`bin/transcripts`, `cmd_propose`): `read_json(os.path.join(d, "sessions", sid + ".json"))`,
  `session_lines(d, sid, entry)` (which globs `DIR/parts/<sid>` and `DIR/projects/*/<sid>.jsonl`),
  `labels.load(lab)[0].get(sid)`, and `write_atomic` of four files under
  `os.path.join(d, "proposals", sid, step)`. Nothing checks `sid`.
- Exact source (`bin/transcripts`): `grade`, `sheet`, `judge`, `judge --repeats` and
  `judge --review` take `--session` as a filter on the names of `DIR/sessions/*.json`, so a
  path there matches no file and builds no path today. `push` filters the archive's
  `sessions/*.json` the same way. `materialize` and `messages` put it, quoted, in a PostgREST
  `session_id=in.(...)` filter; `materialize` then checks each id the store returns before it
  writes a file named by it. `report` takes no `--session`.
- Exact source (`bin/transcripts`, `cmd_repeats`): with `--transcript FILE --out DIR`, the
  session id is the first `"sessionId":"..."` in the file, matched by `[^"]+`, and the answer is
  written to `os.path.join(OUT, "repeats", sid + ".json")`. A transcript whose `sessionId` is
  `../../x` writes outside `OUT`. `transcript_file` (used by `sheet` and `accuracy`) already
  falls back to the file's name when the id is not one id.
- Exact source (PR 17, `cmd_compare`): the check is `re.match(r"^[A-Za-z0-9][A-Za-z0-9._-]*$", sid)`,
  exit 2, `--session '<value>' is not one session id`. In Python `$` also matches before a
  final newline, so `"abc\n"` passes it.
- Exact source (`bin/transcripts`, `archive`): an archived session id is `^[A-Za-z0-9._-]+$`
  not starting with `.`; the ids Claude Code, Codex and Cursor write are UUIDs, which the
  one-id pattern takes.
- Exact source (`bin/transcripts`, `grade/review.py`): the only deletes are of a command's own
  temporary folder and of `DIR/reviews/<id>/<model>/<old>` for an id listed from
  `DIR/sessions`; none is of a path built from `--session`, so no containment check is added.

## Decisions

- One function, `one_session_each(ids)`, says the first value that is not one session id and the
  command exits 2 with `--session '<value>' is not one session id`. Each command calls it right
  after reading its arguments, before any folder, file, key or store is touched. The pattern is
  compare's, kept as `SESSION_ID` and matched whole (`fullmatch`), so a trailing newline is refused too.
- The check goes on every command that takes `--session`: `propose`, where the value builds
  paths, and `grade`, `sheet`, `judge` and its `--repeats` and `--review` modes, `push`,
  `materialize` and `messages`, where it is a filter today. Rejected: `propose` alone, which
  leaves the next command that joins a path to it to find the hole again, and lets a typo that
  is a path pass silently as "no such session".
- `judge --repeats --transcript` takes the transcript's `sessionId` only when it is one id, and
  the file's name otherwise, as `transcript_file` does. Rejected: refusing the transcript,
  which would stop a real transcript whose id is odd from being counted at all.
- `compare` is left as PR 17 has it; once both are merged it can call `one_session_each` too.

## Tasks

1. The check on each command and the repeats fallback. Tests beside each command:
   `bin/transcripts-judge.test.sh` (propose, judge, repeats, review, the repeats transcript),
   `bin/transcripts-grade.test.sh` (grade, sheet), `bin/transcripts-store.test.sh` (push,
   materialize, messages). Red today: each command takes an absolute, `../` or `a/b` session
   and goes on (propose reads and writes outside DIR).

## Checks

The four suites `bin/transcripts.test.sh`, `transcripts-grade.test.sh`,
`transcripts-store.test.sh`, `transcripts-judge.test.sh`. Each new test fails with its
command's check taken out. Real use: `transcripts propose` with `--session /tmp/...` against a
folder holding a session and label there, before and after.

## Outcome
Built test first. The tests were committed failing (9a168ff): 24 in
`transcripts-grade.test.sh`, 42 in `transcripts-store.test.sh`, 52 in
`transcripts-judge.test.sh`. Each command took `/abs`, `../../x`, `a/b`, `.`, `..` and an id
with a trailing newline, and went on with exit 0 or 1. Two of them showed the hole itself:

```
FAIL a session that is a path, not one id, is refused before anything is read or written
     missing [is not one session id] in: transcripts: no label confirms that /tmp/tmp.p7hZxYcsIV/propose/elsewhere/x failed red-first: ...
FAIL a transcript whose sessionId is a path is answered under its file's name, inside --out, not where the id leads
     expected [] got [/tmp/tmp.nRYKh86cM3/rout2/escape.json]
```

So `propose` read the entry and transcript at the path it was given, outside DIR, and stopped
only at the label. `judge --repeats --transcript FILE --out rout2/inner` wrote its answer to
`rout2/escape.json`. With the fix (one call to `one_session_each` in each of `push`,
`materialize`, `messages`, `grade`, `sheet`, `judge`, `judge --repeats`, `judge --review` and
`propose`, plus the repeats fallback):

```
$ bash plugins/change-record/bin/transcripts.test.sh | tail -1
passed=364 failed=0
$ bash plugins/change-record/bin/transcripts-grade.test.sh | tail -1
transcripts grade: 238 passed, 0 failed
$ bash plugins/change-record/bin/transcripts-store.test.sh | tail -1
passed=488 failed=0
$ bash plugins/change-record/bin/transcripts-judge.test.sh | tail -1
transcripts judge and report: 530 passed, 0 failed
```

Each check was then taken out on its own, in a copy of the repository, and that command's suite
run. Every time, only its own test failed:

```
push                 passed=476 failed=12      (all 12 in its own test)
materialize          passed=470 failed=18      (all 18 in its own test)
messages             passed=470 failed=18      (all 18 in its own test)
grade                226 passed, 12 failed     (all 12 in its own test)
sheet                226 passed, 12 failed     (all 12 in its own test)
judge                518 passed, 12 failed     (all 12 in its own test)
repeats              518 passed, 12 failed     (all 12 in its own test)
repeats --transcript 528 passed, 2 failed      (both in its own test)
review               518 passed, 12 failed     (all 12 in its own test)
propose              516 passed, 14 failed     (all 14 in its own test)
```

Real use. An archive made by `transcripts archive` in a scratch folder, with a copy of its
session's entry and parts at `<scratch>/elsewhere/x`, the code before (0f999fd) and after:

```
--- before
$ transcripts propose <archive> --session <scratch>/elsewhere/x --step red-first
transcripts: no label confirms that <scratch>/elsewhere/x failed red-first: ...
exit 1
$ transcripts propose <archive> --session ../../elsewhere/x --step red-first
transcripts: no label confirms that ../../elsewhere/x failed red-first: ...
exit 1
--- after
$ transcripts propose <archive> --session <scratch>/elsewhere/x --step red-first
transcripts: --session '<scratch>/elsewhere/x' is not one session id
exit 2
$ transcripts propose <archive> --session ../../elsewhere/x --step red-first
transcripts: --session '../../elsewhere/x' is not one session id
exit 2
$ transcripts propose <archive> --session 77000000-2222-3333-4444-555555555555 --step red-first   (a real id still passes)
transcripts: no label confirms that 77000000-2222-3333-4444-555555555555 failed red-first: ...
exit 1
```

Left as it was: `report` takes no `--session`. It does join the `session_id` of the rows in
`DIR/scores/*.json` to `DIR/sessions/<id>.json` and `DIR/projects/*/<id>.jsonl` to hash a
transcript, so a score file planted in DIR could make it read, not write, elsewhere. That is
not a `--session` path, and is left for a change of its own. `compare` is not on this branch:
it is in PR 17, unmerged, with its own check.
