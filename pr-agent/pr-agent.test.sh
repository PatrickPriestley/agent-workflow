#!/usr/bin/env bash
# Tests for the PR-Agent config (.pr_agent.toml) and the review skill under pr-agent/skills.
# PR-Agent is not installed here. Ignore matching copies PR-Agent's own rule from
# pr_agent/algo/file_filter.py (4686afb): fnmatch.translate(glob), then re.match against the
# path, case-sensitive; a glob starting with "**/" also matches in its root form.
set -u
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
root="$(cd "$here/.." && pwd)"
TMPROOT="$(mktemp -d)"; trap 'rm -rf "$TMPROOT"' EXIT
pass=0; fail=0; CURRENT=""
it() { CURRENT="$1"; }
ok()  { pass=$((pass+1)); printf '  ok   %s\n' "$CURRENT"; }
bad() { fail=$((fail+1)); printf '  FAIL %s\n       %s\n' "$CURRENT" "$1"; }

config="$root/.pr_agent.toml"
skill_dir="$here/skills/workflow-review"
secret_re="$(sed -n "s/^secret_re='\(.*\)'\$/\1/p" "$root/bin/agent-review")"

# ignored PATH...: prints "ignored" or "reviewed" for each path, as PR-Agent would decide.
ignored() {
  python3 -I - "$config" "$@" <<'PY'
import fnmatch, re, sys, tomllib
with open(sys.argv[1], "rb") as f:
    globs = tomllib.load(f)["ignore"]["glob"]
forms = []
for g in globs:
    forms.append(g)
    if g.startswith("**/"):
        forms.append(g[3:])
regexes = [re.compile(fnmatch.translate(g)) for g in forms if g]
for path in sys.argv[2:]:
    print("ignored" if any(r.match(path) for r in regexes) else "reviewed")
PY
}

secret_paths=(
  .env .env.local config/.env.production .envrc
  certs/server.pem deploy/TLS.PEM keys/private.key
  id_rsa home/.ssh/id_ed25519 id_ecdsa id_dsa keys/id_work deploy/ID_ci
  pr_agent/settings/.secrets.toml config/Secrets.yml aws/credentials
  src/CredentialStore.java auth/token.go api/AccessTokens.ts
)
ordinary_paths=(
  README.md bin/agent-review src/main.rs docs/environment.md docs/keys.md
  src/monkey.py src/ids.py skills/feature-loop/SKILL.md .github/workflows/test.yml
)
# agent-review's (^|/)id_[a-z0-9]+$ has no exact glob, so the globs skip every id_* name: a
# superset. These ordinary paths are skipped too, the accepted cost of never sending a key.
over_matches=(src/id_utils.py lib/id_map.go)

it "the config parses, and keeps PR-Agent's default vendor/** ignore"
out="$(ignored vendor/lib/a.c 2>&1)"
[ "$out" = ignored ] && ok || bad "vendor/lib/a.c: $out"

it "the config turns skills on"
python3 -I -c 'import sys, tomllib; c = tomllib.load(open(sys.argv[1], "rb")); sys.exit(0 if c["skills"]["enabled"] is True else 1)' "$config" 2>/dev/null \
  && ok || bad "[skills] enabled is not true"

it "agent-review's secret regex is readable from bin/agent-review"
[ -n "$secret_re" ] && ok || bad "secret_re not found in bin/agent-review"

it "every path agent-review calls a secret is ignored"
missed=""
i=0; while IFS= read -r verdict; do
  [ "$verdict" = ignored ] || missed="$missed ${secret_paths[$i]}"; i=$((i+1))
done < <(ignored "${secret_paths[@]}")
[ "$i" = "${#secret_paths[@]}" ] && [ -z "$missed" ] && ok || bad "sent to the model:${missed:- (no verdicts)}"

it "ordinary paths are still reviewed"
dropped=""
i=0; while IFS= read -r verdict; do
  [ "$verdict" = reviewed ] || dropped="$dropped ${ordinary_paths[$i]}"; i=$((i+1))
done < <(ignored "${ordinary_paths[@]}")
[ "$i" = "${#ordinary_paths[@]}" ] && [ -z "$dropped" ] && ok || bad "ignored:${dropped:- (no verdicts)}"

it "the globs skip everything agent-review's regex calls a secret, and more only where listed"
all=("${secret_paths[@]}" "${ordinary_paths[@]}" "${over_matches[@]}")
wrong=""
i=0; while IFS= read -r verdict; do
  p="${all[$i]}"; i=$((i+1))
  if printf '%s\n' "$p" | grep -iqE "$secret_re"; then
    [ "$verdict" = ignored ] || wrong="$wrong $p(secret, sent)"
  elif [ "$verdict" = ignored ]; then
    case " ${over_matches[*]} " in *" $p "*) ;; *) wrong="$wrong $p(skipped, not listed)" ;; esac
  fi
done < <(ignored "${all[@]}")
[ "$i" = "${#all[@]}" ] && [ -z "$wrong" ] && ok || bad "${wrong:- (no verdicts)}"

it "the listed over-matches are real: skipped by the globs, not secrets to agent-review"
for p in "${over_matches[@]}"; do
  printf '%s\n' "$p" | grep -iqE "$secret_re" && { bad "$p is a secret to agent-review; move it to secret_paths"; continue; }
  v="$(ignored "$p" 2>&1)"
  [ "$v" = ignored ] && ok || bad "$p: $v (if reviewed, remove it from over_matches)"
done

it "the skill parses as PR-Agent's skills_loader parses it"
python3 -I - "$skill_dir/SKILL.md" <<'PY' && ok || bad "SKILL.md frontmatter is not what PR-Agent accepts"
import sys
lines = open(sys.argv[1], encoding="utf-8").read().splitlines()
assert lines and lines[0].strip() == "---"
end = next(i for i in range(1, len(lines)) if lines[i].strip() == "---")
meta = dict(l.split(":", 1) for l in lines[1:end] if l.strip())
assert set(meta) == {"name", "description"}, meta
assert all(v.strip() for v in meta.values())
assert "\n".join(lines[end + 1:]).strip()
PY

it "the skill fits well inside PR-Agent's 8000-token skills budget (under ~2000 tokens)"
chars="$(find "$skill_dir" -name '*.md' -not -path '*/scripts/*' -not -path '*/assets/*' -exec cat {} + | wc -c | tr -d ' ')"
[ "$chars" -gt 0 ] && [ "$chars" -le 8000 ] && ok || bad "$chars characters of markdown (limit 8000, about 2000 tokens)"

it "the skill is not installed for authoring agents"
H="$TMPROOT/home"; mkdir -p "$H"
out="$(HOME="$H" bash "$root/install.sh" --dev --dry-run 2>&1)"
if [ ! -e "$root/skills/workflow-review" ] && ! printf '%s' "$out" | grep -q 'workflow-review'; then ok
else bad "workflow-review reaches authoring agents: $out"; fi

printf 'passed=%d failed=%d\n' "$pass" "$fail"
[ "$fail" = 0 ]
