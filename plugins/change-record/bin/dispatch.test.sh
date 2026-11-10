#!/usr/bin/env bash
# Tests for dispatch: a repository with a bare remote in a scratch directory, a record on
# main whose frontmatter lists tasks, and a fake agent that applies a canned change and
# prints the JSON claude -p would. Needs bash, git and python3.
set -u
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
D="$here/dispatch"
TMPROOT="$(mktemp -d)"; trap 'rm -rf "$TMPROOT"' EXIT
pass=0; fail=0; CURRENT=""
it() { CURRENT="$1"; }
ok()  { pass=$((pass+1)); printf '  ok   %s\n' "$CURRENT"; }
bad() { fail=$((fail+1)); printf '  FAIL %s\n       %s\n' "$CURRENT" "$1"; }
assert_eq()  { [ "$1" = "$2" ] && ok || bad "expected [$1] got [$2]"; }
has()  { printf '%s' "$1" | grep -qF -- "$2" && ok || bad "missing [$2] in: $(printf '%s' "$1" | head -c 700)"; }
lacks() { printf '%s' "$1" | grep -qF -- "$2" && bad "unexpected [$2] in: $(printf '%s' "$1" | head -c 700)" || ok; }

# The fake agent: reads the brief on stdin, writes a feature file and a TAP test for the task
# the brief names, commits, and prints claude's result JSON with the PR body as `result`.
cat > "$TMPROOT/agent.sh" <<'AGENT'
#!/usr/bin/env bash
set -eu
brief="$(cat)"; printf '%s' "$brief" > .brief-seen.md
name="$(printf '%s\n' "$brief" | sed -n 's/^# Task \([a-z0-9-]*\) of change.*/\1/p' | head -n1)"
id="$(printf '%s\n' "$brief" | sed -n 's/.*docs\/changes\/\([^ `]*\)\.md.*/\1/p' | head -n1)"
rm -f .brief-seen.md
printf 'built %s\n' "$name" > "feature-$name.txt"
mkdir -p tests
printf '#!/usr/bin/env bash\n[ -f feature-%s.txt ] && echo "ok 1 - feature present" || { echo "not ok 1 - feature-%s.txt missing"; exit 1; }\n' "$name" "$name" > "tests/$name.test.sh"
git add -A; git commit -qm "feat: $name"
printf '{"type":"result","subtype":"success","is_error":false,"num_turns":4,"total_cost_usd":0.0123,"result":"Change: docs/changes/%s.md\\n\\nBuilt task %s as the record says."}\n' "$id" "$name"
AGENT
# An agent that reads the brief and commits nothing.
cat > "$TMPROOT/idle.sh" <<'AGENT'
#!/usr/bin/env bash
cat > /dev/null
printf '{"type":"result","subtype":"success","is_error":false,"num_turns":1,"total_cost_usd":0.001,"result":"I could not do this.","permission_denials":[{"tool_name":"Bash","tool_input":{"command":"python3 -m unittest"}},{"tool_name":"Bash","tool_input":{"command":"git commit -m x"}}]}\n'
AGENT
chmod +x "$TMPROOT/agent.sh" "$TMPROOT/idle.sh"

# repo NAME: a repository with a bare remote, main pushed; returns to its directory.
repo() {
  r="$TMPROOT/$1"; mkdir -p "$r"; git init -q --bare "$r/remote.git"
  mkdir -p "$r/work/docs/changes" "$r/work/plugins/cr"; cd "$r/work" || exit 1
  git init -q -b main; git config user.email t@example.com; git config user.name t
  git config core.hooksPath /dev/null
  printf 'hello\n' > lib.txt; printf '# Changes\n' > docs/changes/README.md; printf '{}\n' > plugins/cr/plugin.json
  git add -A; git commit -qm "feat: base"
  git remote add origin "$r/remote.git"; git push -q -u origin main 2>/dev/null
  WT="$r/worktrees"
}
commit_main() { git add -A; git commit -qm "$1"; git push -q origin main 2>/dev/null; }
# record PATH TIER STATUS TASKS-YAML: a record whose Tasks section has three numbered items.
record() {
  { printf -- '---\nid: %s\ntier: %s\nstatus: %s\nrequester: me\napprovers: [me]\nplugin: plugins/cr\n%s---\n# Build the thing\n' "$(basename "$1" .md)" "$2" "$3" "$4"
    printf '## Goal\nThe goal text.\n\n## Probed facts\n- Verified: a fact.\n\n'
    [ "$2" = 2 ] && printf '## Problem\nP.\n\n## Requirements\n- R1.\n\n## Options and concerns\nA.\n\n'
    printf '## Decisions\n- Decided this, not that.\n\n## Tasks\n\n1. **Alpha.** Do alpha.\n   Second line of alpha.\n2. **Beta.** Do beta.\n3. **Gamma.** Do gamma.\n\n## Checks\nRun the tests.\n\n## Outcome\n'; } > "$1"
}
TASKS=$'tasks:\n  - name: alpha\n    branch: thing/alpha\n  - name: beta\n    after: alpha\n  - name: gamma\n    branch: thing/gamma\n    after: beta\n'
dispatch() { bash "$D" "$@" --worktrees "$WT" 2>&1; }
remote_heads() { git ls-remote --heads origin | sed 's/^[0-9a-f]*[[:space:]]*refs\/heads\///' | sort | tr '\n' ' '; }

