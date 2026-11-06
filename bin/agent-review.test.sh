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
for cli in codex claude cursor-agent gemini opencode; do
cat > "$FAKE/$cli" <<FAKEEOF
#!/bin/bash
# Record argv and stdin; answer like a reviewer.
{ printf 'CLI=%s\n' "$cli"; printf 'ARG=%s\n' "\$@"; printf 'OPENCODE_CONFIG_CONTENT=%s\n' "\${OPENCODE_CONFIG_CONTENT:-}"; printf 'OPENCODE_DISABLE_PROJECT_CONFIG=%s\n' "\${OPENCODE_DISABLE_PROJECT_CONFIG:-}"; printf 'OPENCODE_CONFIG_PATHS=%s|%s\n' "\${OPENCODE_CONFIG:-}" "\${OPENCODE_CONFIG_DIR:-}"; printf 'STDIN=%s\n' "\$( [ -t 0 ] || cat )"; } >> "$LOG"
[ -n "\${FAKE_SLEEP:-}" ] && sleep "\$FAKE_SLEEP"
[ -n "\${FAKE_EXIT:-}" ] && { echo "reviewer broke" >&2; exit "\$FAKE_EXIT"; }
[ -n "\${FAKE_WRITE:-}" ] && printf 'tampered\n' >> greet.py
[ -n "\${FAKE_NEWFILE:-}" ] && printf 'x\n' > planted.txt
# FAKE_FAIL="cli:model ..." fails that CLI on that model ("default" when no model is given).
model=default; prev=""; for a in "\$@"; do case "\$prev" in --model|-m) model="\$a" ;; esac; prev="\$a"; done
for f in \${FAKE_FAIL:-}; do [ "\$f" = "$cli:\$model" ] && { echo "You're out of usage credits. Switch to another model" >&2; exit 1; }; done
reply="1. greet.py:3 - something. Fix: something."
[ -n "\${FAKE_NO_MARKER:-}" ] || reply="\$reply
<<AGENT-REVIEW-END>>"
[ "$cli" = codex ] && [ -n "\${FAKE_CODEX_MODEL:-}" ] && printf 'OpenAI Codex\nmodel: %s\nprovider: openai\n' "\$FAKE_CODEX_MODEL" >&2
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

it "a branch above the pr-size stop limit gets a size warning on stderr, and is still reviewed"
SR=$(repo size_big); git -C "$SR" config prsize.aim 0; git -C "$SR" config prsize.stop 0
err=$( { run "$SR" claude code >"$TMPROOT/size.out"; } 2>&1 ); rc=$?
assert_eq 0 "$rc"
assert_has "agent-review: this range adds 1 reviewable lines, above the 0-line stop" "$err"
assert_has "agent-review code BASE..HEAD" "$err"
assert_has "<<AGENT-REVIEW-END>>" "$(cat "$TMPROOT/size.out")"
grep -q "reviewable lines" "$TMPROOT/size.out" && bad "the size warning reached stdout" || ok

it "a branch within the stop limit gets no size warning"
SR=$(repo size_small)
err=$( { run "$SR" claude code >/dev/null; } 2>&1 )
printf '%s' "$err" | grep -q "reviewable lines" && bad "warned: $err" || ok

it "without pr-size beside it, agent-review still reviews, with no size warning"
mkdir -p "$TMPROOT/lonely"; cp "$AR" "$TMPROOT/lonely/agent-review"
SR=$(repo size_lonely); git -C "$SR" config prsize.aim 0; git -C "$SR" config prsize.stop 0
err=$( { (cd "$SR" && env -i PATH="$FAKE:/usr/bin:/bin" HOME="$TMPROOT/home" CLAUDECODE=1 bash "$TMPROOT/lonely/agent-review" code >/dev/null); } 2>&1 ); rc=$?
assert_eq 0 "$rc"
printf '%s' "$err" | grep -q "reviewable lines" && bad "warned without pr-size: $err" || ok

