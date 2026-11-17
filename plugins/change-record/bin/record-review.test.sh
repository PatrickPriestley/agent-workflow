#!/usr/bin/env bash
# Tests for record-review: a repository in a scratch directory with a change record, and a
# stand-in for the reviewing agent that keeps the brief it was given and answers as told.
# No model is called. Needs bash, git and python3.
set -u
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
R="$here/record-review"
# The real path, not a link to it: on macOS the temporary folder is /var/..., a link to /private/var/...,
# and git and python name the real one.
# a suite that cannot make its temporary folder must not go on: TMPROOT would be the folder it was started in
TMPROOT="$(mktemp -d)" && TMPROOT="$(cd "$TMPROOT" && pwd -P)" || { echo "cannot make a temporary folder" >&2; exit 1; }
trap 'rm -rf "$TMPROOT"' EXIT
pass=0; fail=0; CURRENT=""
it() { CURRENT="$1"; }
ok()  { pass=$((pass+1)); printf '  ok   %s\n' "$CURRENT"; }
bad() { fail=$((fail+1)); printf '  FAIL %s\n       %s\n' "$CURRENT" "$1"; }
assert_eq()  { [ "$1" = "$2" ] && ok || bad "expected [$1] got [$2]"; }
has()  { printf '%s' "$1" | grep -qF -- "$2" && ok || bad "missing [$2] in: $(printf '%s' "$1" | head -c 700)"; }
lacks() { printf '%s' "$1" | grep -qF -- "$2" && bad "unexpected [$2] in: $(printf '%s' "$1" | head -c 700)" || ok; }
unset CLAUDE_CODE_SESSION_ID AGENT_TRANSCRIPTS_PARENT
END='<<RECORD-REVIEW-END>>'

# The stand-in: keeps its brief, arguments, folder and one variable in $SEEN, then does what
# the FAKE_ variables say and prints $FAKE_REPLY.
cat > "$TMPROOT/agent.sh" <<'AGENT'
#!/usr/bin/env bash
mkdir -p "$SEEN"; cat > "$SEEN/brief"; printf '%s\n' "$@" > "$SEEN/argv"; pwd -P > "$SEEN/pwd"
printf '%s' "${AGENT_TRANSCRIPTS_PARENT-unset}" > "$SEEN/parent"
[ -z "${FAKE_SLEEP:-}" ] || sleep "$FAKE_SLEEP"
[ -z "${FAKE_TOUCH:-}" ] || : > "$FAKE_TOUCH"
[ -z "${FAKE_EDIT:-}" ] || printf 'changed\n' >> "$FAKE_EDIT"
[ -z "${FAKE_REPLY:-}" ] || cat "$FAKE_REPLY"
exit "${FAKE_EXIT:-0}"
AGENT
chmod +x "$TMPROOT/agent.sh"
export SEEN="$TMPROOT/seen"

REPO="$TMPROOT/repo"; mkdir -p "$REPO/docs/changes" "$REPO/src"; (
  cd "$REPO" && git init -q -b main && git config user.email t@example.com && git config user.name t
  git config core.hooksPath /dev/null
  printf -- '---\nid: 2026-01-01-ledger\ntier: 2\nstatus: open\nrequester: someone\napprovers: []\n---\n# Move the ledger\n\n## Problem\nUNIQUE-PROBLEM-TEXT\n\n## Decisions\n- D1\n' > docs/changes/2026-01-01-ledger.md
  printf 'print(1)\n' > src/app.py
  git add -A && git -c commit.gpgsign=false commit -qm "docs: a record" )
REC=docs/changes/2026-01-01-ledger.md
good="$TMPROOT/good.txt"; printf 'important: Decisions, D1 names no rejected alternative.\n\n%s\n\n' "$END" > "$good"
# review [ARGS]: the tool in the repository with the stand-in, both streams
review() { (cd "$REPO" && "$R" "$@" --agent "$TMPROOT/agent.sh" 2>&1); }
clean() { [ -z "$(git -C "$REPO" status --porcelain)" ] && echo clean || echo dirty; }

echo "usage"
it "no record, an unknown option and a second record are usage errors"
out="$(cd "$REPO" && "$R" 2>&1)"; assert_eq 2 "$?"; has "$out" "usage: record-review RECORD"
out="$(review "$REC" --bogus)"; assert_eq 2 "$?"
out="$(review "$REC" other.md)"; assert_eq 2 "$?"
it "a record that is not there, or has no id in its header, is refused before any reviewer runs"
rm -rf "$SEEN"; out="$(review docs/changes/none.md)"; assert_eq 2 "$?"; has "$out" "docs/changes/none.md"
printf '# no header\n' > "$REPO/docs/changes/bare.md"
out="$(review docs/changes/bare.md)"; assert_eq 2 "$?"; has "$out" "no id"
rm -f "$REPO/docs/changes/bare.md"
[ ! -e "$SEEN/brief" ] && ok || bad "a reviewer ran"
it "a record outside the repository is refused, and so is an id that is not a plain name: it names a folder"
printf -- '---\nid: elsewhere\n---\n# x\n' > "$TMPROOT/elsewhere.md"
out="$(review "$TMPROOT/elsewhere.md")"; assert_eq 2 "$?"; has "$out" "outside the repository"
printf -- '---\nid: ../../escape\n---\n# x\n' > "$REPO/docs/changes/odd.md"
out="$(review docs/changes/odd.md)"; assert_eq 2 "$?"; has "$out" "not a plain name"
rm -f "$REPO/docs/changes/odd.md"; [ ! -e "$REPO/.git/escape" ] && [ ! -e "$SEEN/brief" ] && ok || bad "a folder was made or a reviewer ran"
it "outside a git repository it says so"
out="$(cd "$TMPROOT" && "$R" x.md --agent "$TMPROOT/agent.sh" 2>&1)"; assert_eq 2 "$?"; has "$out" "not inside a git repository"

