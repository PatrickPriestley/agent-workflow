#!/usr/bin/env bash
# Tests for agent-review: real git repos, fake agent CLIs on PATH that record how they were called.
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
AR="$here/agent-review"
TMPROOT="$(mktemp -d)"; trap 'rm -rf "$TMPROOT"' EXIT
pass=0; fail=0; CURRENT=""
it() { CURRENT="$1"; }
ok()  { pass=$((pass+1)); printf '  ok   %s\n' "$CURRENT"; }
bad() { fail=$((fail+1)); printf '  FAIL %s\n       %s\n' "$CURRENT" "$1"; }
assert_eq()  { [ "$1" = "$2" ] && ok || bad "expected [$1] got [$2]"; }
assert_has() { printf '%s' "$2" | grep -qF -- "$1" && ok || bad "expected [$1] in: $(printf '%s' "$2" | head -c 400)"; }

FAKE="$TMPROOT/fake"; mkdir -p "$FAKE"; LOG="$TMPROOT/calls"
for cli in codex claude cursor-agent gemini; do
cat > "$FAKE/$cli" <<FAKEEOF
#!/bin/bash
# Record argv and stdin; answer like a reviewer.
{ printf 'CLI=%s\n' "$cli"; printf 'ARG=%s\n' "\$@"; printf 'STDIN=%s\n' "\$( [ -t 0 ] || cat )"; } >> "$LOG"
[ -n "\${FAKE_SLEEP:-}" ] && sleep "\$FAKE_SLEEP"
[ -n "\${FAKE_EXIT:-}" ] && { echo "reviewer broke" >&2; exit "\$FAKE_EXIT"; }
reply="1. greet.py:3 - something. Fix: something."
[ -n "\${FAKE_NO_MARKER:-}" ] || reply="\$reply
<<AGENT-REVIEW-END>>"
if [ "$cli" = codex ]; then
  out=""; prev=""; for a in "\$@"; do [ "\$prev" = "-o" ] && out="\$a"; prev="\$a"; done
  printf '%s\n' "\$reply" > "\$out"
else
  printf '%s\n' "\$reply"
fi
FAKEEOF
chmod +x "$FAKE/$cli"
done

repo() {  # main with one commit, feature branch with one more
  r="$TMPROOT/$1"; git init -q -b main "$r"
  printf 'print("hi")\n' > "$r/greet.py"; git -C "$r" add -A; git -C "$r" -c user.name=t -c user.email=t@t commit -q -m "chore: init"
  git -C "$r" checkout -q -b feature
  printf 'print("hello")\n' > "$r/greet.py"; git -C "$r" -c user.name=t -c user.email=t@t commit -q -am "feat: hello"
  printf '%s' "$r"
}
run() {  # run in repo $1 as caller $2 (claude|codex|none) with remaining args
  local r="$1" caller="$2"; shift 2; : > "$LOG"
  local envs=(PATH="$FAKE:/usr/bin:/bin" HOME="$TMPROOT/home")
  case "$caller" in
    claude) envs+=(CLAUDECODE=1) ;;
    codex)  envs+=(CLAUDECODE=1 CODEX_THREAD_ID=t1) ;;   # Claude's variables leak into children; Codex's wins
  esac
  (cd "$r" && env -i "${envs[@]}" ${EXTRA_ENV:-} bash "$AR" "$@")
}

it "a Claude caller is reviewed by Codex, read-only"
R=$(repo a)
out=$(run "$R" claude code 2>&1); rc=$?
assert_eq 0 "$rc"
assert_has "CLI=codex" "$(cat "$LOG")"
assert_has "ARG=read-only" "$(cat "$LOG")"
assert_has "<<AGENT-REVIEW-END>>" "$out"

it "a Codex caller is reviewed by Claude with read-only tools, prompt on stdin"
out=$(run "$R" codex code 2>&1); rc=$?
assert_eq 0 "$rc"
assert_has "CLI=claude" "$(cat "$LOG")"
assert_has "ARG=-p" "$(cat "$LOG")"
grep -q "^ARG=Write\|^ARG=Edit\|^ARG=Bash" "$LOG" && bad "claude was granted a write tool" || ok
assert_has "ARG=--allowedTools" "$(cat "$LOG")"
assert_has "STDIN=" "$(grep '^STDIN=.' "$LOG")"

it "the prompt pins the range to commit IDs"
base=$(git -C "$R" rev-parse main); head=$(git -C "$R" rev-parse feature)
assert_has "$base..$head" "$(cat "$LOG")"

