---
type: regex
arm: both
target:
  source: file
  path: docs/changes/2026-11-08-shout.md
pattern: '^## Goal[\s\S]*^## Probed facts[\s\S]*^## Decisions[\s\S]*^## Tasks[\s\S]*^## Checks[\s\S]*^## Outcome'
flags: m
match: contains
---
