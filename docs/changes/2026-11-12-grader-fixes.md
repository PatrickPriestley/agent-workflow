---
id: 2026-11-12-grader-fixes
tier: 1
status: done
requester: Patrick Priestley, in chat on 2026-11-12 ("Can you do these two": "The graders have known faults that are not yet fixed")
approvers: []
---
# The field graders follow the owner's rulings, and say when they could not grade

## Goal

Fix the grader faults the first measurement found (record `2026-11-11-grading-trust`, Outcome,
"the first measurement"): four wrong verdicts on `probe-before-record`, two on `change-line`,
`outcome-filled` called not applicable where a commit is missing, and the labelling sheet's
wording, which the owner's rulings of 2026-11-12 overtook. The grader's version goes up, so
scores made under the old rules and the new are kept apart.

## Probed facts

All verified against the real system on 2026-11-12, in this container, at `d454c0a`: the
grader run on the fifteen fixture sessions (`transcripts accuracy --transcript` on
`grade/fixtures/*.jsonl.gz` and `grade/fixtures/evals/*.jsonl.gz`), and `grade/fields.py` called
on each command below.

- `4c14e156`, false pass on `probe-before-record`: the only command before the record that the
  grader takes for a probe is `python3 --version`. `probe_command(['python3', '--version'])` is
  true twice over: `--version` is in its list, and an interpreter with no script is read as
  taking its program from stdin.
- `74a1b42a`, false fail: before the record the session ran `ls -la /srv/audit 2>&1 | head;
  echo "AUDIT_LOG=$AUDIT_LOG"`. `probe_command` is false for both; it knows no look at the
  environment.
- `9d1fcbcc`, false fail: before the record the session ran `python3 -m unittest discover -s
  tests -t .`, and its result shows the run. `probe_command` returns false for every test
  command, by design until the ruling.
- `c76ecdac`, false fail: the record was written by `cat > docs/changes/2026-11-08-names.md
  <<'EOF'` in a command that failed, and its result ends `/bin/bash: line 33:
  docs/changes/2026-11-08-names.md: Read-only file system`. The grader counts a failed shell
  command as run and so counts the write; the session then has a record it never wrote.
- `d178b31d`, false pass on `change-line`: no pull request call. The last message says "Here is
  the pull request description I would open:", then a bold title, a paragraph and four
  bullets, and only then `Change: docs/changes/2026-11-08-shout.md`. The grader passes any
  last message holding the line alone on a line, wherever it is.
- `fc657482`, false pass: the last message holds no pull request description and never names
  one; its `Change:` line is inside a `git commit -m "..."` it suggests.
- The ten fixture sessions whose last message does hold a description name it on a line of its
  own first: a heading (`## Pull request description`, `## Pull request description (not
  opened)`), a bold line (`**Pull request description I would open**`) or a sentence ending in a
  colon (`Here is the pull request description:`). Between that line and the `Change:` line
  there is nothing but blank lines, a rule (`---`), a code fence, and in three sessions a
  `**Title:** ...` line.
- `outcome-filled`, six false n/a: the fixtures have no commit, so the record cannot be read, and
  the row says not applicable with no `error` in its evidence. `tier-declared` carries the
  `error` in the same case, and `accuracy` and the report then list the row as one the grader
  could not grade and count it nowhere. `record-check` with no commit is the same as
  `outcome-filled`: not applicable, no `error`.
- `outcome-filled` counts a task as marked done only from `done: true` in the frontmatter. The
  eval fixtures' records mark tasks with `- [x]` under `## Tasks` and have no task list in the
  frontmatter.
- The sheet (`grade/labels.py`, `QUESTIONS`) says to label `tier-declared` `na` "when the session
  wrote no record and no code", which contradicts the ruling for a session that says `Tier: 0`;
  its probe question lists "inline code, a module, a scratch script, `--help`, a request to
  another system" and nothing the rulings added or took away.

## Decisions

- The rulings in `2026-11-11-grading-trust` ("Rulings, 2026-11-12") are the specification. Where
  a ruling needs a line drawn for a program to follow, the line is here.
- **`--version` is no probe**, with or without an interpreter in front; `--help` still is.
  Rejected: dropping `--help` too, which the skill's probing reference names as a probe.
- **A test command that ran before the record is a probe.** Rejected: asking that its result
  show a test ran; a suite that cannot start is still something tried, and `red-first` already
  judges what a run showed.
