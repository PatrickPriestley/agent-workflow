---
type: regex
arm: both
target:
  source: file
  path: docs/changes/2026-11-08-audit-log.md
pattern: '^## Problem[\s\S]*^## Requirements[\s\S]*^## Options and concerns'
flags: m
match: contains
---