it "a tier 2 record that is open on main is refused before any worktree is made"
repo gate; record docs/changes/2026-11-08-t.md 2 open "$TASKS"; commit_main "docs(change): t"
out="$(dispatch docs/changes/2026-11-08-t.md --agent "$TMPROOT/agent.sh")"; rc=$?
assert_eq 2 "$rc"; has "$out" "approved"; assert_eq "main " "$(remote_heads)"; [ -d "$WT/2026-11-08-t/alpha" ] && bad "worktree made" || ok

it "a record absent from main is refused"
repo absent; record docs/changes/2026-11-08-t.md 2 approved "$TASKS"
out="$(dispatch docs/changes/2026-11-08-t.md --agent "$TMPROOT/agent.sh")"; rc=$?
assert_eq 2 "$rc"; has "$out" "origin/main"

it "a record without tasks in its frontmatter is refused"
repo notasks; record docs/changes/2026-11-08-t.md 2 approved ""; commit_main "docs(change): t"
out="$(dispatch docs/changes/2026-11-08-t.md --agent "$TMPROOT/agent.sh")"; rc=$?
assert_eq 2 "$rc"; has "$out" "tasks"

it "a done or abandoned record has nothing to dispatch"
repo done; record docs/changes/2026-11-08-t.md 2 done "$TASKS"; commit_main "docs(change): t"
out="$(dispatch docs/changes/2026-11-08-t.md --agent "$TMPROOT/agent.sh")"; rc=$?
assert_eq 2 "$rc"; has "$out" "done"

it "--dry-run lists the tasks in order with their branches and gates, and runs nothing"
repo dry; record docs/changes/2026-11-08-t.md 2 approved "$TASKS"; commit_main "docs(change): t"
out="$(dispatch docs/changes/2026-11-08-t.md --dry-run)"; rc=$?
assert_eq 0 "$rc"; has "$out" "alpha"; has "$out" "thing/alpha"; has "$out" "2026-11-08-t/beta"; has "$out" "after alpha"; has "$out" "thing/gamma"
assert_eq "main " "$(remote_heads)"

it "the first task runs in a worktree on its branch from main, gets a brief from the record, and is pushed"
repo first; record docs/changes/2026-11-08-t.md 2 approved "$TASKS"; commit_main "docs(change): t"
out="$(dispatch docs/changes/2026-11-08-t.md --agent "$TMPROOT/agent.sh")"; rc=$?
assert_eq 0 "$rc"; has "$out" "alpha"; has "$out" "pushed"; has "$out" "record-check=ok"
assert_eq "main thing/alpha " "$(remote_heads)"
brief="$(cat "$WT/2026-11-08-t/alpha.brief.md")"
has "$brief" "# Task alpha of change 2026-11-08-t"; has "$brief" "The goal text."; has "$brief" "Verified: a fact."; has "$brief" "Decided this, not that."
has "$brief" "Do alpha."; has "$brief" "Second line of alpha."; lacks "$brief" "Do beta."; has "$brief" "Run the tests."
has "$brief" "Change: docs/changes/2026-11-08-t.md"; has "$brief" "do not push"
assert_eq "Change: docs/changes/2026-11-08-t.md" "$(head -n1 "$WT/2026-11-08-t/alpha.pr-body.md")"
git fetch -q origin; assert_eq "1" "$(git rev-list --count origin/main..origin/thing/alpha -- feature-alpha.txt)"
has "$(git show origin/thing/alpha:docs/changes/2026-11-08-t.md)" "done: true"
has "$(git show origin/thing/alpha:docs/changes/2026-11-08-t.md | sed -n '/- name: beta/,/- name: gamma/p')" "after: alpha"
lacks "$(git show origin/thing/alpha:docs/changes/2026-11-08-t.md | sed -n '/- name: beta/,$p')" "done: true"
has "$out" "turns=4"; has "$out" "cost=0.0123"

it "the next task waits while its after task is in flight, and the in-flight task is not run twice"
out="$(dispatch docs/changes/2026-11-08-t.md --agent "$TMPROOT/agent.sh")"; rc=$?
assert_eq 0 "$rc"; has "$out" "alpha"; has "$out" "already"; has "$out" "beta"; has "$out" "waiting"
assert_eq "main thing/alpha " "$(remote_heads)"

it "--task on a gated task is refused with the gate named"
out="$(dispatch docs/changes/2026-11-08-t.md --task beta --agent "$TMPROOT/agent.sh")"; rc=$?
assert_eq 2 "$rc"; has "$out" "alpha"

