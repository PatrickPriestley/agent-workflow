---
name: README drift check
description: Check that every file, folder and command the README names still exists

# Manual only while we learn the tool: it never runs on its own.
on:
  workflow_dispatch:

# The agent job gets read-only access. Writing the issue happens in a
# separate safe-outputs job that gh-aw generates with issues: write.
permissions:
  contents: read

engine: claude

strict: true
timeout-minutes: 10
max-turns: 20

# Read-only shell commands only. No edit tool, no network beyond what the
# engine itself needs. (The bare `bash:` form shown in the docs is rejected
# by the v1.2.2 compiler; `bash: true` would allow every command.)
tools:
  bash: ["ls", "cat", "grep", "head", "wc", "test"]

safe-outputs:
  create-issue:
    title-prefix: "[readme-drift] "
    max: 1
    close-older-issues: true
---

# README drift check

You are checking this repository's documentation against its actual contents.
Do not change any files.

1. Read `README.md` and `AGENT-WORKFLOW.md`.
2. List every repository path they mention (for example `skills/feature-loop`,
   `bin/agent-review`, `evals/`) and every command they tell the reader to run
   that refers to a script in this repository.
3. For each one, check with `ls` that it exists. For a command, check that the
   script it names exists.
4. Ignore paths in the user's home directory (`~/...`) and commands that belong
   to other tools (`git`, `claude`, `codex`, `gh`). Also ignore things that look
   like paths but are not files here: git refs (`origin/main`), model names
   (`provider/model-id`), and folder names given as examples of a kind of path
   (such as "it leaves out `fixtures/`").

If everything exists, call `noop` with a one-line message saying how many
paths and commands you checked.

If anything is missing, create one issue titled "README names N missing paths"
whose body has a table: the path or command, the file and line that mentions it,
and what you found instead (a renamed file, a near match, or nothing). Do not
guess at fixes beyond pointing out a near match.
