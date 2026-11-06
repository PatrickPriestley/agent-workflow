#!/usr/bin/env bash
# try.sh: run PR-Agent locally on this branch's committed diff, with agent-workflow's review
# skill and secret ignore globs, and print the result. Nothing is posted anywhere.
#
#   pr-agent/try.sh [review|describe|improve] [--base REF] [--no-skill] [--no-ignore]
#                   [--verbose] [--dry-run]
#
# PR-Agent does not read .pr_agent.toml in local mode, so this passes the settings as
# environment variables: IGNORE__GLOB (agent-workflow's globs plus the repository's own),
# SKILLS__ENABLED and SKILLS__PATHS (pr-agent/skills next to this script).
#
# Needs: CONFIG__MODEL (a hosted model of another family than the author's; local models are
# refused), the provider's key (for example OPENROUTER__KEY), and PR-Agent installed in the
# python named by PR_AGENT_PYTHON (default ~/.venvs/pr-agent/bin/python).
#
# --no-skill and --no-ignore are for control runs. --verbose logs the full prompts
# (verbosity level 2) to log.txt. Each run is kept in .git/pr-agent/<run>/: diff.patch,
# settings.txt, review.md, review.json (review only) and log.txt.
#
# Exit: PR-Agent's own status, or 2 for a usage or setup problem.
set -uo pipefail
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
usage() { echo "usage: try.sh [review|describe|improve] [--base REF] [--no-skill] [--no-ignore] [--verbose] [--dry-run]" >&2; exit 2; }
fail() { echo "try.sh: $*" >&2; exit 2; }

cmd=review; base_ref=""; skill=true; ignore=true; verbose=false; dry=false
while [ "$#" -gt 0 ]; do
  case "$1" in
    review|describe|improve) cmd="$1"; shift ;;
    --base) [ -n "${2:-}" ] || usage; base_ref="$2"; shift 2 ;;
    --no-skill) skill=false; shift ;;
    --no-ignore) ignore=false; shift ;;
    --verbose) verbose=true; shift ;;
    --dry-run) dry=true; shift ;;
    *) usage ;;
  esac
done

# ---- model: required, never local ----------------------------------------------------
fallbacks="${CONFIG__FALLBACK_MODELS:-[]}"
bash "$here/check-model.sh" "${CONFIG__MODEL:-}" "$fallbacks" || exit 2

py="${PR_AGENT_PYTHON:-$HOME/.venvs/pr-agent/bin/python}"
if ! $dry; then
  "$py" -I -c 'import pr_agent' >/dev/null 2>&1 || fail "PR-Agent not found for $py. Install it with:
  python3.12 -m venv ~/.venvs/pr-agent && ~/.venvs/pr-agent/bin/pip install pr-agent==0.49.0
or set PR_AGENT_PYTHON to a python that has it."
fi

# ---- the diff: committed work only, from a clean tree -----------------------------------
git rev-parse --git-dir >/dev/null 2>&1 || fail "not inside a git repository"
root="$(git rev-parse --show-toplevel)"; cd "$root" || exit 2
# PR-Agent adds the changed files' working-tree contents to the prompt, so uncommitted edits
# would reach the model without being in the diff.
[ -z "$(git status --porcelain --untracked-files=no)" ] || fail "uncommitted changes to tracked files: commit or stash them (PR-Agent reads the working tree)"
head="$(git rev-parse HEAD)"
if [ -n "$base_ref" ]; then
  base="$(git merge-base HEAD "$base_ref" 2>/dev/null)" || fail "unknown base $base_ref"
else
  base=""
  for cand in origin/HEAD main master origin/main origin/master; do
    git rev-parse --verify --quiet "$cand^{commit}" >/dev/null || continue
    base="$(git merge-base HEAD "$cand")" && break
  done
  [ -n "$base" ] || fail "cannot find a base branch (main, master or origin/HEAD); pass --base"
fi
[ -n "$(git diff --name-only "$base" "$head")" ] || fail "nothing to review: no committed changes since $(git rev-parse --short "$base")"