it "once the first task's branch has squash-merged into main (and been deleted), the next task runs"
git fetch -q origin; git checkout -q main; git merge -q --squash origin/thing/alpha; git commit -qm "feat: alpha (#1)"; git push -q origin main 2>/dev/null; git push -q origin --delete thing/alpha 2>/dev/null
out="$(dispatch docs/changes/2026-11-08-t.md --agent "$TMPROOT/agent.sh")"; rc=$?
assert_eq 0 "$rc"; has "$out" "beta"; has "$out" "pushed"; lacks "$out" "waiting for alpha"
assert_eq "2026-11-08-t/beta main " "$(remote_heads)"
has "$(cat "$WT/2026-11-08-t/beta.brief.md")" "Do beta."; lacks "$(cat "$WT/2026-11-08-t/beta.brief.md")" "Do alpha."
git fetch -q origin; has "$(git show origin/2026-11-08-t/beta:docs/changes/2026-11-08-t.md | sed -n '/- name: beta/,/- name: gamma/p')" "done: true"
has "$out" "gamma"; has "$out" "waiting"

it "the worktree is cut from the base, not from whatever the controller has checked out"
repo head; record docs/changes/2026-11-08-t.md 2 approved "$TASKS"; commit_main "docs(change): t"
printf 'local only\n' > local.txt; git add -A; git commit -qm "wip: not pushed"
out="$(dispatch docs/changes/2026-11-08-t.md --agent "$TMPROOT/agent.sh")"; rc=$?
assert_eq 0 "$rc"; git fetch -q origin
git cat-file -e origin/thing/alpha:local.txt 2>/dev/null && bad "the branch carries the controller's unpushed commit" || ok
assert_eq "$(git rev-parse origin/main)" "$(git merge-base origin/main origin/thing/alpha)"

it "an agent that commits nothing fails the task and nothing is pushed, and its denied commands are shown"
repo idle; record docs/changes/2026-11-08-t.md 2 approved "$TASKS"; commit_main "docs(change): t"
out="$(dispatch docs/changes/2026-11-08-t.md --agent "$TMPROOT/idle.sh")"; rc=$?
assert_eq 1 "$rc"; has "$out" "no commits"; assert_eq "main " "$(remote_heads)"; has "$out" "denied=2"; has "$out" "git commit -m x"

it "with a red-check run command the new test is judged; a red test passes and the branch is pushed"
repo red; record docs/changes/2026-11-08-t.md 2 approved "$TASKS"; commit_main "docs(change): t"
out="$(dispatch docs/changes/2026-11-08-t.md --agent "$TMPROOT/agent.sh" --red-run 'bash {files}' --red-match '**/*.test.sh')"; rc=$?
assert_eq 0 "$rc"; has "$out" "red-check=ok"; assert_eq "main thing/alpha " "$(remote_heads)"

it "a test that passes on the base fails red-check and the branch is not pushed"
cat > "$TMPROOT/green.sh" <<'AGENT'
#!/usr/bin/env bash
set -eu; cat > /dev/null; mkdir -p tests
printf '#!/usr/bin/env bash\necho "ok 1 - always"\n' > tests/alpha.test.sh; printf 'x\n' > feature-alpha.txt
git add -A; git commit -qm "feat: alpha"
printf '{"type":"result","result":"Change: docs/changes/2026-11-08-t.md\\n\\nDone.","num_turns":2,"total_cost_usd":0.002}\n'
AGENT
chmod +x "$TMPROOT/green.sh"
repo green; record docs/changes/2026-11-08-t.md 2 approved "$TASKS"; commit_main "docs(change): t"
out="$(dispatch docs/changes/2026-11-08-t.md --agent "$TMPROOT/green.sh" --red-run 'bash {files}' --red-match '**/*.test.sh')"; rc=$?
assert_eq 1 "$rc"; has "$out" "red-check=fail"; assert_eq "main " "$(remote_heads)"; [ -d "$WT/2026-11-08-t/alpha" ] && ok || bad "worktree removed; it should stay for inspection"

it "without a run command red-check is reported as skipped, not as passed"
repo skip; record docs/changes/2026-11-08-t.md 2 approved "$TASKS"; commit_main "docs(change): t"
out="$(dispatch docs/changes/2026-11-08-t.md --agent "$TMPROOT/agent.sh")"; rc=$?
assert_eq 0 "$rc"; has "$out" "red-check=skipped"

it "a tier 1 record that is open on main dispatches too"
repo t1; record docs/changes/2026-11-08-t.md 1 open "$TASKS"; commit_main "docs(change): t"
out="$(dispatch docs/changes/2026-11-08-t.md --agent "$TMPROOT/agent.sh")"; rc=$?
assert_eq 0 "$rc"; has "$out" "pushed"

