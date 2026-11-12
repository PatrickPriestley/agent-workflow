The two rubrics `transcripts judge --rubrics` asks (record
`docs/changes/2026-11-12-session-quality.md`, R4 and C7).

`code-quality.md` and `verbosity.md` are adapted from the scorers of Skill Doctor
(`warpdotdev/common-skills`, `.agents/skills/skill-doctor/scorers/`, at `8792394`), which is
MIT-licensed work of Denver Technologies, Inc.; its licence is `LICENSE-skill-doctor.txt` here.
What changed: each rubric is asked of one thing this tool can show a judge (the diff between a
session's first and last commit; the messages the session wrote), not of a whole condensed
transcript; the labels are kept as labels and carry no score; `insufficient_evidence` is gone,
since a session with no diff is not asked; and the answer is one line of JSON.

Each file is a top block (`labels:`, the allowed answers, good first) and the text the judge
reads. Changing either changes what is judged: bump `RUBRIC` in `grade/rubric.py`.
