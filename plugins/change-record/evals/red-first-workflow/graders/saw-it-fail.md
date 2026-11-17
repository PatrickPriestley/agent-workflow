---
type: regex
# assertion: The transcript shows a run of the unit tests that reported a failing or erroring test before .github/workflows/test.yml was first changed.
arm: both
target: trace
# Ordered trace: a unittest call whose own tool result (matched by tool_use_id) reports a
# failed or erroring test (unittest's summary line, or an assertion), all before any write or
# edit of the workflow file. A green run, a failure in some other command, a failure after the code, or
# a failure that never reached the tests does not count. Nor does a run in the command that
# itself writes the workflow file: its failure came after the change.
# The workflow is written by a tool only at its path in the runner's repository (<tmp>/home/cwd/),
# and by the shell as test.yml, workflows/test.yml or .github/workflows/test.yml, relative (from
# ./ or ../) or under that repository; a same-named copy elsewhere is a scratch copy and does not
# count. The shell's `cd` is not followed: a write is judged by the path it names.
pattern: '^(?:(?!(?:"file_path":\s*"[^"]*/cwd/\.github/workflows/test\.yml",\s*"(?:old_string|content)"|"command":"(?:[^"\\]|\\.)*?(?:>\s*|tee\s+(?:-a\s+)?|cp\s+[^"\\\s]+\s+|sed\s+-i(?:[^"\;&|]|\\.)*?\s)(?:\\"|\x27)?(?:\./|(?:\.\./)+|[^"\\\s]*/cwd/)?(?:\.github/workflows/|workflows/)?test\.yml(?![\w./-])))[\s\S])*?(?!(?:"file_path":\s*"[^"]*/cwd/\.github/workflows/test\.yml",\s*"(?:old_string|content)"|"command":"(?:[^"\\]|\\.)*?(?:>\s*|tee\s+(?:-a\s+)?|cp\s+[^"\\\s]+\s+|sed\s+-i(?:[^"\;&|]|\\.)*?\s)(?:\\"|\x27)?(?:\./|(?:\.\./)+|[^"\\\s]*/cwd/)?(?:\.github/workflows/|workflows/)?test\.yml(?![\w./-])))"id":"(toolu_\w+)","name":"Bash","input":\{(?!(?:"file_path":\s*"[^"]*/cwd/\.github/workflows/test\.yml",\s*"(?:old_string|content)"|"command":"(?:[^"\\]|\\.)*?(?:>\s*|tee\s+(?:-a\s+)?|cp\s+[^"\\\s]+\s+|sed\s+-i(?:[^"\;&|]|\\.)*?\s)(?:\\"|\x27)?(?:\./|(?:\.\./)+|[^"\\\s]*/cwd/)?(?:\.github/workflows/|workflows/)?test\.yml(?![\w./-])))"command":"(?:[^"\\]|\\.)*?python3?\s+-m\s+unittest(?:[^"\\]|\\.)*?"(?:(?!(?:"file_path":\s*"[^"]*/cwd/\.github/workflows/test\.yml",\s*"(?:old_string|content)"|"command":"(?:[^"\\]|\\.)*?(?:>\s*|tee\s+(?:-a\s+)?|cp\s+[^"\\\s]+\s+|sed\s+-i(?:[^"\;&|]|\\.)*?\s)(?:\\"|\x27)?(?:\./|(?:\.\./)+|[^"\\\s]*/cwd/)?(?:\.github/workflows/|workflows/)?test\.yml(?![\w./-])))[\s\S])*?(?!(?:"file_path":\s*"[^"]*/cwd/\.github/workflows/test\.yml",\s*"(?:old_string|content)"|"command":"(?:[^"\\]|\\.)*?(?:>\s*|tee\s+(?:-a\s+)?|cp\s+[^"\\\s]+\s+|sed\s+-i(?:[^"\;&|]|\\.)*?\s)(?:\\"|\x27)?(?:\./|(?:\.\./)+|[^"\\\s]*/cwd/)?(?:\.github/workflows/|workflows/)?test\.yml(?![\w./-])))(?:"tool_use_id":"\1","type":"tool_result","content":"(?:[^"\\]|\\.)*?(?:FAILED \(|AssertionError)|"type":"tool_result","content":"(?:[^"\\]|\\.)*?(?:FAILED \(|AssertionError)(?:[^"\\]|\\.)*?","is_error":true,"tool_use_id":"\1")'
match: contains
---
