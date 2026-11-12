#!/usr/bin/env bash
# Tests for pr-agent/try.sh and pr-agent/scratch.sh: scratch git repositories and a fake
# PR-Agent python that records what it is given.
set -u
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
root="$(cd "$here/.." && pwd)"
TMPROOT="$(mktemp -d)"; trap 'rm -rf "$TMPROOT"' EXIT
pass=0; fail=0; CURRENT=""
it() { CURRENT="$1"; }
ok()  { pass=$((pass+1)); printf '  ok   %s\n' "$CURRENT"; }
bad() { fail=$((fail+1)); printf '  FAIL %s\n       %s\n' "$CURRENT" "$1"; }
assert_eq()  { [ "$1" = "$2" ] && ok || bad "expected [$1] got [$2]"; }
has() { printf '%s' "$1" | grep -qF -- "$2" && ok || bad "missing [$2] in: $1"; }
lacks() { printf '%s' "$1" | grep -qF -- "$2" && bad "unexpected [$2] in: $1" || ok; }

# Fake PR-Agent: "-I -c import pr_agent" succeeds; "-I -m pr_agent.cli ..." records its
# arguments, environment and stdin under $FAKE_LOG, writes --output, and exits $FAKE_RC.
FAKE="$TMPROOT/fake-python"
cat > "$FAKE" <<'SH'
#!/usr/bin/env bash
if [ "${1:-}" = -I ] && [ "${2:-}" = -c ]; then exit 0; fi
mkdir -p "$FAKE_LOG"
printf '%s\n' "$@" > "$FAKE_LOG/args"
env > "$FAKE_LOG/env"
cat > "$FAKE_LOG/stdin"
out=""; prev=""
for a in "$@"; do [ "$prev" = --output ] && out="$a"; prev="$a"; done
[ -n "$out" ] && printf 'FAKE REVIEW\n' > "$out"
echo "fake log line" >&2
exit "${FAKE_RC:-0}"
SH
chmod +x "$FAKE"

new_repo() {  # a repository with main, a feature branch checked out, and a later main commit
  r="$TMPROOT/$1"; mkdir -p "$r"; cd "$r" || exit 1
  git init -q -b main; git config user.email t@example.com; git config user.name t
  git config core.hooksPath /dev/null
  echo base > app.txt; git add app.txt; git commit -qm "feat: base"
  git checkout -qb feature; echo feature-change >> app.txt; git commit -qam "feat: change"
  git checkout -q main; echo main-only > later.txt; git add later.txt; git commit -qm "feat: later"
  git checkout -q feature
  printf '%s' "$r"
}
try() {  # run try.sh in the current directory with the fake python
  PR_AGENT_PYTHON="$FAKE" FAKE_LOG="$TMPROOT/log" bash "$here/try.sh" "$@"
}
envvar() { sed -n "s/^$1=//p" "$TMPROOT/log/env"; }
reset_log() { rm -rf "$TMPROOT/log"; }

R=$(new_repo repo); cd "$R"
export CONFIG__MODEL="openrouter/example/model"

it "refuses to run without CONFIG__MODEL (PR-Agent would default to an OpenAI model)"
out=$(CONFIG__MODEL="" try 2>&1); rc=$?
assert_eq 2 "$rc"; has "$out" "CONFIG__MODEL"

it "refuses a local model"
out=$(CONFIG__MODEL="ollama/llama3" try 2>&1); rc=$?
assert_eq 2 "$rc"; has "$out" "local model"

it "refuses a local fallback model"
out=$(CONFIG__FALLBACK_MODELS='["lm_studio/qwen"]' try 2>&1); rc=$?
assert_eq 2 "$rc"; has "$out" "local model"

it "says how to install PR-Agent when it is missing"
out=$(PR_AGENT_PYTHON="$TMPROOT/nope" bash "$here/try.sh" 2>&1); rc=$?
assert_eq 2 "$rc"; has "$out" "pip install"

it "refuses uncommitted changes to tracked files (PR-Agent reads the working tree)"
echo dirty >> app.txt
out=$(try 2>&1); rc=$?
assert_eq 2 "$rc"; has "$out" "uncommitted"
git checkout -q app.txt

