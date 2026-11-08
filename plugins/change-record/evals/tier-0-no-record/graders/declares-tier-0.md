---
type: regex
arm: both
target: last_message
# "Tier: 0" in any of the markdown styles agents write it: plain, bold around the whole line,
# bold around the word, or bold around "Tier:".
pattern: '\**Tier\**\s*:\s*\**\s*0(?!\d)'
---
