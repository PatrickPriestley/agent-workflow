---
id: 2026-11-15-probe-sample
tier: 1
status: done
requester: Patrick Priestley, in chat on 2026-11-15 (concern C5 of record 2026-11-15-checkable-judges, "Between tasks 2 and 4"; then "Continue with the fixes and tasks")
approvers: []
---
# The probe's sample keeps no host name, leaves no half-written file, and counts a text transcript's last line

## Goal

`transcripts probe` keeps its promise that a sample holds "no prompt, answer, command,
path, address or id" for a value written as dotted words, removes what it could not
finish writing, and counts every line of a text transcript.

## Probed facts

- Exact source (`plugins/change-record/probe/agent_sample.py`, `IDENT` and `identifier`):
  the value of a field that names a kind of thing is copied when it is a letter followed
  by letters, digits, `_`, `.`, `:` or `-`. So `db.internal.corp.example.com` and
  `jane.doe.example.org` are copied.
- Verified against the real system (the defect scripts a reviewer left, record
  `2026-11-15-checkable-judges`; run again by this session in the box against
  `origin/main`, 2026-11-15): three scripts exit 0. A host name given as a `model` is in
  the sample. A sample whose last step fails (its name is taken by a folder) leaves
  `codex-stop.json.tmp<pid>` in the output folder, which by default is the committed
  fixtures folder. A text transcript of four lines, one of which reads as JSON, with no
  newline after the last, is counted as three lines and its last line's `assistant:` is
  not counted. A fourth script of the same reviewer (a `name` inside a call's arguments
  kept) exits 1 on `main`: an earlier change fixed it.
- Exact source (the made-up hooks of `bin/transcripts.test.sh` and the samples in
  `grade/fixtures/agents/`): the dotted values there are model names and versions,
  `gpt-5.1-codex`, `claude-4.5-sonnet`, `2.1.321`, each dot between two digits.

## Decisions

- A value is copied only if each of its dots stands between two digits. Rejected:
  refusing a value that ends like a host name, which needs a list of endings; and
  refusing every dot, which would lose the versions in model names. What this costs: an
  event type written as dotted words (`response.output_text.delta`) is counted as a
  string and not named. No sample in the repository has one.
- The unfinished file is removed where the write fails. Rejected: writing it in a
  temporary folder elsewhere, which may be another file system, where the last step is
  no longer one step.
- In a text transcript the last line counts though no newline follows it. In a file of
  JSON lines it still does not: there it is a line still being written.

## Tasks

1. The three fixes. Test: `plugins/change-record/bin/transcripts.test.sh`. Red first: 8
   assertions.

## Checks

`bash plugins/change-record/bin/transcripts.test.sh`, which compares the made-up
sessions' samples with the stored ones. Real use: the reviewer's scripts in the box,
against `origin/main` and against this change.

## Outcome

Test first: 8 assertions failed before the fix, committed red, then the fix. The suite is
at 364, the stored samples unchanged.

Guards, each broken by hand in a clone of the repository: 6 breaks, all caught (a dot
anywhere let through; a dot needing a digit on one side only, either side; the
unfinished file left; the last line not counted; its start not counted).

Real use, the reviewer's scripts in the box:

```
a host name kept in the sample
  origin/main        exit 0 | hostname leaked into sample
  fix/probe-sample   exit 1 | no hostname in sample
a half-written file left behind
  origin/main        exit 0 | stale temp file left
  fix/probe-sample   exit 1 | clean
a text transcript's last line not counted
  origin/main        exit 0 | 3 {'user:': 1}
  fix/probe-sample   exit 1 | 4 {'assistant:': 1, 'user:': 1}
```

Not done: one script of the sandboxed run exits 0 at the base as well (a line of JSON
nested too deep to read ends the probe with no sample), so it was not counted as shown;
it is true of `main` and is left on the list.