- **A look at the environment is a probe**, and it is one of two things. A value read from the
  environment: `printenv`, `env` with no command, or `echo`/`printf` of a variable in capitals
  that the same command did not set, the shell's own (`PWD`, `HOME`, `USER`, `TMPDIR` and the
  like) left out. Or a path looked at outside the working tree: `ls`, `stat`, `test`, `[`,
  `file`, `find`, `du`, `df`, `readlink` on an absolute path that is not under the working
  tree, a temporary folder, or a plugin's or skill's own folder. Rejected: counting `cat` and
  `head` of such a path, since the ruling says reading files is no probe and the sessions read
  the skill's reference files that way; and counting `which` or `command -v`, which says no
  more than `--version`.
- **A shell write the shell refused did not happen.** A target is dropped when the command's
  result has a line, from the shell or from the command that writes (`tee`, `cp`, `mv`,
  `install`, `sed`), ending in that path and a refusal (`Read-only file system`, `Permission
  denied`, `No such file or directory`, `Is a directory`, `Operation not permitted`, `No space
  left on device`). A line from a command that only looked (`ls: cannot access ...`) refuses
  nothing. Rejected: treating every failed command as not run, which would lose the writes of
  a command whose last step failed.
- **The description in a last message starts at the line that names it**: a heading, a bold
  line or a line ending in a colon that says "pull request" or "PR" and "description" or
  "body". The `Change:` line passes when nothing but blank lines, rules, code fences and a
  `Title:` line stands between it and that line, or between it and the start of the message.
  Where the message names a description and the line is elsewhere or names another record, the
  step fails. Where the message names no description and does not open with the line, the step
  does not apply. Rejected: the first line of the whole message only, which fails every
  session that reports before it gives the description.
- Not changed: a last message that holds a description and no `Change:` line at all is still
  not applicable. That is a likely false n/a, no labelled session shows it, and it is left for
  the owner (Outcome).
- **Ticked tasks count as done**: a `[x]` item under `## Tasks` counts as `done: true` does, and
  `outcome-filled` applies when the last commit has more of either than the first.
- **No commit is "could not grade"** for `record-check` and `outcome-filled` as it already is
  for `tier-declared`: the verdict stays not applicable and the evidence carries the `error`.
  Rejected: rebuilding the record from the session's own writes, which cannot follow a shell
  edit and would be a new grader, not a fix.
- The grader becomes `fields/2`. Rows of `fields/1` stay in the store and the report keeps the
  two apart, as it does for any two graders.
- The sheet's wording follows the rulings. Sheets already built are not rebuilt; the fifteen
  fixture labels were ruled on under the same four rules.
- `evals/cases.test.cjs` checks that the field grader gives the eval grader's verdict on its
  probe fixtures. One now differs, and is written there as a ruled divergence beside the one
  already there: a test written and run before the record passes here (a run of the tests is a
  probe) and fails the eval grader, which asks for a probe of `fileinput` itself.
- (Added after grading the store sessions; see Outcome.) **A file an inline Python script
  opened for writing was written**: `python - <<EOF` or `python -c` with `open(X, 'w')`, `'a'`,
  `'x'`, or `X.write_text(`, where X is a string or a name the script sets to one, and only when
  the command did not fail. Rejected: any path-like string in a script that writes something,
  which would count files the script only read; and other interpreters, which no session used.
- (Added after grading the store sessions.) **A session that wrote or named several records
  gets no verdict on the record's steps or on `tier-declared`**: not applicable with an
  `error`, as for a missing commit. `red-first` is still graded, and a `Tier: 0` said somewhere
  in such a session exempts nothing. Rejected: grading against the last record written, which
  would judge one change's record against another's code; grading each change apart is the
  real answer and is a design of its own (Outcome, "Not done").
