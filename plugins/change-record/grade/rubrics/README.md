Two rubrics that `transcripts judge --rubrics` asked, and no longer does (record
`docs/changes/2026-11-12-session-quality.md`, R4, C2 and C7). Each was measured against a
person's labels on 2026-11-12 and was wrong on more than one session in five:

- `verbosity.md`, asked of Claude Haiku: 14 labelled sessions, wrong on 3. It answered
  `proportionate` every time.
- `code-quality.md`, asked of Claude Sonnet with no tools: 7 labelled sessions, wrong on 4,
  each an `approve` where the label says `block` for a defect the labeller reproduced.

The files stay because the labels in `grade/labels/` were made against them, and
`grade/labels.py` reads each rubric's allowed answers from its top block.

`code-quality.md` and `verbosity.md` are adapted from the scorers of Skill Doctor
(`warpdotdev/common-skills`, `.agents/skills/skill-doctor/scorers/`, at `8792394`), which is
MIT-licensed work of Denver Technologies, Inc.; its licence is `LICENSE-skill-doctor.txt` here.
What changed: each rubric is asked of one thing this tool can show a judge (the diff between a
session's first and last commit; the messages the session wrote), not of a whole condensed
transcript; the labels are kept as labels and carry no score; `insufficient_evidence` is gone,
since a session with no diff is not asked; and the answer is one line of JSON.

Each file is a top block (`labels:`, the allowed answers, good first) and the text the judge
read.
