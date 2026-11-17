#!/usr/bin/env bash
# Run eval cases against the current agent configuration.
#
#   run-eval.sh <change_id> [--runs N]        run the agent N times (default 1)
#   run-eval.sh ... --agent claude|codex|gemini   which agent CLI to drive (default:
#                                             $EVAL_AGENT, else claude)
#   run-eval.sh <change_id> --at <commit>     negative control: no agent; check the
#                                             given commit against its parent
#   run-eval.sh --all [--runs N]              every case under evals/cases/
#
# Optional per-case files in evals/cases/<id>/:
#   base   a commit to start the agent from (default HEAD), e.g. the incident's parent
#   add-dirs  directories outside the repo the agent may read, one per line (~ allowed);
#             passed as each agent's own flag (--add-dir / --include-directories)
#   setup     executable run in the sandbox before the agent, for state a snapshot cannot
#             carry (local git config, a directory beside the sandbox). Each line it prints
#             on stdout is another directory for the agent, as in add-dirs. A non-zero
#             exit fails that run.
# check.sh finds the agent's final message as {"result": "..."} in "$PWD.agent.json",
# whichever agent ran, and the agent's name in $EVAL_AGENT.
#
# Agent runs start from a snapshot of the base commit in a fresh repository with no
# history and no other refs, so the agent cannot read later work (e.g. the fix, or
# the corrected artifact) from other branches. --at runs use a worktree of the repo.
#
# Run from the repository root. Needs git and, except for --at, the agent's CLI.
set -euo pipefail

ROOT=$(git rev-parse --show-toplevel)
cd "$ROOT"
RUNS=1; AT=""; CASES=(); AGENT=${EVAL_AGENT:-claude}