echo "the brief: the record and nothing of the caller"
rm -rf "$SEEN"; out="$(FAKE_REPLY="$good" review "$REC")"; rc=$?
it "a complete review exits 0 and is printed under a line that says who reviewed and with what"
assert_eq 0 "$rc"
assert_eq "Reviewed by: agent.sh, with no context but the record and the repository" "$(printf '%s\n' "$out" | head -1)"
has "$out" "D1 names no rejected alternative"
it "the end marker is not part of what is printed"
lacks "$out" "$END"
it "the reviewer is given the record's whole text and its path, on standard input"
brief="$(cat "$SEEN/brief")"
has "$brief" "UNIQUE-PROBLEM-TEXT"; has "$brief" "id: 2026-01-01-ledger"; has "$brief" "$REC"
it "the brief says the reviewer has not seen the conversation, may only read, and what to look for"
has "$brief" "have not seen the conversation"; has "$brief" "Do not change any file"
for w in "cannot understand" "evidence" "no test could check" "rejected alternative" "would pass today" "no owner" "tier"; do has "$brief" "$w"; done
it "the brief asks for a severity for each finding and for the end marker as the last line"
has "$brief" "critical, important or minor"; has "$brief" "$END"
it "the reviewer runs from the repository's root, whatever folder the tool was started in"
out2="$(cd "$REPO/src" && FAKE_REPLY="$good" "$R" "../$REC" --agent "$TMPROOT/agent.sh" 2>&1)"; assert_eq 0 "$?"
assert_eq "$REPO" "$(cat "$SEEN/pwd")"
it "the review, the brief and the reviewer's raw answer are kept inside .git, out of the working tree"
d="$REPO/.git/record-review/2026-01-01-ledger"
has "$(cat "$d/review.md" 2>/dev/null)" "D1 names no rejected alternative"
has "$(cat "$d/brief.md" 2>/dev/null)" "UNIQUE-PROBLEM-TEXT"
assert_eq clean "$(clean)"
it "the reviewer's session is tied to the calling session for the capture, and to none when there is none"
assert_eq "unset" "$(cat "$SEEN/parent")"
out="$(CLAUDE_CODE_SESSION_ID=parent-1 FAKE_REPLY="$good" review "$REC")"
assert_eq "parent-1" "$(cat "$SEEN/parent")"
it "a parent left in the environment by something else is not passed on when there is no calling session"
out="$(AGENT_TRANSCRIPTS_PARENT=stale FAKE_REPLY="$good" review "$REC")"
assert_eq "unset" "$(cat "$SEEN/parent")"

echo "a review that is not one"
it "an answer whose last nonblank line is not the end marker exits 3 and prints no review"
printf 'important: something.\n%s\nand then more\n' "$END" > "$TMPROOT/cut.txt"
out="$(FAKE_REPLY="$TMPROOT/cut.txt" review "$REC")"; assert_eq 3 "$?"
has "$out" "no end marker"; lacks "$out" "Reviewed by:"
it "an answer that is the end marker and nothing else exits 3: it reviewed nothing"
printf '%s\n' "$END" > "$TMPROOT/empty.txt"
out="$(FAKE_REPLY="$TMPROOT/empty.txt" review "$REC")"; assert_eq 3 "$?"; lacks "$out" "Reviewed by:"
it "a reviewer that fails exits 4, whatever it printed"
out="$(FAKE_REPLY="$good" FAKE_EXIT=7 review "$REC")"; assert_eq 4 "$?"; has "$out" "exit 7"; lacks "$out" "Reviewed by:"
it "a reviewer that takes longer than --timeout is stopped and exits 4"
t=$SECONDS; out="$(FAKE_REPLY="$good" FAKE_SLEEP=20 review "$REC" --timeout 1)"; rc=$?
assert_eq 4 "$rc"; has "$out" "1 s"; [ $((SECONDS - t)) -lt 15 ] && ok || bad "it waited $((SECONDS - t)) s"
it "--timeout takes whole seconds only"
out="$(review "$REC" --timeout soon)"; assert_eq 2 "$?"

