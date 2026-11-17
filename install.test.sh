#!/usr/bin/env bash
# Tests for install.sh: a scratch HOME and real symlinks.
set -u
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TMPROOT="$(mktemp -d)"; trap 'rm -rf "$TMPROOT"' EXIT
pass=0; fail=0; CURRENT=""
it() { CURRENT="$1"; }
ok()  { pass=$((pass+1)); printf '  ok   %s\n' "$CURRENT"; }
bad() { fail=$((fail+1)); printf '  FAIL %s\n       %s\n' "$CURRENT" "$1"; }
assert_eq()  { [ "$1" = "$2" ] && ok || bad "expected [$1] got [$2]"; }
assert_link(){ [ -L "$1" ] && [ "$(readlink "$1")" = "$2" ] && ok || bad "$1 should link to $2, is $(readlink "$1" 2>/dev/null || echo 'not a link')"; }
fresh_home() { h="$TMPROOT/$1"; mkdir -p "$h"; printf '%s' "$h"; }
# The tests below check linking itself, so they link this checkout (--dev); the pinned
# default is tested at the end.
run() { HOME="$1" bash "$here/install.sh" --dev "${@:2}"; }

it "fresh install links the rules, skills, workflow and commands"
H=$(fresh_home fresh)
out=$(run "$H" 2>&1); rc=$?
assert_eq 0 "$rc"
assert_link "$H/AGENT-WORKFLOW.md" "$here/AGENT-WORKFLOW.md"
assert_link "$H/.agents/skills/feature-loop" "$here/skills/feature-loop"
assert_link "$H/.claude/skills/feature-loop" "$H/.agents/skills/feature-loop"
assert_link "$H/.agents/skills/agent-review" "$here/skills/agent-review"
assert_link "$H/.claude/skills/agent-review" "$H/.agents/skills/agent-review"
assert_link "$H/.claude/workflows/feature-loop.js" "$here/workflows/feature-loop.js"
assert_link "$H/.local/bin/agent-review" "$here/bin/agent-review"
assert_link "$H/.local/bin/commit-gate" "$here/bin/commit-gate"
assert_link "$H/.local/bin/pr-size" "$here/bin/pr-size"
for sk in intent spec plan incident-to-eval; do
  assert_link "$H/.agents/skills/$sk" "$here/skills/$sk"
  assert_link "$H/.claude/skills/$sk" "$H/.agents/skills/$sk"
done
it "without --wire, agent config files are left alone"
[ ! -e "$H/.claude/CLAUDE.md" ] && ok || bad "CLAUDE.md was written without --wire"
it "fresh install does not create or edit Claude settings"
[ ! -e "$H/.claude/settings.json" ] && ok || bad "settings.json was written"

it "second run is idempotent"
out=$(run "$H" 2>&1); rc=$?
assert_eq 0 "$rc"
printf '%s' "$out" | grep -q "^linked" && bad "second run relinked: $out" || ok

it "refuses to overwrite a differing file, before changing anything"
H=$(fresh_home conflict)
printf 'my own rules\n' > "$H/AGENT-WORKFLOW.md"
out=$(run "$H" 2>&1); rc=$?
assert_eq 1 "$rc"
assert_eq "my own rules" "$(cat "$H/AGENT-WORKFLOW.md")"
printf '%s' "$out" | grep -q "AGENT-WORKFLOW.md" && ok || bad "error does not name the file: $out"
[ ! -e "$H/.claude/workflows/feature-loop.js" ] && ok || bad "later links were created despite the refusal"

it "refuses to replace a real folder"
H=$(fresh_home folder)
mkdir -p "$H/.claude/skills/feature-loop"
out=$(run "$H" 2>&1); rc=$?
assert_eq 1 "$rc"
[ -d "$H/.claude/skills/feature-loop" ] && [ ! -L "$H/.claude/skills/feature-loop" ] && ok || bad "folder was replaced"

it "replaces an identical file with a link"
H=$(fresh_home identical)
cp "$here/AGENT-WORKFLOW.md" "$H/AGENT-WORKFLOW.md"
run "$H" >/dev/null 2>&1; rc=$?
assert_eq 0 "$rc"
assert_link "$H/AGENT-WORKFLOW.md" "$here/AGENT-WORKFLOW.md"

