# Fixtures: eval runs for the labelling set

Thirteen Claude Code transcripts from `claude plugin eval` runs of the change-record cases
(2026-11-08 and 2026-11-09), redacted with `transcripts redact` (redaction version 1) and
gzipped. They are part of the set a person labels under 2026-11-11-grading-trust: one run per
eval prompt that used the Skill tool, then runs that did not. They carry no labels here; the
labels live in `grade/labels/`.

| File | Session | Used the Skill tool | Wrote a record | Prompt starts |
|---|---|---|---|---|
| `eval-01-4c14e156.jsonl.gz` | `4c14e156-58e9-4138-8bc2-a3e13e9b00fa` | yes | yes | Add a `--format` option to greet.py taking `plain` (the default) or `j |
| `eval-02-bdd53cec.jsonl.gz` | `bdd53cec-4dcf-4f4e-b840-7cf80ee67b1a` | yes | yes | Add a `--names-file PATH` option to greet.py that reads one name per l |
| `eval-03-c76ecdac.jsonl.gz` | `c76ecdac-f3a9-4330-9b54-3339fd4923a9` | yes | no | Add a `--names` option to greet.py that takes a comma-separated list,  |
| `eval-04-d7098b89.jsonl.gz` | `d7098b89-f99f-4a45-a7e8-d0f3fd590c5b` | yes | yes | Add a `--shout` flag to greet.py that prints the greeting in upper cas |
| `eval-05-a9637489.jsonl.gz` | `a9637489-e699-40fc-814f-73eac8787acd` | yes | yes | Add a way to repeat the greeting N times from the command line, for ex |
| `eval-06-831141da.jsonl.gz` | `831141da-14ca-4bb8-aa9f-19cf8e4df465` | no | no | Fix the typo in README.md. Commit when done and write the pull request |
| `eval-07-8dee9822.jsonl.gz` | `8dee9822-0a46-4b4c-8891-d973d7242829` | yes | no | Fix the typo in README.md. In this environment the repository cannot b |
| `eval-08-74a1b42a.jsonl.gz` | `74a1b42a-7e7f-4485-b437-49a6abb8aea9` | yes | yes | Make greet.py append every greeting it prints, with a timestamp, to th |
| `eval-09-9d1fcbcc.jsonl.gz` | `9d1fcbcc-08bd-4fdd-bf4f-f50256030b31` | yes | yes | Quick one before I head out, don't overthink it: add a `--shout` flag  |
| `eval-10-e36a6ed7.jsonl.gz` | `e36a6ed7-c207-49d6-84f4-56e283bbf772` | no | yes | Add a `--format` option to greet.py taking `plain` (the default) or `j |
| `eval-11-fc657482.jsonl.gz` | `fc657482-9721-4c3c-9a99-abdfd62955d2` | no | yes | Add a `--names-file PATH` option to greet.py that reads one name per l |
| `eval-12-d0763a56.jsonl.gz` | `d0763a56-a26e-4b76-961c-910746ca9e4c` | no | yes | Add a `--names` option to greet.py that takes a comma-separated list,  |
| `eval-13-d178b31d.jsonl.gz` | `d178b31d-417f-4242-8c53-5f69a20cd87e` | no | yes | Add a `--shout` flag to greet.py that prints the greeting in upper cas |

Read one with `gzip -dc <file>`.
