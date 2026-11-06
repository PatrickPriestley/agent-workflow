# Pinned install (#18)

## Problem
`install.sh` linked the working checkout. Checking out a feature branch to work on
agent-workflow changed the skills, rules and commands every agent on the machine ran, and a
teammate who cloned the repo got whatever branch they happened to be on.

## Change
- By default the installer clones this checkout into
  `${XDG_DATA_HOME:-~/.local/share}/agent-workflow` and checks out `origin/main` (or `main`
  when there is no `origin/main`) detached, then links from there.
- `--ref REF` pins a tag, branch or commit. An unknown ref stops before anything changes.
- A pinned clone with local changes, or a non-git folder at that path, stops the install.
- `--dev` keeps the old behaviour: link this checkout. `--dev` with `--ref` is a usage error.
- `--dry-run` reports the pin without cloning.
- Update: `git fetch` in the checkout, rerun `install.sh`; the clone fetches the commit from
  the checkout, so no network access is needed from the pinned copy.

## Tests (install.test.sh)
Default pin; branch switch in the checkout does not change the install; rerun after a new
commit updates; `--ref` tag; unknown ref; local changes; non-git folder; `--dry-run`; no
`origin/main` falls back to `main`; `--dev` links the checkout.

## Mutation check
Each guard was broken in turn and the suite failed: local-changes check (5 failures),
`origin/main` preference (4), checkout target (5), ref resolution (7).

## Not done
Release tags and a version bump are left to the owner.