it "repoints a stale link"
H=$(fresh_home stale)
mkdir -p "$H/.claude/workflows"; ln -s /nowhere/feature-loop.js "$H/.claude/workflows/feature-loop.js"
run "$H" >/dev/null 2>&1
assert_link "$H/.claude/workflows/feature-loop.js" "$here/workflows/feature-loop.js"

it "dry run changes nothing"
H=$(fresh_home dry)
out=$(run "$H" --dry-run 2>&1); rc=$?
assert_eq 0 "$rc"
[ ! -e "$H/AGENT-WORKFLOW.md" ] && ok || bad "dry run created files"
printf '%s' "$out" | grep -q "would" && ok || bad "dry run printed no plan: $out"

it "--wire gives each installed agent the rules themselves, once"
H=$(fresh_home wire); mkdir -p "$H/.claude" "$H/.codex" "$H/.config/opencode" "$H/.gemini" "$H/.cursor/rules"
printf '# my notes\n' > "$H/.claude/CLAUDE.md"
run "$H" --wire >/dev/null 2>&1; rc=$?
assert_eq 0 "$rc"
assert_eq 1 "$(grep -c '^@~/AGENT-WORKFLOW.md$' "$H/.claude/CLAUDE.md")"
grep -q '^# my notes' "$H/.claude/CLAUDE.md" && ok || bad "existing CLAUDE.md content was lost"
assert_link "$H/.codex/AGENTS.md" "$H/AGENT-WORKFLOW.md"
assert_link "$H/.config/opencode/AGENTS.md" "$H/AGENT-WORKFLOW.md"
assert_link "$H/.gemini/GEMINI.md" "$H/AGENT-WORKFLOW.md"
grep -q 'Probe before you assert' "$H/.cursor/rules/agent-workflow.mdc" && ok || bad "Cursor rule does not contain the rules"
grep -q '^alwaysApply: true' "$H/.cursor/rules/agent-workflow.mdc" && ok || bad "Cursor rule is not always applied"
run "$H" --wire >/dev/null 2>&1
assert_eq 1 "$(grep -c 'AGENT-WORKFLOW.md' "$H/.claude/CLAUDE.md")"

it "--wire regenerates the Cursor rule when the rules change"
R="$TMPROOT/repocopy"; mkdir -p "$R"; cp "$here/install.sh" "$here/AGENT-WORKFLOW.md" "$R/"
printf '\n7. **Extra rule for the test.**\n' >> "$R/AGENT-WORKFLOW.md"
HOME="$H" bash "$R/install.sh" --dev --wire >/dev/null 2>&1
grep -q 'Extra rule for the test' "$H/.cursor/rules/agent-workflow.mdc" && ok || bad "Cursor rule went stale"
grep -q 'Extra rule for the test' "$here/AGENT-WORKFLOW.md" && bad "the test edited the real rules file" || ok

it "--wire adds the import when CLAUDE.md only mentions the rules in prose"
H=$(fresh_home wireprose); mkdir -p "$H/.claude"
printf 'Follow the rules in `~/AGENT-WORKFLOW.md` (canonical, shared across agents).\n' > "$H/.claude/CLAUDE.md"
run "$H" --wire >/dev/null 2>&1
assert_eq 1 "$(grep -c '^@~/AGENT-WORKFLOW.md$' "$H/.claude/CLAUDE.md")"

it "--wire leaves a link to someone's own instructions alone"
H=$(fresh_home wireownlink); mkdir -p "$H/.codex" "$H/dotfiles"
printf 'my dotfile notes\n' > "$H/dotfiles/AGENTS.md"; ln -s "$H/dotfiles/AGENTS.md" "$H/.codex/AGENTS.md"
out=$(run "$H" --wire 2>&1)
assert_link "$H/.codex/AGENTS.md" "$H/dotfiles/AGENTS.md"
printf '%s' "$out" | grep -q '.codex/AGENTS.md' && ok || bad "no note about the link it left alone: $out"

