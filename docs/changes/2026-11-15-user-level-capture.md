---
id: 2026-11-15-user-level-capture
tier: 2
status: approved
requester: Patrick Priestley, in chat on 2026-11-15 ("Can we do this next ... User-level capture, so sessions from your other work flow in. Ten sessions from one repository is too small a base to find skill failures in.")
approvers: [Patrick Priestley, 2026-11-15]
---
# Sessions in the owner's other repositories are captured, where the owner has said so

## Goal

Sessions the owner runs in other repositories than this one reach the archive and the
store, so that the graders and labels have more than one repository's sessions to find a
failure of the `change` skill in. No session is captured from a repository the owner has
not named.

## Probed facts

- Exact source (`.claude/settings.json` of this repository, and record
  `2026-11-09-skill-transcripts`, concern C4, resolved 2026-11-10): the `Stop` and
  `SessionEnd` hooks that run `transcripts archive` are this repository's own. The owner
  ruled "this repository and its `dispatch` worktrees", to be "widened later if the scores
  prove useful". A session anywhere else is not captured.
- Exact source (`plugins/change-record/bin/transcripts`, `cmd_archive`): `archive` does
  nothing when `AGENT_TRANSCRIPTS` is unset, and otherwise archives whatever session the
  hook names; it has no notion of scope. The entry's `repository` is the working folder's
  `origin` URL, normalised (`github.com/owner/name`), or none. `import` takes sessions of
  the current repository or of each `--repo URL`.
- Verified against the real system (Claude Code 2.1.325 in this container, 2026-11-15, two
  sessions on Haiku in two scratch folders that are no repository): a `Stop` hook in a
  plugin's `hooks/hooks.json`, loaded with `--plugin-dir`, fired, with `CLAUDE_PLUGIN_ROOT`
  set to the plugin's folder; and a `Stop` hook in a settings file given with `--settings`
  fired. Each got JSON on standard input with `session_id`, `transcript_path` and `cwd`,
  and the transcript file was there.
- Verified against the real system (the same CLI, 2026-11-15): a throwaway plugin with a
  `Stop` hook, put in a local marketplace and installed with `claude plugin install
  --scope user`, fired its hook in a session started in an unrelated folder with no
  `--plugin-dir`. It was then uninstalled and the marketplace removed.
- Exact source (`claude plugin install --help`, 2.1.325): the scope of an install is
  `user` (the default), `project` or `local`.
- Verified against the real system (`transcripts archive` with `AGENT_TRANSCRIPTS` unset, in
  this container, ten runs): it returns in 61 ms at the median, 72 at most.
- Verified against the real system (the store, read with the read key through the
  environment `agent-workflow-admin`, 2026-11-15): 14 sessions, 267 chunks, 60.4 MB of
  redacted text before compression, all sent with redaction version 1.
- Exact source (`bin/transcripts`, `REDACTION = 2`, and record
  `2026-11-14-redact-account-id`, Outcome): a push with the present code sends every
  session whose archive a machine still holds again, as a new generation, and the rows of
  version 1 stay. The store can therefore about double before one new session arrives.
- Verified against the real system (the 23 transcripts of one long cloud session with its
  subagents, measured on 2026-11-14 for that record): 48.8 MB before redaction.
- Assumed: the store's plan allows 500 MB of database. Not read from the project.
- Exact source (`bin/transcripts`, `cmd_archive`): when the hook's JSON was read and
  `AGENT_TRANSCRIPTS_URL` is set, `archive` starts `push --background` whether or not it
  archived anything, and a push sends every unsent session in the archive.
- Exact source (`bin/transcripts`, `normalise_url`): a repository is its `origin` as
  `host/owner/name` in lower case; an `origin` that is a local path becomes that absolute
  path, in lower case.
- Exact source (`bin/dispatch`): its children run with `--plugin-dir` on this plugin.
- Exact source (`plugins/change-record/outcome-evals/run.py`, `PLUGIN_PARTS`): the outcome
  evals give their plugin arm a copy of the plugin without a `hooks` folder, and run both
  arms with no setting sources.
- Exact source (`plugins/change-record/README.md`, "Keys"): on a laptop the insert-only key
  is a file in `~/.config/agent-transcripts/`; in a cloud environment it is a network
  secret.
- Not probed: how a cloud session in another repository would come to have this plugin.
  `claude plugin install` takes a plugin from a marketplace, and the only marketplace this
  plugin is in is this repository, which is private.

## Problem

Everything the graders and labels have seen is fourteen sessions of one repository, most of
them this project's own work on itself. Record `2026-11-12-session-quality` cannot draft an
edit to the skill until a label confirms a failure of the skill's text (its C5), and in
those sessions no label has. The owner works with Claude Code in other repositories every
day; none of that is captured.

