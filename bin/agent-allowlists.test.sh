#!/usr/bin/env bash
# Tests for the shell allowlists of the gh-aw agent workflows, read from each
# lock's --allowed-tools list (what Claude is actually given). Every Bash entry
# must be one of the known forms below; anything else fails, so a new or widened
# grant has to be added here on purpose.
#
# A prefix such as "bash bin/:*" is not a boundary (bin/../x matches it, and the
# tests it runs are the pull request's own code). These checks rule out the
# one-line escapes: bare Bash, bash -c, sed, git -C/-c, env, xargs, eval, sh.
set -u
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
root="$(cd "$here/.." && pwd)"
pass=0; fail=0; CURRENT=""
it() { CURRENT="$1"; }
ok()  { pass=$((pass+1)); printf '  ok   %s\n' "$CURRENT"; }
bad() { fail=$((fail+1)); printf '  FAIL %s\n       %s\n' "$CURRENT" "$1"; }

safe='^(cd:\*|safeoutputs:\*'
safe+='|(cat|ls|head|tail|grep|wc|jq|yq|sort|uniq|echo|printf|pwd|date)(:\*)?'   # yq: added by gh-aw to every list
safe+='|git (log|diff|show|status|rev-parse)(:\*)?|git worktree add:\*'
safe+='|git (add|branch|checkout|commit|merge|rm|switch)(:\*)?'                    # added by gh-aw for push-to-pull-request-branch
# Test files, exactly, at the head or in a worktree; no :* (it would allow any argument).
safe+='|bash (/tmp/gh-aw/agent/(ci/head|verify/base)/)?[a-z0-9_./-]+(\.test\.sh|/test-[a-z0-9-]+\.sh|/selftest\.sh)'
safe+='|node --test (/tmp/gh-aw/agent/(ci/head|verify/base)/)?[a-z0-9_./-]+\.test\.(cjs|js|mjs)'
# Tools a pull request description reports results from, with their arguments.
safe+='|bash (bin/mutate|bin/pr-size|plugins/change-record/bin/red-check):\*'
safe+='|python3 -m venv /tmp/gh-aw/agent/venv|/tmp/gh-aw/agent/venv/bin/pip install hegeltest==0\.5\.1|/tmp/gh-aw/agent/venv/bin/python -I:\*'
safe+=')$'

# Codex cannot take a shell allowlist (gh aw v1.2.2 rejects one), so a codex
# workflow is checked for having no edit tool and no write output instead.
checked=0
for md in "$root"/.github/workflows/*.md; do
  name="$(basename "$md" .md)"; lock="${md%.md}.lock.yml"
  engine="$(awk '/^engine:/{if($2!="")print $2; else e=1; next} e&&/^  id:/{print $2; exit}' "$md")"
  [ -n "$engine" ] || continue
  if [ "$engine" = codex ]; then
    it "$name (codex, no allowlist possible): no edit tool and no push or pull request output"
    grep -qE '^  edit:|push-to-pull-request-branch:|create-pull-request:' "$md" && bad "codex workflow can write" || ok
    continue
  fi
  checked=$((checked+1))
  tools="$(grep -o -- "--allowed-tools '\\\\''[^']*'" "$lock" 2>/dev/null | head -1 | sed "s/^--allowed-tools '\\\\''//; s/'\$//; s/\\\\\$//")"
  it "$name: the lock has an --allowed-tools list"; [ -n "$tools" ] && ok || bad "none in $lock"
  bash_entries="$(printf '%s' "$tools" | tr ',' '\n' | grep -E '^Bash(\(|$)')"
  it "$name: no bare Bash (every command)"
  printf '%s\n' "$bash_entries" | grep -qx 'Bash' && bad "bare Bash granted" || ok
  it "$name: every Bash entry is a known form, with no .."
  odd="$(printf '%s\n' "$bash_entries" | sed -n 's/^Bash(\(.*\))$/\1/p' | grep -vE "$safe"; printf '%s\n' "$bash_entries" | grep -F '..')"
  [ -z "$odd" ] && ok || bad "unexpected: $(printf '%s' "$odd" | tr '\n' ' ')"
done
it "the Claude agent workflows were all found (ci-diagnose, ci-fix, property-scout, verify)"
[ "$checked" -ge 4 ] && ok || bad "only $checked checked"

# Claude Code matches "bash bin/:*" only against "bash bin/" and a space, never
# "bash bin/x.test.sh" (run 45173430477), so every test file must be listed exactly.
tests="$(cd "$root" && git ls-files '*.test.sh' 'skills/plan/scripts/test-*.sh' 'plugins/change-record/outcome-evals/checks/selftest.sh' | sed 's/^/bash /'; cd "$root" && git ls-files '*.test.cjs' '*.test.js' '*.test.mjs' | sed 's/^/node --test /')"
lists() {  # WORKFLOW PREFIX: every test file has its exact entry in the lock
  local miss; miss="$(printf '%s\n' "$tests" | while read -r runner file; do
    case "$runner" in node) runner="node --test"; file="${file#--test }";; esac
    grep -qF "Bash($runner $2$file)" "$root/.github/workflows/$1.lock.yml" || printf '%s ' "$runner $2$file"
  done)"
  [ -z "$miss" ] && ok || bad "missing from $1.lock.yml: $miss"
}
it "ci-fix's lock lists every test file at the head"; lists ci-fix ""
it "verify's lock lists every test file at the head and in the merge-base worktree"
lists verify ""; lists verify /tmp/gh-aw/agent/verify/base/
it "ci-diagnose's lock lists every test file in the failing commit's worktree"; lists ci-diagnose /tmp/gh-aw/agent/ci/head/
it "no lock keeps a directory prefix, which matches nothing below it"
grep -hoE 'Bash\((bash|node --test) [^)]*/:\*\)' "$root"/.github/workflows/*.lock.yml | head -1 | grep -q . && bad "a directory prefix is still there" || ok
it "the sources' test-file blocks are what bin/agent-allowlists-sync writes"
(cd "$root" && bin/agent-allowlists-sync --check) && ok || bad "run bin/agent-allowlists-sync, then gh aw compile"
it "ci-diagnose's prompt does not repeat the old claim that cd with && is refused"
grep -q 'joined to `cd` with `&&`' "$root/.github/workflows/ci-diagnose.md" && bad "old sentence still there" || ok
it "this test runs in CI"
grep -qF 'bash bin/agent-allowlists.test.sh' "$root/.github/workflows/test.yml" && ok || bad "not in test.yml"

echo; echo "passed=$pass failed=$fail"
[ "$fail" -eq 0 ]