it "an installed agent-review finds pr-size on PATH when it is not beside it"
mkdir -p "$TMPROOT/onpath"; cp "$here/pr-size" "$TMPROOT/onpath/pr-size"; chmod +x "$TMPROOT/onpath/pr-size"
err=$( { (cd "$SR" && env -i PATH="$FAKE:$TMPROOT/onpath:/usr/bin:/bin" HOME="$TMPROOT/home" CLAUDECODE=1 bash "$TMPROOT/lonely/agent-review" code >/dev/null); } 2>&1 )
assert_has "above the 0-line stop" "$err"

it "the prompt asks for feasibility against the real system before anything else"
out=$(run "$R" claude code 2>&1)
assert_has "Feasibility first" "$(cat "$LOG")"
assert_has "verified against the real system" "$(cat "$LOG")"
assert_has "Missing real-system evidence for a new external operation is blocking" "$(cat "$LOG")"

it "--goal puts the desired outcome in the prompt"
out=$(run "$R" claude code --goal "page_up scrolls the focused pane" 2>&1); rc=$?
assert_eq 0 "$rc"
assert_has "Desired outcome: page_up scrolls the focused pane" "$(cat "$LOG")"

it "--goal needs a value"
out=$(run "$R" claude code --goal 2>&1); rc=$?
assert_eq 2 "$rc"

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

it "the default base prefers origin/main to a stale local main, as pr-size does"
ST=$(repo stale); O="$TMPROOT/stale-origin.git"; git clone -q --bare "$ST" "$O"
git -C "$ST" remote add origin "$O"
git -C "$ST" checkout -q main; printf 'merged by someone else\n' > "$ST/other.txt"
git -C "$ST" add -A; git -C "$ST" -c user.name=t -c user.email=t@t commit -q -m "feat: other"
git -C "$ST" push -q origin main; git -C "$ST" reset -q --hard HEAD~1; git -C "$ST" fetch -q origin
git -C "$ST" checkout -q feature; git -C "$ST" merge -q --no-edit origin/main
out=$(run "$ST" claude code 2>&1)
dir=$(grep -o '/[^ ]*/agent-review/[^ /]*' "$LOG" | head -1)
grep -q "merged by someone else" "$dir/diff.patch" && bad "diffed from the stale local main" || ok

it "a three-dot range is refused, not read as tip to tip"
out=$(run "$R" claude code main...feature 2>&1); rc=$?
assert_eq 2 "$rc"
assert_has "two dots" "$out"

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

it "opencode reviews read-only with an OpenCode Go model"
out=$(run "$R" claude code --reviewer opencode 2>&1); rc=$?
assert_eq 0 "$rc"
assert_has "CLI=opencode" "$(cat "$LOG")"
assert_has "ARG=opencode-go/kimi-k3.1-pro" "$(cat "$LOG")"
assert_has "ARG=agentreview" "$(cat "$LOG")"

it "the opencode reviewer agent denies everything but reading"
out=$(run "$R" claude code --reviewer opencode 2>&1)
cfg=$(grep '^OPENCODE_CONFIG_CONTENT=' "$LOG" | head -1)
assert_has '"permission":{"*":"deny","read":"allow","grep":"allow","glob":"allow","list":"allow"}' "$cfg"

it "a non-Go opencode model is refused"
out=$(run "$R" claude code --reviewer opencode --model opencode/gpt-5.5 2>&1); rc=$?
assert_eq 2 "$rc"
assert_has "OpenCode Go" "$out"

it "a local model is refused for any reviewer"
for m in ollama/gemma4 lmstudio/qwen local/llama llama.cpp/x; do
  out=$(run "$R" claude code --reviewer gemini --model "$m" 2>&1); rc=$?
  assert_eq 2 "$rc"
done
assert_has "local model" "$out"
[ -s "$LOG" ] && bad "a reviewer ran with a local model" || ok

it "a same-family opencode model is refused"
out=$(run "$R" claude code --reviewer opencode --model opencode-go/claude-haiku-5-5 2>&1); rc=$?
assert_eq 2 "$rc"
out=$(run "$R" codex code --reviewer opencode --model opencode-go/gpt-6-luna 2>&1); rc=$?
assert_eq 2 "$rc"
assert_has "same family" "$out"

