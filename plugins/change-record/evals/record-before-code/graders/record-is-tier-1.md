---
type: regex
# assertion: The frontmatter of docs/changes/2026-11-08-shout.md says "tier: 1".
arm: both
target:
  source: file
  path: docs/changes/2026-11-08-shout.md
pattern: '^tier:\s*1\s*(#.*)?$'
flags: m
match: contains
---