# ---- settings ---------------------------------------------------------------------------
globs_from() {  # JSON list of [ignore] glob from each given .pr_agent.toml, merged in order
  python3 -I - "$@" <<'PY'
import json, sys, tomllib
seen = []
for path in sys.argv[1:]:
    try:
        with open(path, "rb") as f:
            globs = tomllib.load(f).get("ignore", {}).get("glob", [])
    except FileNotFoundError:
        continue
    for g in globs if isinstance(globs, list) else [globs]:
        if isinstance(g, str) and g not in seen:
            seen.append(g)
print(json.dumps(seen))
PY
}
if $ignore; then
  sources=("$here/../.pr_agent.toml")
  [ "$root/.pr_agent.toml" -ef "$here/../.pr_agent.toml" ] || sources+=("$root/.pr_agent.toml")
  glob_json="$(globs_from "${sources[@]}")" || fail "cannot read the ignore globs (needs python3 3.11 or later)"
  [ "$glob_json" != "[]" ] || fail "no ignore globs found in $here/../.pr_agent.toml"
else
  glob_json='[]'
fi
export IGNORE__GLOB="$glob_json"
export SKILLS__ENABLED="$skill"
export SKILLS__PATHS="[\"$here/skills\"]"
export CONFIG__FALLBACK_MODELS="$fallbacks"
$verbose && export CONFIG__VERBOSITY_LEVEL=2
# OpenCode Go asks each client to name itself and send one stable x-opencode-session per
# conversation, and rejects requests without it. One session per branch head; headers the
# caller set win.
# Kimi K3 and K3.1 Pro (Go's default here) accept only temperature 1; PR-Agent 0.49.0 sends 0.2.
# This is the newer no_temperature_models list from PR-Agent's main, as in the workflow.
no_temperature_models='["deepseek/deepseek-reasoner", "o1-mini", "o1-mini-2024-09-12", "o1", "o1-2024-12-17", "o3-mini", "o3-mini-2025-01-31", "o3", "o3-2025-04-16", "o4-mini", "o4-mini-2025-04-16", "gpt-5.1-codex", "gpt-5.1-codex-mini", "gpt-5.2-codex", "gpt-5.3-codex", "gpt-5-mini", "moonshotai.kimi-k3", "us.moonshotai.kimi-k3", "global.moonshotai.kimi-k3", "kimi-k3", "kimi-k3.1-pro", "zai.glm-5"]'
case "${OPENAI__API_BASE:-}" in
  *opencode.ai/zen/go*)
    [ -n "${CONFIG__NO_TEMPERATURE_MODELS:-}" ] || export CONFIG__NO_TEMPERATURE_MODELS="$no_temperature_models"
    # Kimi K3.1 Pro can take minutes per review, past PR-Agent's 120-second default.
    [ -n "${CONFIG__AI_TIMEOUT:-}" ] || export CONFIG__AI_TIMEOUT=600
    [ -n "${LITELLM__EXTRA_HEADERS:-}" ] || export LITELLM__EXTRA_HEADERS="{\"User-Agent\": \"pr-agent/local (agent-workflow try.sh)\", \"x-opencode-session\": \"pr-agent-try-$(git rev-parse --short "$head")\"}"
    ;;
esac

dir="$(git rev-parse --path-format=absolute --git-path pr-agent)/$(date +%Y%m%d-%H%M%S)-$$"
args=(-I -m pr_agent.cli --stdin --output "$dir/review.md")
[ "$cmd" = review ] && args+=(--json-output "$dir/review.json")
args+=("$cmd")

settings="range: $base..$head
model: $CONFIG__MODEL
CONFIG__FALLBACK_MODELS=$CONFIG__FALLBACK_MODELS
IGNORE__GLOB=$IGNORE__GLOB
SKILLS__ENABLED=$SKILLS__ENABLED
SKILLS__PATHS=$SKILLS__PATHS
CONFIG__VERBOSITY_LEVEL=${CONFIG__VERBOSITY_LEVEL:-0}
LITELLM__EXTRA_HEADERS=${LITELLM__EXTRA_HEADERS:-}
CONFIG__NO_TEMPERATURE_MODELS=${CONFIG__NO_TEMPERATURE_MODELS:-}
command: $py ${args[*]}"
if $dry; then
  printf '%s\n' "$settings"
  exit 0
fi

mkdir -p "$dir" || fail "cannot create $dir"
git diff "$base" "$head" > "$dir/diff.patch"
printf '%s\n' "$settings" > "$dir/settings.txt"
echo "try.sh: $cmd of $(git rev-parse --short "$base")..$(git rev-parse --short "$head") with $CONFIG__MODEL; run folder $dir" >&2
"$py" "${args[@]}" < "$dir/diff.patch" > "$dir/log.txt" 2>&1
rc=$?
[ -s "$dir/review.md" ] && cat "$dir/review.md"
[ "$rc" = 0 ] || echo "try.sh: PR-Agent exited $rc; see $dir/log.txt" >&2
exit "$rc"