it "runs PR-Agent isolated, in plain-diff mode, with output files"
reset_log; out=$(try 2>&1); rc=$?
assert_eq 0 "$rc"
args="$(cat "$TMPROOT/log/args" 2>/dev/null)"
assert_eq "-I" "$(sed -n 1p "$TMPROOT/log/args" 2>/dev/null)"
has "$args" "pr_agent.cli"; has "$args" "--stdin"; has "$args" "--json-output"
assert_eq review "$(tail -n1 "$TMPROOT/log/args" 2>/dev/null)"

it "sends the branch diff since the merge base, not main's later commits"
d="$(cat "$TMPROOT/log/stdin" 2>/dev/null)"
has "$d" "+feature-change"; lacks "$d" "main-only"

it "prints the review and keeps the run under .git/pr-agent"
has "$out" "FAKE REVIEW"
run="$(ls -d "$R"/.git/pr-agent/*/ 2>/dev/null | head -n1)"
[ -n "$run" ] && [ -s "$run/review.md" ] && [ -s "$run/diff.patch" ] && [ -s "$run/log.txt" ] && ok \
  || bad "run folder incomplete: $run"
has "$(cat "$run/log.txt" 2>/dev/null)" "fake log line"

it "passes agent-workflow's ignore globs"
g="$(envvar IGNORE__GLOB)"
has "$g" '**/.[eE][nN][vV]*'; has "$g" 'vendor/**'

it "adds the repository's own .pr_agent.toml globs to them"
printf '[ignore]\nglob = ["fixtures/**"]\n' > .pr_agent.toml; git add .pr_agent.toml; git commit -qm "chore: config"
reset_log; try >/dev/null 2>&1
g="$(envvar IGNORE__GLOB)"
has "$g" 'fixtures/**'; has "$g" '*[tT][oO][kK][eE][nN]*'

it "turns the review skill on, from agent-workflow's pr-agent/skills"
assert_eq true "$(envvar SKILLS__ENABLED)"
has "$(envvar SKILLS__PATHS)" "$here/skills"

it "has no fallback model unless one is set"
assert_eq '[]' "$(envvar CONFIG__FALLBACK_MODELS)"

it "--no-skill and --no-ignore turn each off, for the control runs"
reset_log; try --no-skill --no-ignore >/dev/null 2>&1
assert_eq false "$(envvar SKILLS__ENABLED)"
assert_eq '[]' "$(envvar IGNORE__GLOB)"

it "for OpenCode Go, requests identify PR-Agent and carry a session for the branch"
reset_log; OPENAI__API_BASE=https://opencode.ai/zen/go/v1 try >/dev/null 2>&1
h="$(envvar LITELLM__EXTRA_HEADERS)"
python3 -I -c 'import json,sys; h=json.loads(sys.argv[1]); assert h["User-Agent"].startswith("pr-agent/"); assert h["x-opencode-session"].startswith("pr-agent-try-")' "$h" 2>/dev/null \
  && ok || bad "headers: [$h]"

it "for OpenCode Go, Kimi gets no temperature unless the caller set the list"
reset_log; OPENAI__API_BASE=https://opencode.ai/zen/go/v1 try >/dev/null 2>&1
printf '%s' "$(envvar CONFIG__NO_TEMPERATURE_MODELS)" | grep -q '"kimi-k3.1-pro"' && ok || bad "no_temperature_models: [$(envvar CONFIG__NO_TEMPERATURE_MODELS)]"
reset_log; OPENAI__API_BASE=https://opencode.ai/zen/go/v1 CONFIG__NO_TEMPERATURE_MODELS='["x"]' try >/dev/null 2>&1
assert_eq '["x"]' "$(envvar CONFIG__NO_TEMPERATURE_MODELS)"

it "for OpenCode Go, one call may take 10 minutes unless the caller set a timeout"
reset_log; OPENAI__API_BASE=https://opencode.ai/zen/go/v1 try >/dev/null 2>&1
assert_eq 600 "$(envvar CONFIG__AI_TIMEOUT)"
reset_log; OPENAI__API_BASE=https://opencode.ai/zen/go/v1 CONFIG__AI_TIMEOUT=30 try >/dev/null 2>&1
assert_eq 30 "$(envvar CONFIG__AI_TIMEOUT)"

