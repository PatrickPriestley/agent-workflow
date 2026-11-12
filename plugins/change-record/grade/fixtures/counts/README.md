Made-up transcripts and index entries for the counts and the skill coverage of `transcripts
report` (bin/transcripts-judge.test.sh; record docs/changes/2026-11-12-session-quality.md, R1 to
R3). There is no `scores/` here on purpose: the counts need only the transcripts. Three sessions:

- `d1000000`: a message written on three lines (counted once), a failed call and a refused one,
  a line the harness wrote and a notification (neither is a person), one more turn from a
  person, and the skill called with the Skill tool.
- `d2000000`: the skill file read through the shell, which the index entry does not list; a tool
  result with a text block attached (no person); and a blank text block (no message).
- `d3000000`: no token usage at all, a subagent's lines kept inline (one calls the skill), and a
  compaction summary.

`expected.md` is the report they must give, written by hand before the code.
