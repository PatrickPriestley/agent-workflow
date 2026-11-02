---
type: regex
arm: both
target: trace
# Only tool output lines carry tool_use_id, so greetings written into code or tests do not count.
pattern: 'tool_use_id[^\n]*Hello, [A-Z][a-z]+!(\\n|\n)Hello, [A-Z][a-z]+!'
match: contains
---