- (The owner's rulings on the store labels, 2026-11-12, "As recommended" in chat.) Three
  questions the labellers left open. `659da00f` `red-first` stays `fail`: `store/schema.sql` was
  written before any test ran, and the rule holds as written though the task's brief asked for
  that order. `5ac54a69` `red-first` stays `pass`: the run before the first code ran to the end
  and its assertions failed, though every failure was the tool under test not existing yet. A
  session that works on several changes gets no verdict on its record steps until grading is
  done per change, in its labels as from the grader: those six lines of `5ac54a69`'s label file
  now carry no verdict and keep the first pass's reading as their reason.

## Tasks

1. `grade/fields.py`, `grade/labels.py` (the sheet's questions), `bin/transcripts` (`GRADER`), the
   README's grader notes. Test: new cases in `bin/transcripts-grade.test.sh`, one or more per
   fault, on made-up sessions shaped like the fixture ones, and the fixture sessions' own
   verdicts. They fail today because the grader gives the verdicts listed under Probed facts.

## Checks

`bash plugins/change-record/bin/transcripts-grade.test.sh` and the other change-record suites.
Real use: `transcripts accuracy --transcript` on the fifteen fixtures before and after, pasted.
Error path: a session whose commit is missing shows as "could not grade" and is counted
nowhere. The reviewer should attack: a command the new probe rules count that tries nothing
(a false pass is worse here than a false fail), a write wrongly dropped because its path
appears in an error about something else, and a `Change:` line passed in a message whose
description starts somewhere else.

## Outcome

Shipped: `grade/fields.py` follows the four rulings and the lines drawn under Decisions; the
grader is `fields/2`; the sheet's questions and the README say the same. All eight
change-record suites pass here (`transcripts-grade.test.sh` 168, up from 130; `transcripts-judge`
149, `transcripts` 250, `transcripts-store` 82, `record-check` 85, `red-check` 107, `dispatch` 218,
`evals/cases.test.cjs` 25).

Red first: the first test commit (`85c7ba4`) failed 23 assertions on `d454c0a`'s graders, one
group per fault; the second (`512fa85`, for the two faults found later) failed 9.

Guards: 44 were broken by hand, one at a time, in a copy of the plugin, and the suite run.
Five survived the first round (`env` with a command, a relative path, a path inside the tree,
the boundary before a refused path, and `python` not being the command the heredoc feeds);
each got a test and all 44 now fail the suite. (The message of commit `04819ec` lists "the
tree itself" among the survivors; it was a guard added with its test, not a survivor.)

### Real use: the fifteen fixture sessions, before and after

    $ transcripts accuracy --transcript plugins/change-record/grade/fixtures/*.jsonl.gz plugins/change-record/grade/fixtures/evals/*.jsonl.gz

Before (`fields/1`, at `d454c0a`):

    | Step | Labelled | Agree | False fail | False pass | False n/a |
    | tier-declared | 2 | 2 | 0 | 0 | 0 |
    | probe-before-record | 15 | 11 | 3 | 1 | 0 |
    | record-before-code | 15 | 15 | 0 | 0 | 0 |
    | red-first | 15 | 15 | 0 | 0 | 0 |
    | change-line | 15 | 13 | 0 | 2 | 0 |
    | record-check | 15 | 15 | 0 | 0 | 0 |
    | outcome-filled | 15 | 9 | 0 | 0 | 6 |

After (`fields/2`):

    | Step | Labelled | Agree | False fail | False pass | False n/a |
    | tier-declared | 3 | 3 | 0 | 0 | 0 |
    | probe-before-record | 15 | 15 | 0 | 0 | 0 |
    | record-before-code | 15 | 15 | 0 | 0 | 0 |
    | red-first | 15 | 15 | 0 | 0 | 0 |
    | change-line | 15 | 15 | 0 | 0 | 0 |
    | record-check | 3 | 3 | 0 | 0 | 0 |
    | outcome-filled | 3 | 3 | 0 | 0 | 0 |

    ## Disagreements

    None.

This is no independent result: the rules were written from these fifteen sessions and their
labels, so agreement on them shows the rules do what was meant, not that they are right on
the next session.

Error path, in the same output: the twelve fixture sessions that have a record and no commit
are now listed three times each under "Not counted" and counted nowhere, for example

    - 4c14e156-58e9-4138-8bc2-a3e13e9b00fa, record-check: the grader could not grade it (no commit for the session)
    - 4c14e156-58e9-4138-8bc2-a3e13e9b00fa, outcome-filled: the grader could not grade it (no commit for the session)

### Real use: the five store sessions, labelled for the first time

The five sessions in the store were rebuilt in this container on 2026-11-11 for the owner's
read check (record `2026-11-09-skill-transcripts`, Outcome); that folder was still here, so
nothing was read from the store again. Three fresh Claude sessions labelled them from sheets
(`transcripts sheet <folder> --repo-dir .`), barred from the graders and their scores as for the
fixtures, and told the four rulings. The label files are in `grade/labels/`, marked as a
model's first pass for the owner to adjudicate. These five were not used to write the rules
above, so the first run on them is the one independent check this change has:

    $ transcripts grade <folder> --repo-dir . && transcripts accuracy <folder> --labels <labels>

With the fixes for the fixture faults only (`5c28a37`), and identically with `fields/1`:

    | Step | Labelled | Agree | False fail | False pass | False n/a |
    | tier-declared | 5 | 4 | 1 | 0 | 0 |
    | probe-before-record | 5 | 4 | 0 | 0 | 1 |
    | record-before-code | 5 | 4 | 0 | 0 | 1 |
    | red-first | 5 | 4 | 0 | 0 | 1 |
    | change-line | 5 | 4 | 0 | 0 | 1 |
    | record-check | 5 | 4 | 0 | 0 | 1 |
    | outcome-filled | 5 | 4 | 0 | 0 | 1 |

So the fixes for the fixture faults changed nothing on real sessions: eight wrong verdicts
before, the same eight after, all in two sessions and from two causes the fixtures do not
have.

- `659da00f` (the `store` task's session): it edited its record with `python3 - <<'EOF'` and
  `open(p, 'w')`, which the grader did not see, and it was cut off before it opened a pull
  request, so nothing tied it to its record. It was graded as a session with no record:
  `tier-declared` failed ("code written with no record and no Tier: 0") and `record-check` was
  not applicable. This is the same false fail the first report printed on 2026-11-11.
- `5ac54a69` (the long session that ran the whole change): it wrote three records and named
  two, so it was tied to none and graded as having none. Five steps were not applicable where
  the label has a verdict, and `tier-declared` passed for a reason that is false: the session
  "declares Tier: 0" because one of its messages explains what `Tier: 0` is.

Both are fixed in this change (Decisions, the two added ones), each test first. After:

    | Step | Labelled | Agree | False fail | False pass | False n/a |
    | tier-declared | 4 | 4 | 0 | 0 | 0 |
    | probe-before-record | 4 | 4 | 0 | 0 | 0 |
    | record-before-code | 4 | 4 | 0 | 0 | 0 |
    | red-first | 5 | 5 | 0 | 0 | 0 |
    | change-line | 4 | 4 | 0 | 0 | 0 |
    | record-check | 4 | 4 | 0 | 0 | 0 |
    | outcome-filled | 4 | 4 | 0 | 0 | 0 |

    ## Not counted
    - 5ac54a69-3ba4-5369-bb2d-6980aeb1a0d6, tier-declared: the grader could not grade it (the session wrote or named 3 records; the graders tie a session to one)
    ...the same for its five record steps

That second table is, again, agreement on sessions the rules were then fitted to. The honest
measure of `fields/2` is the next set of sessions labelled before anyone looks at its verdicts.

### What the twenty labelled sessions cover

A session covers a step when its label or the grader gives a verdict and the grader could
grade it. Over the fifteen fixtures and the five store sessions, with `fields/2`:

    | Step | Covered | Wrong | Both n/a | Could not grade |
    | tier-declared | 4 | 0 | 3 | 13 |
    | probe-before-record | 10 | 0 | 9 | 1 |
    | record-before-code | 9 | 0 | 10 | 1 |
    | red-first | 15 | 0 | 5 | 0 |
    | change-line | 12 | 0 | 7 | 1 |
    | record-check | 3 | 0 | 4 | 13 |
    | outcome-filled | 2 | 0 | 5 | 13 |

`tier-declared`, `record-check` and `outcome-filled` are still under the five covered sessions
the report asks for before it prints an error, so they stay "not yet checked". They need the
session's commit, the fixtures have none, and of the five store sessions one is empty and one
has several records. Labelling the five did not close that gap; more captured sessions with
commits will.

### Not done, for the owner

- The store labels are a model's first pass. The owner ruled on the three questions the
  labellers left open (Decisions); the other verdicts agree with the graders and were not
  looked at one by one by a person.
- A session that works on several changes is not graded on its records at all. Grading each
  change of a session apart would need the session split by record, which is a design of its
  own.
- Three labellers said the sheet cuts a long record (the last 218 lines of one), so their
  `record-check` labels lean on the session's own `record-check` runs. Two also saw the
  session run the graders on itself inside the transcript. The sheet should show the whole
  record; hiding a session's own grader output is harder.
- A last message that holds a description and no `Change:` line at all is still not applicable
  (Decisions).
- `5ac54a69`'s label was made from its first 6,281 lines. The session went on, so on a folder
  rebuilt today the label is stale and is left out, as designed.
- The inline-script rule reads Python only, and takes the command's starting directory, not a
  `cd` earlier in the same command.
