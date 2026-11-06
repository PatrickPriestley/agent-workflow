#!/usr/bin/env bash
# scratch.sh: create two local branches for trying PR-Agent with pr-agent/try.sh. They start
# from the current branch (so they carry try.sh), are made in a temporary worktree, so the
# checkout is untouched, and are never pushed. Review them with try.sh --base <that branch>.
#
#   pr-agent/scratch.sh [--base REF] [--force]
#
# scratch/pr-agent-no-test  changes agent-review's default timeout (900 to 300 seconds) with no
#                           test and no doc change: the review skill should flag both.
# scratch/pr-agent-canary   adds .env and config/secrets.yml holding a fake secret (the canary,
#                           recorded in .git/pr-agent/canary.txt) next to an ordinary README
#                           change. With --verbose, the canary must not appear in the log.
#
# --force deletes and recreates the two scratch/ branches. Exit 0, or 2 for a usage problem.
set -uo pipefail
usage() { echo "usage: scratch.sh [--base REF] [--force]" >&2; exit 2; }
fail() { echo "scratch.sh: $*" >&2; exit 2; }

base_ref=""; force=false
while [ "$#" -gt 0 ]; do
  case "$1" in
    --base) [ -n "${2:-}" ] || usage; base_ref="$2"; shift 2 ;;
    --force) force=true; shift ;;
    *) usage ;;
  esac
done

git rev-parse --git-dir >/dev/null 2>&1 || fail "not inside a git repository"
root="$(git rev-parse --show-toplevel)"; cd "$root" || exit 2
if [ -z "$base_ref" ]; then
  base_ref="$(git symbolic-ref --quiet --short HEAD || git rev-parse HEAD)"
fi
case "$base_ref" in scratch/pr-agent-*) fail "run this from the branch the scratch branches should start from, not $base_ref";; esac
base="$(git rev-parse --verify --quiet "$base_ref^{commit}")" || fail "unknown base $base_ref"
git cat-file -e "$base:bin/agent-review" 2>/dev/null || fail "$base_ref has no bin/agent-review: run this in agent-workflow"
git cat-file -e "$base:pr-agent/try.sh" 2>/dev/null || fail "$base_ref has no pr-agent/try.sh, so the scratch branches could not run it; pass --base"

branches=(scratch/pr-agent-no-test scratch/pr-agent-canary)
for b in "${branches[@]}"; do
  git rev-parse --verify --quiet "refs/heads/$b" >/dev/null || continue
  $force || fail "$b exists; rerun with --force to recreate both scratch branches"
  [ "$(git rev-parse --abbrev-ref HEAD)" != "$b" ] || fail "$b is checked out; switch away first"
  git branch -q -D "$b" || fail "cannot delete $b"
done

state="$(git rev-parse --path-format=absolute --git-path pr-agent)"
mkdir -p "$state" || fail "cannot create $state"
wt="$(mktemp -d)/wt"
cleanup() { git worktree remove --force "$wt" >/dev/null 2>&1; rm -rf "$(dirname "$wt")"; }
trap cleanup EXIT

# The scratch commits skip the repository's hooks (--no-verify): they are never pushed, and a
# commit-gate test command would reject the deliberately untested change.
commit() { git -C "$wt" add -A && git -C "$wt" commit -q --no-verify -m "$1" || fail "commit failed in $wt"; }

git worktree add -q -b scratch/pr-agent-no-test "$wt" "$base" || fail "cannot create the worktree"
sed -i.orig 's/^target=""; reviewer=""; model=""; timeout=900; goal=""$/target=""; reviewer=""; model=""; timeout=300; goal=""/' "$wt/bin/agent-review"
rm -f "$wt/bin/agent-review.orig"
[ -n "$(git -C "$wt" status --porcelain)" ] || fail "the timeout line in bin/agent-review has changed; update scratch.sh"
commit "feat(agent-review): shorten the default reviewer timeout to five minutes"

git -C "$wt" checkout -q -b scratch/pr-agent-canary "$base" || fail "cannot create scratch/pr-agent-canary"
canary="SYNTHETIC_CANARY_$(od -An -N8 -tx1 /dev/urandom | tr -d ' \n')"
printf '%s\n' "$canary" > "$state/canary.txt"
printf '# fake, for a PR-Agent test\nAPI_KEY=%s\n' "$canary" > "$wt/.env"
mkdir -p "$wt/config"
printf '# fake, for a PR-Agent test\napi_key: %s\n' "$canary" > "$wt/config/secrets.yml"
printf '\nSee `pr-agent/try.sh` to try PR-Agent locally.\n' >> "$wt/README.md"
git -C "$wt" add -f .env config/secrets.yml
commit "docs(readme): point to the PR-Agent trial script"

cat <<EOF
Created scratch/pr-agent-no-test and scratch/pr-agent-canary from $base_ref (local only).
Canary: $state/canary.txt

1. Does the skill change the review?
     git switch scratch/pr-agent-no-test
     pr-agent/try.sh --base $base_ref               # should flag the missing test and the stale README
     pr-agent/try.sh --base $base_ref --no-skill    # control
2. Do the globs keep secrets out?
     git switch scratch/pr-agent-canary
     pr-agent/try.sh --base $base_ref --verbose; grep -c "\$(cat $state/canary.txt)" .git/pr-agent/<run>/log.txt   # want 0
     pr-agent/try.sh --base $base_ref --verbose --no-ignore   # control: the canary should appear
3. Does a failed call exit non-zero?
     OPENROUTER__KEY=invalid pr-agent/try.sh --base $base_ref; echo "exit \$?"
EOF
