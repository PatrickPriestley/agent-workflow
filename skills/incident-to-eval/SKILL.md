---
name: incident-to-eval
description: Turn a production incident, a fixed bug or security finding, or a mistake an agent made twice into a permanent eval case that regression-tests the agent's configuration, and record the lesson in the agent instructions file (AGENTS.md). Use after a postmortem or a fix ships, or when the same review finding recurs.
---

Every incident gets an eval, written by the team that owned it, and it stays in the
suite. The eval tests the **agent's configuration** (the agent instructions file, skills,
hooks): given the same task again, does the agent avoid the mistake? The runner can drive
Claude Code, Codex or Gemini CLI, so a case can show the configuration holds for each.

Inputs: an incident or ticket id, and the change that fixed it (`change_id`, or a commit
sha). The case is keyed on `change_id`; the README records the incident id.

## Layout

```
evals/cases/<change_id>/prompt.md    the task as an engineer would have phrased it
evals/cases/<change_id>/README.md    incident id, what happened, why the check works
evals/checks/<change_id>/check.sh    exits non-zero if the mistake is repeated
```

Checks live outside the case directory so the agent under test never sees or edits
them. Protect `evals/checks/` with CODEOWNERS (or equivalent) if the repo has one.

`check.sh` runs with its working directory set to the sandbox, where `git diff base HEAD`
shows what changed. Prefer deterministic checks (files touched, commands run, a
targeted test passing). Assert on behaviour, not on commit wording or a string the
agent can write. Run only the relevant tests, not the whole suite.

## Procedure

1. Read the incident record and the fix. Identify the agent behaviour that would have
   prevented it: a rule ignored, a test not run, a path touched, a policy missed.
2. Write `prompt.md`, `README.md` and `check.sh` (make it executable). `prompt.md` must
   reproduce the decision point: the task before the fix, not "fix bug X".
3. **Negative control.** The check must fail against the actual bad change:
   `run-eval.sh <change_id> --at <bad-commit>`. The runner ships in this skill at
   `scripts/run-eval.sh` (for a personal install,
   `~/.agents/skills/incident-to-eval/scripts/run-eval.sh`); run it from the repo root.
   If the check passes, it is too weak; fix it before going on.
4. **Baseline.** `run-eval.sh <change_id> --runs 5` against current
   configuration. Record the pass count.
5. **Fix the configuration.** A general rule goes in the agent instructions file
   (`AGENTS.md`) under a "Things agents get wrong" section (one line). A policy goes in its owning skill, approved by the
   policy owner.
6. **Re-run** with `--runs 5`. Target at least 4 of 5. Put before and after counts in the
   commit or PR.
7. Append a dated paragraph to `lessons/incidents.md`: what happened, the eval id, the
   rule or skill change. Commit `eval: <change_id> <one line>`.

## Running the suite

`run-eval.sh --all --runs 3` runs every case. Run it whenever the agent instructions
file, the skills, `.claude/`, `.agents/` or `evals/` changes, and on a schedule; a configuration change that lowers
the pass rate is reviewed before it merges. In CI, call the same script after
installing the agent's CLI with an API key.