it "a failing reviewer falls back to its fallback model"
out=$(EXTRA_ENV="FAKE_FAIL=claude:default" run "$R" codex code 2>&1); rc=$?
assert_eq 0 "$rc"
assert_has "ARG=sonnet" "$(cat "$LOG")"
assert_has "out of usage credits" "$out"
grep -q "^CLI=opencode" "$LOG" && bad "fell through past a working fallback model" || ok

it "then to OpenCode Go"
: > "$LOG"
out=$(cd "$R" && env -i PATH="$FAKE:/usr/bin:/bin" HOME="$TMPROOT/home" CLAUDECODE=1 CODEX_THREAD_ID=t1 FAKE_FAIL="claude:default claude:sonnet" bash "$AR" code 2>&1); rc=$?
assert_eq 0 "$rc"
assert_has "CLI=opencode" "$(cat "$LOG")"
assert_has "Reviewed by: opencode opencode-go/kimi-k3.1-pro" "$out"

it "git config sets the fallback model"
git -C "$R" config agentreview.codex.fallbackModel gpt-6-sol
out=$(EXTRA_ENV="FAKE_FAIL=codex:default" run "$R" claude code 2>&1); rc=$?
assert_eq 0 "$rc"
assert_has "ARG=gpt-6-sol" "$(cat "$LOG")"
git -C "$R" config --unset agentreview.codex.fallbackModel

it "all attempts failing exits 4 and lists each one"
out=$(EXTRA_ENV="FAKE_FAIL=claude:default FAKE_EXIT=1" run "$R" codex code 2>&1); rc=$?
assert_eq 4 "$rc"
assert_has "claude (sonnet) exited" "$out"
assert_has "opencode (opencode-go/kimi-k3.1-pro) exited" "$out"

it "no end marker does not fall back"
out=$(EXTRA_ENV=FAKE_NO_MARKER=1 run "$R" codex code 2>&1); rc=$?
assert_eq 3 "$rc"
assert_eq 1 "$(grep -c '^CLI=' "$LOG")"

it "the review names the reviewer used, on stdout and in reviewer.txt"
out=$(run "$R" claude code 2>/dev/null)
assert_eq "Reviewed by: codex default model" "$(printf '%s\n' "$out" | head -1)"
dir=$(grep -o '/[^ ]*/agent-review/[^ /]*' "$LOG" | head -1)
assert_eq "codex default model" "$(cat "$dir/reviewer.txt")"

it "a fallback model equal to the chosen model is not tried twice"
out=$(EXTRA_ENV="FAKE_FAIL=claude:sonnet" run "$R" codex code --model sonnet 2>&1)
assert_eq 1 "$(grep -c '^ARG=sonnet$' "$LOG")"

it "a local fallback model is refused before anything runs"
git -C "$R" config agentreview.codex.fallbackModel ollama/gemma4
out=$(run "$R" claude code 2>&1); rc=$?
assert_eq 2 "$rc"
git -C "$R" config --unset agentreview.codex.fallbackModel

it "a failing OpenCode reviewer is not retried as its own fallback"
out=$(EXTRA_ENV="FAKE_FAIL=opencode:opencode-go/kimi-k3.1-pro" run "$R" claude code --reviewer opencode 2>&1); rc=$?
assert_eq 4 "$rc"
assert_eq 1 "$(grep -c '^CLI=' "$LOG")"

it "a non-Go OpenCode fallback model is refused even when another reviewer is chosen"
git -C "$R" config agentreview.opencode.model ollama/qwen
out=$(run "$R" claude code 2>&1); rc=$?
assert_eq 2 "$rc"
git -C "$R" config --unset agentreview.opencode.model

it "each OpenCode run uses its own agent name, so a repository's config cannot redefine it"
out=$(run "$R" claude code --reviewer opencode 2>&1)
n1=$(grep -A1 '^ARG=--agent$' "$LOG" | sed -n 2p | sed 's/^ARG=//')
cfg=$(grep '^OPENCODE_CONFIG_CONTENT=' "$LOG" | head -1)
out=$(run "$R" claude code --reviewer opencode 2>&1)
n2=$(grep -A1 '^ARG=--agent$' "$LOG" | sed -n 2p | sed 's/^ARG=//')
printf '%s' "$n1" | grep -qE '^agentreview-[a-f0-9]{16}$' && ok || bad "agent name [$n1] is not unique-looking"
[ "$n1" != "$n2" ] && ok || bad "two runs shared agent name [$n1]"
assert_has "\"$n1\":{" "$cfg"

