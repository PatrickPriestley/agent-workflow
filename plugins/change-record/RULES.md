# Working rules (change-record)

Agent-agnostic. Every change, every agent. The `change` skill says how.

1. **Every change has a tier.** No behaviour change (a typo, a comment, formatting): tier 0,
   no record. Anything else gets a change record at `docs/changes/<id>.md` before code, and a
   tier 2 record is approved on the default branch before any code for it is built.
2. **Probe before you assert.** Label every claim about another system by its evidence:
   verified against the real system, exact source, mock only, or assumed. Until the real call
   succeeds, the work is a prototype, and the record says so.
3. **Red before green.** Write the test, see it fail on the missing behaviour, commit it, then
   make it pass. A repository may run `red-check`, locally or in CI, to verify it: a changed
   test that passes on the base commit fails the check.
4. **Guards get mutation-checked**, by tool where the language has one, by hand otherwise.
   A survivor gets a test or a reason in the record.
5. **Use what you built as its user would,** main path and one error path, and paste the
   commands and output into the record's Outcome.
6. **An independent review runs on every PR** by a model family other than the author's.
   Findings are claims: probe each, fix verified ones test-first, dismiss only with evidence.
7. **Ask before merging into the default branch, releasing or deleting.** Pushing a branch and
   opening a PR need no approval. Never answer another agent's trust, permission or login prompt.
8. **Commits are Conventional Commits** (`feat:`, `fix(scope):`, ...).
