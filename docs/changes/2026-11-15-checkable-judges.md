---
id: 2026-11-15-checkable-judges
tier: 2
status: approved
requester: Patrick Priestley, in chat on 2026-11-15 ("Can we do this next and then fix the verbosity and code/test quality judges?"; "this" was user-level capture, record 2026-11-15-user-level-capture, since done)
approvers: [Patrick Priestley, 2026-11-15]
---
# The two retired judges come back as measures whose every claim can be checked

## Goal

The two questions taken out on 2026-11-12 are asked again in a form that can be checked
claim by claim. For prose: how much of a session's closing message is said twice, each
repeat given as two quotes found in the message. For code and tests: the defects a reviewer
that runs the code reproduced, each as a script that shows the defect at the session's last
commit and not at its base. Neither gives a label such as `verbose` or `block`.

## Probed facts

- Exact source (`plugins/change-record/grade/rubrics/README.md`, and record
  `2026-11-12-session-quality`, Outcome): `verbosity`, asked of Haiku, answered
  `proportionate` for all 14 labelled sessions and was wrong on the 3 labelled verbose;
  `code-quality`, asked of Sonnet with no tools on a diff cut at 60,000 characters, was
  wrong on 4 of 7, each an `approve` where a labeller had reproduced a defect by running
  the code. Both were taken out under that record's C2: wrong on more than one labelled
  session in five.
- Exact source (the label files in `grade/labels/`, the `verbosity:` lines): the reasons
  written for two sessions labelled `proportionate` (`4c14e156`, `bdd53cec`) say that the
  summary's results are said again in the description. That record says the labellers were
  torn on six sessions and the owner ruled "verbose only when most of the summary is said
  again".
- Verified against the real system (a script over the eleven fixture sessions that have a
  `verbosity` label, no model, 2026-11-15): the share of the closing message's sentences
  whose words mostly appear in another sentence is 0.12 to 0.22 for the three labelled
  verbose and 0.00 to 0.17 for the eight labelled proportionate. The ranges overlap; the
  repeats are paraphrases, which word overlap does not see.
- Verified against the real system (Claude Haiku, the same eleven, one call each, $0.02):
  asked to list each point of the closing message with a quote of where it is first said
  and a quote of where it is said again, Haiku's share of points said again does not
  order the sessions as the labels do (0.83 for one labelled proportionate, 0.35 for one
  labelled verbose), and 14 of its quotes were not in the message.
- Verified against the real system (Claude Sonnet, the same question, two calls each, 22
  calls, $0.31): every quote was in the message. The two calls for a session differ by at
  most 0.07 for nine sessions, by 0.13 and 0.19 for the other two. The share, as the mean
  of the two: 0.47, 0.56 and 0.63 for the three labelled verbose; 0.60 and 0.61 for
  `4c14e156` and `bdd53cec`; 0.04 to 0.44 for the other six. No line through that number
  gives the labels: the best one is wrong on two of eleven.
- Verified against the real system (Claude Sonnet with a shell, `Read`, `Grep` and `Glob`,
  in a scratch clone holding only the reviewed commit's history, 2026-11-15, the commits of
  two labelled sessions): told only to review and to block for what it reproduced, it ran
  8 and 7 commands in 50 and 103 seconds ($0.13, $0.16) and approved both, `172fe91d`
  among them, whose label is `block`.
- Verified against the real system (the same, with a method in the brief: read every
  changed file, write down each stated guarantee, try to break each with inputs the tests
  do not use, at least 15 experiments): on `172fe91d` Sonnet blocked ($0.21, 18
  experiments) for content reaching the probe's sample, and Opus blocked ($0.56, 15
  experiments) for exactly the labelled defect, `Shape.add` reading a string that is JSON
  as structure. On `478c69ad`, the one session labelled `approve`, Sonnet blocked ($0.42)
  because a score row's skill name and evidence keys reach the report without redaction,
  against the report's own "every text taken from a row ... passes through the caller's
  redaction". That was run again by this session on `main` as it was then (`cf829ae`, an
  ancestor of today's): a token in a row's skill name is printed in six headings.
