---
id: 2026-11-12-portable-evals
tier: 1
status: done
requester: Patrick Priestley, in chat on 2026-11-12 ("Yes, generate the evals.json", then "Yes, add the verification script")
approvers: []
---
# The change skill's eval cases are also kept as an `evals.json`, generated from the case folders

## Goal

The eight eval cases of the `change` skill exist only in the layout `claude plugin eval` reads.
Generate from them the `evals/evals.json` the open Agent Skills guide describes, so the same
cases can be given to tools and agents that are not Claude's, and keep the two from drifting.

## Probed facts

- Exact source (`agentskills/agentskills` at `83021e2`, 2026-11-04,
  `docs/skill-creation/evaluating-skills.mdx`, cloned 2026-11-12): test cases are stored in
  `evals/evals.json` inside the skill directory. The file is `{"skill_name", "evals": [...]}`
  and each entry has `id` (a number in the examples), `prompt`, `expected_output`, an optional
  `files` list of paths relative to the skill directory (`evals/files/...`), and `assertions`,
  a list of plain statements. The guide says how to run a case (once with the skill, once
  without, each in a clean context) and that an assertion is graded pass or fail with
  evidence, by a model or by a script. It defines no runner, no grader types, no place for a
  setup script, and does not say where input files land in the working folder.
- Exact source (`agent-skills-eval` 0.1.1 from npm, `README.md` and `dist/skill.js`, read
  2026-11-12): this third-party runner reads `skill_name`, `evals[].id`, `prompt`,
  `expected_output`, `files` and `assertions`, also reads an optional `name` per entry, and
  takes the fields it knows from an entry without rejecting others. It checks that the name in
  `SKILL.md` matches the skill's folder. It sends each prompt to a chat model with the skill in
  context (`--target gpt-4o-mini` in its quickstart): it does not drive an agent that edits
  files or runs commands.
- Exact source (the skill-creator reference installed in this session, `references/schemas.md`):
  it calls `evals.json` the older format, reads `assertions` or `expectations`, and takes a
  test's label from `eval_name` or `name`.
- Verified against the real system (`claude plugin eval --help`, Claude Code in this container,
  2026-11-12): it runs `<eval dir>/**/case.yaml` below the plugin, `evals/` by default, so a
  folder `skills/change/evals/` is outside what it reads.
- Exact source (`plugins/change-record/evals/`): eight cases; every `scaffold.sh` runs the same
  `_scaffold/greet.sh`, which writes six files and makes one commit. Each case has a
  `skill-fired` grader, which the README calls an activation indicator and not part of the
  score, and 29 scored graders in all: 7 `llm`, 14 `regex`, 5 `file_exists`, 3 `tool_used`. Nine
  of the regex and tool graders read the trace of calls, not a file or the last message.
  Comment lines inside a grader's top block are already there in several graders and ran on
  2026-11-08.
- Assumed: a runner or agent given `files` makes them available to the run with their folder
  structure kept. The guide does not say, and no agent run was made here.

## Decisions

- **The case folders stay the source; `evals.json` is generated.** `evals/export-evals-json`
  writes it, and `--check` fails when the committed file is not what the folders give.
  Rejected: writing the file by hand, which drifts the first time a prompt changes.
- **It goes where the guide puts it**: `skills/change/evals/evals.json`, with the input files in
  `skills/change/evals/files/repo/`. Rejected: beside the case folders, where no tool that
  follows the guide would look.
- **Each scored grader carries its own statement**, as a comment line `# assertion: ...` in its
  top block, and that line becomes the entry's assertion. Rejected: deriving statements from
  the patterns, which cannot be done; and a separate list, which is a second place to forget.
  The `llm` graders' "PASS if ... FAIL if ..." is restated as one statement for the same reason
  the guide gives: an assertion is a statement about the output.
- **`skill-fired` is left out.** It asks whether Claude's Skill tool was called, which is not
  part of the score and means nothing in another agent.
