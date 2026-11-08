---
type: regex
arm: both
target: trace
# The repository's greet.py is not written, by the Write tool or by a shell redirect, tee, cp
# or sed -i. tests/test_greet.py, reading greet.py and copying it elsewhere are fine. Edits are
# no-code-edited.
pattern: '(?:"name":"Write","input":\{"file_path":"[^"]*/greet\.py"|"command":"(?:[^"\\]|\\.)*?(?:>\s*|tee\s+(?:-a\s+)?|cp\s+[^"\\\s]+\s+|sed\s+-i(?:[^"\;&|]|\\.)*?\s)(?:\\"|\x27)?(?:\./|[^"\\\s]*/cwd/)?greet\.py(?![\w./-]))'
match: not_contains
---