it "headers the caller set are kept, and other endpoints get none"
reset_log; OPENAI__API_BASE=https://opencode.ai/zen/go/v1 LITELLM__EXTRA_HEADERS='{"x":"1"}' try >/dev/null 2>&1
assert_eq '{"x":"1"}' "$(envvar LITELLM__EXTRA_HEADERS)"
reset_log; OPENAI__API_BASE=https://api.example.com/v1 try >/dev/null 2>&1
assert_eq "" "$(envvar LITELLM__EXTRA_HEADERS)"

it "--verbose logs the prompts (verbosity level 2)"
reset_log; try --verbose >/dev/null 2>&1
assert_eq 2 "$(envvar CONFIG__VERBOSITY_LEVEL)"

it "describe gets no --json-output (PR-Agent allows it for review only)"
reset_log; try describe >/dev/null 2>&1
lacks "$(cat "$TMPROOT/log/args" 2>/dev/null)" "--json-output"
assert_eq describe "$(tail -n1 "$TMPROOT/log/args" 2>/dev/null)"

it "passes PR-Agent's exit status through"
reset_log; FAKE_RC=7 try >/dev/null 2>&1; assert_eq 7 "$?"

it "--dry-run shows the settings, runs nothing and never prints key values"
reset_log; out=$(OPENROUTER__KEY=sekrit-value try --dry-run 2>&1); rc=$?
assert_eq 0 "$rc"; has "$out" "IGNORE__GLOB"; lacks "$out" "sekrit-value"
[ ! -e "$TMPROOT/log/args" ] && ok || bad "dry run started PR-Agent"

it "fails when there is nothing to review"
git checkout -q main
out=$(try --base main 2>&1); rc=$?
assert_eq 2 "$rc"; has "$out" "nothing to review"
git checkout -q feature

it "rejects an unknown option"
out=$(try --bogus 2>&1); assert_eq 2 "$?"

it "refuses to run when agent-workflow's config has no ignore globs"
X="$TMPROOT/emptycfg"; mkdir -p "$X/pr-agent"; cp "$here/try.sh" "$here/check-model.sh" "$X/pr-agent/"; : > "$X/.pr_agent.toml"
git rm -q .pr_agent.toml; git commit -qm "chore: drop config"
out=$(PR_AGENT_PYTHON="$FAKE" FAKE_LOG="$TMPROOT/log" bash "$X/pr-agent/try.sh" 2>&1); rc=$?
assert_eq 2 "$rc"; has "$out" "no ignore globs"

it "scratch.sh needs agent-workflow's bin/agent-review"
out=$(bash "$here/scratch.sh" 2>&1); rc=$?
assert_eq 2 "$rc"; has "$out" "bin/agent-review"

it "scratch.sh stops when the timeout line it edits has changed"
mkdir -p bin pr-agent; echo 'timeout=901' > bin/agent-review; cp "$here/try.sh" pr-agent/; git add bin pr-agent; git commit -qm "feat: tool"
git checkout -q main; git merge -q --ff-only feature 2>/dev/null || git reset -q --hard feature; git checkout -q feature
out=$(bash "$here/scratch.sh" 2>&1); rc=$?
assert_eq 2 "$rc"; has "$out" "update scratch.sh"

# ---- scratch.sh -------------------------------------------------------------------------
C="$TMPROOT/clone"; git clone -q "$root" "$C"; cd "$C"
git config user.email t@example.com; git config user.name t
git checkout -q -B main "$(git -C "$root" rev-parse HEAD)"
git rm -rq --ignore-unmatch pr-agent   # main without the trial scripts, as before this branch merges
printf '.env\nconfig/secrets.yml\n' >> .gitignore; git add .gitignore; git commit -q --no-verify -m "chore: ignore env files"
git checkout -q -b tooling; mkdir -p pr-agent; cp "$here/try.sh" "$here/check-model.sh" pr-agent/; git add pr-agent
git commit -q --no-verify -m "chore: try.sh"
before="$(git rev-parse --abbrev-ref HEAD) $(git status --porcelain | wc -l | tr -d ' ')"