echo "a reviewer that writes"
it "a reviewer that adds a file exits 5 and names it; the review is not printed"
out="$(FAKE_REPLY="$good" FAKE_TOUCH="$REPO/new.txt" review "$REC")"; assert_eq 5 "$?"
has "$out" "new.txt"; lacks "$out" "Reviewed by:"; rm -f "$REPO/new.txt"
it "a reviewer that changes a tracked file exits 5 and names it"
out="$(FAKE_REPLY="$good" FAKE_EDIT="$REPO/src/app.py" review "$REC")"; assert_eq 5 "$?"
has "$out" "src/app.py"; git -C "$REPO" checkout -q -- src/app.py
it "work the author had not committed is not taken for the reviewer's: the tree may be dirty before"
printf 'draft\n' >> "$REPO/$REC"; printf 'wip\n' > "$REPO/wip.txt"
out="$(FAKE_REPLY="$good" review "$REC")"; assert_eq 0 "$?"
has "$(cat "$SEEN/brief")" "draft"
it "but a change the reviewer makes to a file that was already dirty is still seen"
out="$(FAKE_REPLY="$good" FAKE_EDIT="$REPO/wip.txt" review "$REC")"; assert_eq 5 "$?"; has "$out" "wip.txt"
git -C "$REPO" checkout -q -- "$REC"; rm -f "$REPO/wip.txt"

echo "a fresh session, or none"
it "an --agent command that continues or resumes a session is refused: that is not a fresh context"
# stand-ins for both agents come first on PATH: were the refusal ever broken, no real session would start
mkdir -p "$TMPROOT/none"; printf '#!/usr/bin/env bash\ncat > /dev/null\n' > "$TMPROOT/none/claude"; cp "$TMPROOT/none/claude" "$TMPROOT/none/codex"; chmod +x "$TMPROOT/none/claude" "$TMPROOT/none/codex"
for a in "claude -p --continue" "claude -p -c" "claude --resume abc -p" "claude -p -r abc" "codex exec resume --last"; do
  out="$(cd "$REPO" && PATH="$TMPROOT/none:$PATH" "$R" "$REC" --agent "$a" 2>&1)"; rc=$?
  [ "$rc" = 2 ] && printf '%s' "$out" | grep -q "fresh" && ok || bad "[$a] gave exit $rc: $out"
done
it "a command that merely has those letters in a word is not refused"
cp "$TMPROOT/agent.sh" "$TMPROOT/resumer-c.sh"
out="$(cd "$REPO" && FAKE_REPLY="$good" "$R" "$REC" --agent "$TMPROOT/resumer-c.sh" 2>&1)"; assert_eq 0 "$?"

it "-c is refused for claude only: for another agent it is an ordinary option"
mkdir -p "$TMPROOT/other"; cp "$TMPROOT/agent.sh" "$TMPROOT/other/codex"
out="$(cd "$REPO" && PATH="$TMPROOT/other:$PATH" FAKE_REPLY="$good" "$R" "$REC" --agent "codex exec -c model=x" 2>&1)"; assert_eq 0 "$?"
assert_eq "Reviewed by: codex, with no context but the record and the repository" "$(printf '%s\n' "$out" | head -1)"
assert_eq "exec -c model=x" "$(tr '\n' ' ' < "$SEEN/argv" | sed 's/ $//')"

echo "the default reviewer"
# a claude on PATH that keeps its arguments and prints the JSON claude -p prints
mkdir -p "$TMPROOT/bin"; cat > "$TMPROOT/bin/claude" <<'FAKE'
#!/usr/bin/env bash
mkdir -p "$SEEN"; cat > "$SEEN/brief"; printf '%s\n' "$@" > "$SEEN/argv"
python3 -c 'import json,os,sys; print(json.dumps({"is_error": os.environ.get("FAKE_ERROR") == "1", "result": open(os.environ["FAKE_REPLY"]).read(), "modelUsage": {"made-up-model-1": {}}}))'
FAKE
chmod +x "$TMPROOT/bin/claude"
default() { (cd "$REPO" && PATH="$TMPROOT/bin:$PATH" "$R" "$@" 2>&1); }
rm -rf "$SEEN"; out="$(FAKE_REPLY="$good" default "$REC")"; rc=$?
it "without --agent the reviewer is claude -p with tools that only read, and JSON out"
assert_eq 0 "$rc"
assert_eq "-p --tools Read Grep Glob --output-format json" "$(tr '\n' ' ' < "$SEEN/argv" | sed 's/ $//')"
it "its JSON is opened: the review is its result, and the line above names the model it reports"
assert_eq "Reviewed by: claude made-up-model-1, with no context but the record and the repository" "$(printf '%s\n' "$out" | head -1)"
has "$out" "D1 names no rejected alternative"; lacks "$out" '"result"'
it "a result the reviewer marks as an error exits 4"
out="$(FAKE_REPLY="$good" FAKE_ERROR=1 default "$REC")"; assert_eq 4 "$?"; lacks "$out" "Reviewed by:"
it "no claude on PATH and no --agent: it says what to install or pass"
out="$(cd "$REPO" && PATH="/usr/bin:/bin" "$R" "$REC" 2>&1)"; assert_eq 2 "$?"; has "$out" "--agent"

echo "passed=$pass failed=$fail"; [ "$fail" -eq 0 ]
