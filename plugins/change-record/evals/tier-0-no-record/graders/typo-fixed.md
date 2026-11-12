---
type: llm
# assertion: README.md says "prints a greeting", spelled correctly, and is otherwise unchanged in meaning.
focus:
  source: file
  path: README.md
---
PASS if the README says "prints a greeting" (spelled correctly) and is otherwise unchanged in meaning. FAIL if it still says "greating".
