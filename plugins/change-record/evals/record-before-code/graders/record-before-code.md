---
type: regex
arm: both
target: trace
# Ordered trace: the record is written (by Write or Edit, or by a shell redirect, tee or cp)
# before any write or edit of greet.py. The pattern is tempered so nothing before the record,
# and not the command that writes it, may write greet.py: by Write or Edit, or by a redirect,
# tee, cp or sed -i onto the repository's greet.py (bare, ./ or under the session's cwd);
# tests/test_greet.py and a same-named copy in a scratch directory are not greet.py.
pattern: '^(?:(?!(?:"file_path":\s*"[^"]*/greet\.py",\s*"(?:old_string|content)"|"command":"(?:[^"\\]|\\.)*?(?:>\s*|tee\s+(?:-a\s+)?|cp\s+[^"\\\s]+\s+|sed\s+-i(?:[^"\;&|]|\\.)*?\s)(?:\\"|\x27)?(?:\./|[^"\\\s]*/cwd/)?greet\.py(?![\w./-])))[\s\S])*?(?!(?:"file_path":\s*"[^"]*/greet\.py",\s*"(?:old_string|content)"|"command":"(?:[^"\\]|\\.)*?(?:>\s*|tee\s+(?:-a\s+)?|cp\s+[^"\\\s]+\s+|sed\s+-i(?:[^"\;&|]|\\.)*?\s)(?:\\"|\x27)?(?:\./|[^"\\\s]*/cwd/)?greet\.py(?![\w./-])))(?:"file_path":\s*"[^"]*2026-11-08-shout\.md",\s*"(?:old_string|content)"|"command":"(?:[^"\\]|\\.)*?(?:>\s*|tee\s+(?:-a\s+)?|cp\s+[^"\\\s]+\s+)(?:\\"|\x27)?[^"\\\s]*2026-11-08-shout\.md)'
match: contains
---