it "--wire keeps a hand-written Cursor rule as a backup before replacing it"
H=$(fresh_home wirecursor); mkdir -p "$H/.cursor/rules"
printf -- '---\nalwaysApply: true\n---\nFollow the working rules in ~/AGENT-WORKFLOW.md.\n' > "$H/.cursor/rules/agent-workflow.mdc"
run "$H" --wire >/dev/null 2>&1; rc=$?
assert_eq 0 "$rc"
grep -q 'Follow the working rules' "$H/.cursor/rules/agent-workflow.mdc.bak" && ok || bad "hand-written rule was not backed up"
grep -q 'Probe before you assert' "$H/.cursor/rules/agent-workflow.mdc" && ok || bad "rule not replaced"

it "--wire leaves an agent's own instruction file alone and says so"
H=$(fresh_home wireown); mkdir -p "$H/.codex"
printf 'my codex notes\n' > "$H/.codex/AGENTS.md"
out=$(run "$H" --wire 2>&1); rc=$?
assert_eq 0 "$rc"
assert_eq "my codex notes" "$(cat "$H/.codex/AGENTS.md")"
printf '%s' "$out" | grep -q '.codex/AGENTS.md' && ok || bad "no note about the file it left alone: $out"

it "--wire leaves a dangling link to someone's own instructions alone"
H=$(fresh_home wiredangle); mkdir -p "$H/.gemini"
ln -s "$H/unmounted/GEMINI.md" "$H/.gemini/GEMINI.md"
run "$H" --wire >/dev/null 2>&1
assert_link "$H/.gemini/GEMINI.md" "$H/unmounted/GEMINI.md"

it "--wire never overwrites an earlier Cursor backup"
H=$(fresh_home wirebak); mkdir -p "$H/.cursor/rules"
printf 'first\n' > "$H/.cursor/rules/agent-workflow.mdc"; run "$H" --wire >/dev/null 2>&1
printf 'second\n' > "$H/.cursor/rules/agent-workflow.mdc"; run "$H" --wire >/dev/null 2>&1
assert_eq "first" "$(cat "$H/.cursor/rules/agent-workflow.mdc.bak")"
cat "$H/.cursor/rules/"agent-workflow.mdc.bak* | grep -q second && ok || bad "second hand-written rule was lost"

it "--wire adds the import when CLAUDE.md imports some other file of that name"
H=$(fresh_home wireother); mkdir -p "$H/.claude"
printf '@~/archive/AGENT-WORKFLOW.md.bak\n@~/AGENT-WORKFLOW.md.bak\n' > "$H/.claude/CLAUDE.md"
run "$H" --wire >/dev/null 2>&1
assert_eq 1 "$(grep -c '^@~/AGENT-WORKFLOW.md$' "$H/.claude/CLAUDE.md")"

it "--wire accepts an absolute import of the rules"
H=$(fresh_home wireabs); mkdir -p "$H/.claude"
printf '@%s/AGENT-WORKFLOW.md\n' "$H" > "$H/.claude/CLAUDE.md"
run "$H" --wire >/dev/null 2>&1
assert_eq 1 "$(grep -c 'AGENT-WORKFLOW.md' "$H/.claude/CLAUDE.md")"

it "--wire never writes through a linked Cursor rule"
H=$(fresh_home wirecursorlink); mkdir -p "$H/.cursor/rules" "$H/dotfiles"
printf 'mine\n' > "$H/dotfiles/rule.mdc"; ln -s "$H/dotfiles/rule.mdc" "$H/.cursor/rules/agent-workflow.mdc"
run "$H" --wire >/dev/null 2>&1
assert_eq "mine" "$(cat "$H/dotfiles/rule.mdc")"
[ -f "$H/.cursor/rules/agent-workflow.mdc" ] && [ ! -L "$H/.cursor/rules/agent-workflow.mdc" ] && ok || bad "rule is still a link"
assert_link "$H/.cursor/rules/agent-workflow.mdc.bak" "$H/dotfiles/rule.mdc"

