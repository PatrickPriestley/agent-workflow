Made-up score rows, index entries, judge files, transcripts and label files for `transcripts
report` (bin/transcripts-judge.test.sh; records docs/changes/2026-11-09-skill-transcripts.md, R11,
and docs/changes/2026-11-11-grading-trust.md, R4 and R5): five sessions over two skill versions
and one with no blob, a red-first row re-graded from fail to pass, judge rows, and two sessions
judged by both judges. Every session is labelled: tier-declared is covered by five (one a false
pass), red-first by four (one a false fail, on a step that failed), the others by fewer. The
transcripts under `projects/` hold the calls the failed rows cite, with a made-up address and
token for the redaction. `expected.md` is the report they must give, written by hand before the
code and read line by line since.
