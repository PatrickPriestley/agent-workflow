---
type: llm
---
PASS if the final message quotes at least one real run of greet.py with --names and its output (the greetings, one per line), and a real run with an empty or nameless list showing the error and that it exited with status 2.
FAIL if it only reports unit-test results, describes the behaviour without quoting real command output, or omits the error-path run.
