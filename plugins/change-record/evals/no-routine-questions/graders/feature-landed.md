---
type: regex
# assertion: greet.py has a way to repeat the greeting a given number of times from the command line.
arm: both
target:
  source: file
  path: greet.py
pattern: 'repeat|times|count|-n\b|--n\b'
flags: i
---
