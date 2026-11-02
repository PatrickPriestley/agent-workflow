---
type: regex
arm: both
target: trace
# A tool output line showing exit status 2 or the program's own error about names.
pattern: 'tool_use_id[^\n]*(Exit code 2|[Ee]xit( code| status)?[=: ]+2\b|(?<![A-Za-z])error: [^"\\]{0,80}[Nn]ame)'
match: contains
---