while [ $# -gt 0 ]; do
  case "$1" in
    --runs) RUNS=$2; shift 2 ;;
    --at)   AT=$2; shift 2 ;;
    --agent) AGENT=$2; shift 2 ;;
    --all)  for d in evals/cases/*/; do CASES+=("$(basename "$d")"); done; shift ;;
    *)      CASES+=("$1"); shift ;;
  esac
done
[ ${#CASES[@]} -gt 0 ] || { echo "usage: run-eval.sh <change_id>|--all [--runs N] [--at commit]" >&2; exit 64; }

TMP=$(mktemp -d)
trap 'git worktree prune >/dev/null 2>&1; rm -rf "$TMP"' EXIT

run_check() {  # $1 case, $2 sandbox
  local check="$ROOT/evals/checks/$1/check.sh"
  [ -x "$check" ] || { echo "missing or not executable: $check" >&2; return 2; }
  (cd "$2" && "$check") >"$2.check.log" 2>&1
}

new_sandbox() {  # $1 name, $2 commit to check out; tags its parent or itself as base
  local dir="$TMP/$1"
  git worktree add --detach -q "$dir" "$2"
  echo "$dir"
}

new_snapshot() {  # $1 name, $2 commit: history-free copy of that tree, tagged base
  local dir="$TMP/$1"
  mkdir -p "$dir"
  git -C "$dir" init -q -b main
  git archive "$2" | tar -x -C "$dir"
  git -C "$dir" add -A
  git -C "$dir" -c user.name="$(git config user.name)" -c user.email="$(git config user.email)" \
    -c commit.gpgsign=false commit -qm "snapshot of $(git rev-parse --short "$2")" --allow-empty
  git -C "$dir" -c tag.gpgsign=false tag base
  echo "$dir"
}

run_agent() {  # $1 sandbox, $2 prompt file, $3 extra dirs (newline-separated); leaves {"result": ...} in $1.agent.json
  local sb=$1 text; text=$(cat "$2"); local dirs=() flags=()
  if [ -f "$ROOT/evals/cases/$c/add-dirs" ]; then
    while IFS= read -r line; do [ -n "$line" ] && dirs+=("${line/#\~/$HOME}"); done \
      <"$ROOT/evals/cases/$c/add-dirs"
  fi
  while IFS= read -r line; do [ -n "$line" ] && dirs+=("$line"); done <<<"${3:-}"
  case "$AGENT" in
    claude)
      for d in ${dirs[@]+"${dirs[@]}"}; do flags+=(--add-dir "$d"); done
      (cd "$sb" && claude -p "$text" ${flags[@]+"${flags[@]}"} \
        --permission-mode acceptEdits --output-format json >"$sb.agent.raw" 2>&1) || true
      python3 - "$sb.agent.raw" "$sb.agent.json" <<'PY'
import json, sys
try: r = json.load(open(sys.argv[1])).get("result") or ""
except Exception: r = open(sys.argv[1]).read()
json.dump({"result": r}, open(sys.argv[2], "w"))
PY
      ;;
    codex)
      for d in ${dirs[@]+"${dirs[@]}"}; do flags+=(--add-dir "$d"); done
      (cd "$sb" && codex exec --sandbox workspace-write ${flags[@]+"${flags[@]}"} \
        -o "$sb.agent.last" "$text" >"$sb.agent.raw" 2>&1) || true
      python3 -c 'import json,sys,os; p=sys.argv[1]; json.dump({"result": open(p).read() if os.path.exists(p) else ""}, open(sys.argv[2],"w"))' \
        "$sb.agent.last" "$sb.agent.json"
      ;;
    gemini)  # untested: Gemini sign-in was unavailable when this adapter was written
      for d in ${dirs[@]+"${dirs[@]}"}; do flags+=(--include-directories "$d"); done
      (cd "$sb" && gemini -p "$text" ${flags[@]+"${flags[@]}"} \
        --approval-mode auto_edit -o json >"$sb.agent.raw" 2>"$sb.agent.err") || true
      python3 - "$sb.agent.raw" "$sb.agent.json" <<'PY'
import json, sys
try: r = json.load(open(sys.argv[1])).get("response") or ""
except Exception: r = ""
json.dump({"result": r}, open(sys.argv[2], "w"))
PY
      ;;
    *) echo "unknown agent: $AGENT" >&2; exit 64 ;;
  esac
}

overall=0
for c in "${CASES[@]}"; do
  prompt="$ROOT/evals/cases/$c/prompt.md"
  [ -f "$prompt" ] || { echo "$c: missing $prompt" >&2; overall=1; continue; }

  if [ -n "$AT" ]; then
    sb=$(new_sandbox "$c-at" "$AT")
    git -C "$sb" tag -f base "$AT^" >/dev/null
    if run_check "$c" "$sb"; then
      echo "$c: NEGATIVE CONTROL FAILED (check passed on the bad change; too weak)"
      overall=1
    else
      echo "$c: negative control ok (check fails on the bad change)"
    fi
    git worktree remove --force "$sb"
    continue
  fi

  start=HEAD
  [ -f "evals/cases/$c/base" ] && start=$(tr -d '[:space:]' <"evals/cases/$c/base")
  pass=0
  for i in $(seq 1 "$RUNS"); do
    sb=$(new_snapshot "$c-$i" "$start")
    setup_dirs=""
    if [ -x "$ROOT/evals/cases/$c/setup" ]; then
      if ! setup_dirs=$(cd "$sb" && "$ROOT/evals/cases/$c/setup" 2>"$sb.setup.log"); then
        echo "  run $i: setup failed"; sed 's/^/    /' "$sb.setup.log"; rm -rf "$sb"; continue
      fi
    fi
    run_agent "$sb" "$prompt" "$setup_dirs"
    # Commit whatever the agent left so checks can diff base..HEAD.
    git -C "$sb" add -A && git -C "$sb" -c user.name=eval -c user.email=eval@local \
      commit -qm "eval run" --allow-empty
    if EVAL_AGENT=$AGENT run_check "$c" "$sb"; then pass=$((pass+1))
    else echo "  run $i failed:"; sed 's/^/    /' "$sb.check.log"; fi
    rm -rf "$sb"
  done
  echo "$c [$AGENT]: $pass/$RUNS passed"
  [ "$pass" -eq "$RUNS" ] || overall=1
done
exit $overall