Widening capture is a privacy change. A transcript holds file contents and command output
of the repository it ran in. Redaction takes out addresses, keys and account ids, not code.
A hook that fires for every session would send an employer's or a client's code to the
owner's personal store.

## Requirements

- R1. `transcripts archive --scoped` archives a session only when its repository matches
  the owner's scope list, `${XDG_CONFIG_HOME:-~/.config}/agent-transcripts/scope`: one
  pattern a line, `#` for a comment, `!pattern` to exclude, an exclusion winning over any
  match. A pattern is matched against the whole normalised repository
  (`github.com/owner/name`), without regard to case, with the shell's wildcards, `*`
  crossing `/`: `github.com/Owner/*` is every repository of that owner. Check:
  `bin/transcripts.test.sh`, sessions in a repository that matches, one that does not, one
  excluded, and a pattern written in the capitals the URL has.
- R2. With `--scoped`, each of these archives nothing, starts no push, prints nothing and
  exits 0: no scope list; an empty one; no line that matches; a line that excludes; a
  session outside any repository; a repository with no `origin`; an `origin` that is a
  local path. Check: the same suite, each case, with an archive that already holds an
  unsent session of a repository in scope: the archive is seen unchanged and the stand-in
  store to get no request.
- R3. `transcripts archive` without `--scoped` does what it does today, so this
  repository's own hook and `dispatch`'s worktrees are captured as before. Check: the
  existing assertions pass unchanged.
- R4. `transcripts scope [DIR]` says whether the repository at DIR (default: here) is in
  scope and by which line, or which of R2's seven reasons keeps it out, then the size of
  the archive on this machine; it exits 0 when in scope and 1 when not. Check: the same
  suite, in scope and each reason.
- R5. The plugin carries the hook: `hooks/hooks.json` runs
  `"${CLAUDE_PLUGIN_ROOT}/bin/transcripts" archive --scoped || true` on `Stop` and
  `SessionEnd` with a time limit of 10 seconds, as the repository's own hook has. Check: a
  test reads the file for the command, the two events and the limit; and real sessions,
  with the plugin installed for the user from a local marketplace, in a scratch repository
  on a scratch scope list (archived) and in one off it (not archived).
- R6. `transcripts import --scoped` registers the sessions already under
  `~/.claude/projects` whose repository is in scope. Check: the same suite.
- R7. Nothing else about a captured session changes: the same index entry, the same
  redaction, the same store. Check: the store suite passes unchanged.
- R8. `transcripts report --store` says how many sessions the store holds and how many MB
  of redacted text, by redaction version. Check: `bin/transcripts-judge.test.sh`, against
  the stand-in store.

## Options and concerns

Options considered:

- A. A hook in the owner's user settings, written by a new `transcripts hook --install`.
  It needs the path of a checkout that stays put, and it edits a file of the owner's that
  other tools also write.
- B. The plugin ships the hook, and the owner installs the plugin for their user.
  Recommended: one step, the path is always the plugin's own, and removing the plugin
  removes the hook.
- C. Capture every session and choose what to send at push time. Rejected: the archive
  would hold unredacted copies of repositories the owner never meant to keep.
- D. No scope list: install the plugin with `--scope local` in each repository to be
  captured, so that Claude Code's own enablement is the list. Not recommended: it ties
  capture to having the skill, so a repository where the owner wants the skill and no
  capture cannot be said; and each repository needs its own install. It needs none of R1,
  R2, R4 and R6, which is its merit. C2 puts the choice to the owner.

Concerns:

### C1: which repositories
A transcript carries a repository's code. Failure case: the hook sends a client's source to
the owner's personal store. Recommended: nothing is in scope until a line of the owner's
scope list names it; the list is the owner's file on the owner's machine and is not in any
repository; no line is written by the tool. The owner writes the lines, and should name
repositories or owners they hold the rights to, not `*`. Owner: Patrick Priestley.
Resolved: deny by default, by the owner's own list, as recommended. Patrick Priestley, in
chat, 2026-11-15.

### C2: where the hook lives, and that it then runs for everyone who installs the plugin
Failure case of option B: a stranger installs the plugin and every stop of every session
starts `transcripts archive --scoped`. It does nothing without `AGENT_TRANSCRIPTS` and a
scope list, both theirs to set, and nothing can reach the owner's store without the owner's
key; it costs them about 60 ms at each stop (Probed facts). Failure case of option D: the
owner wants the skill in a client's repository, installs the plugin there, and capture
comes with it. Recommended: option B, the plugin ships the hook and the scope list says
where it captures, and the README says so. Owner: Patrick Priestley.
Resolved: option B, the hook in the plugin with the scope list. Patrick Priestley, in chat,
2026-11-15.

