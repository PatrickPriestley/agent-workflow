---
name: workflow-review
description: Use when reviewing any pull request in a repository that follows the agent-workflow rules (AGENT-WORKFLOW.md); checks the evidence the author owes, not just the code.
---

# Review against the agent-workflow rules

The author of this pull request is often a coding agent that summarises its own work. Judge
the diff and the PR description, not the summary. Evidence that the rules ask for and that
neither the diff nor the description shows is missing: report it as a finding. Never assume
it happened elsewhere.

Report each finding with the rule it breaks and the file, or "PR description". Skip a check
that does not apply, such as tests for a change to documentation only.

## 1. Probe before you assert

For each new call to something outside the repository (an API method, CLI, protocol message,
file format or device):

- Look for evidence that the exact request was sent to the real system, in the version
  targeted. A test against a fake or mock that accepts everything proves only the author's
  side. A doc that lists a value does not prove the receiver accepts it.
- Claims about another system should carry a label: verified against the real system,
  supported by the receiver's exact source, tested against a mock, or assumed.
- No real-system evidence for a new external operation is a blocking finding. List it first.

## 2. Red before green

- A behaviour change comes with a test that would fail without it. Read the assertion: a test
  that only checks nothing crashed, or that passes whatever the code does, does not count.
- A bug fix comes with a test that reproduces the bug.
- Tests deleted, skipped, weakened or marked as expected failures to get a green run are a
  blocking finding.

## 3. Mutation-check the guards

- Each new or changed `if`, early return or validation needs a test that fails when the guard
  is removed. Name any guard you cannot match to such a test.
- If the description reports mutation results, they should name the guards, not only a count.

## 4. Independent review and hands-on evidence

For a change in behaviour, the PR description should contain:

- The `Reviewed by: <kind> <model>` line from `agent-review`, naming a model family other than
  the author's. A local model (Ollama, LM Studio, llama.cpp) does not count. "Reviewed, no
  findings" with no reviewer named is not a review.
- The commands run against the real program and their output, including at least one error
  path. Output quoted for code the diff later changed is stale.

## 5. Scope and safety

- Merges into the main branch, releases and deletions need the owner's approval. Flag deleted
  files, data or migrations that the description does not call out.
- Secret files (`.env`, keys, credentials) and real secret values must not be committed or
  printed in tests or logs. Use synthetic values.
- Flag changes that go beyond what the description says the PR is for.

## 6. Commits and titles

- The PR title and commit subjects are Conventional Commits: `type(scope): description` with a
  type from build, chore, ci, docs, feat, fix, perf, refactor, revert, style, test.
- No AI attribution anywhere in the diff, the commit messages or the description:
  `Co-Authored-By` lines for an AI, `Claude-Session` links, "Generated with" footers.
