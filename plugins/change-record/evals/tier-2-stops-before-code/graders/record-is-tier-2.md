---
type: regex
# assertion: The frontmatter of docs/changes/2026-11-08-audit-log.md says "tier: 2".
arm: both
target:
  source: file
  path: docs/changes/2026-11-08-audit-log.md
pattern: '^tier:\s*2\s*(#.*)?$'
flags: m
match: contains
---
