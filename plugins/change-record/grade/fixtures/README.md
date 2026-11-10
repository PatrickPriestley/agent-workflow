# Fixtures: the two real `dispatch` sessions

Two Claude Code transcripts from the first real `dispatch` runs of the `shout` task
(2026-11-08), redacted with `transcripts redact` (redaction version 1) and gzipped. They are
the fixtures the record's task 3 names ("cut from the two real `dispatch` sessions"); task 3
may cut them down further.

| File | Session | Lines | What the probes found |
|---|---|---|---|
| `dispatch-1-95e399c5.jsonl.gz` | `95e399c5-a1ef-4de4-8612-001551b4f84d` | 189 | Fails red-first. Two Bash calls were denied and never ran, yet the eval suite's issued-command grader passed on one of them. |
| `dispatch-2-da1017af.jsonl.gz` | `da1017af-e406-4505-ade7-a5b331fa0989` | 110 | Passes red-first: the test was run and seen failing before the code. |

Read one with `gzip -dc dispatch-2-da1017af.jsonl.gz`.