it "--wire replaces a link even when it points at the current generated rule"
H=$(fresh_home wirecurlink); mkdir -p "$H/.cursor/rules" "$H/dotfiles"
run "$H" --wire >/dev/null 2>&1
mv "$H/.cursor/rules/agent-workflow.mdc" "$H/dotfiles/rule.mdc"; cp "$H/dotfiles/rule.mdc" "$H/expected"
ln -s "$H/dotfiles/rule.mdc" "$H/.cursor/rules/agent-workflow.mdc"
ln -s "$H/gone" "$H/.cursor/rules/agent-workflow.mdc.bak"
run "$H" --wire >/dev/null 2>&1
[ -f "$H/.cursor/rules/agent-workflow.mdc" ] && [ ! -L "$H/.cursor/rules/agent-workflow.mdc" ] && ok || bad "rule is still a link"
cmp -s "$H/expected" "$H/dotfiles/rule.mdc" && ok || bad "linked file was changed"
assert_link "$H/.cursor/rules/agent-workflow.mdc.bak" "$H/gone"

it "--wire treats a CLAUDE.md that links to the rules as wired"
H=$(fresh_home wireclaudelink); R="$TMPROOT/repocopy2"; mkdir -p "$H/.claude" "$R"
cp "$here/install.sh" "$here/AGENT-WORKFLOW.md" "$R/"; cp "$R/AGENT-WORKFLOW.md" "$H/expected"
ln -s "$H/AGENT-WORKFLOW.md" "$H/.claude/CLAUDE.md"
HOME="$H" bash "$R/install.sh" --wire >/dev/null 2>&1
cmp -s "$H/expected" "$R/AGENT-WORKFLOW.md" && ok || bad "the rules file was edited through the link"

it "--wire names a kept file even when it mentions a file of a similar name"
H=$(fresh_home wiresimilar); mkdir -p "$H/.gemini"
printf 'Archived notes: ~/AGENT-WORKFLOW.md.bak\n' > "$H/.gemini/GEMINI.md"
out=$(run "$H" --wire 2>&1)
printf '%s' "$out" | grep -q 'left .*\.gemini/GEMINI.md' && ok || bad "no note: $out"

it "--wire accepts a link to the repository's rules file"
H=$(fresh_home wirerepolink); mkdir -p "$H/.codex"
ln -s "$here/AGENT-WORKFLOW.md" "$H/.codex/AGENTS.md"
out=$(run "$H" --wire 2>&1)
assert_link "$H/.codex/AGENTS.md" "$here/AGENT-WORKFLOW.md"
printf '%s' "$out" | grep -q 'left .*\.codex' && bad "noted a file that is already the rules: $out" || ok

it "--wire --dry-run accepts a link to the rules before the rules are linked"
H=$(fresh_home wiredrylink); mkdir -p "$H/.codex"
ln -s "$H/AGENT-WORKFLOW.md" "$H/.codex/AGENTS.md"
out=$(run "$H" --wire --dry-run 2>&1)
printf '%s' "$out" | grep -q 'left .*\.codex' && bad "noted a link that is already wired: $out" || ok

it "--wire skips agents that are not installed"
H=$(fresh_home wirenone); mkdir -p "$H/.claude"
run "$H" --wire >/dev/null 2>&1; rc=$?
assert_eq 0 "$rc"
[ ! -e "$H/.codex" ] && [ ! -e "$H/.cursor" ] && [ ! -e "$H/.config/opencode" ] && ok || bad "created folders for agents that are not installed"

it "--wire with --dry-run writes nothing"
H=$(fresh_home wiredry); mkdir -p "$H/.claude" "$H/.codex"
out=$(run "$H" --wire --dry-run 2>&1)
[ ! -e "$H/.claude/CLAUDE.md" ] && [ ! -e "$H/.codex/AGENTS.md" ] && ok || bad "dry run wrote files"
printf '%s' "$out" | grep -q "would:" && ok || bad "dry run did not show the wiring: $out"