it "a PR description without the Change: line gets it as its first line, and the push proceeds"
cat > "$TMPROOT/noline.sh" <<'AGENT'
#!/usr/bin/env bash
set -eu; cat > /dev/null; printf 'x\n' > feature-alpha.txt; git add -A; git commit -qm "feat: alpha"
printf '{"type":"result","result":"Built alpha. See the record for details.","num_turns":2,"total_cost_usd":0.002}\n'
AGENT
chmod +x "$TMPROOT/noline.sh"
repo noline; record docs/changes/2026-11-08-t.md 2 approved "$TASKS"; commit_main "docs(change): t"
out="$(dispatch docs/changes/2026-11-08-t.md --agent "$TMPROOT/noline.sh")"; rc=$?
assert_eq 0 "$rc"; has "$out" "added it"; assert_eq "Change: docs/changes/2026-11-08-t.md" "$(head -n1 "$WT/2026-11-08-t/alpha.pr-body.md")"
has "$(cat "$WT/2026-11-08-t/alpha.pr-body.md")" "Built alpha."; assert_eq "main thing/alpha " "$(remote_heads)"

it "a record that fails record-check on the branch is not pushed"
cat > "$TMPROOT/breaker.sh" <<'AGENT'
#!/usr/bin/env bash
set -eu; cat > /dev/null; printf 'x\n' > feature-alpha.txt
sed -i 's/^## Checks$/## Cheques/' docs/changes/2026-11-08-t.md
git add -A; git commit -qm "feat: alpha"
printf '{"type":"result","result":"Change: docs/changes/2026-11-08-t.md\\n\\nDone.","num_turns":2,"total_cost_usd":0.002}\n'
AGENT
chmod +x "$TMPROOT/breaker.sh"
repo breaker; record docs/changes/2026-11-08-t.md 2 approved "$TASKS"; commit_main "docs(change): t"
out="$(dispatch docs/changes/2026-11-08-t.md --agent "$TMPROOT/breaker.sh")"; rc=$?
assert_eq 1 "$rc"; has "$out" "record-check=fail"; has "$out" "Checks"; assert_eq "main " "$(remote_heads)"

it "the default agent command names the plugin from the frontmatter"
repo default; record docs/changes/2026-11-08-t.md 2 approved "$TASKS"; commit_main "docs(change): t"
out="$(dispatch docs/changes/2026-11-08-t.md --dry-run)"
has "$out" "--plugin-dir $TMPROOT/default/work/plugins/cr"; has "$out" "claude -p"; has "$out" "--allowedTools Bash"; has "$out" "acceptEdits"

# Review findings on the first push.
it "task lines with trailing comments, as the template shows them, still get their done marker"
COMMENTED=$'tasks:\n  - name: alpha   # the first task\n    branch: thing/alpha   # its branch\n  - name: beta\n    after: alpha   # once alpha is done\n'
repo commented; record docs/changes/2026-11-08-t.md 2 approved "$COMMENTED"; commit_main "docs(change): t"
out="$(dispatch docs/changes/2026-11-08-t.md --agent "$TMPROOT/agent.sh")"; rc=$?
assert_eq 0 "$rc"; has "$out" "pushed=yes"; git fetch -q origin
has "$(git show origin/thing/alpha:docs/changes/2026-11-08-t.md | sed -n '/- name: alpha/,/- name: beta/p')" "done: true"
has "$(git show origin/thing/alpha:docs/changes/2026-11-08-t.md)" "# the first task"

it "a task whose done marker cannot be written fails loudly and is not pushed"
cat > "$TMPROOT/renamer.sh" <<'AGENT'
#!/usr/bin/env bash
set -eu; cat > /dev/null; printf 'x\n' > feature-alpha.txt
sed -i 's/- name: alpha/- name: alfa/' docs/changes/2026-11-08-t.md
git add -A; git commit -qm "feat: alpha"
printf '{"type":"result","result":"Change: docs/changes/2026-11-08-t.md\\n\\nDone.","num_turns":2,"total_cost_usd":0.002}\n'
AGENT
chmod +x "$TMPROOT/renamer.sh"
repo renamer; record docs/changes/2026-11-08-t.md 2 approved "$TASKS"; commit_main "docs(change): t"
out="$(dispatch docs/changes/2026-11-08-t.md --agent "$TMPROOT/renamer.sh")"; rc=$?
assert_eq 1 "$rc"; has "$out" "done: true"; has "$out" "alpha"; assert_eq "main " "$(remote_heads)"

it "tasks without a plugin line are refused unless --agent replaces the command"
repo noplugin; record docs/changes/2026-11-08-t.md 2 approved "$TASKS"; sed -i '/^plugin:/d' docs/changes/2026-11-08-t.md; commit_main "docs(change): t"
out="$(dispatch docs/changes/2026-11-08-t.md --dry-run)"; rc=$?
assert_eq 2 "$rc"; has "$out" "plugin"
out="$(dispatch docs/changes/2026-11-08-t.md --agent "$TMPROOT/agent.sh")"; rc=$?
assert_eq 0 "$rc"; has "$out" "pushed=yes"

