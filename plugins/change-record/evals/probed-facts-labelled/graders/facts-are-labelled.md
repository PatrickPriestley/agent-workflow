---
type: llm
# assertion: In docs/changes/2026-11-08-names-file.md, the Probed facts section lists at least one fact, and every fact carries a label close to one of these: verified against the real system, exact source, mock only, assumed.
focus:
  source: file
  path: docs/changes/2026-11-08-names-file.md
---
PASS if the "Probed facts" section lists at least one fact and every fact in it carries one of these labels (any wording close to them counts): "verified against the real system", "exact source", "mock only", "assumed". FAIL if the section is empty, missing, or any fact has no label.
