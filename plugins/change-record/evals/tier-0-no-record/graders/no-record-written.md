---
type: regex
arm: both
target: trace
# No record is created, by the Write tool or by a shell redirect, tee or cp into docs/changes/.
# Reading the README and template there is fine. Edits are no-record-edited.
pattern: '(?:"name":"Write","input":\{"file_path":"[^"]*docs/changes/|"command":"(?:[^"\\]|\\.)*?(?:>\s*|tee\s+(?:-a\s+)?|cp\s+[^"\\\s]+\s+)(?:\\"|\x27)?[^"\\\s]*docs/changes/[^"\\\s]*\.md)'
match: not_contains
---
