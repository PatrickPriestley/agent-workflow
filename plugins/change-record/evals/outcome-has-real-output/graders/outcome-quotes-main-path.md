---
type: regex
# assertion: In docs/changes/2026-11-08-names.md, the Outcome section contains a greeting the program printed, such as "Hello, Ana!".
arm: both
target:
  source: file
  path: docs/changes/2026-11-08-names.md
pattern: '^## Outcome[\s\S]*Hello, [A-Za-z]+!'
flags: m
match: contains
---