it "a kept worktree from a failed attempt is not discarded without --fresh"
repo keep; record docs/changes/2026-11-08-t.md 2 approved "$TASKS"; commit_main "docs(change): t"
out="$(dispatch docs/changes/2026-11-08-t.md --agent "$TMPROOT/idle.sh")"; rc=$?
assert_eq 1 "$rc"; [ -d "$WT/2026-11-08-t/alpha" ] && ok || bad "worktree not kept"
printf 'hand edit\n' > "$WT/2026-11-08-t/alpha/by-hand.txt"
out="$(dispatch docs/changes/2026-11-08-t.md --agent "$TMPROOT/agent.sh")"; rc=$?
assert_eq 1 "$rc"; has "$out" "--fresh"; has "$out" "$WT/2026-11-08-t/alpha"; [ -f "$WT/2026-11-08-t/alpha/by-hand.txt" ] && ok || bad "the kept worktree was discarded"
assert_eq "main " "$(remote_heads)"
out="$(dispatch docs/changes/2026-11-08-t.md --agent "$TMPROOT/agent.sh" --fresh)"; rc=$?
assert_eq 0 "$rc"; has "$out" "pushed=yes"; [ -f "$WT/2026-11-08-t/alpha/by-hand.txt" ] && bad "--fresh kept the old worktree" || ok

it "a commit hook that refuses the done-marker commit fails the task instead of pushing without it"
repo hooked; record docs/changes/2026-11-08-t.md 2 approved "$TASKS"; commit_main "docs(change): t"
mkdir -p "$TMPROOT/hooks"; printf '#!/usr/bin/env bash\ngrep -q dispatched "$1" && { echo "hook: no dispatcher commits here" >&2; exit 1; }; exit 0\n' > "$TMPROOT/hooks/commit-msg"; chmod +x "$TMPROOT/hooks/commit-msg"
git config core.hooksPath "$TMPROOT/hooks"
out="$(dispatch docs/changes/2026-11-08-t.md --agent "$TMPROOT/agent.sh")"; rc=$?
assert_eq 1 "$rc"; has "$out" "could not commit the done marker"; assert_eq "main " "$(remote_heads)"
git config core.hooksPath /dev/null

# Second review round.
it "a local branch with unpushed commits and no worktree is not force-deleted without --fresh"
repo stale; record docs/changes/2026-11-08-t.md 2 approved "$TASKS"; commit_main "docs(change): t"
git checkout -qb thing/alpha; printf 'kept\n' > kept.txt; git add -A; git commit -qm "wip: unpushed"; git checkout -q main
out="$(dispatch docs/changes/2026-11-08-t.md --agent "$TMPROOT/agent.sh")"; rc=$?
assert_eq 1 "$rc"; has "$out" "--fresh"; has "$out" "thing/alpha"; assert_eq "main " "$(remote_heads)"
git cat-file -e thing/alpha:kept.txt 2>/dev/null && ok || bad "the unpushed branch was deleted"
out="$(dispatch docs/changes/2026-11-08-t.md --agent "$TMPROOT/agent.sh" --fresh)"; rc=$?
assert_eq 0 "$rc"; has "$out" "pushed=yes"
git cat-file -e thing/alpha:kept.txt 2>/dev/null && bad "--fresh kept the stale commit" || ok

it "a local branch with no commits beyond the base is reused without ceremony"
repo plain; record docs/changes/2026-11-08-t.md 2 approved "$TASKS"; commit_main "docs(change): t"
git branch thing/alpha origin/main
out="$(dispatch docs/changes/2026-11-08-t.md --agent "$TMPROOT/agent.sh")"; rc=$?
assert_eq 0 "$rc"; has "$out" "pushed=yes"

it "a task with no numbered item under Tasks fails instead of briefing the whole section"
repo noitem; record docs/changes/2026-11-08-t.md 2 approved "$TASKS"; sed -i 's/^[0-9]\. \*\*/- **/' docs/changes/2026-11-08-t.md; commit_main "docs(change): t"
out="$(dispatch docs/changes/2026-11-08-t.md --agent "$TMPROOT/agent.sh")"; rc=$?
assert_eq 1 "$rc"; has "$out" "numbered item"; has "$out" "alpha"; assert_eq "main " "$(remote_heads)"; [ -f "$WT/2026-11-08-t/alpha.brief.md" ] && bad "a brief was written" || ok

