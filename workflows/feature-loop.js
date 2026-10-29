export const meta = {
  name: 'feature-loop',
  description: 'Execute a plan with fresh context per task group: implementer, then review and fix until approved',
  whenToUse: 'Optional, for feature-loop changes with many tasks across separate modules',
  phases: [
    { title: 'Implement', detail: 'one fresh agent per task group, TDD, one commit per task' },
    { title: 'Review', detail: 'does it do what the tasks require, and is it correct; concrete failure cases required' },
  ],
}

// args: {
//   repo: '/abs/path',                       the git repo (clean tree)
//   plan: '/abs/path/docs/plans/x.md',       the design note with its task list
//   groups: [{ name, tasks, lines, context }], sequential; lines like "22-94"; context = what earlier groups built
//   rules: 'free text appended to every brief'  (author identity, commands never to run, ...)
//   fixRounds: 2,                            review/fix rounds per review stage (default 2)
//   model: undefined,                        optional override for every agent (e.g. 'sonnet' for a smoke run)
// }
// Returns: per group, the implementer report, the final verdict of each review, and open minor issues.

const a = args || {}
if (!a.repo || !a.plan || !Array.isArray(a.groups) || a.groups.length === 0) {
  throw new Error('feature-loop needs args.repo, args.plan and a non-empty args.groups')
}
const FIX_ROUNDS = a.fixRounds ?? 2
const opts = (extra) => (a.model ? { model: a.model, ...extra } : extra)
const rules = a.rules ? `\n\n## Standing rules\n${a.rules}` : ''

const IMPL = {
  type: 'object',
  properties: {
    commits: { type: 'array', items: { type: 'string' }, description: 'short SHAs, one per task, in order' },
    tests: { type: 'string', description: 'the final test summary line(s), verbatim' },
    deviations: { type: 'string', description: 'every departure from the plan, or "none"' },
    concerns: { type: 'string' },
    report: { type: 'string', description: 'what was implemented, per task, for the reviewers' },
  },
  required: ['commits', 'tests', 'deviations', 'report'],
}
const QUALITY = {
  type: 'object',
  properties: {
    approved: { type: 'boolean', description: 'true when nothing Critical or Important remains' },
    strengths: { type: 'string' },
    issues: { type: 'array', items: { type: 'object', properties: {
      severity: { type: 'string', enum: ['critical', 'important', 'minor'] },
      file: { type: 'string' }, line: { type: 'integer' },
      summary: { type: 'string' },
      failure_case: { type: 'string', description: 'concrete input and wrong outcome; required for critical and important' },
    }, required: ['severity', 'file', 'summary'] } },
  },
  required: ['approved', 'issues'],
}

const common = (g) => `Repository: ${a.repo} (work only there; the tree is clean at the start of your task).
Plan: ${a.plan}. Read its header (the probed facts) first, then lines ${g.lines} for ${g.name}.
Context: ${g.context || 'see the plan'}${rules}`

const implementBrief = (g) => `You are implementing ${g.name} of an implementation plan, in order, one task at a time.

${common(g)}

The plan lists the tasks, files and tests; it does not contain the code. Write it. If a task cannot be done as described, or the design turns out wrong, stop and report it in "deviations" rather than redesigning silently.

TDD per task: write the tests, run them and confirm they fail the way the plan says, implement, confirm they pass, commit with the plan's commit message. One commit per task. Do not add anything the plan does not name.

Before reporting, self-review: every step of every task done, names as in the plan, nothing extra, the build has no new warnings, the suite passes.

Your final output is the structured report and it must carry real values: "commits" are the short SHAs from \`git log\` for the commits you made, "tests" is the suite's summary line pasted verbatim, "report" says what each task added. A placeholder in any field is a failed task.`

const qualityBrief = (g, impl) => `Review the code quality of ${g.name}. Read-only: do not edit or commit.

${common(g)}

What was implemented: ${impl.report}
Commits: ${impl.commits.join(', ')}.

Review the diff of those commits for correctness bugs the tests do not catch, state that leaks between calls, unclear names, duplication, and test quality (do tests assert behaviour; would a test fail if each guard were removed). Also check it does what the plan's tasks and tests require, with nothing missing and nothing extra; report a gap as an important issue with what the plan asks for.

Every critical or important issue needs a concrete failure case: an input or sequence and the wrong outcome. Findings without one are minor. approved=true means nothing critical or important remains.`

const fixBrief = (g, kind, issues) => `You are fixing ${kind} findings on ${g.name}. Test-first for every behaviour change: write the test, watch it fail, fix it.

${common(g)}

Findings to fix (each was verified by a reviewer; if you disagree with one, say so with evidence instead of applying it):
${JSON.stringify(issues, null, 2)}

Make ONE commit for the batch with a message that names what changed. Report what you changed per finding, the commit SHA, the test summary line, and any finding you rejected and why.`

async function reviewLoop(g, impl, kind, brief, schema, isClean, phase) {
  let verdict = await agent(brief(g, impl), opts({ label: `${kind}:${g.name}`, phase, schema }))
  let rounds = 0
  while (verdict && !isClean(verdict) && rounds < FIX_ROUNDS) {
    rounds++
    const toFix = kind === 'quality'
      ? verdict.issues.filter(i => i.severity !== 'minor')
      : verdict.issues
    log(`${g.name}: ${kind} review found ${toFix.length} issue(s); fix round ${rounds}`)
    const fix = await agent(fixBrief(g, kind, toFix), opts({ label: `fix-${kind}:${g.name}`, phase, schema: IMPL }))
    if (fix) impl = { ...impl, report: `${impl.report}\n\nFix round ${rounds}: ${fix.report}`, commits: [...impl.commits, ...fix.commits], tests: fix.tests }
    verdict = await agent(brief(g, impl), opts({ label: `${kind}:${g.name}:re${rounds}`, phase, schema }))
  }
  return { verdict, impl, rounds }
}

const results = []
for (const g of a.groups) {
  // Groups run one after another: they share files such as the crate root.
  log(`${g.name}: implementing`)
  let impl = await agent(implementBrief(g), opts({ label: `implement:${g.name}`, phase: 'Implement', schema: IMPL }))
  if (!impl) { results.push({ group: g.name, status: 'implementer-failed' }); break }
  if (impl.commits.length === 0) log(`${g.name}: the implementer reported no commits; the reviewers will read git log themselves`)

  const quality = await reviewLoop(g, impl, 'quality', qualityBrief, QUALITY, v => v.approved, 'Review')
  impl = quality.impl
  const minor = quality.verdict ? quality.verdict.issues.filter(i => i.severity === 'minor') : []
  results.push({
    group: g.name,
    status: quality.verdict && quality.verdict.approved ? 'done' : 'review-unresolved',
    impl, review: quality.verdict, fixRounds: quality.rounds, minor,
  })
  if (!(quality.verdict && quality.verdict.approved)) break
}

const stopped = results.length < a.groups.length || results.some(r => r.status !== 'done')
if (stopped) log(`stopped after ${results.length} of ${a.groups.length} group(s); see the last result's status`)
return { results, completed: !stopped }