### C3: the store fills
Fourteen sessions are 60 MB of text, one long session alone was 49 MB before redaction, and
the next push after redaction version 2 sends again whatever archives a machine still
holds. Failure case: the store's allowance fills, and pushes then fail for every session,
this repository's included; nobody is watching, because only the read key can see its
size. Recommended: no cap in this change. R8 puts the store's size at the top of the
report the owner already reads, and R4 the archive's size beside the scope. The owner
looks at both when a report is read, and decides at 250 MB whether to delete the rows of
version 1 or cap what is sent. Owner: Patrick Priestley.
Resolved: show the size, no cap, as recommended. Patrick Priestley, in chat, 2026-11-15.

### C4: cloud sessions in other repositories
How a cloud session elsewhere would get this plugin is not known (Probed facts). Failure
case: the owner expects cloud sessions in other repositories to be captured and they are
not. Recommended: this change covers the owner's own machines only, and says so in the
README; cloud sessions in other repositories are their own change, with that mechanism
probed first. Owner: Patrick Priestley.
Resolved: the owner's own machines only. Patrick Priestley, in chat, 2026-11-15.

## Decisions

- Scope is by repository, read from the working folder's `origin`, as the index entry
  already records it. Rejected: by folder path, which differs between machines and
  worktrees; and by whether the `change` skill was used, which is only known at the end of
  a session and would drop the sessions the owner wants the general judges to read.
- Deny by default. `--scoped` with no list captures nothing. Rejected: a list of
  exclusions only, under which a new client's repository is captured until someone
  remembers to exclude it.
- A session outside any repository, in one with no `origin`, or in one whose `origin` is a
  local path is never in scope, whatever the list says. Rejected: a `*` that takes those
  too. The first are the sessions least likely to be about code and most likely to be
  personal; a path names a folder on one machine, not a project.
- An out-of-scope stop starts no push. Rejected: starting one as `archive` does today,
  which is harmless but makes a session in a client's repository the trigger for traffic
  to the store.
- Patterns are matched without regard to case, because the repository is kept in lower
  case and the owner will write the name as GitHub shows it.
- The repository's own hook stays, unscoped. In this repository, and in every worktree
  `dispatch` cuts (its children load the plugin), both hooks fire; the second finds nothing
  new or the session's lock held, which `archive` already treats as nothing to do. Rejected: removing it, which would stop capture in `dispatch`'s worktrees and in a
  checkout where the plugin is not installed.
- The scope list is plain lines, not JSON, so the owner can write it with an editor and
  read it at a glance.
- Decided while building task 1. A session is in scope only when the folder it is in at the
  stop and the folder its transcript began in are both in scope. Rejected: the stop's
  folder alone, as the index entry takes its repository; a session begun in a client's
  repository and moved to one on the list would then be kept whole. What this does not
  cover: a session that visits another folder in between, or reads a file by its full
  path; scope is by where a session runs, not by what it reads.
- Decided while building task 1. A scope list that is there and cannot be read archives
  nothing and starts no push, and says so on standard error: it is a fault to see, not
  one of R2's seven quiet cases. `#` starts a comment anywhere on a line, since no
  repository's name holds one. `import --scoped` with `--repo` or `--evals` is a usage
  error, so that the list alone says what is taken. When several of the seven reasons
  hold, `transcripts scope` gives the list's before the folder's.
- The outcome evals are unaffected: their plugin copy has no `hooks` folder and their
  agents load no user settings.

## Tasks

One pull request each.

1. **Scope.** `bin/transcripts`: the scope list, `archive --scoped`, `import --scoped`,
   `transcripts scope`, and the store's size in `report --store`. Test:
   `bin/transcripts.test.sh` and `bin/transcripts-judge.test.sh`. Red today: a session in a
   repository on the list is not archived, because `--scoped` is a usage error; the
   out-of-scope cases print a usage line where R2 asks for nothing; `transcripts scope`
   does not exist; the report has no size. That an out-of-scope session leaves the archive
   empty is true today for the wrong reason, so that guard is shown by breaking it.
2. **The hook.** `hooks/hooks.json` and the README's section on capture. The manifest
   needs no change: the probe's plugin named no hooks in its manifest and its hook fired.
   Test: the file's content in `bin/transcripts.test.sh`; the real sessions of R5, pasted
   into Outcome.

## Checks

