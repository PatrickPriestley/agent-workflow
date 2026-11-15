---
id: 2026-11-15-report-redaction
tier: 1
status: done
requester: Patrick Priestley, in chat on 2026-11-15 (concern C5 of record 2026-11-15-checkable-judges, "Between tasks 2 and 4"; then "Continue with the fixes and tasks")
approvers: []
---
# The report redacts three texts it printed as they were, and survives a row with odd evidence

## Goal

`transcripts report` keeps its own rule, that every text it takes from a row, a label or a
transcript is redacted, for the three texts found to break it, and no longer ends in a
traceback on a score row whose evidence is not an object.

## Probed facts

- Exact source (`plugins/change-record/grade/report.py`, its first lines): "Every text
  taken from a row, a label or a transcript passes through the caller's redaction".
- Verified against the real system (the defect scripts a reviewer left, record
  `2026-11-15-checkable-judges`, the probes and the real use of task 2; run again by this
  session in the box against `origin/main`, 2026-11-15): four scripts exit 0, each showing
  its defect. A row's skill name is printed in the headings as it is (`label`). An
  evidence key is printed as it is in "Its evidence:" (only the value is redacted). The
  name of the tool of a cited call, which comes from the transcript, is printed as it is
  in a failed step's heading. A row whose evidence is a list ends the report in
  `AttributeError: 'list' object has no attribute 'get'`, from `labels.compare`. A fifth
  script shows an error text's line break becoming a heading in the page.
- Exact source (`grade/report.py`, `coverage_section`): the skill names of the coverage
  table come from index entries and transcripts and are printed as they are.
- Exact source (`grade/report.py`): a failed step's evidence value is redacted and then
  cut to 200 characters, in that order, so a secret is not cut into something no pattern
  knows.

## Decisions

- Each of the three texts is redacted where it is taken, and the whole page is passed
  through the redaction once more as it is returned. Rejected: the last pass alone; a
  text cut before it could hold half a secret. Rejected: the three fixes alone; the
  coverage table's skill names and a grader's name were found printed raw while writing
  the tests, and the next such text would be missed the same way.
- A row's evidence that is not an object is read as no evidence. Rejected: refusing the
  row; the report is read by a person and should show what it can.
- The stray heading is not fixed here. The owner ruled it stays on the list (C5).

## Tasks

1. The fixes. Test: `plugins/change-record/bin/transcripts-judge.test.sh`. Red first: 9
   assertions.

## Checks

The judge suite and the other transcripts suites. Real use: the reviewer's own scripts,
which are the reports of these defects, run in the box against `origin/main` and against
this change.

## Outcome

Test first: 9 assertions failed before the fix (the address or the token in the page for
each of the three texts; a traceback for the odd row), committed red, then the fix.
Tests for the last pass were added after: a grader's name and a skill's name in the
coverage table, on the page with score rows and on the page without. The suite is at
355; transcripts-grade 212.

Guards, each broken by hand in a clone of the repository: 7 breaks. Four were caught:
the last pass taken off either page, the odd evidence used as it is, an object's
evidence dropped. Three survive, and each is one of the three fixes where the text is
taken: with the last pass in place, taking one of them off changes nothing a reader can
see. They stay, for the order: a text is redacted before anything is cut from it.

Real use, the reviewer's scripts in the box, against `origin/main` and against this
change:

```
a row whose evidence is not an object: a traceback
  origin/main        exit 0 | AttributeError: 'list' object has no attribute 'get'
  fix/report-leaks   exit 1 |
an address in an evidence key
  origin/main        exit 0 | 234:Its evidence: record none; note for bob@example.com x.
  fix/report-leaks   exit 1 |
an address in a call's tool name
  origin/main        exit 0 | email leaked into report
  fix/report-leaks   exit 1 | no leak
an error text's line break becomes a heading (not fixed here)
  origin/main        exit 0 | 155:## Injected heading
  fix/report-leaks   exit 0 | 155:## Injected heading
```

The skill name in the headings has no script of the reviewer's own; the suite's
assertion for it failed before the fix and passes now.

Not done: the stray heading. Not checked: the sheet (`transcripts sheet`), which prints
the same kinds of text by its own code.