it "the diff file holds exactly the pinned range's diff"
dir=$(grep -o '/[^ ]*/agent-review/[^ /]*' "$LOG" | head -1)
[ -f "$dir/diff.patch" ] && ok || bad "no diff.patch in [$dir]"
assert_eq "$(git -C "$R" diff "$base" "$head")" "$(cat "$dir/diff.patch")"

it "the review leaves the working tree clean"
assert_eq "" "$(git -C "$R" status --porcelain)"

it "asking for the caller's own kind is refused"
out=$(run "$R" claude code --reviewer claude 2>&1); rc=$?
assert_eq 2 "$rc"
assert_has "same kind" "$out"

it "--reviewer picks Cursor in plan mode"
out=$(run "$R" claude code --reviewer cursor 2>&1); rc=$?
assert_eq 0 "$rc"
assert_has "CLI=cursor-agent" "$(cat "$LOG")"
assert_has "ARG=plan" "$(cat "$LOG")"

it "--reviewer picks Gemini in plan approval mode"
out=$(run "$R" claude code --reviewer gemini 2>&1); rc=$?
assert_has "CLI=gemini" "$(cat "$LOG")"
assert_has "ARG=plan" "$(cat "$LOG")"

it "git config agentreview.reviewer sets the default"
git -C "$R" config agentreview.reviewer gemini
out=$(run "$R" claude code 2>&1)
assert_has "CLI=gemini" "$(cat "$LOG")"
git -C "$R" config --unset agentreview.reviewer

it "a reply without the end marker is not a review"
out=$(EXTRA_ENV=FAKE_NO_MARKER=1 run "$R" claude code 2>&1); rc=$?
assert_eq 3 "$rc"
assert_has "end marker" "$out"

it "a failing reviewer is reported"
out=$(EXTRA_ENV=FAKE_EXIT=5 run "$R" claude code 2>&1); rc=$?
assert_eq 4 "$rc"

it "a reviewer that runs too long is stopped"
start=$(date +%s)
out=$(EXTRA_ENV=FAKE_SLEEP=20 run "$R" claude code --timeout 2 2>&1); rc=$?
assert_eq 4 "$rc"
assert_has "timed out" "$out"
[ $(( $(date +%s) - start )) -lt 15 ] && ok || bad "timeout did not stop the reviewer"

it "uncommitted work is included, and secret files are listed by name only"
printf 'print("wip")\n' > "$R/greet.py"; printf 'TOKEN=abc\n' > "$R/.env"; printf 'x\n' > "$R/new.py"
out=$(run "$R" claude code 2>&1)
dir=$(grep -o '/[^ ]*/agent-review/[^ /]*' "$LOG" | head -1)
assert_has "wip" "$(cat "$dir/worktree.patch")"
assert_has "new.py" "$(cat "$dir/untracked.txt")"
grep -q "abc" "$dir"/* && bad "secret contents reached the review folder" || ok
assert_has ".env (looks like a secret: do not open)" "$(cat "$dir/untracked.txt")"
git -C "$R" checkout -q greet.py; rm -f "$R/.env" "$R/new.py"

it "plan mode names the plan file"
printf '# Plan\n' > "$TMPROOT/plan.md"
out=$(run "$R" claude plan "$TMPROOT/plan.md" 2>&1); rc=$?
assert_eq 0 "$rc"
assert_has "$TMPROOT/plan.md" "$(cat "$LOG")"
out=$(run "$R" claude plan "$TMPROOT/missing.md" 2>&1); rc=$?
assert_eq 2 "$rc"

it "an explicit range is used as given"
out=$(run "$R" claude code main..feature 2>&1)
assert_has "$base..$head" "$(cat "$LOG")"

it "with no reviewer installed it says so"
mkdir -p "$TMPROOT/empty"
out=$(cd "$R" && env -i PATH="$TMPROOT/empty:/usr/bin:/bin" HOME="$TMPROOT/home" CLAUDECODE=1 bash "$AR" code 2>&1); rc=$?
assert_eq 2 "$rc"
assert_has "no reviewer" "$out"

it "nothing to review is an error, not an empty review"
out=$(cd "$R" && git checkout -q main && env -i PATH="$FAKE:/usr/bin:/bin" HOME="$TMPROOT/home" CLAUDECODE=1 bash "$AR" code 2>&1); rc=$?
assert_eq 2 "$rc"
git -C "$R" checkout -q feature

printf 'passed=%d failed=%d\n' "$pass" "$fail"
[ "$fail" = 0 ]