`bash plugins/change-record/bin/transcripts.test.sh` and the other change-record suites;
`outcome-evals/run.test.sh`, for the plugin copy. Real use: the plugin installed for the
user from a local marketplace in this container, then two real sessions with no
`--plugin-dir` in scratch repositories, one on a scratch scope list and one off it, with a
scratch archive; the archive after each; the plugin uninstalled after. Error path: no
scope list. The owner's own machine
is the owner's step: install the plugin for the user, set `AGENT_TRANSCRIPTS`, write the
scope list. The independent reviewer should attack: a session captured from a repository
the list does not name; a pattern that matches more than it reads as; and the hook failing
or slowing a session.

## Review

One round, by a fresh session with no context but the record and the repository
(`plugins/change-record/bin/record-review`), on 2026-11-15: 1 critical, 7 important, 5
minor. Each was checked against the repository.

- Critical, fixed. The mechanism of the recommended option, a plugin installed for the
  user firing its hook in every repository, was not probed. It is now (Probed facts), and
  the real use in Checks installs the plugin that way.
- Important, fixed. A sentence on how a cloud session loads a plugin was labelled exact
  source and is in no source: it is now "not probed", and C4 says the mechanism is not
  known. The store's baseline ignored redaction version 2: C3 now counts the resend. Two
  of task 1's tests would have passed today: R2 now asks for no output and no push, with an
  archive that holds something to send, and the task says which guard is shown by breaking
  it. Whether an out-of-scope stop pushes: it does not (Decisions). Case and `/` in
  patterns, and a local-path `origin`: R1, R2 and Decisions. Claude Code's own install
  scopes as the list: option D, put to the owner in C2. No way to see the store's size: R8.
- Minor, fixed: the seven reasons named; `|| true` and the time limit in R5; evidence for
  the 60 ms and the 49 MB; both hooks in `dispatch`'s worktrees; the manifest.

Open: no second round was run, so these fixes have not been read by a fresh session.

## Outcome

### Task 1: the scope list and its commands

Built test first: 47 assertions of `bin/transcripts.test.sh` and 2 of
`bin/transcripts-judge.test.sh` failed before the code (`--scoped` a usage error, no
`transcripts scope`, no size in the report), committed red, then the code. Suites after:
transcripts 342, transcripts-judge 228, transcripts-store 156, transcripts-grade 212, none
failing.

Guards shown by breaking them by hand, one at a time, each caught by a named test: 35
breaks of `bin/transcripts`. Among them the one task 1 said is true today for the wrong
reason: with `--scoped` made to archive everything, 21 assertions fail. Also: no list, an
empty list and no match each treated as in scope; exclusions ignored, or winning only
when first; patterns keeping their case, or matching a part of the repository; only one of
the two folders checked; an out-of-scope stop starting a push, or printing; an unreadable
list treated as in scope; `import --scoped` ignoring the list; the store's size counting
chunks, reading one page, or not split by version. Two breaks were caught by one assertion
only (the reason `transcripts scope` prints): with "no repository" or "no origin" not
checked, the session still falls to a later refusal, so nothing was archived.

Real use, in this container, on this session's own transcript (43 MB with 22 subagent
transcripts) in the real checkout, with a scratch scope list and a scratch archive:

```
--- 1. no scope list
exit 0 ; archive: (none)
not in scope: there is no scope list at <scratch>/config/agent-transcripts/scope
the archive <scratch>/archive holds 0 sessions, 0.0 MB of transcripts, not redacted
exit 1
--- 2. a list that names another owner
exit 0 ; archive: (none)
not in scope: no line of <scratch>/config/agent-transcripts/scope matches github.com/patrickpriestley/agent-workflow
exit 1
--- 3. the list names this repository's owner (github.com/PatrickPriestley/*)
exit 0 in 615 ms; archive: locks parts sessions ; sessions: 1
github.com/patrickpriestley/agent-workflow is in scope: line 2 of <scratch>/config/agent-transcripts/scope, github.com/PatrickPriestley/*
the archive <scratch>/archive holds 1 session, 53.3 MB of transcripts, not redacted
exit 0
--- 4. the same session, but the stop is in a repository the list does not name
exit 0
not in scope: no line of <scratch>/config/agent-transcripts/scope matches github.com/someone-else/client-code
exit 1
--- 5. timing out of scope (no list), ten runs
55 56 56 57 57 57 59 59 59 63 ms
```

And `transcripts report --store` on the real store, read through the environment
`agent-workflow-admin`: it agrees with the probe of the same day.

```
# Change skill report

The store holds 14 sessions and 60.4 MB of redacted text: under redaction 1, 14 sessions and 60.4 MB.
```

Not done here: the hook itself and the README (task 2). Until task 2 nothing calls
`archive --scoped`.