# Third review round: --task names a task that exists but is finished or in flight.
it "--task on a task that is in flight or done says so, and only an unknown name is refused, in a dry run too"
repo named; record docs/changes/2026-11-08-t.md 2 approved "$TASKS"; commit_main "docs(change): t"
out="$(dispatch docs/changes/2026-11-08-t.md --dry-run --task nope)"; rc=$?
assert_eq 2 "$rc"; has "$out" "no task named nope"
out="$(dispatch docs/changes/2026-11-08-t.md --task alpha --agent "$TMPROOT/agent.sh")"; rc=$?
assert_eq 0 "$rc"; has "$out" "pushed=yes"
out="$(dispatch docs/changes/2026-11-08-t.md --task alpha --agent "$TMPROOT/agent.sh")"; rc=$?
assert_eq 0 "$rc"; has "$out" "already dispatched"; lacks "$out" "no task named"
git fetch -q origin; git checkout -q main; git merge -q --squash origin/thing/alpha; git commit -qm "feat: alpha (#1)"; git push -q origin main 2>/dev/null; git push -q origin --delete thing/alpha 2>/dev/null
out="$(dispatch docs/changes/2026-11-08-t.md --task alpha --agent "$TMPROOT/agent.sh")"; rc=$?
assert_eq 0 "$rc"; has "$out" "done on"; lacks "$out" "no task named"
out="$(dispatch docs/changes/2026-11-08-t.md --task nope --agent "$TMPROOT/agent.sh")"; rc=$?
assert_eq 2 "$rc"; has "$out" "no task named nope"

it "an after: that names no task in the record is refused up front, not waited on forever"
DANGLING=$'tasks:\n  - name: alpha\n  - name: beta\n    after: alfa\n'
repo dangling; record docs/changes/2026-11-08-t.md 2 approved "$DANGLING"; commit_main "docs(change): t"
out="$(dispatch docs/changes/2026-11-08-t.md --dry-run)"; rc=$?
assert_eq 2 "$rc"; has "$out" "alfa"; has "$out" "beta"; lacks "$out" "waiting for"
out="$(dispatch docs/changes/2026-11-08-t.md --agent "$TMPROOT/agent.sh")"; rc=$?
assert_eq 2 "$rc"; assert_eq "main " "$(remote_heads)"

# Fifth review round: names are paths, and order matters.
it "a task name that is not a plain slug is refused before any directory is touched, even with --fresh"
BADNAME=$'tasks:\n  - name: ../../escape\n  - name: beta\n'
repo badname; record docs/changes/2026-11-08-t.md 2 approved "$BADNAME"; commit_main "docs(change): t"
mkdir -p "$WT/canary"; printf 'keep me\n' > "$WT/canary/file.txt"
out="$(dispatch docs/changes/2026-11-08-t.md --fresh --agent "$TMPROOT/agent.sh")"; rc=$?
assert_eq 2 "$rc"; has "$out" "../../escape"; has "$out" "name"; [ -f "$WT/canary/file.txt" ] && ok || bad "a directory outside the task's own was removed"
assert_eq "main " "$(remote_heads)"
for bad in "alpha beta" "a/b" "." ".hidden"; do
  repo "badname-$RANDOM"; record docs/changes/2026-11-08-t.md 2 approved "tasks:
  - name: $bad
"; commit_main "docs(change): t"
  out="$(dispatch docs/changes/2026-11-08-t.md --dry-run)"; rc=$?
  assert_eq 2 "$rc"
done

it "worktrees are kept per record, so two records with the same task name do not share one directory"
repo twice; record docs/changes/2026-11-08-t.md 2 approved "$TASKS"; commit_main "docs(change): t"
out="$(dispatch docs/changes/2026-11-08-t.md --agent "$TMPROOT/agent.sh")"; rc=$?
assert_eq 0 "$rc"; [ -d "$WT/2026-11-08-t/alpha" ] && ok || bad "worktree not under the record's id: $(ls "$WT")"
[ -f "$WT/2026-11-08-t/alpha.brief.md" ] && ok || bad "brief not beside the worktree under the record's id"

it "an after: that names a task listed later is refused, since the run would stop before reaching it"
LATER=$'tasks:\n  - name: gamma\n    after: beta\n  - name: beta\n'
repo later; record docs/changes/2026-11-08-t.md 2 approved "$LATER"; commit_main "docs(change): t"
out="$(dispatch docs/changes/2026-11-08-t.md --dry-run)"; rc=$?
assert_eq 2 "$rc"; has "$out" "gamma"; has "$out" "beta"; lacks "$out" "waiting for"
out="$(dispatch docs/changes/2026-11-08-t.md --agent "$TMPROOT/agent.sh")"; rc=$?
assert_eq 2 "$rc"; assert_eq "main " "$(remote_heads)"