# ---- the pinned default ------------------------------------------------------------------
# A scratch clone of this repository stands in for a teammate's checkout: main (with an
# origin/main), a tag, and a development branch checked out with an extra commit.
SRC="$TMPROOT/src"; git clone -q "$here" "$SRC" 2>/dev/null
git -C "$SRC" config user.email t@t; git -C "$SRC" config user.name t; git -C "$SRC" config core.hooksPath /dev/null
cp "$here/install.sh" "$SRC/install.sh"   # the installer under test, not the last committed one
git -C "$SRC" checkout -q -B main; git -C "$SRC" -c commit.gpgsign=false commit -qam "chore: installer under test" --allow-empty
git -C "$SRC" update-ref refs/remotes/origin/main HEAD; git -C "$SRC" -c tag.gpgsign=false tag v-test
git -C "$SRC" checkout -q -b dev; printf '\n# dev branch edit\n' >> "$SRC/AGENT-WORKFLOW.md"; git -C "$SRC" -c commit.gpgsign=false commit -qam "docs: dev edit"
pinned_run() { HOME="$1" bash "$SRC/install.sh" "${@:2}"; }

it "by default it installs from a pinned copy at origin/main, not from this checkout"
H=$(fresh_home pin1); P="$H/.local/share/agent-workflow"
out=$(pinned_run "$H" 2>&1); rc=$?
assert_eq 0 "$rc"
assert_link "$H/AGENT-WORKFLOW.md" "$P/AGENT-WORKFLOW.md"
assert_link "$H/.local/bin/agent-review" "$P/bin/agent-review"
assert_eq "$(git -C "$SRC" rev-parse origin/main)" "$(git -C "$P" rev-parse HEAD 2>/dev/null)"
grep -q "dev branch edit" "$H/AGENT-WORKFLOW.md" && bad "the installed rules have the dev branch's edit" || ok
assert_has_line() { printf '%s' "$2" | grep -qF -- "$1" && ok || bad "expected [$1] in: $2"; }
assert_has_line "pinned $P at origin/main" "$out"

it "switching branches in the checkout does not change what is installed"
git -C "$SRC" checkout -q main; git -C "$SRC" checkout -q dev
grep -q "dev branch edit" "$H/AGENT-WORKFLOW.md" && bad "the installed rules followed the checkout" || ok

it "rerunning after origin/main moves updates the pinned copy, and is otherwise a no-op"
out=$(pinned_run "$H" 2>&1); printf '%s' "$out" | grep -q "^linked" && bad "second run relinked: $out" || ok
git -C "$SRC" update-ref refs/remotes/origin/main dev
out=$(pinned_run "$H" 2>&1); assert_eq 0 "$?"
assert_eq "$(git -C "$SRC" rev-parse dev)" "$(git -C "$P" rev-parse HEAD)"
grep -q "dev branch edit" "$H/AGENT-WORKFLOW.md" && ok || bad "the update did not reach the installed rules"
git -C "$SRC" update-ref refs/remotes/origin/main main

it "--ref pins a tag or branch"
H=$(fresh_home pin2); P="$H/.local/share/agent-workflow"
out=$(pinned_run "$H" --ref v-test 2>&1); assert_eq 0 "$?"
assert_eq "$(git -C "$SRC" rev-parse v-test)" "$(git -C "$P" rev-parse HEAD)"

it "an unknown --ref fails before anything changes"
H=$(fresh_home pin3)
out=$(pinned_run "$H" --ref no-such-ref 2>&1); rc=$?
[ "$rc" != 0 ] && ok || bad "an unknown ref was accepted"
[ ! -e "$H/.local/share/agent-workflow" ] && [ ! -e "$H/AGENT-WORKFLOW.md" ] && ok || bad "files were written for an unknown ref"

it "a pinned copy with local edits is not overwritten"
H=$(fresh_home pin4); P="$H/.local/share/agent-workflow"
pinned_run "$H" >/dev/null 2>&1; printf 'mine\n' >> "$P/README.md"
git -C "$SRC" update-ref refs/remotes/origin/main dev
out=$(pinned_run "$H" 2>&1); rc=$?
[ "$rc" != 0 ] && ok || bad "local edits in the pinned copy were overwritten"
assert_has_line "has local changes" "$out"
grep -q '^mine$' "$P/README.md" && ok || bad "the local edit was lost"
git -C "$SRC" update-ref refs/remotes/origin/main main

