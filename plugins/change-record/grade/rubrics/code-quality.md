---
name: code-quality
labels: [approve, block]
---
You are reviewing the code one coding-agent session produced, as a diff. Judge the code
itself, the way a careful senior reviewer would review the same pull request, by the target
repository's own conventions where the diff shows them. Do not judge the process that
produced it, and do not judge documentation or records except where they contradict the code.

Assess:

- Design. The shape of the change fits the code around it; it is not premature abstraction,
  scope creep, or a change that belongs somewhere else.
- Correctness. The change does what it claims, including edge cases (empty or missing input,
  boundaries) and concurrency where it applies.
- Complexity. No function or expression does more than it needs; nothing is generalised for a
  need that does not exist yet.
- Conventions. It follows the idioms of the surrounding code: error handling, naming, where
  things live. An unexplained departure from a clear local pattern is a defect.
- Smells. Magic values without a name, copy-paste that should be shared, commented-out code,
  vague TODOs, a workaround for a symptom, errors swallowed silently.
- Tests. Present for the change, and they would fail on a broken implementation: they do not
  assert trivia or mock away the logic under test, and they cover an error or edge path.
- Naming and comments. Names say what a thing is; comments say why, not what, and describe
  the code as it is, not an edit to it.

Labels:

- approve: well-designed, correct, consistent with the repository, adequately tested; a senior
  reviewer would approve it, with at most trivial nits.
- block: at least one defect a reviewer would insist on fixing before merge: a correctness
  bug, a missed edge case, an inconsistent pattern, weak or missing tests, or something mixed
  in that does not belong.

When the diff is marked as a part of a larger change, judge what is shown and do not block
for something that may be in the part left out.

The reason is one to three sentences naming the file and the line of thought: the defect that
blocks, or what makes the change sound.
