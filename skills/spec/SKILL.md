---
name: spec
description: Turn an accepted intent.md into a requirements and design spec.md (AI-native SDLC Stage 2 Design), constrained by the policy skills available, with areas of concern flagged. Use when an intent has been accepted and needs a spec.
---

Read `<root>intent/<change_id>.md` and produce `<root>specs/<change_id>.md`. The product
owner reviews the spec; they do not write it. `<root>`, artifact paths, `change_id` and
"accept" follow the conventions in the `intent` skill.

The playbook prompt this skill applies, copied verbatim into `generated_by.prompt`:

"Read the attached intent.md and produce a requirements and design spec for integrating it into our existing codebase. Apply the skills available to you so the plan conforms to our brand guidelines, security policies and UX standards. Document the spec fully as spec.md, ready to hand to the engineering team. Describe clearly any areas of concern, especially where you cannot satisfy contradicting policies."

## Template

Use `<root>specs/TEMPLATE.md` if present; otherwise:

```markdown
---
change_id: <change_id>
status: draft            # draft -> approved (only in step 9)
risk: low|medium|high
risk_reason: <one line>
mock: <path or null>
generated_by: { skill: spec, commit: <short sha>, skills: { intent: <hash>, spec: <hash>, <policy-skill>: <hash> }, prompt: <verbatim> }
approved_by: null
approved_on: null
tech_lead_signoff: null  # required when risk: high
---
# Spec: <title>
## Concerns
## Requirements
## Design
## Open questions (carried forward)
```

## Procedure

1. If the intent is not accepted (on the default branch), stop.
2. Read the intent, the agent instructions file (per Conventions), every skill with `policy: true` in its
   frontmatter (brand, security, compliance, UX), and the code the intent touches.
   Search for policy skills in the shared and per-agent skill folders: `~/.agents/skills`,
   `<repo>/.agents/skills`, `~/.claude/skills`, `<repo>/.claude/skills`,
   `~/.claude/plugins` and `~/.codex/skills`, e.g.
   `grep -rl --include=SKILL.md '^policy: true' <those dirs> 2>/dev/null` (exit 2 only means a dir is missing). If none exist, that is a
   concern in its own right: say which policy areas went unchecked. If
   the intent names a mock, read it and set `mock`.
3. Requirements: testable statements with ids (R1, R2...) and an acceptance check a
   test could encode. Each requirement, check included, is at most 3 lines; split one
   that needs more.
4. Design: components touched, data changes, interfaces, failure modes, observability,
   rollback. No file lists or ordering; that is the plan's job.
5. Concerns, first in the file: every conflict with a policy skill, another
   requirement, or the current code. Each in exactly this shape, at most 6 lines:

   ```markdown
   ### C<n>: <title>
   <the conflict and its concrete failure case>
   Owner: <who decides> (<the policy or document it comes from>).
   Resolved by:
   ```

   Number from C1 with no gaps. Leave `Resolved by:` empty; the owner fills it in
   (step 8) before engineering sees the spec. Solo, you are every owner; still write
   the line. Tools check this shape, so do not vary it.
6. Carry forward every open question from the intent; check every affected system is
   covered.
7. Set `risk` and `generated_by`. `commit` is `git rev-parse --short HEAD` and records
   the code the spec read. Skills live outside the repo, so the commit does not record
   them: `skills` maps each SDLC and policy skill applied to the first 12 hex digits of
   `shasum -a 256 <its SKILL.md>`. Branch `spec/<change_id>`, commit `docs(spec): <change_id>`
   per Conventions, and put it up for review (a PR, or show a summary and the path if
   there is no remote).
8. Resolve concerns as an interview: one message per concern, stating it in two or
   three lines and asking one question, e.g. "accept as proposed, change it, or drop
   the requirement?". Wait for the answer. Write the owner's decision into the concern
   as `Resolved by: <owner>, <date>: <decision in their words>`, and update any
   requirement or design text the decision changes. Then do the same for each open
   question the owner wants to answer now; the rest stay carried forward. Commit each
   round on the spec branch.
9. Approval: the product owner checks the spec solves the stated problem. Only when
   every concern has `Resolved by:` (and `tech_lead_signoff` for high risk) do they set
   `status: approved`, `approved_by`, `approved_on`; then accept per Conventions (merge
   the PR, or `--no-ff` merge the branch locally). That acceptance starts the `plan`
   skill.
