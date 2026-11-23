#!/usr/bin/env bash
# Tests for the shell allowlists of the gh-aw agent workflows, in each source
# and its lock: none may allow a command that runs other commands or reaches
# every subcommand (bare bash, bash -c, sed, git -C, git -c, env, xargs, eval).
set -u
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
root="$(cd "$here/.." && pwd)"
pass=0; fail=0; CURRENT=""
it() { CURRENT="$1"; }
ok()  { pass=$((pass+1)); printf '  ok   %s\n' "$CURRENT"; }
bad() { fail=$((fail+1)); printf '  FAIL %s\n       %s\n' "$CURRENT" "$1"; }
lacks() { printf '%s' "$1" | grep -qE -- "$2" && bad "unexpected [$(printf '%s' "$1" | grep -oE -- "$2" | head -1)]" || ok; }

# Allowlist entries: quoted "- " items in the source's tools.bash, Bash(...) in the lock.
risky_src='^ *- "(bash(:\*)?|bash -c[^"]*|sed[^"]*|git -C[^"]*|git -c[^"]*|env[^"]*|xargs[^"]*|eval[^"]*|sh[^"]*)"$'
risky_lock='Bash\((bash(:\*)?|bash -c[^)]*|sed[^)]*|git -C[^)]*|git -c[^)]*|env[^)]*|xargs[^)]*|eval[^)]*|sh(:[^)]*)?)\)'

for name in ci-diagnose ci-fix property-scout verify; do
  md="$root/.github/workflows/$name.md"; lock="$root/.github/workflows/$name.lock.yml"
  tools="$(awk '/^tools:/{t=1;next} t&&/^[a-z]/{t=0} t' "$md" 2>/dev/null)"
  it "$name: the source and lock exist and the source has a bash allowlist"
  [ -n "$tools" ] && [ -s "$lock" ] && ok || bad "$md or $lock missing, or no tools:"
  it "$name: no entry in the source runs other commands or every git subcommand"
  lacks "$tools" "$risky_src"
  it "$name: nor in the lock"
  lacks "$(cat "$lock" 2>/dev/null)" "$risky_lock"
done

it "ci-diagnose runs tests only from the failing commit's worktree"
grep -qF -- '- "bash /tmp/gh-aw/agent/ci/head/:*"' "$root/.github/workflows/ci-diagnose.md" && ok || bad "no worktree bash prefix"
it "ci-diagnose's prompt does not repeat the old claim that cd with && is refused"
grep -q 'joined to `cd` with `&&`' "$root/.github/workflows/ci-diagnose.md" && bad "old sentence still there" || ok
it "this test runs in CI"
grep -qF 'bash bin/agent-allowlists.test.sh' "$root/.github/workflows/test.yml" && ok || bad "not in test.yml"

echo; echo "passed=$pass failed=$fail"
[ "$fail" -eq 0 ]
