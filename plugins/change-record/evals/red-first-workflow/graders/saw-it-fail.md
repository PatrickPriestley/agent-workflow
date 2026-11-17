---
type: regex
# assertion: The transcript shows a run of the unit tests that reported a failing or erroring test before .github/workflows/test.yml was first changed.
arm: both
target: trace
# Ordered trace: a unittest call whose own tool result (matched by tool_use_id) reports a
# failed or erroring test (unittest's summary line, or an assertion), all before any write or
# edit of the workflow file. A green run, a failure in some other command, a failure after the code, or
# a failure that never reached the tests does not count.
pattern: '^(?:(?!(?:"file_path":\s*"[^"]*/(?:\.github/workflows/)?test\.yml",\s*"(?:old_string|content)"|"command":"(?:[^"\\]|\\.)*?(?:>\s*|tee\s+(?:-a\s+)?|cp\s+[^"\\\s]+\s+|sed\s+-i(?:[^"\;&|]|\\.)*?\s)(?:\\"|\x27)?(?:\./|[^"\\\s]*/cwd/)?(?:\.github/workflows/)?test\.yml(?![\w./-])))[\s\S])*?(?!(?:"file_path":\s*"[^"]*/(?:\.github/workflows/)?test\.yml",\s*"(?:old_string|content)"|"command":"(?:[^"\\]|\\.)*?(?:>\s*|tee\s+(?:-a\s+)?|cp\s+[^"\\\s]+\s+|sed\s+-i(?:[^"\;&|]|\\.)*?\s)(?:\\"|\x27)?(?:\./|[^"\\\s]*/cwd/)?(?:\.github/workflows/)?test\.yml(?![\w./-])))"id":"(toolu_\w+)","name":"Bash","input":\{"command":"(?:[^"\\]|\\.)*?python3?\s+-m\s+unittest(?:[^"\\]|\\.)*?"(?:(?!(?:"file_path":\s*"[^"]*/(?:\.github/workflows/)?test\.yml",\s*"(?:old_string|content)"|"command":"(?:[^"\\]|\\.)*?(?:>\s*|tee\s+(?:-a\s+)?|cp\s+[^"\\\s]+\s+|sed\s+-i(?:[^"\;&|]|\\.)*?\s)(?:\\"|\x27)?(?:\./|[^"\\\s]*/cwd/)?(?:\.github/workflows/)?test\.yml(?![\w./-])))[\s\S])*?(?!(?:"file_path":\s*"[^"]*/(?:\.github/workflows/)?test\.yml",\s*"(?:old_string|content)"|"command":"(?:[^"\\]|\\.)*?(?:>\s*|tee\s+(?:-a\s+)?|cp\s+[^"\\\s]+\s+|sed\s+-i(?:[^"\;&|]|\\.)*?\s)(?:\\"|\x27)?(?:\./|[^"\\\s]*/cwd/)?(?:\.github/workflows/)?test\.yml(?![\w./-])))(?:"tool_use_id":"\1","type":"tool_result","content":"(?:[^"\\]|\\.)*?(?:FAILED \(|AssertionError)|"type":"tool_result","content":"(?:[^"\\]|\\.)*?(?:FAILED \(|AssertionError)(?:[^"\\]|\\.)*?","is_error":true,"tool_use_id":"\1")'
match: contains
---