- Verified against the real system (the same, with each defect to be left as a script
  that exits 0 only when it shows the defect): Sonnet left two scripts for `172fe91d`
  ($0.36) and three for `478c69ad` ($0.42). Run by this session in fresh clones, all five
  exit 0 at the session's last commit and 1 at its base, none changed the clone, and all
  five still exit 0 on `origin/main` at `36abbcf` (after #80 and #81). What they show: a hostname kept in the probe's
  sample; a temporary file left when the sample cannot be written; `transcripts report`
  ending in a traceback on a row whose evidence is not an object; an address in an
  evidence key printed in the report; an error text with a line break becoming a heading
  in the report.
- Verified against the real system (the four runs with a method on `172fe91d`, counted):
  the labelled defect was named exactly by Opus, in its one run. Of Sonnet's three runs,
  one named it as part of a wider finding ("JSON object keys inside tool output" reach the
  sample) and two did not report it; all three reported other defects in the same file.
- Verified against the real system (Claude Code 2.1.325, a Haiku session started with
  `--settings` holding `{"sandbox": {"enabled": true, "autoAllowBashIfSandboxed": true},
  "permissions": {"deny": ["Read(//home/user/agent-workflow/**)"]}}`): its shell could
  write in its own folder and under the `TMPDIR` it was given (`mktemp -d` worked), could
  not write `/tmp/outside-probe.txt` ("Read-only file system"), could not reach
  `example.com` ("deny network-outbound"), could reach a server it started itself on
  127.0.0.1, and could not read the owner's checkout: `head`, `ls` and `git -C` on it each
  said there was no such file. Without the deny rule it could read it.
- Verified against the real system (Sonnet, the script brief, in that sandbox, on
  `172fe91d`, $0.36, 113 seconds): it ran the suite and 16 experiments and left four
  scripts; none of its commands named the owner's checkout. Run again by this session,
  three exit 0 at the last commit and 1 at the base; the fourth exits 0 at both (it takes
  "no sample written" as the defect, which is also what a commit without the code gives),
  so the rule of R3 drops it.
- Exact source (`claude --help`, 2.1.325): `--max-budget-usd <amount>` is "Maximum dollar
  amount to spend on API calls". Every reviewer run here had it at 3 and none came near,
  so the limit itself has not been seen to stop a run. The outcome evals pass it at 1.
- Exact source (the probe's `review.sh`, kept in the session's scratch folder): the clone
  is made with `git clone --no-hardlinks`, the commit checked out, the `origin` remote
  removed, every ref deleted, the reflog expired and unreachable objects pruned; the brief
  names the two commits and nothing of where the clone came from.
- Verified against the real system (the reviewers' event streams): the reviewers wrote
  scratch files under `/tmp`, outside the clone they were started in. They were run with
  `--permission-mode acceptEdits --allowedTools Bash Read Grep Glob --setting-sources ""`.
- Verified against the real system (the scratch clone, `git rev-list --all`): made by
  cloning, checking out the commit, deleting every ref and pruning, the clone holds the 35
  commits up to `bf0bd4f` and nothing later: no label file, and not the commit that fixed
  the labelled defect.
- Exact source (`bin/transcripts`, `session_commits`): a session's own commits are the
  first-parent, non-merge commits from the newest commit made before its first line to its
  last commit; a session with no commit has none.
- Exact source (record `2026-11-12-session-quality`, C6): what is sent to a model is
  redacted as for the store, Claude only, and the owner chooses which sessions are sent.
- Exact source (`bin/transcripts`, `cmd_judge`): the record judge of today runs with no
  `--session` and no `--limit`, on at most 20 sessions.
- Exact source (`grade/labels.py`, `parse`): a line whose key is not a step or a retired
  rubric is rejected as an unknown line, so a `said-again:` line is rejected today
  whatever it names.
- Exact source (`.github/workflows/pr-agent.yml`): the review bot posts its findings as a
  comment on the pull request. Verified against the real system: Actions has started no
  job for this repository since 2026-11-13, so no such comment exists for any pull request
  since.
- Verified against the real system (`bwrap` in this container, 2026-11-15, no model):
  started with `--unshare-all`, the file system bound read-only, `/tmp`, `/home` and
  `/root` replaced by empty ones, a clone bound writable, and the environment cleared but
  for `PATH`, `HOME` and `TMPDIR`, a shell could write in the clone and under `/tmp`,
  could not write `/usr/outside`, could not see the owner's checkout or anything under
  `/root`, could not resolve `example.com`, had no GitHub login (`gh auth status`: "not
  logged into any GitHub hosts"), and could reach a server it started on 127.0.0.1. The
  five scripts above, run that way against `origin/main` at `36abbcf`, each exited 0 and
  left the clone unchanged. Not probed: a Mac, which has no `bwrap`.
- Exact source (`grade/measures.py`, `last_message`): a session's last message is the last
  text the session itself wrote that is not empty, a subagent's left out. For a session
  cut off in mid-work that is a progress note, and for a `dispatch` child it is addressed
  to the dispatcher. The probes took the same.
- Spent on these probes: $2.96 (33 calls for prose, 8 reviewer runs, 3 sandbox checks).
- Not probed: a reviewer on a change of more than 1,380 lines; a session in another
  repository or another language; closing messages of long sessions (the eleven are eval
  and `dispatch` runs of 6 to 37 calls); repeats across messages, not within the last one;
  the sandbox on a Mac; a repository whose tests need the network.
- Assumed: that a defect script which passes at the last commit and fails at the base
  shows a defect of the change. It could also show intended behaviour the reviewer
  misread; only a person can rule that.

## Problem

Both judges gave a label and were measured by whether the label matched a person's. For
prose the person's labels themselves do not follow one rule, so no judge can match them.
For code the judge could not run anything, and the labellers could. The probes show two
further things: a reviewer that runs code finds real defects only when its brief demands a
method, and once it does, it finds one in the session labelled `approve` as well. So the
only `approve` label there is was wrong, and a verdict has nothing left to be measured
against. Whether a reviewer with a method would block every change of this size is not
known from two sessions; that it blocked both is why the verdict is dropped for the list
of what it showed.

Meanwhile the report has no measure of what a session wrote to the person or of the code
it left, which is half of what record `2026-11-12-session-quality` set out to show.

## Requirements

- R1. `transcripts judge --repeats [DIR] [--session ID]...`, or `--repeats --transcript
  FILE...` for transcript files, asks, for each chosen session, one call of Claude Sonnet
  with the brief of Appendix A and the session's closing message (its last message to the
  person, redacted as for the store). A pair counts only when both quotes are found in the
  message that was sent and differ, compared after removing every backtick and asterisk,
  turning each run of white space into one space and lowering the case, and in no other
  way. It keeps, per session: the points, the pairs, how many quotes were not found, and
  the share of points said again, and which message it took (its place in the transcript
  and its length). The closing message is the one `grade/measures.py` already counts as
  the last. Each pair has an id: the first six hex digits of the SHA-256 of the first
  quote, a line feed and the second quote, both as compared. A session that already has
  an answer for the same brief is not asked again without `--again`. Check: `bin/transcripts-judge.test.sh` with the
  suite's stand-in for `claude` answering from a file: a known answer gives known numbers
  and ids; a quote that is not in the message, a pair whose quotes are the same, an answer
  that is not JSON and a session with no message are each counted apart and not as a pair;
  the brief the stand-in received is Appendix A's text followed by the redacted message.
- R2. `transcripts judge --review [DIR] [--session ID]... --repo-dir REPO` runs, for each
  chosen session whose own commits `session_commits` finds in REPO with a base, a reviewer:
  Claude with a shell, `Read`, `Grep` and `Glob`, the brief of Appendix B,
  `--max-budget-usd 1.5` and 20 minutes. `--model sonnet|opus` says which model; each
  model's answer for a session is kept apart, and a session that already has one for the
  same model and brief is not reviewed again without `--again`. It runs in a scratch clone outside every working
  tree, made as the probe made it (no remote, no ref, no commit after the session's last),
  and in Claude Code's sandbox with reading REPO denied. A session with no commit, or with
  no base (its line began with the session), is not reviewed and says which. The reviewer
  leaves each defect as `.review/defect-N.sh` and names it in its answer with a kind.
  Check: the same suite, with the stand-in given a mode that writes scripts and an answer
  in the folder it is started in: the clone it was started in has no remote, no ref and no
  commit after the last; the brief it received is Appendix B's with the two commits and
  does not hold REPO's path; its settings hold the sandbox and the deny rule for REPO; a
  session with no commit and one with no base are not reviewed, each with its reason.
- R3. The tool copies every script under `.review/` out of the reviewer's clone, named in
  the answer or not. A defect counts as shown only if its script, run by the tool from the
  root of a fresh clone that does not hold the script, in the box of R7, with 120 seconds,
  exits 0 at the session's last commit and not 0 at its base, and `git status --porcelain`
  is empty in both clones after. Every other script is kept and counted under its reason:
  not shown at the last commit, shown at the base too, timed out, changed the clone, named
  in the answer but missing. A script the answer does not name is run like the others and
  marked so. A shown defect's id is the
  first six hex digits of the SHA-256 of its script. A run in which any of the reviewer's
  commands names REPO's path is kept, marked as having looked outside, and its defects are
  not counted. Check: the stand-in leaves one script of each sort and the counts and ids
  are as expected; the scripts and what they printed are under `DIR/reviews/<session>/`.
- R4. The report shows, per session and per skill version: for prose, points, pairs and
  the share said again; for code, defects shown by kind, changed lines (lines added plus
  lines removed between the base and the last commit, as `git diff --numstat` counts them,
  binary files left out), and defects shown per 1,000 changed lines, with a sentence that
  the count is a floor. It gives no label and no pass rate for either. Check: the stored
  expected report, from made-up judge files; the changed lines of a made-up repository.
- R5. Each measure is checked by a person claim by claim. The sheet lists a session's
  pairs and its shown defects with their ids. A label file may carry `said-again: wrong
  <id>... | right <id>...` and `defects: wrong <id>... | right <id>...`. The report gives
  each measure's error as claims ruled wrong over claims ruled, and "not yet checked"
  under ten ruled claims (a number chosen, twice the five sessions the report asks for a
  step). A ruling applies to whichever of the session's present answers holds its id, a
  review's from either model; one on an id no present answer holds (the session was asked
  again and answered differently) is reported as stale and not counted. Check: the stored
  expected report; a label line naming an id of the wrong form is rejected with a reason
  that says so, which is not today's "unknown line"; a stale ruling is listed and not
  counted.
- R6. `--repeats` and `--review` print, before any call, the sessions they will send, how
  many calls (the sandbox check of R7 among them), and the most they can spend, and make
  none without `--session` or `--limit N`. The record judge's default of today is not changed. Check: the same suite: with
  neither, the stand-in is never run and the message names the two options, which is not
  today's usage error.
- R7. Before the first review of a run, `--review` checks the reviewer's sandbox with one
  Haiku call in it: writing a file beside its folder (in the folder's parent, which is
  neither its folder nor its temporary folder) and reading `.git/HEAD` of REPO must both
  fail, or nothing is reviewed and it says which did not. The tool runs the scripts in a
  box of its own, `bwrap` as probed: no network, the file system read-only but for the
  fresh clone and an empty `/tmp`, REPO and the home folders hidden, the environment
  cleared. Where there is no `bwrap` it refuses to run them unless `--local` is given, and
  says that the scripts would then run with the owner's own access. Check: the same suite:
  a stand-in whose check finds either one possible stops the run with that message; a
  script that writes outside its clone, reads REPO or names a variable of the caller's
  environment is seen to fail at it; with `bwrap` taken off `PATH`, the refusal by its
  message.
- R8. The retired labels stay as they are: a `verbosity:` or `code-quality:` line still
  loads and counts for nothing, and `judge --rubrics` still refuses. Check: the existing
  assertions pass unchanged; this is a guard on what is there, with no red step.

## Options and concerns

Options considered, for prose:

- A. Ask a stronger model for the label. Not recommended: the labels do not follow one
  rule (Probed facts), so the measurement would again be of the labels.
- B. Count repeats in code, with no model. Rejected: word overlap does not see a
  paraphrase, and the ranges overlap.
- C. A model lists the points and their repeats with quotes; code checks the quotes and
  counts. Recommended: stable between calls on Sonnet, and each pair can be ruled right or
  wrong by reading two quotes.

For code:

- D. The old judge with a larger diff or a stronger model. Rejected: the measurement of
  2026-11-12 says the gap is running the code, not reading more of it.
- E. A reviewer with tools and a verdict. Rejected: with a method it blocked the session
  labelled `approve` too, for a real defect, so the labels cannot measure a verdict; and a
  verdict hides which defect, which is the part a person can check.
- F. A reviewer with tools that leaves each defect as a script the tool runs again at the
  last commit and at the base. Recommended: eight of nine scripts held up in the probes,
  and the ninth was dropped by the rule, as it should be.
- G. No judge: count what the review found on each pull request. Rejected for this change:
  the bot's findings are prose in a comment that no tool has checked, and there has been
  none since 2026-11-13 (Probed facts).
- H. As F, but the reviewer adds a failing test to the repository's own suite, which
  `red-check` could verify. Rejected: it needs each repository's test command and runner,
  and a script that makes its own inputs needs neither.
- I. The reviewer in a container instead of the CLI's own sandbox. Not recommended: the
  CLI's sandbox was seen to do what is needed for a Claude session and needs nothing
  installed. The scripts are not run by a Claude session, so they get `bwrap`, which is
  what that sandbox is built on here.
- J. The scripts run again with no box, in a cloud session only. Rejected after the second
  review: a cloud session has the owner's access to GitHub, and a thrown-away machine does
  not take a push back.

Concerns:

### C1: prose is reported as a number, not as verbose or proportionate
The share of the closing message said again does not reproduce the 2026-11-12 labels, and
this change stops trying to. Failure case: the owner reads "0.61" where they wanted to be
told which sessions were padded, and the fourteen verbosity labels are never used again.
The alternative is to keep a label and write the rule into it (verbose when more than half
the points are said again), which makes the label a restatement of the number.
Recommended: the number, the pairs behind it, and no label. It covers the closing message
only; repeats across a long session's messages are not counted (not probed). Owner:
Patrick Priestley.
Resolved: the number and the quoted pairs, no label, as recommended. Patrick Priestley, in
chat, 2026-11-15.

### C2: code is reported as defects shown, not as approve or block
Only what a script can show is counted: behaviour. Design, naming, complexity and a change
that belongs elsewhere, which the old rubric also asked about, are not reported at all,
and test quality only as a defect of kind "test cannot fail". Failure case: a session
whose code is correct and badly shaped reads as clean. A second one: the reviewer finds
different defects on different runs (Probed facts: four runs on `172fe91d` gave four
different lists), so "0 shown" is weak evidence of none. Recommended: accept the
narrowing, report defects shown per 1,000 changed lines beside the count, and say in the
report that the count is a floor. Tests judged by hand-made mutants (the reviewer breaks
the code and the tool checks which breaks the tests notice) are a later change, not probed
here. A measure is taken out, as before, if more than one in five of its ruled claims is
wrong. Owner: Patrick Priestley.
Resolved: defects shown, as recommended; mutants are a later change. Patrick Priestley, in
chat, 2026-11-15.

### C3: which model, what it may spend, and on which sessions first
In the probes Sonnet with the method cost $0.21 to $0.42 a session and Opus $0.56. On the
one session tried with both, Opus named the labelled defect exactly in its one run;
Sonnet, in three runs, named it once as part of a wider finding and missed it twice,
finding other real defects each time. One session cannot say which model shows more that
a person rules real. Prose is one Sonnet call, about $0.015. Failure case: the cheaper
model is chosen on that one session and shows mostly minor defects; or a run over every
captured session costs tens of dollars. Recommended: prose on Sonnet; the review measured
with both Sonnet and Opus on the seven sessions labelled for code quality, and the one
with more defects ruled real for each dollar kept as the default; at most $1.50 a session
and 10 sessions a run; $30 for building and measuring this change, of which the limits
alone allow $21 for the fourteen reviews and the probes' prices make about $7 likely. The first measurement
is on sessions already sent to a model for these questions: the eleven fixture sessions
for prose, the seven for the review. The owner rules on every pair and every shown defect
of those, after a model's blind first pass, as on 2026-11-12. Owner: Patrick Priestley.
Resolved: both models measured and one kept, with the limits as recommended. Patrick
Priestley, in chat, 2026-11-15.

### C4: the reviewer has a shell, and reads the repository as it is
It runs the session's code and whatever else it types; without a sandbox it wrote outside
its clone and could read the owner's checkout, where the labels and the later fix are.
Failure case: a command of the reviewer's, or one of its scripts when the tool runs it
again, removes or sends something of the owner's, on a laptop or, in a cloud session,
through the session's access to GitHub; or the reviewer reads the answer and the
measurement means nothing. In the probes neither could: the reviewer in Claude Code's
sandbox, and the scripts in a `bwrap` box, had no network, no write outside the clone and
a temporary folder, and no sight of the owner's checkout. A second failure case, which
conflicts with C6 of record `2026-11-12-session-quality` ("redacted as for the store"):
the reviewer reads the clone's files unredacted and what it reads goes to the model; a
session that committed a fixture holding a real address sends it. The old judge was shown
a redacted diff. Recommended: both boxes as probed, the sandbox checked before each run
(R7), a run whose commands name the owner's checkout not counted, and no `--review` on a
Mac without `--local` until a box for the scripts is probed there. On redaction: accept
that a review sends repository files as they are, because it is run only on sessions the
owner names, in repositories the owner already works in with Claude Code, whose files
those sessions sent the same way; say so in the README. Owner: Patrick Priestley.
Resolved: boxed as probed, `--local` for a machine with no `bwrap`, and repository files
sent as they are. Patrick Priestley, in chat, 2026-11-15.

### C5: the defects the probes found on `main`
Six were shown and still hold on `origin/main` at `36abbcf` (Probed facts): in
`probe/agent_sample.py`, a hostname kept in the sample and a temporary file left behind;
in `grade/report.py` and `grade/labels.py`, a traceback on a row whose evidence is not an
object, an evidence key printed without redaction, a row's skill name printed without
redaction, and an error text's line break becoming a heading. Three more from the
sandboxed run are shown and not yet run against `main`. Failure case: the next
`transcripts report` on real rows prints an address, or a probe sample with a hostname is
committed, and no change is on record to fix either. None is fixed by this change.
Recommended: one tier 1 change for the two leaks in the report and the traceback, one for
the probe's two, built after task 2 of this record and before task 4, so that the review
is not measured on defects already known; the heading is left on the list. Owner: Patrick
Priestley.
Resolved: two tier 1 changes between tasks 2 and 4, as recommended. Patrick Priestley, in
chat, 2026-11-15.

## Decisions

- A claim, not a session, is the unit that is checked. Rejected: a label a session, as
  before; it needed labels that follow one rule and sessions of both kinds, and had
  neither.
- The quotes of a pair are checked in code against the redacted message the model was
  sent, compared as R1 says and as the probe compared them. Rejected: trusting them; Haiku
  gave 14 that were not there.
- A ruling names a claim by an id made from the claim's own content, not by its place in
  a list. Rejected: numbers; a session asked again gives its claims in another order, or
  other claims, and a ruling would land on the wrong one.
- A defect must fail at the base. Rejected: the last commit alone, under which a script
  that always exits 0, or a defect the session inherited, would count against it.
- The reviewer's clone holds only the history up to the last commit and has no remote,
  and the sandbox denies reading the owner's checkout, so a later fix or a label file
  cannot be read from the clone or beside it. Rejected: a worktree of the owner's checkout.
- One call for prose and one run for the review, no votes. Rejected: three votes, as the
  old judges had; claims that are each checked do not need a majority, and the cost is a
  third.
- The two briefs are Appendix A and Appendix B, word for word as probed, and each is
  kept as one file under `grade/briefs/` that the tests compare with what the stand-in
  received. Rejected: leaving depth to the model; without the method Sonnet approved in
  under a minute.
- The 2026-11-12 labels for the two rubrics are kept and not converted. Rejected: turning
  each `verbosity:` reason into `said-again:` rulings; the reasons quote a passage or two
  and name no pair. The labelled defects of six sessions are used once, to say how many of
  them the review also shows; that count is reported and removes nothing.
- The tool, not the reviewer, decides what is shown, and it runs the scripts where they
  can reach nothing of the owner's. Rejected: taking the reviewer's word that it ran them.
- An answer is kept until `--again`, and a review's answers are kept per model, so that
  rulings made on one run are not lost to the next and two models can be compared on the
  same sessions.
- Decided while building task 1. `--repeats --transcript FILE...` takes `--out DIR` for the
  answers, as `sheet --transcript` does; R1 named no place for them. A kept answer is for
  the message it was given: when the session has since written a later one it is asked
  again, with no `--again`. A point that is not an object counts among the quotes not
  found, and a pair listed twice counts once, as the probe counted them. The model's
  answer is kept redacted as well as the message, since a model can write what it was not
  sent. One call may spend 25 cents (`--max-budget-usd 0.25`), sixteen times what a call
  has cost.

## Tasks

One pull request each, built in this order by one session; they are not written for
`dispatch`. The stand-in for `claude` in `bin/transcripts-judge.test.sh`
answers from a fixed script and writes no file; tasks 1 and 2 give it two modes, one that
answers from a file named in its environment and one that writes `.review/` scripts and
an answer in the folder it is started in, and records its arguments, its settings file,
its standard input and that folder's git state.

1. **Repeats.** `judge --repeats`, its judge file, the quote check, the ids, `grade/briefs/
   repeats.md`. Test: `bin/transcripts-judge.test.sh`. Red today: `--repeats` is a usage
   error, so every assertion on numbers, ids and the brief fails; R6's assertion fails on
   the message.
2. **Review.** `judge --review`: the clone, the sandbox and its check, the brief, the
   scripts copied out and run again at the last commit and the base, `--local`,
   `grade/briefs/review.md`. Test: the same suite. Red today: `--review` is a usage error;
   R7's assertions fail on their messages.
3. **Report and labels.** The two measures in the report and the sheet, the `said-again:`
   and `defects:` lines, each measure's error, stale rulings. Test: the stored expected
   report. Red today: the report names neither, and a `said-again:` line is rejected as an
   unknown line where the test asks for the reason of R5.
Between tasks 2 and 4, as C5 was resolved: two tier 1 changes of their own, each with its
own record, for the defects the probes showed on `main` (the report's two leaks and its
traceback; the probe's hostname and its temporary file).

4. **Measured.** Both run for real on the sessions of C3, the claims ruled, the numbers in
   the README and in Outcome; a measure wrong on more than one ruled claim in five is
   taken out in this same task. It has no test of its own: it is the measurement. It
   needs the seven sessions' index entries, which are in the store: rebuilt with
   `materialize` and the read key, through the `agent-workflow-admin` environment as on
   2026-11-12, which needs the owner's leave again.

## Checks

`bash plugins/change-record/bin/transcripts-judge.test.sh` and the other change-record
suites. Rule 6 of `RULES.md` asks for a review by another model family: the PR-Agent job
has not run since 2026-11-13 and `agent-review` has no key in this session, so until
either is back each pull request gets a fresh session's read only, and says so. Real use: task 4 is the real use, on real sessions with the real models; before
it, one real session through each command in tasks 1 and 2. Error path: a reviewer that
leaves a script which passes at the base. The independent reviewer should attack: a pair
or a defect counted that the text or the code does not bear out; a reviewer able to read
the answer (a later fix, a label) from its clone; and a run that spends without the owner
having chosen the sessions.

## Review

Two rounds, each by a fresh session with no context but the record and the repository
(`plugins/change-record/bin/record-review`), on 2026-11-15. Each finding was checked
against the repository.

Round one: 8 important, 3 minor, all fixed. The briefs were nowhere a builder could read
them: they are Appendix A and B. A count that favoured Sonnet was wrong: the four runs are
now counted one by one, and C3 measures both models. Rulings by number would land on the
wrong claim after a second run: claims have ids made from their content. The reviewer's
isolation was asserted, not specified: the clone's steps are listed, and a probe showed
Claude Code's sandbox denying writes, network and the owner's checkout. Which commands
need `--session` or `--limit`, how spending is limited, a session with no base, and three
checks that would have passed today for the wrong reason: R2, R5, R6, R7.

Round two: 1 critical, 8 important, 14 minor. Critical, fixed: the scripts were to be run
again with no box in a cloud session, which has the owner's access to GitHub; they now
run in a `bwrap` box, probed (R7, option J). Important, fixed: no way to run Opus, and one
model's answer replacing the other's (R2, R5); whether a session is asked again (R1, R2);
the defects found on `main` had no owner (C5); the reviewer reads the repository
unredacted, against C6 (C4); a trend claimed from two sessions (Problem, option E); a
commit a reader could not find (the scripts were run again at `36abbcf`); no numbers for
the limits (R2, R3); which message is the last (R1). Minor, fixed: where the unknown-line
check lives; the reason given for ten claims; R8 named as a guard; a rejected alternative
for the old labels; a script the answer does not name; what the sandbox check writes; how
an id is made; the check counted among the calls; the requester's "this"; rule 6 of
`RULES.md`; the order of the tasks; the budget against its own limits. Not changed: the
probe's `review.sh` is not in the repository, so the steps R2 lists are the specification.

Open: these last fixes have not been read by a fresh session.

## Appendix A: the brief for repeats, as probed

The session's closing message follows the last line.

    Below is the last message a coding agent wrote to a person at the end of a session. Do not judge it. Take it apart.

    1. List every distinct point the message makes: a fact, a result, a decision, a caveat, an instruction to the reader. A point is what is said, not how: two passages that tell the reader the same thing in different words are one point said twice. Headings and blank scaffolding are not points.
    2. For each point, give "first": a short exact quote (5 to 15 words, copied character for character from the message) of where it is first said, and "again": an exact quote of where the same thing is told a second time, or null when it is said only once. A later passage counts as "again" only if a reader who had read the first would learn nothing new from it.

    Answer with one JSON object and nothing else:
    {"points": [{"first": "...", "again": "..." or null}, ...]}

    ----- the message -----

## Appendix B: the brief for the review, as probed

`@BASE@` and `@HEAD@` are the first ten hex digits of the session's base and last commit.

    You are reviewing a change in this repository: the commits @BASE@..@HEAD@. @HEAD@ is checked out;
    `git diff @BASE@ @HEAD@` is the change and `git log @BASE@..@HEAD@` its commits.

    Review the code and its tests the way a careful senior reviewer would. Unlike a reader of a
    diff you can run it: this is a scratch clone, you may run anything in it and write scratch
    files (do not commit). Find defects by trying the code: unusual inputs, error paths, the
    guarantees its comments, tests and documentation claim. Judge code and tests, not the process
    that produced them, and not documentation except where it contradicts the code.

    Method, all of it required:

    1. Read every changed code file in full, not only the diff, and the tests that came with it.
    2. For each thing the change adds that is called from outside (a command, an option, a
       function other code calls), write down the guarantees it states: in its docstring, its
       comments, its usage text, the names of its tests, the README.
    3. For each guarantee, try to break it with inputs the tests do not use. Look at what the
       tests feed the code, then feed it something else: nested where they are flat, empty,
       very long, the wrong type, hostile content inside otherwise valid input, a second run
       after a first, a failure half way.
    4. Do not stop before you have run at least 15 such experiments. A guarantee you could not
       break after two honest tries is fine; say so and move on.

    Defects. Report a defect only if you reproduced it, and leave the reproduction as a
    script: `.review/defect-1.sh`, `.review/defect-2.sh`, and so on, in this clone. Each script
    is run with bash from the repository's root, in a fresh clone of the same commit, with
    nothing else of yours there: it makes its own inputs in a folder from `mktemp -d`, runs the
    repository's code, prints what it saw, and exits 0 if and only if it saw the defect (exit 1
    when the code behaves correctly). It must not pass by default: on a commit where the defect
    is fixed, or where the code does not exist, it exits 1. Run each script yourself before you
    report it. A suspicion you could not turn into such a script goes under "unverified".

    End with a last message that is one JSON object and nothing else:
    {"defects": [{"script": ".review/defect-1.sh", "file": "path", "kind": "wrong result" or "crash" or "data lost or leaked" or "stated guarantee broken" or "test cannot fail" or "other", "what": "one or two sentences", "guarantee": "where the code or its documents promise otherwise, quoted, or null"}],
     "unverified": ["..."],
     "experiments": ["one line each: what you tried and what happened"]}

## Outcome

### Task 1: repeats

Built test first: 27 assertions of `bin/transcripts-judge.test.sh` failed before the code
(`--repeats` a usage error), committed red, then `grade/repeats.py`, `grade/briefs/
repeats.md` and `cmd_repeats` in `bin/transcripts`. One assertion then failed for a reason
of the code's own: the model's answer was kept as given, and the stand-in's answer held an
address. Suites after: transcripts-judge 266, transcripts 350, transcripts-grade 212,
transcripts-store 156, none failing.

Guards shown by breaking them by hand, one at a time: 34 breaks. 30 were caught. Four
survived and each was a gap in the tests, now closed and the break seen caught: a run that
failed with a well-formed answer was read as an answer; the judge's call inheriting the
caller's environment, and running in the caller's folder (the assertions for both could
not fail); and a kept answer being used for a later closing message.

Real use, in this container, Claude Sonnet, on three fixture sessions of this repository
(made-up eval runs): one labelled verbose on 2026-11-12, one proportionate, one that wrote
no code.

```
$ transcripts judge --repeats --transcript eval-04-d7098b89.jsonl.gz eval-09-9d1fcbcc.jsonl.gz eval-06-831141da.jsonl.gz --out <scratch>
transcripts: 3 sessions to send to Claude Sonnet, 3 calls, at most $0.75: d7098b89, 9d1fcbcc, 831141da
d7098b89 repeats: 10 of 18 points said again (0.56)
9d1fcbcc repeats: 1 of 14 points said again (0.07)
831141da repeats: 2 of 11 points said again (0.18)
transcripts: repeats asked of 3 sessions into <scratch>/repeats, $0.04
$ the same again, for the first two
transcripts: repeats asked of 0 sessions into <scratch>/repeats, $0.00; 2 already answered
$ transcripts judge --repeats <scratch>
transcripts: nothing was sent: choose the sessions whose closing message goes to Claude Sonnet with --session ID or --limit N (the newest N)
exit 2
```

The first two shares are the probe's (0.56, 0.07). Each answer was served by
`claude-sonnet-5-5`, every quote was found, and the calls cost $0.011 to $0.020. Two of the
pairs it kept, as a person would be shown them:

```
34282d | `greet.py` now takes `--shout` and prints the greeting in upper case. => `python3 greet.py [name] [--shout]` prints the greeting in upper case
4c9a82 | I fixed the typo, but I couldn't commit it. => It's unstaged in the working tree.
```

The first is one point said twice. The second is arguable, which is what the rulings of
task 3 are for. Spent on this task: $0.04.

Not done here: the report and the sheet do not show the measure yet (task 3), and no claim
has been ruled (task 4).
