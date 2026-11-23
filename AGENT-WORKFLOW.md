# Working rules

Agent-agnostic. Canonical copy: `~/AGENT-WORKFLOW.md`. Other agents' config files point
here. These rules apply to every change, whichever loop it goes through.

## Which loop

- **Accepted intent or spec:** the `intent`, `spec` and `plan` skills.
  The plan replaces feature-loop's design note; the rules below still apply.
- **Anything that changes behaviour, or touches more than one file** (refactors and renames
  included): load the `feature-loop` skill as your first action, before reading code, with
  your agent's skill tool (in Claude Code, the Skill tool). "Quick", "small" or "don't
  overthink it" does not change this.
- **A one-file change with no behaviour change** (a typo, a comment, formatting): no loop.

## Rules

1. **Probe before you assert.** Try a tool, API or command in a scratch directory before
   relying on how it behaves. Memory and cached docs have been wrong about exit codes, flags
   and event lists. Before building on a call to another system (an API method, CLI,
   protocol message, file format or device), send the exact request to the version you
   target, in a disposable environment, and see the outcome you need. A fake or mock that
   accepts everything proves only your own side; a doc or one parser that lists a value does
   not prove another accepts it. Until that check passes, the work is a prototype, and say so.
   Label each claim by its evidence: verified against the real system, supported by the
   receiver's exact source, tested against a mock, or assumed. A claim changes label only on
   new evidence.
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
   happen. `agent-review code` runs one headless; if the reviewer fails it switches to another
   model, then to OpenCode Go. Never review with a local model (Ollama, LM Studio, llama.cpp):
   such a review does not count. If no other family answers, say so and push: Open Code Review
   on the pull request is then the review, from the author's family, and its findings are
   handled the same way. Name the reviewer actually used when reporting the review. Never send secret files (`.env`, keys, credentials) to a reviewer.
5. **Ask first** before merging into the main branch, releasing or deleting, unless the
   request already asked for it. Pushing a branch and opening a PR need no approval. Never answer another agent's trust, permission, login or update prompt.
6. **Commits** are Conventional Commits (`feat:`, `fix(scope):`, ...) and carry no AI
   attribution: no `Co-Authored-By`, `Claude-Session` or "Generated with" lines, in messages
   or in files. `commit-gate enable` enforces both in a repository.
