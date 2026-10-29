# Working rules

Agent-agnostic. Canonical copy: `~/AGENT-WORKFLOW.md`. Other agents' config files point
here. These rules apply to every change, whichever loop it goes through.

## Which loop

- **Accepted intent or spec:** the `intent`, `spec` and `plan` skills.
  The plan replaces feature-loop's design note; the rules below still apply.
- **Anything that changes behaviour, or touches more than one file** (refactors and renames
  included): the `feature-loop` skill, from its first step.
- **A one-file change with no behaviour change** (a typo, a comment, formatting): no loop.

## Rules

1. **Probe before you assert.** Try a tool, API or command in a scratch directory before
   relying on how it behaves. Memory and cached docs have been wrong about exit codes, flags
   and event lists.
2. **Red before green.** Write the test first and see it fail on an assertion about the
   missing behaviour. A test that passes at once, or fails on an import or compile error,
   or asserts only that nothing happened, does not count yet.
3. **Mutation-check the guards** the change adds or touches: break each `if`, early return
   and validation in turn, see a test fail, restore it at once. A survivor gets a test that
   fails without it; delete it only if no input can reach it, and say why in the commit.
4. **Independent review.** Before anything that changes behaviour is pushed, a model family
   other than the author's reads the diff. The review counts only if the reply is complete,
   ending with the end marker the prompt asked for. Findings are claims: probe each one, fix
   verified ones test-first, dismiss one only when a probe or cited code shows it cannot
   happen. `agent-review code` runs one headless. Never send secret files (`.env`, keys, credentials) to a reviewer.
5. **Ask first** before merging into the main branch, releasing or deleting, unless the
   request already asked for it. Pushing a branch and opening a PR need no approval. Never answer another agent's trust, permission, login or update prompt.
6. **Commits** are Conventional Commits (`feat:`, `fix(scope):`, ...) and carry no AI
   attribution: no `Co-Authored-By`, `Claude-Session` or "Generated with" lines, in messages
   or in files. `commit-gate enable` enforces both in a repository.
