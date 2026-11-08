---
type: regex
arm: both
target:
  source: file
  path: docs/changes/2026-11-08-names.md
pattern: '^## Outcome[\s\S]*Hello, [A-Za-z]+!'
flags: m
match: contains
---
