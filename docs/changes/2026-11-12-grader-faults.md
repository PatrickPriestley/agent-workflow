---
id: 2026-11-12-grader-faults
tier: 1
status: done
requester: Patrick Priestley, in chat on 2026-11-12 ("Privacy and capture first", to the order of fixing the defects the labellers found: "3. The grader faults, with corrected rows stored")
approvers: []
---
# The field graders start a session where it started, and read five commands right

## Goal

Fix the faults behind the four verdicts the field graders got wrong on the five store
sessions labelled on 2026-11-12 (record `2026-11-12-session-quality`, Outcome), and one
crash the code-quality judge found, and store the corrected rows.

## Probed facts

- Verified against the real system (`transcripts accuracy` on the ten sessions rebuilt from
  the store, against the labels in `grade/labels/`, in this container): 31 of 35 verdicts on
  the five new sessions agree with the labels. The four that do not: red-first false fail on
  `172fe91d` and `478c69ad`, record-check false fail on `1305be25`, outcome-filled false n/a
  on `508c7884`.
- Exact source (`bin/transcripts`, `grade_one` and `record_checker`, on `main` at `5a815dc`):
  the commit at the session's first stop is taken as where the session started. The record
  "was there" when that commit holds it, `record-check` runs from that commit, and a task is
  "marked done" only if it was not done there. For a session that stops once, that commit is
  its last. This is the mistake the code-quality judge made (the same record's Outcome).
- Verified against the real system (the grader's evidence for `1305be25` and `508c7884`):
  `record-check` ran from `077eec1`, a commit the session itself made, and found the record
  open there; `outcome-filled` saw no task marked done, because first and last stop were
  one commit.
- Verified against the real system (`grade/fields.py` run on the commands of `478c69ad`): its
  test runs are `env -u AGENT_TRANSCRIPTS -u AGENT_TRANSCRIPTS_URL bash
  bin/transcripts-judge.test.sh`. `unwrap` drops the options of `env` one word at a time, so
  the variable's name is left as the command and the run is not a test run.
- Verified against the real system (the grader's evidence for `172fe91d`): its first code
  write is given as `plugins/change-record/codex-rollout.jsonl`. The command was `mkdir -p
  grade/fixtures/agents/made-up probe && cd grade/fixtures/agents/made-up && python3 - <<'EOF'`:
  `inline_writes` places the file in the directory the command began in, not the one it
  had moved to, so a fixture counts as code.
- Verified against the real system (`shlex.shlex("echo one ; # a comment ; python3 -m
  unittest", posix=True, punctuation_chars=True)` in this container): the tokens are `echo
  one ;`. `simple_commands` joins a command's lines with ` ; ` and then lexes, so a comment
  line hides every line after it. Found by a blind labeller on `6cc07e5f`.
- Verified against the real system (`bin/transcripts-grade.test.sh` with this record's tests):
  grading a session whose record has no `---` header ends in a traceback and no row for any
  session of the run. `frontmatter()` returns a list where a count is expected. Found by the
  Sonnet judge on `6cc07e5f`.
- Verified against the real system (the same tests): two things the labeller reported at
  `68db645` do not happen on `main`: `sed -i 's#a#b#' file` is seen as a write, and a
  here-string does not swallow the lines after it. Their tests are kept.

## Decisions

- A session started at the newest commit, on its last commit's own line, made before its
  first line: `session_commits`, as the label sheet has it since the session-quality record.
  A session that made no commit started where it ended. Rejected: keeping the first stop
  where the start time is not known; an entry always has its first line's time.
- A comment is taken out before a command is lexed: a `#` that starts a word outside
  quotes, to the end of its line. A `#` inside a word stays. Rejected: `shlex` with no
  comment character and nothing else, which makes each word of a comment a command.
- `env` is unwrapped with the options that take a value (`-u NAME`, `-C DIR`, `-S STRING`).
- An inline script's writes are placed where the command was when it ran the script.
- A record with no header has no fields and no task marked done.
- The grader is `fields/3`. Rows of `fields/2` stay in the store beside the new ones; the
  report reads the latest row of each grader, and shows both graders until the old rows are
  removed with the read key.

## Tasks

1. `bin/transcripts` (`grade_one`, `GRADER`), `grade/fields.py` (`strip_comments`, `unwrap`,
   `inline_writes`, `frontmatter`). Test: in `bin/transcripts-grade.test.sh`, a case for each
   fault; they fail today as Probed facts say. The suite's repository gets dated commits, so
   that a session's start can be told from them.

## Checks

`bash plugins/change-record/bin/transcripts-grade.test.sh` and the other suites; the fifteen
fixture sessions must still agree with their labels. Real use: `transcripts grade` and
`accuracy` on the ten store sessions, then `grade --store`. Error path: a record with no
header. The reviewer should attack: a verdict that was right under `fields/2` and is wrong
now.

## Outcome

Shipped: in `bin/transcripts`, `grade_one` takes the session's start from `session_commits`
and the grader is `fields/3`; in `grade/fields.py`, `strip_comments`, a lexer that goes line
by line and leaves out what never closes its quote, `unwrap` for `env -u`, `cd` and
`base_after` for an inline script's writes, and `frontmatter()` returning a count. The README.
`transcripts-grade.test.sh` goes from 168 assertions to 192; the other suites pass (279, 224,
112), and the eval cases (40).

Red first: 10 of the first 13 new assertions failed on the old code:

    FAIL a session started where the newest commit made before its first line is, ...
         expected [fail] got [not_applicable]
    FAIL a test run under env -u NAME is a test run
         expected [pass] got [fail]
    FAIL a record with no header is graded, not a crash ...
         expected [fail not_applicable] got [no-scores no-scores]
         unexpected [Traceback] in: ...

A verdict the fix itself made wrong, which is what the reviewer was to look for. With the
comments fixed, the first re-grade of the store sessions turned red-first on `508c7884` from
right to wrong. One of its commands had failed: a heredoc had ended early and left text
whose quotes never balance. The old lexer fell back to splitting such text on spaces, and
read `sed -i` targets out of it; under `fields/2` the comment bug had cut the text off
before that. The shell stops at such text too, so the lexer now leaves it out. A test holds
it.

Use, on the ten sessions rebuilt from the store, against the labels in `grade/labels/`:

    | Step | Labelled | Agree | False fail | False pass | False n/a |
    | tier-declared | 9 | 9 | 0 | 0 | 0 |
    | probe-before-record | 9 | 9 | 0 | 0 | 0 |
    | record-before-code | 9 | 9 | 0 | 0 | 0 |
    | red-first | 9 | 9 | 0 | 0 | 0 |
    | change-line | 9 | 9 | 0 | 0 | 0 |
    | record-check | 9 | 8 | 1 | 0 | 0 |
    | outcome-filled | 9 | 9 | 0 | 0 | 0 |

62 of 63, where `fields/2` had 59. The fifteen fixture sessions still agree on every step
they are labelled for (69 of 69). `transcripts grade --store` wrote the 70 `fields/3` rows
for the ten sessions.

The one still wrong: record-check on `1305be25`, a false fail. That session approved a
record and then merged `main` into its branch. From where it started to its last commit,
the range holds the code that came in with the merge, so `record-check` reads a code change
against a record that was open at the start. The session's own commits changed two files
under `docs/changes/`. Not fixed here: `record-check` takes a range, and leaving a merge
out of one needs a decision about which base stands for the session, which is the owner's.

Guards: 13 broken by hand, 10 failed the suite. The three that survived each have a test
now: a session with no commit of its own started where it ended, and a `#` inside an
unquoted word is no comment (two guards).

Not done: the `fields/2` rows stay in the store, four of them known false; removing them
takes the read key and a delete, which this change does not do. The session with nine
records (`5ac54a69`) is still not graded for the steps that need one record.
