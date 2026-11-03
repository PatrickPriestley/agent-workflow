# Native evaluator context

Goal: distinguish package discovery from explicit skill execution and shared working rules,
without claiming the native package reproduces the full installed tooling environment.

Evidence: Claude Code 2.1.316 help documents scaffold opt-in, with/without ablation and
with-only Skill graders as activation indicators. The real CLI's local synthetic-model
probe advertises the workflow description under feature-loop, shadowing the skill.
Synthetic model responses verify transport/context only, not model quality.

Decisions:
- Give the optional plan execution workflow a distinct identity. Preserve its installer
  path if the real loader respects metadata; otherwise rename and migrate owned links.
- Keep wrong-finding as the discovery/no-rules control; do not replace its historical task.
- Add wrong-finding-rules with canonical repository rules loaded from project CLAUDE.md
  in both arms. A clear availability instruction lets the baseline follow the rules
  without claiming it can invoke an absent skill. This measures the plugin's increment
  over shared rules, not the rules' own benefit.
- Add wrong-finding-explicit with a conditional request to invoke the namespaced skill
  when available; both arms still receive the identical review task.
- Reuse the original task and outcome graders, including the with-only activation
  indicator. Do not install global helpers or bypass sandbox safeguards.

Work/checks: add deterministic Node tests for unique runtime identities, scaffold rules
and fair prompts; see them fail before changes, mutate their target contracts, run shell
suites. Probe real CLI 2.1.316 with synthetic model endpoint for actual advertised names,
loaded rules and both arms. Independent review occurs before push via the parent task.

Verified implementation evidence: real Claude Code 2.1.316 sent requests advertising both
`agent-workflow:feature-loop` with the skill's behavior-change description and the distinct
`agent-workflow:execute-feature-plan`. Changing exported metadata is sufficient; filename
and installer links stay compatible. Local synthetic-model runs accepted both new case
schemas and executed both arms. These probes do not measure model output quality.

Probe-driven adjustment: native 2.1.316 did not load scaffold CLAUDE.md into either
arm's initial model request. Therefore rules are supplied explicitly in the shared prompt
as well as the project copy. A drift assertion matches the canonical repository rules.
This is a rules-supplied case, not proof of installed global configuration loading.

Validation: four Node contract/scaffold tests pass after initial assertion failures;
four mutations (workflow collision, prompt rules drift, scaffold rules omission, baseline
availability removal) were killed and restored. Installer 73, commit-gate 79 and
agent-review 108 shell checks pass. Real Skill invocation through the local synthetic
endpoint loaded the feature-loop SKILL.md body, not workflow argument validation. The
shared prompt's canonical rules and baseline fallback appeared in both model requests.
No paid model-quality evaluation was performed.

Additional bounded correction: the red-first `committed` grader matched a Bash command,
not its result, so even a sandbox-denied commit could pass. Remove that assertion and
commit request; retain the existing test-first graders. Real native macOS sandbox Git
writes succeeded, but hosted Linux writes remain unverified because the failed run did
not retain its tool trace. Do not weaken the sandbox or infer universal Git failure.

Review corrections and evidence:
- Updated the skill's optional-workflow reference to `execute-feature-plan`, with an
  assertion that failed on the stale reference before the change. Added a scaffold
  equality assertion for the explicit variant; mutating its source text fails the test.
- A real Claude Code 2.1.316 `-p` session in an isolated temporary HOME after running
  install.sh advertised unnamespaced `feature-loop` with its skill description and
  distinct `execute-feature-plan` with its workflow description. The unchanged symlink
  filename therefore works in the installed loader as well as the plugin loader.
- Inspected actual requests 0 (with) and 5 (without) from each new native-case probe:
  both contain the entire matching prompt.md, including its unavailable-skill fallback.
  Canonical rules are present in both rules-case requests. This checks application of
  the shared prompt by the real receiver, not just local fixture equality.
- The real native case probes already executed path-relative scaffolds successfully in
  both arms. Moving the scaffold elsewhere is not the receiver's observed behavior.
- README describes explicit invocation compliance, not guaranteed skill execution.
  Successful scaffolding is outside the agent Bash sandbox; the hosted agent Git-write
  limitation remains unverified separately.