it "a reviewer that changes the working tree fails the review"
out=$(EXTRA_ENV=FAKE_WRITE=1 run "$R" claude code 2>&1); rc=$?
assert_eq 5 "$rc"
assert_has "changed the working tree" "$out"
git -C "$R" checkout -q -- greet.py

it "OpenCode ignores the reviewed repository's own config"
out=$(run "$R" claude code --reviewer opencode 2>&1)
assert_has "OPENCODE_DISABLE_PROJECT_CONFIG=1" "$(grep -A0 '^OPENCODE_DISABLE_PROJECT_CONFIG=' "$LOG" | head -1)"

it "saving the review to a file inside the repository is not a tree change"
: > "$LOG"
(cd "$R" && env -i PATH="$FAKE:/usr/bin:/bin" HOME="$TMPROOT/home" CLAUDECODE=1 bash "$AR" code > "$R/review-out.txt" 2> "$R/review-err.txt"); rc=$?
assert_eq 0 "$rc"
rm -f "$R/review-out.txt" "$R/review-err.txt"

it "a reviewer that creates a file fails the review"
out=$(EXTRA_ENV=FAKE_NEWFILE=1 run "$R" claude code 2>&1); rc=$?
assert_eq 5 "$rc"
rm -f "$R/planted.txt"

it "an Ollama-style local model tag is refused"
for m in gemma4:e4b llama3.2:latest gemma4:e2b; do
  out=$(run "$R" claude code --reviewer codex --model "$m" 2>&1); rc=$?
  assert_eq 2 "$rc"
done
[ -s "$LOG" ] && bad "a reviewer ran with a local Ollama model" || ok

it "an Ollama cloud model is not mistaken for a local one"
out=$(run "$R" claude code --reviewer codex --model kimi-k3:cloud 2>&1); rc=$?
assert_eq 0 "$rc"

it "inherited OpenCode config paths are cleared for the reviewer"
out=$(EXTRA_ENV="OPENCODE_CONFIG=./opencode.json OPENCODE_CONFIG_DIR=./.opencode" run "$R" claude code --reviewer opencode 2>&1)
assert_eq "OPENCODE_CONFIG_PATHS=|" "$(grep '^OPENCODE_CONFIG_PATHS=' "$LOG" | head -1)"

it "Codex runs with the OpenAI provider forced, so a local default cannot run"
out=$(run "$R" claude code 2>&1)
assert_has 'ARG=model_provider="openai"' "$(cat "$LOG")"

it "Codex's default model is named from its run header"
out=$(EXTRA_ENV=FAKE_CODEX_MODEL=gpt-6-sol run "$R" claude code 2>/dev/null); rc=$?
assert_eq 0 "$rc"
assert_eq "Reviewed by: codex gpt-6-sol (Codex default)" "$(printf '%s\n' "$out" | head -1)"

it "a caller-family model is refused through any reviewer"
out=$(run "$R" claude code --reviewer cursor --model claude-opus-5-5 2>&1); rc=$?
assert_eq 2 "$rc"
out=$(run "$R" codex code --reviewer cursor --model gpt-6-sol 2>&1); rc=$?
assert_eq 2 "$rc"
assert_has "same family" "$out"

it "family aliases are refused too"
for m in sonnet opus haiku claude-fable-5-1; do
  out=$(run "$R" claude code --reviewer cursor --model "$m" 2>&1); rc=$?; assert_eq 2 "$rc"
done
for m in o3 o4-mini; do
  out=$(run "$R" codex code --reviewer cursor --model "$m" 2>&1); rc=$?; assert_eq 2 "$rc"
done

printf 'passed=%d failed=%d\n' "$pass" "$fail"
[ "$fail" = 0 ]