it "a folder at the pinned path that is not a git checkout stops the install"
H=$(fresh_home pin5); mkdir -p "$H/.local/share/agent-workflow"; echo x > "$H/.local/share/agent-workflow/x"
out=$(pinned_run "$H" 2>&1); rc=$?
[ "$rc" != 0 ] && ok || bad "installed over a folder that is not a checkout"

it "a pinned path inside another repository is never taken for the pinned copy"
H=$(fresh_home pin5b); git init -q "$H"; echo keep > "$H/mine.txt"
git -C "$H" add mine.txt; git -C "$H" -c user.email=t@t -c user.name=t -c commit.gpgsign=false commit -qm "chore: home"
mkdir -p "$H/.local/share/agent-workflow"; before="$(git -C "$H" rev-parse HEAD)"
out=$(pinned_run "$H" 2>&1); rc=$?
[ "$rc" != 0 ] && ok || bad "installed into the enclosing repository"
assert_eq "$before" "$(git -C "$H" rev-parse HEAD)"
[ -f "$H/mine.txt" ] && ok || bad "the enclosing repository's files were removed"
assert_has_line "is not a git checkout" "$out"

it "an install linked to the checkout moves to the pinned copy on the next default run"
H=$(fresh_home pin5e); P="$H/.local/share/agent-workflow"
HOME="$H" bash "$SRC/install.sh" --dev >/dev/null 2>&1
assert_link "$H/AGENT-WORKFLOW.md" "$SRC/AGENT-WORKFLOW.md"
pinned_run "$H" >/dev/null 2>&1; assert_eq 0 "$?"
assert_link "$H/AGENT-WORKFLOW.md" "$P/AGENT-WORKFLOW.md"
assert_link "$H/.local/bin/agent-review" "$P/bin/agent-review"

it "a file at the pinned path stops the install"
H=$(fresh_home pin5d); mkdir -p "$H/.local/share"; echo x > "$H/.local/share/agent-workflow"
out=$(pinned_run "$H" 2>&1); rc=$?
[ "$rc" != 0 ] && ok || bad "installed over a file"
assert_has_line "is not a git checkout" "$out"

it "--ref pins a commit that is no branch or tag tip, even one the pinned copy lacks"
H=$(fresh_home pin5c); P="$H/.local/share/agent-workflow"; pinned_run "$H" >/dev/null 2>&1
git -C "$SRC" checkout -q -b mid main; git -C "$SRC" -c commit.gpgsign=false commit -q --allow-empty -m "chore: mid"
mid="$(git -C "$SRC" rev-parse HEAD)"; git -C "$SRC" -c commit.gpgsign=false commit -q --allow-empty -m "chore: past mid"
git -C "$SRC" checkout -q dev
out=$(pinned_run "$H" --ref "$mid" 2>&1); rc=$?
assert_eq 0 "$rc"
assert_eq "$mid" "$(git -C "$P" rev-parse HEAD 2>/dev/null)"

it "--dry-run says what it would pin and changes nothing"
H=$(fresh_home pin6)
out=$(pinned_run "$H" --dry-run 2>&1); assert_eq 0 "$?"
assert_has_line "would: pin $H/.local/share/agent-workflow at origin/main" "$out"
[ ! -e "$H/.local/share/agent-workflow" ] && [ ! -e "$H/AGENT-WORKFLOW.md" ] && ok || bad "dry run wrote files"

it "without origin/main it pins main"
H=$(fresh_home pin7); P="$H/.local/share/agent-workflow"
git -C "$SRC" update-ref -d refs/remotes/origin/main
out=$(pinned_run "$H" 2>&1); assert_eq 0 "$?"
assert_eq "$(git -C "$SRC" rev-parse main)" "$(git -C "$P" rev-parse HEAD)"
git -C "$SRC" update-ref refs/remotes/origin/main main

it "--dev links this checkout, as before"
H=$(fresh_home pin8)
out=$(pinned_run "$H" --dev 2>&1); assert_eq 0 "$?"
assert_link "$H/AGENT-WORKFLOW.md" "$SRC/AGENT-WORKFLOW.md"

printf 'passed=%d failed=%d\n' "$pass" "$fail"
[ "$fail" = 0 ]
