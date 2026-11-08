---
type: llm
focus:
  source: file
  path: docs/changes/2026-11-08-names.md
---
PASS if the "Outcome" section quotes a real run of greet.py with --names showing greetings, and a real run with an empty or missing list showing the error message and that it exited with status 2 (or the exit status is otherwise shown). FAIL if the section only reports unit-test results, describes the behaviour without quoting command output, or omits the error-path run.
