---
id: 2026-11-12-sheet-and-scaffolding
tier: 1
status: done
requester: Patrick Priestley, in chat on 2026-11-12 ("Privacy and capture first", to the order of fixing the defects the labellers found: "4. The sheet cut and the test scaffolding")
approvers: []
---
# The label sheet shows every section of a record, and a suite with no temp folder stops

## Goal

Fix the last two defects of the round of 2026-11-12 (record `2026-11-12-session-quality`,
Outcome): the sheet a labeller works from cuts a long record before the sections two of its
questions ask about, and seven test suites remove the folder they were started in when they
cannot make a temporary one.

## Probed facts

- Exact source (`plugins/change-record/grade/labels.py`, `sheet`, on `main` at `5a815dc`): the
  record is shown through `clip(text, 200)`: its first 200 lines and a count of the rest.
- Verified against the real system (`wc -l docs/changes/*.md` in this repository): the tier 2
  records run to 690, 868 and 1,239 lines. On 2026-11-12 three of five sheets cut the record
  before Tasks, Checks or Outcome, and the labellers read it in the repository instead.
- Verified against the real system (`bin/transcripts-grade.test.sh` with this record's test):
  the sheet of a session whose record has 300 probed facts shows no `## Decisions`, `## Tasks`,
  `## Checks` or `## Outcome`.
- Exact source (the seven `plugins/change-record/bin/*.test.sh`): each begins
  `TMPROOT="$(cd "$(mktemp -d)" && pwd -P)"` and ends, by a trap, with `rm -rf "$TMPROOT"`.
  When `mktemp` fails it prints nothing on stdout, `cd ""` succeeds where it is, and
  `TMPROOT` is the folder the suite was started in.
- Verified against the real system (`bin/record-check.test.sh` with this record's test, in a
  scratch folder, `TMPDIR` naming a folder that is not there): each of the seven suites
  prints `mktemp: failed to create directory`, runs all its tests in the folder it was
  started in, and that folder is gone afterwards. Found by a blind labeller on `bf01bd72`,
  whose run of it wrote into `/`.
- Exact source (`bin/*.test.sh`, `install.test.sh` and `pr-agent/*.test.sh` at the root of the
  repository): they set `TMPROOT="$(mktemp -d)"` with nothing after it. Where `mktemp` fails
  their `TMPROOT` is empty: the trap removes nothing, and what they write goes to paths from
  `/`. Not run.

## Decisions

- The sheet shows the record section by section: what comes before the first `## ` heading
  whole, then each section's heading and its first 40 lines, with a count of what is left
  out of that section. A labeller sees the frontmatter, every heading, the first tasks and
  the start of the Outcome, which is what the questions ask. Rejected: the whole record,
  which is longer than most sessions; and a larger single cut, which the next long record
  outgrows.
- A suite that cannot make its temporary folder says so and exits 1 before it does anything.
- The suites outside this plugin are not changed here. Their failure writes under `/` and
  removes nothing; they belong to other parts of the repository, and the owner named the
  seven.

## Tasks

1. `grade/labels.py` (`sheet`), the seven suites' first lines. Test: in
   `bin/transcripts-grade.test.sh`, the sheet of a long record; in `bin/record-check.test.sh`,
   each suite started with no temporary folder. They fail today as Probed facts say.

## Checks

The plugin's suites. Real use: the sheets of the store sessions whose records were cut on
2026-11-12. Error path: the suites themselves, with `TMPDIR` naming nothing. The reviewer
should attack: a short record that the sheet now shows differently.

## Outcome

Shipped: `record_shown` in `grade/labels.py`, and the first lines of the seven suites in
`plugins/change-record/bin/`. `transcripts-grade.test.sh` goes from 192 assertions to 212 and
`record-check.test.sh` from 85 to 113; the others pass unchanged (218, 107, 279, 224, 112),
and the eval cases (40).

Red first, on the old code. The sheet of the long record:

    FAIL a record longer than the sheet shows whole still has each section's heading and its first lines
         missing [## Decisions] in: ...
         missing [## Tasks] in: ...

and for the suites, 21 of the 28 new assertions of `record-check.test.sh`; for one suite:

    FAIL transcripts-store.test.sh stops when it cannot make its temporary folder, ...
         expected [keep] got []
         missing [cannot make a temporary folder] in: mktemp: failed to create directory ...
         unexpected [  ok ] in: ...

Use, on the store sessions whose sheets cut the record on 2026-11-12: the five sheets
written again show every section of their record (13 to 28 headings each), with what is
left out counted section by section, for instance `[... 353 more lines of this section]`
in the Outcome of `478c69ad`'s record. Use of the scaffolding is its test: each suite,
started in a scratch folder with `TMPDIR` naming nothing, prints `cannot make a temporary
folder`, exits 1, runs no test and leaves the folder as it was.

Guards: 8 broken by hand, 6 failed the suites. Of the two that survived, one was a step
that did nothing (the lines were already trimmed) and is removed; the other, that the
record on the sheet is redacted, was a gap older than this change and has a test now.

What the reviewer was asked to attack: a short record shown differently. A record with no
section over 41 lines is shown line for line as before, and the sheets of the two real
dispatch sessions in the suite are unchanged.

Not done: the suites outside this plugin (`bin/`, `install.test.sh`, `pr-agent/`) still go
on with an empty `TMPROOT` when `mktemp` fails, and write under `/`. They remove nothing.