# Sixth review round: a relative --worktrees path must work, since the checks run after a cd.
it "a relative --worktrees path is taken from the caller's directory and the checks still find their files"
repo relwt; record docs/changes/2026-11-08-t.md 2 approved "$TASKS"; commit_main "docs(change): t"
mkdir -p "$TMPROOT/relwt/elsewhere"; cd "$TMPROOT/relwt/elsewhere" || exit 1
out="$(bash "$D" "$TMPROOT/relwt/work/docs/changes/2026-11-08-t.md" --agent "$TMPROOT/agent.sh" --worktrees rel/wt 2>&1)"; rc=$?
cd "$TMPROOT/relwt/work" || exit 1
assert_eq 2 "$rc"; has "$out" "not inside a git repository"
cd "$TMPROOT/relwt/work" && out="$(bash "$D" docs/changes/2026-11-08-t.md --agent "$TMPROOT/agent.sh" --worktrees rel/wt 2>&1)"; rc=$?
assert_eq 0 "$rc"; has "$out" "pushed=yes"; has "$out" "record-check=ok"
[ -d "$TMPROOT/relwt/work/rel/wt/2026-11-08-t/alpha" ] && ok || bad "worktree not under the caller's rel/wt: $(find "$TMPROOT/relwt" -maxdepth 3 -name alpha 2>/dev/null)"
[ -f "$TMPROOT/relwt/work/rel/wt/2026-11-08-t/alpha.record-check.log" ] && ok || bad "record-check log not beside the worktree"

# Seventh review round: a tasks entry without a name must not vanish and shift the others.
it "a tasks entry with an empty name, or one that does not start with name:, is refused rather than dropped"
EMPTYNAME=$'tasks:\n  - name:\n    branch: thing/alpha\n  - name: beta\n'
repo emptyname; record docs/changes/2026-11-08-t.md 2 approved "$EMPTYNAME"; commit_main "docs(change): t"
out="$(dispatch docs/changes/2026-11-08-t.md --dry-run)"; rc=$?
assert_eq 2 "$rc"; has "$out" "name"; lacks "$out" "1. beta"
out="$(dispatch docs/changes/2026-11-08-t.md --agent "$TMPROOT/agent.sh")"; rc=$?
assert_eq 2 "$rc"; assert_eq "main " "$(remote_heads)"
FIRSTLINE=$'tasks:\n  - branch: thing/alpha\n    name: alpha\n  - name: beta\n'
repo firstline; record docs/changes/2026-11-08-t.md 2 approved "$FIRSTLINE"; commit_main "docs(change): t"
out="$(dispatch docs/changes/2026-11-08-t.md --dry-run)"; rc=$?
assert_eq 2 "$rc"; has "$out" "name"
COMMENTONLY=$'tasks:\n  - name:   # forgot the value\n  - name: beta\n'
repo commentonly; record docs/changes/2026-11-08-t.md 2 approved "$COMMENTONLY"; commit_main "docs(change): t"
out="$(dispatch docs/changes/2026-11-08-t.md --dry-run)"; rc=$?
assert_eq 2 "$rc"; has "$out" "name"

# Eighth review round: the tasks grammar is checked line by line, and the id guards have tests.
it "a dash glued to name:, or any line under tasks: outside the grammar, is refused and quoted"
GLUED=$'tasks:\n  -name: alpha\n  - name: beta\n'
repo glued; record docs/changes/2026-11-08-t.md 2 approved "$GLUED"; commit_main "docs(change): t"
out="$(dispatch docs/changes/2026-11-08-t.md --dry-run)"; rc=$?
assert_eq 2 "$rc"; has "$out" "-name: alpha"
UNKNOWNKEY=$'tasks:\n  - name: alpha\n    brnch: thing/alpha\n'
repo unknownkey; record docs/changes/2026-11-08-t.md 2 approved "$UNKNOWNKEY"; commit_main "docs(change): t"
out="$(dispatch docs/changes/2026-11-08-t.md --dry-run)"; rc=$?
assert_eq 2 "$rc"; has "$out" "brnch"

it "a comment on the tasks: line itself, as the template shows, is not a defect, in a dry run or a full run"
COMMENTED_TASKS=$'tasks:   # optional, for dispatch\n  - name: alpha   # first\n    branch: thing/alpha\n  - name: beta\n    after: alpha\n'
repo tasklinecomment; record docs/changes/2026-11-08-t.md 2 approved "$COMMENTED_TASKS"; commit_main "docs(change): t"
out="$(dispatch docs/changes/2026-11-08-t.md --dry-run)"; rc=$?
assert_eq 0 "$rc"; has "$out" "1. alpha"; has "$out" "2. beta"
out="$(dispatch docs/changes/2026-11-08-t.md --agent "$TMPROOT/agent.sh")"; rc=$?
assert_eq 0 "$rc"; has "$out" "pushed=yes"; lacks "$out" "could not set done"
git fetch -q origin; has "$(git show origin/thing/alpha:docs/changes/2026-11-08-t.md | sed -n '/- name: alpha/,/- name: beta/p')" "done: true"

it "a record whose id does not match its file name, or whose id is not a slug, is refused"
repo idmismatch; record docs/changes/2026-11-08-t.md 2 approved "$TASKS"; sed -i 's/^id: .*/id: 2026-11-08-other/' docs/changes/2026-11-08-t.md; commit_main "docs(change): t"
out="$(dispatch docs/changes/2026-11-08-t.md --dry-run)"; rc=$?
assert_eq 2 "$rc"; has "$out" "does not match"
repo idslug; record "docs/changes/.hidden.md" 2 approved "$TASKS"; commit_main "docs(change): t"
out="$(dispatch docs/changes/.hidden.md --dry-run)"; rc=$?
assert_eq 2 "$rc"; has "$out" "slug"

