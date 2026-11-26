# Reusable workflows

Six of this repository's plain workflows (no model in them) can be called from another
repository, so it reports to the same transcript store and gets every fix here without copying
files:

| Workflow | What it does in the caller |
|---|---|
| `probe-report.yml` | The weekly report on the caller (or every repository) to the run's summary |
| `agent-sessions.yml` | Collects a finished Claude agent run's session into the store |
| `probe-ci-fix.yml` | Labels a held probe `ci-fix` once its test run fails |
| `probe-score.yml` | Scores one probe against its sealed key, stores the scores, closes it |
| `probe-score-auto.yml` | Every three hours, dispatches `probe-score.yml` for each probe that is ready |
| `probe-sweep.yml` | Daily, deletes closed probes' branches, closes probes left open 14 days, and closes gh-aw's expired issues |

Each checks out its tools (`bin/`, `plugins/change-record`) from this repository, never the
caller's code: they read the caller through the GitHub API and its artifacts. `github.repository`
in them is the caller, so everything they store or report is the caller's.

## Updates and pinning

Calling `@main` takes every change merged here, on its next run, as asked. It also means the
caller runs this repository's latest code with the secrets it passes. To hold a version instead,
call a commit and give the same commit as `tools-ref`:

```text
uses: PatrickPriestley/agent-workflow/.github/workflows/probe-report.yml@<commit>
with:
  tools-ref: <commit>
```

`tools-repository` (default `PatrickPriestley/agent-workflow`) points the tools at a fork.

## Secrets

Pass the store's secrets by name rather than `secrets: inherit`, so each workflow gets only what
it uses:

- `AGENT_TRANSCRIPTS_URL` and `AGENT_TRANSCRIPTS_INSERT_KEY`: the store and its publishable,
  insert-only key (plugins/change-record/store). Every repository may share one store: the report
  functions take a repository, and each row carries its own.
- `PROBE_KEY`: opens the planter's sealed answer keys (probe scoring only).
- `PROBE_TOKEN`: a fine-grained token that can label pull requests, so the label starts CI fix
  (probe-ci-fix only).

A called workflow gets no more permissions than the calling job grants, so each caller below
grants what its workflow needs.

## Callers

Each block is a whole file in the caller's `.github/workflows/`.

The weekly report (`probe-report.yml`), on the caller alone; tick "all repositories" by hand
for every repository in the store:

```yaml
name: probe-report
on:
  schedule:
    - cron: "17 12 * * 2"
  workflow_dispatch:
    inputs:
      all_repositories:
        type: boolean
        default: false
permissions:
  contents: read
jobs:
  report:
    uses: PatrickPriestley/agent-workflow/.github/workflows/probe-report.yml@main
    with:
      all_repositories: ${{ inputs.all_repositories || false }}
    secrets:
      AGENT_TRANSCRIPTS_URL: ${{ secrets.AGENT_TRANSCRIPTS_URL }}
      AGENT_TRANSCRIPTS_INSERT_KEY: ${{ secrets.AGENT_TRANSCRIPTS_INSERT_KEY }}
```

The session collector (`agent-sessions.yml`). List the caller's gh-aw agents that run on
Claude; leave out any that hold an answer key, as this repository leaves out its planter:

```yaml
name: agent-sessions
on:
  workflow_run:
    workflows: ["Verify PR claims", "CI diagnosis"]
    types: [completed]
permissions:
  actions: read
  contents: read
jobs:
  collect:
    uses: PatrickPriestley/agent-workflow/.github/workflows/agent-sessions.yml@main
    secrets:
      AGENT_TRANSCRIPTS_URL: ${{ secrets.AGENT_TRANSCRIPTS_URL }}
      AGENT_TRANSCRIPTS_INSERT_KEY: ${{ secrets.AGENT_TRANSCRIPTS_INSERT_KEY }}
```

### Probes

Scoring needs probes: pull requests opened by a planter, `probe-plant.lock.yml`, with their key
sealed in its run's `probe-key` artifact. The planter is an agentic workflow written for this
repository's files and is not shared yet. With one in place, the scorer must be named
`probe-score.yml` and keep this run name: `bin/probe-ready` finds scoring runs by both.

```yaml
name: probe-score
run-name: probe-score #${{ inputs.pr }}
on:
  workflow_dispatch:
    inputs:
      pr:
        required: true
        type: string
      key_run:
        required: true
        type: string
      close:
        type: boolean
        default: true
permissions: {}
jobs:
  score:
    permissions:
      contents: read
      actions: read
      pull-requests: write
      issues: write
    uses: PatrickPriestley/agent-workflow/.github/workflows/probe-score.yml@main
    with:
      pr: ${{ inputs.pr }}
      key_run: ${{ inputs.key_run }}
      close: ${{ inputs.close }}
    secrets:
      PROBE_KEY: ${{ secrets.PROBE_KEY }}
      AGENT_TRANSCRIPTS_URL: ${{ secrets.AGENT_TRANSCRIPTS_URL }}
      AGENT_TRANSCRIPTS_INSERT_KEY: ${{ secrets.AGENT_TRANSCRIPTS_INSERT_KEY }}
```

```yaml
name: probe-score-auto
on:
  schedule:
    - cron: "23 */3 * * *"
  workflow_dispatch:
permissions:
  contents: read
  pull-requests: read
  issues: read
  actions: write
jobs:
  dispatch:
    uses: PatrickPriestley/agent-workflow/.github/workflows/probe-score-auto.yml@main
```

The sweep needs no secret: the built-in token does it all.

```yaml
name: probe-sweep
on:
  schedule:
    - cron: "29 5 * * *"
  workflow_dispatch:
permissions:
  contents: write
  pull-requests: write
  issues: write
jobs:
  sweep:
    uses: PatrickPriestley/agent-workflow/.github/workflows/probe-sweep.yml@main
```

For loud probes, name the caller's test workflow:

```yaml
name: probe-ci-fix
on:
  workflow_run:
    workflows: ["test"]
    types: [completed]
permissions:
  contents: read
  pull-requests: read
  issues: read
jobs:
  label:
    uses: PatrickPriestley/agent-workflow/.github/workflows/probe-ci-fix.yml@main
    secrets:
      PROBE_TOKEN: ${{ secrets.PROBE_TOKEN }}
```