- **Assertions about what the agent did, not what it left behind, begin "The transcript
  shows".** The guide grades outputs; these seven need the run's transcript, and the wording
  makes a grader without one say so instead of guessing. Two trace graders that only ask that
  a file was left alone are stated about the file.
- **The input files are the scaffold's six files, kept as plain files**, and each prompt
  begins with one sentence saying they are the repository. Rejected: carrying the scaffold
  script, which the format has no field for. The copy has no git history; no case's
  assertions read it.
- **Each entry also has `name`, the case folder's name.** It is outside the guide, both tools
  read above accept it, and without it an entry is only a number. Ids are 1 to 8 in the
  folders' alphabetical order.
- What is lost is written in the README: typed graders become statements a judge reads, and
  the with-and-without comparison is the runner's to make.
- (Task 2, the owner's "Yes, add the verification script".) **The statements code can check
  are checked by a script, as the guide asks**: `skills/change/evals/verify EVAL OUTPUTS` reads
  the folder a run left and answers in the shape of the guide's `grading.json`, with no model.
  It lives in the skill's folder and uses only Python's standard library, so it travels with
  `evals.json`. Rejected: a script beside the case folders, which a copy of the skill would
  not carry.
- **What it checks is generated too**: `export-evals-json` also writes `evals/checks.json`, one
  entry per statement that code can check, taken from the grader itself (a `file_exists`
  grader's path; the pattern, flags and sense of a `regex` grader that reads a file or the
  last message). Two graders read the trace but are stated about a file (no record created,
  `greet.py` unchanged); each carries a `# check:` line saying how, since the trace pattern
  cannot be turned into a file check. Rejected: writing the checks by hand in the script,
  which would be a third copy of each grader to keep in step.
- **It checks 13 statements from the files alone and 2 more when given the run's final
  message** (`--final-message FILE`), since the guide does not say where a runner keeps that
  message. The other 14 are listed as not checked, with why: seven need a judge and seven
  need the transcript. Rejected: reading transcripts here; each agent writes its own format,
  and reading them is what `2026-11-11-codex-cursor-capture` is for.
- The patterns are the graders' own, written for JavaScript's regular expressions and run
  here by Python's. The ones that reach `checks.json` use only what both read alike; a test
  compiles each one.

## Tasks

1. `evals/export-evals-json`, the `# assertion:` lines in the 29 scored graders, the generated
   `skills/change/evals/`, and the README. Test: new checks in `evals/cases.test.cjs` (every
   scored grader has one statement, the committed file is what the generator gives and has the
   guide's shape, `--check` fails on drift). They fail today because the script and the
   statements do not exist.

2. `skills/change/evals/verify`, `evals/checks.json` from the generator, and the two `# check:`
   lines. Test: new checks in `evals/cases.test.cjs` on made-up output folders (a record that
   is there, missing, of the wrong tier, with its sections out of order; an extra file under
   `docs/changes/`; a changed `greet.py`; with and without the final message). They fail today
   because neither file exists.

## Checks

`node --test plugins/change-record/evals/cases.test.cjs` and the other change-record suites.
Real use: generate, then load the skill folder with a third-party runner's own loader and
paste what it read. Error path: `--check` on a changed prompt. The reviewer should attack: a
statement that says more or less than its grader checks, a grader with no statement passing
the test, and the generated files differing from what the scaffold writes.

## Outcome

Shipped: `evals/export-evals-json`; a `# assertion:` line in each of the 29 scored graders;
the generated `skills/change/evals/evals.json` (8 cases, 29 assertions, 7 of them about the
transcript) and `skills/change/evals/files/repo/` (6 files); a section in the evals README.
`cases.test.cjs` goes from 25 tests to 32, and every other suite passes unchanged
(`transcripts-grade` 168, `transcripts-judge` 149, `transcripts` 250, `transcripts-store` 82,
`record-check` 85, `red-check` 107, `dispatch` 218, the root `install.test.sh` 112).

Red first: the test commit failed five tests (no statements, no generator, no generated
files). Guards: 19 were broken by hand in a copy of the plugin, one at a time, and the tests
run; all 19 failed them in the first round.

### Real use

    $ plugins/change-record/evals/export-evals-json
    export-evals-json: wrote 8 cases to .../plugins/change-record/skills/change/evals/evals.json and 6 input files
    $ plugins/change-record/evals/export-evals-json --check; echo $?
    0

One entry, as written:

    {
      "id": 6,
      "name": "red-first",
      "prompt": "The repository for this task is the folder `repo/` of the input files (greet.py, tests/ and docs/changes/). Work in a copy of it, with that copy as the working directory.\n\nQuick one before I head out, don't overthink it: add a `--shout` flag to greet.py ...",
      "expected_output": "A small feature under time pressure; the agent should write a test and see it fail before changing greet.py.",
      "files": ["evals/files/repo/README.md", "evals/files/repo/docs/changes/README.md", "evals/files/repo/docs/changes/TEMPLATE.md",
                "evals/files/repo/greet.py", "evals/files/repo/tests/__init__.py", "evals/files/repo/tests/test_greet.py"],
      "assertions": [
        "The transcript shows a run of the unit tests that reported a failing or erroring test before greet.py was first changed.",
        "The transcript shows the unit tests were run before greet.py was first changed, in an earlier command than the change."
      ]
    }

Error path, in a scratch copy with one word of a prompt changed in `evals.json` and one input
file changed (from the tests):

    export-evals-json: evals/evals.json is not what the case folders give
    export-evals-json: evals/files/repo/greet.py differs from what the scaffold writes
    export-evals-json: run export-evals-json to write them again        (exit 1)

Claude's own runner still reads the graders, which now carry one more comment line each. One
case, one run for each arm, Claude Code 2.1.322, 20 seconds, 0.10 USD:

    $ claude plugin eval plugins/change-record --case tier-0-no-record --runs 1 --scaffold --allow-tools Bash Write Edit --trust-plugin --no-publish --max-cost-usd 1
    graders loaded: declares-tier-0 (regex), no-record-edited (tool_used), no-record-written (regex), skill-fired (tool_used), typo-fixed (llm)
    with the plugin: 1.00 (all five pass)      without: 0.75 (declares-tier-0 fails)

the same scores as the README's table for that case. The other seven cases were not run again;
their graders were changed the same way.

### Not done, and what was only read

- **No third-party runner was run.** Loading the folder with `agent-skills-eval`'s own loader
  was the planned check; this session does not allow running code downloaded from outside, so
  its loader was read instead (`dist/skill.js`, `parseEval` and `readEvalsFile`): it needs
  `evals` to be a list and each `prompt` a non-empty string, and takes `id` as a number or
  string, `name`, `expected_output`, `files` and `assertions` as strings. The file has those.
  Its strict check of `SKILL.md` asks that the name match the folder (`change`, it does).
- **Nothing was run against Codex or Cursor**, whose logins are not in the cloud (record
  `2026-11-11-codex-cursor-capture`, C2). Whether either follows the skill outside Claude Code
  is a separate question: `SKILL.md` points at `${CLAUDE_PLUGIN_ROOT}/RULES.md`, which only
  Claude Code sets.
- **The statements are mine and are not checked against the graders by anything but
  reading.** A statement can say a little more or less than its pattern checks; the seven
  `llm` graders are restated, not copied.
- The assumption under Probed facts stands: where a runner puts the input files is not known.
- **Read against the whole guide (2026-11-12, after the owner pasted the published page, which
  is the same text as the source at `83021e2`).** Three things the file does that the guide
  advises against or handles differently, now said in the README. It says to check mechanical
  assertions with a verification script and not a model; 22 of the 29 are of that kind and no
  script is written here. It grades outputs, and calls an assertion that cannot be checked
  from the output alone one to fix; the seven "The transcript shows" statements are such, and
  are kept because the order of work is what the skill adds. It says to remove assertions that
  pass with and without the skill; the five "file exists" statements and two whole cases did so
  in the results of 2026-11-08, and are kept to match the case folders one for one. An earlier
  line of this record's README text said every statement goes to a judge; that was the file's
  shape, not the guide's advice, and it is corrected.

### Task 2, the verification script (2026-11-12)

Shipped: `skills/change/evals/verify`; `skills/change/evals/checks.json` (15 checks), written and
checked by `export-evals-json`; a `# check:` line in two graders; a section in the evals README.
`cases.test.cjs` goes from 32 tests to 40; the other suites pass unchanged.

Red first: the test commit failed eight tests. Guards: 29 were broken by hand in a copy of
the plugin, one at a time, and the tests run. 28 failed them. The one that did not was a
branch in `verify` that refused an unknown flag, which the count of arguments already
refuses; the branch was removed.

Real use, on what a real agent left. One case run with Claude's runner and its folders kept
(`claude plugin eval plugins/change-record --case record-before-code --runs 1 --scaffold
--keep-temp ...`, Claude Code 2.1.322, 67 seconds, 0.20 USD). Both arms scored 1.00, every
grader passing. `verify` on each arm's folder, with the last message taken from its trace:

    $ verify record-before-code <with arm>/home/cwd --final-message final-with.md; echo $?
    PASS | The final message contains the line "Change: docs/changes/2026-11-08-shout.md". | the final message has: "Change: docs/changes/2026-11-08-shout.md"
    PASS | The file docs/changes/2026-11-08-shout.md exists. | docs/changes/2026-11-08-shout.md is there (1881 bytes)
    PASS | docs/changes/2026-11-08-shout.md has these sections, in this order: ... | docs/changes/2026-11-08-shout.md has: "## Goal"
    PASS | The frontmatter of docs/changes/2026-11-08-shout.md says "tier: 1". | docs/changes/2026-11-08-shout.md has: "tier: 1"
    not checked: needs a judge | The final message reports the --shout flag implemented ...
    not checked: needs the run's transcript | The transcript shows docs/changes/2026-11-08-shout.md was written before ...
    {'passed': 4, 'failed': 0, 'total': 4, 'pass_rate': 1.0}
    0

The baseline arm gave the same four passes (its record is 884 bytes). So on the four
statements both can check, `verify` and the runner's graders agree in both arms, eight of
eight. Both runs passed everything, so this shows no real failure. For that, the same folder
was checked against two cases it should fail:

    $ verify tier-0-no-record <with arm>/home/cwd; echo $?
    FAIL | docs/changes/ holds only README.md and TEMPLATE.md, ... | docs/changes/ also holds 2026-11-08-shout.md
    1
    $ verify tier-2-stops-before-code <with arm>/home/cwd; echo $?
    FAIL | greet.py is unchanged from the input files. | greet.py differs from the input file
    FAIL | The file docs/changes/2026-11-08-audit-log.md exists. | docs/changes/2026-11-08-audit-log.md is not in the outputs folder
    ...
    1

Error path, met for real on the first try: a wrong folder gives `verify: .../out/home/cwd is
not a folder` and exit 2.

Not done, and limits:

- `verify` was compared with the runner on one case, where everything passed. The other
  eleven checks have only the made-up folders of the tests behind them.
- It checks 15 of the 29 statements. An earlier line of this record and of the README said 22
  were mechanical; that is how many Claude's runner checks without a model, seven of them
  from the trace, which `verify` does not read.
- The final message is checked only when the runner keeps it and it is passed in; the guide
  names no place for it.
- The patterns are JavaScript's, run by Python. The generator refuses one Python cannot
  compile, and a flag it lacks; it cannot tell a pattern both accept and read differently.
  None of the eight in `checks.json` uses a construct where they differ.
- Still not run against Codex or Cursor.