# Ninth review round: duplicate task names.
it "two tasks with the same name are refused up front"
DUP=$'tasks:\n  - name: alpha\n  - name: alpha\n    branch: thing/alpha2\n'
repo dup; record docs/changes/2026-11-08-t.md 2 approved "$DUP"; commit_main "docs(change): t"
out="$(dispatch docs/changes/2026-11-08-t.md --dry-run)"; rc=$?
assert_eq 2 "$rc"; has "$out" "alpha"; has "$out" "twice"
out="$(dispatch docs/changes/2026-11-08-t.md --agent "$TMPROOT/agent.sh")"; rc=$?
assert_eq 2 "$rc"; assert_eq "main " "$(remote_heads)"

# Tenth review round: two tasks on one branch.
it "two tasks that resolve to the same branch are refused up front"
DUPBRANCH=$'tasks:\n  - name: alpha\n    branch: thing/shared\n  - name: beta\n    branch: thing/shared\n'
repo dupbranch; record docs/changes/2026-11-08-t.md 2 approved "$DUPBRANCH"; commit_main "docs(change): t"
out="$(dispatch docs/changes/2026-11-08-t.md --dry-run)"; rc=$?
assert_eq 2 "$rc"; has "$out" "thing/shared"; has "$out" "beta"
DUPDEFAULT=$'tasks:\n  - name: alpha\n  - name: beta\n    branch: 2026-11-08-t/alpha\n'
repo dupdefault; record docs/changes/2026-11-08-t.md 2 approved "$DUPDEFAULT"; commit_main "docs(change): t"
out="$(dispatch docs/changes/2026-11-08-t.md --agent "$TMPROOT/agent.sh")"; rc=$?
assert_eq 2 "$rc"; has "$out" "2026-11-08-t/alpha"; assert_eq "main " "$(remote_heads)"

# Eleventh review round: a task branch that is the base branch itself.
it "a task whose branch is the base branch is refused up front, not reported as in flight"
ONBASE=$'tasks:\n  - name: alpha\n    branch: main\n  - name: beta\n'
repo onbase; record docs/changes/2026-11-08-t.md 2 approved "$ONBASE"; commit_main "docs(change): t"
out="$(dispatch docs/changes/2026-11-08-t.md --dry-run)"; rc=$?
assert_eq 2 "$rc"; has "$out" "main"; has "$out" "alpha"; lacks "$out" "already dispatched"
out="$(dispatch docs/changes/2026-11-08-t.md --agent "$TMPROOT/agent.sh")"; rc=$?
assert_eq 2 "$rc"; assert_eq "main " "$(remote_heads)"
ONBASEFULL=$'tasks:\n  - name: alpha\n    branch: origin/main\n'
repo onbasefull; record docs/changes/2026-11-08-t.md 2 approved "$ONBASEFULL"; commit_main "docs(change): t"
out="$(dispatch docs/changes/2026-11-08-t.md --dry-run)"; rc=$?
assert_eq 2 "$rc"

# Transcripts: each child is told which session dispatched it, and a stale value is not passed on.
it "the agent runs with AGENT_TRANSCRIPTS_PARENT set to the dispatching session's id, or unset without one"
printf '#!/usr/bin/env bash\nprintf "[%%s]" "${AGENT_TRANSCRIPTS_PARENT-unset}" >> "%s/parent-seen"\nexec "%s/agent.sh"\n' "$TMPROOT" "$TMPROOT" > "$TMPROOT/parent.sh"; chmod +x "$TMPROOT/parent.sh"
ONE=$'tasks:\n  - name: alpha\n'
repo parent; record docs/changes/2026-11-08-t.md 2 approved "$ONE"; commit_main "docs(change): t"
rm -f "$TMPROOT/parent-seen"
out="$(CLAUDE_CODE_SESSION_ID=sess-dispatcher AGENT_TRANSCRIPTS_PARENT=stale dispatch docs/changes/2026-11-08-t.md --no-push --agent "$TMPROOT/parent.sh")"; rc=$?
assert_eq 0 "$rc"; assert_eq "[sess-dispatcher]" "$(cat "$TMPROOT/parent-seen" 2>&1)"
repo parent2; record docs/changes/2026-11-08-t.md 2 approved "$ONE"; commit_main "docs(change): t"
rm -f "$TMPROOT/parent-seen"
out="$(env -u CLAUDE_CODE_SESSION_ID AGENT_TRANSCRIPTS_PARENT=stale bash "$D" docs/changes/2026-11-08-t.md --no-push --agent "$TMPROOT/parent.sh" --worktrees "$WT" 2>&1)"; rc=$?
assert_eq 0 "$rc"; assert_eq "[unset]" "$(cat "$TMPROOT/parent-seen" 2>&1)"

echo "passed=$pass failed=$fail"; [ "$fail" -eq 0 ]