it "scratch.sh creates both branches from the current branch, without touching the checkout"
out=$(bash "$here/scratch.sh" 2>&1); rc=$?
assert_eq 0 "$rc"
has "$out" "pr-agent/try.sh --base tooling"
assert_eq "$(git rev-parse tooling)" "$(git rev-parse scratch/pr-agent-canary~1)"
assert_eq "$before" "$(git rev-parse --abbrev-ref HEAD) $(git status --porcelain | wc -l | tr -d ' ')"
assert_eq 1 "$(git worktree list | wc -l | tr -d ' ')"
git rev-parse -q --verify scratch/pr-agent-no-test >/dev/null && git rev-parse -q --verify scratch/pr-agent-canary >/dev/null \
  && ok || bad "branches missing"

it "the no-test branch changes behaviour in one file and adds no test"
assert_eq "bin/agent-review" "$(git diff --name-only tooling scratch/pr-agent-no-test)"
has "$(git diff tooling scratch/pr-agent-no-test)" "+target=\"\"; reviewer=\"\"; model=\"\"; timeout=300"

it "the canary branch adds fake secrets carrying the recorded canary, and an ordinary change"
canary="$(cat "$(git rev-parse --git-path pr-agent)/canary.txt" 2>/dev/null)"
case "$canary" in SYNTHETIC_CANARY_*) ok ;; *) bad "canary not recorded: [$canary]" ;; esac
files="$(git diff --name-only tooling scratch/pr-agent-canary | LC_ALL=C sort | tr '\n' ' ')"
assert_eq ".env README.md config/secrets.yml " "$files"
has "$(git show scratch/pr-agent-canary:.env)" "$canary"
has "$(git show scratch/pr-agent-canary:config/secrets.yml)" "$canary"

it "the canary files are ones the globs keep from the model"
v="$(python3 -I - "$root/.pr_agent.toml" .env config/secrets.yml README.md <<'PY'
import fnmatch, re, sys, tomllib
globs = tomllib.load(open(sys.argv[1], "rb"))["ignore"]["glob"]
forms = [f for g in globs for f in ([g, g[3:]] if g.startswith("**/") else [g])]
for p in sys.argv[2:]:
    print("ignored" if any(re.match(fnmatch.translate(f), p) for f in forms) else "reviewed")
PY
)"
assert_eq "ignored ignored reviewed" "$(printf '%s' "$v" | tr '\n' ' ' | sed 's/ $//')"

it "scratch.sh refuses to overwrite existing branches without --force"
out=$(bash "$here/scratch.sh" 2>&1); rc=$?
assert_eq 2 "$rc"; has "$out" "--force"

it "--force recreates them with a new canary"
old="$canary"
bash "$here/scratch.sh" --force >/dev/null 2>&1; assert_eq 0 "$?"
new="$(cat "$(git rev-parse --git-path pr-agent)/canary.txt" 2>/dev/null)"
[ -n "$new" ] && [ "$new" != "$old" ] && ok || bad "canary not renewed: $old -> $new"
has "$(git show scratch/pr-agent-canary:.env)" "$new"

it "scratch.sh will not delete a scratch branch that is checked out"
git checkout -q scratch/pr-agent-canary
out=$(bash "$here/scratch.sh" --force --base tooling 2>&1); rc=$?
assert_eq 2 "$rc"; has "$out" "checked out"

it "scratch.sh will not start the scratch branches from a scratch branch"
out=$(bash "$here/scratch.sh" --force 2>&1); rc=$?
assert_eq 2 "$rc"; has "$out" "not scratch/pr-agent-canary"
git checkout -q tooling

it "scratch.sh needs a base that has try.sh"
out=$(bash "$here/scratch.sh" --force --base main 2>&1); rc=$?
assert_eq 2 "$rc"; has "$out" "no pr-agent/try.sh"

printf 'passed=%d failed=%d\n' "$pass" "$fail"
[ "$fail" = 0 ]
