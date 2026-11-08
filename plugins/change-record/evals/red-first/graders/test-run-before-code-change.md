---
type: regex
arm: both
target: trace
# Ordered trace: a unittest run before any write or edit of greet.py (same guard as
# record-before-code), and not in the same command as the write.
pattern: '^(?:(?!(?:"file_path":\s*"[^"]*/greet\.py",\s*"(?:old_string|content)"|"command":"(?:[^"\\]|\\.)*?(?:>\s*|tee\s+(?:-a\s+)?|cp\s+[^"\\\s]+\s+|sed\s+-i(?:[^"\;&|]|\\.)*?\s)(?:\\"|\x27)?(?:\./|[^"\\\s]*/cwd/)?greet\.py(?![\w./-])))[\s\S])*?(?!(?:"file_path":\s*"[^"]*/greet\.py",\s*"(?:old_string|content)"|"command":"(?:[^"\\]|\\.)*?(?:>\s*|tee\s+(?:-a\s+)?|cp\s+[^"\\\s]+\s+|sed\s+-i(?:[^"\;&|]|\\.)*?\s)(?:\\"|\x27)?(?:\./|[^"\\\s]*/cwd/)?greet\.py(?![\w./-])))"command":"(?:[^"\\]|\\.)*?python3?\s+-m\s+unittest'
match: contains
---
