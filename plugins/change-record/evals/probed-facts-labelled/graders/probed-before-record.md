---
type: regex
arm: both
target: trace
# Ordered trace: a probe of fileinput before the record is written (by Write or Edit, or by a
# shell redirect, tee or cp of the template), and not in the same command. A probe is python -c
# or python - with a heredoc mentioning fileinput, pydoc or python -m on it, a line piped into
# python, or a scratch script (not a test, not greet.py) written with fileinput in it and then
# run. Commands are JSON strings, so the pattern steps over escaped quotes; a heredoc that
# merely writes "import fileinput" into a test file does not count.
pattern: '^(?:(?!(?:"file_path":\s*"[^"]*2026-11-08-names-file\.md",\s*"(?:old_string|content)"|"command":"(?:[^"\\]|\\.)*?(?:>\s*|tee\s+(?:-a\s+)?|cp\s+[^"\\\s]+\s+)(?:\\"|\x27)?[^"\\\s]*2026-11-08-names-file\.md))[\s\S])*?(?!(?:"file_path":\s*"[^"]*2026-11-08-names-file\.md",\s*"(?:old_string|content)"|"command":"(?:[^"\\]|\\.)*?(?:>\s*|tee\s+(?:-a\s+)?|cp\s+[^"\\\s]+\s+)(?:\\"|\x27)?[^"\\\s]*2026-11-08-names-file\.md))(?:"command":"(?:[^"\\]|\\.)*?python3?(?:\s+-[A-Za-z]+)*\s+-(?:c\s|\s*<<)(?:[^"\\]|\\.)*?fileinput|"command":"(?:[^"\\]|\\.)*?(?:python3?\s+-m\s+(?:pydoc\s+)?|pydoc3?\s+)fileinput|"command":"(?:[^"\\]|\\.)*?fileinput(?:[^"\\]|\\.)*?\|\s*python3?(?![\w.-])|(?:"name":"Write","input":\{"file_path":"[^"]*/|"command":"(?:[^"\\]|\\.)*?(?:>\s*|tee\s+(?:-a\s+)?)(?:\\"|\x27)?(?:[^"\\\s]*/)?)((?!test|greet)[\w-]+)\.py(?:",\s*"content":"|\s*<<)(?:[^"\\]|\\.)*?fileinput(?:(?!(?:"file_path":\s*"[^"]*2026-11-08-names-file\.md",\s*"(?:old_string|content)"|"command":"(?:[^"\\]|\\.)*?(?:>\s*|tee\s+(?:-a\s+)?|cp\s+[^"\\\s]+\s+)(?:\\"|\x27)?[^"\\\s]*2026-11-08-names-file\.md))[\s\S])*?(?!(?:"file_path":\s*"[^"]*2026-11-08-names-file\.md",\s*"(?:old_string|content)"|"command":"(?:[^"\\]|\\.)*?(?:>\s*|tee\s+(?:-a\s+)?|cp\s+[^"\\\s]+\s+)(?:\\"|\x27)?[^"\\\s]*2026-11-08-names-file\.md))(?:"command":"(?:[^"\\]|\\.)*?|\\n|&&|;)\s*python3?\s+(?:[^"\\\s]*/)?\1\.py(?![\w./-]))'
match: contains
---
