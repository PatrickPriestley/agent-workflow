---
type: regex
# assertion: The transcript shows the unit tests were run before .github/workflows/test.yml was first changed, in an earlier command than the change.
arm: both
target: trace
# Ordered trace: a unittest run before any write or edit of the workflow file (same guard as
# record-before-code), and not in the same command as the write.
pattern: '^(?:(?!(?:"file_path":\s*"[^"]*/(?:\.github/workflows/)?test\.yml",\s*"(?:old_string|content)"|"command":"(?:[^"\\]|\\.)*?(?:>\s*|tee\s+(?:-a\s+)?|cp\s+[^"\\\s]+\s+|sed\s+-i(?:[^"\;&|]|\\.)*?\s)(?:\\"|\x27)?(?:\./|[^"\\\s]*/cwd/)?(?:\.github/workflows/)?test\.yml(?![\w./-])))[\s\S])*?(?!(?:"file_path":\s*"[^"]*/(?:\.github/workflows/)?test\.yml",\s*"(?:old_string|content)"|"command":"(?:[^"\\]|\\.)*?(?:>\s*|tee\s+(?:-a\s+)?|cp\s+[^"\\\s]+\s+|sed\s+-i(?:[^"\;&|]|\\.)*?\s)(?:\\"|\x27)?(?:\./|[^"\\\s]*/cwd/)?(?:\.github/workflows/)?test\.yml(?![\w./-])))"command":"(?:[^"\\]|\\.)*?python3?\s+-m\s+unittest'
match: contains
---
