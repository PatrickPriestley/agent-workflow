#!/usr/bin/env bash
# check-model.sh: refuse a PR-Agent model that would not give an independent review.
#
#   pr-agent/check-model.sh MODEL [FALLBACKS] [--exclude WORD]...
#
# MODEL is PR-Agent's config.model, FALLBACKS its config.fallback_models (a JSON list,
# default []). Refuses an empty model, any local provider, and any
# model or fallback whose name contains an --exclude word, ignoring case: pass the families
# that author the pull requests, so the reviewer is never one of them.
# Used by pr-agent/try.sh and .github/workflows/pr-agent.yml. Exit 0 ok, 2 refused or misused.
set -uo pipefail
fail() { echo "check-model.sh: $*" >&2; exit 2; }
[ "$#" -ge 1 ] || fail "usage: check-model.sh MODEL [FALLBACKS] [--exclude WORD]..."
model="$1"; shift
fallbacks='[]'
if [ "$#" -gt 0 ] && [ "$1" != --exclude ]; then fallbacks="$1"; shift; fi
excludes=()
while [ "$#" -gt 0 ]; do
  case "$1" in
    --exclude) [ -n "${2:-}" ] || fail "--exclude needs a word"; excludes+=("$2"); shift 2 ;;
    *) fail "unknown argument $1" ;;
  esac
done

[ -n "$model" ] || fail "no model: set CONFIG__MODEL (the repository variable PR_AGENT_MODEL on GitHub) to a hosted model of another family than the author's, for example openrouter/<provider>/<model>. PR-Agent's own default is an OpenAI model."
local_re='(^|["[:space:],[])(ollama|ollama_chat|lm_studio|lmstudio|llamacpp|llama\.cpp|llamafile|local|hosted_vllm|vllm)/'
for m in "$model" "$fallbacks"; do
  printf '%s\n' "$m" | grep -iqE "$local_re" && fail "refusing a local model ($m): a review by one does not count"
  for x in ${excludes[@]+"${excludes[@]}"}; do
    printf '%s\n' "$m" | grep -iqF -- "$x" && fail "refusing $m: it names \"$x\", a family that authors these pull requests"
  done
done
exit 0
