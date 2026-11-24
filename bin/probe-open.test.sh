#!/usr/bin/env bash
# Tests for bin/probe-open: it checks what the planter agent handed over and builds the probe's
# branch, commit and final answer key, refusing anything that is not a small, blind change.
#   bash bin/probe-open.test.sh
set -u
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PO=(python3 -I "$here/probe-open")
pass=0; fail=0; CURRENT=""
it() { CURRENT="$1"; }
ok()  { pass=$((pass+1)); printf '  ok   %s\n' "$CURRENT"; }
bad() { fail=$((fail+1)); printf '  FAIL %s\n       %s\n' "$CURRENT" "$1"; }
assert_eq() { [ "$1" = "$2" ] && ok || bad "expected [$1] got [$2]"; }
T="$(mktemp -d "${TMPDIR:-/tmp}/probe-open.XXXXXX")"; [ -n "${KEEP:-}" ] || trap 'rm -rf "$T"' EXIT
g() { git -C "$T/repo" -c user.name=t -c user.email=t@t "$@"; }

mkdir -p "$T/repo/bin" "$T/repo/.github/workflows"
printf '#!/usr/bin/env bash\nn="${1:-0}"\nif [ "$n" -gt 10 ]; then echo big; else echo small; fi\n' > "$T/repo/bin/tool"
printf '#!/usr/bin/env bash\n[ "$(bash bin/tool 11)" = big ] || exit 1\n' > "$T/repo/bin/tool.test.sh"
printf 'other\n' > "$T/repo/bin/other"; printf 'name: x\n' > "$T/repo/.github/workflows/x.yml"; printf 'rules\n' > "$T/repo/AGENTS.md"
for f in f1 f2 f3; do printf 'x\n' > "$T/repo/bin/$f"; done
git -C "$T/repo" init -q -b main && g add -A && g commit -qm base
base="$(git -C "$T/repo" rev-parse HEAD)"

# A patch the agent might hand over: the limit moves from 10 to 9 (an off-by-one).
patch_for() {  # FILE SED -> unified diff of that edit against base
  git -C "$T/repo" checkout -q "$base" -- . ; sed -i.bak "$2" "$T/repo/$1"; rm -f "$T/repo/$1.bak"
  git -C "$T/repo" diff; git -C "$T/repo" checkout -q "$base" -- .
}
good_patch="$(patch_for bin/tool 's/-gt 10/-gt 9/')"
# Agent output, as gh-aw writes it: {"items": [{"type": "open_probe", ...}]}, with overrides.
out() {  # NAME, then python assignments to i (the item) -> $T/NAME.json
  local name="$1"; shift
  PATCH="$good_patch" python3 - "$T/$name.json" "$@" <<'PY'
import json, os, sys
i = {"type": "open_probe", "title": "fix(tool): treat a size of exactly 10 as big",
     "body": "The tool now calls 10 big, as the docs say.\n\nExisting sizes are unchanged.",
     "commit_message": "fix(tool): treat a size of exactly 10 as big\n\nExisting sizes are unchanged.",
     "patch": os.environ["PATCH"],
     "key": json.dumps({"kind": "off-by-one", "loud": False, "file": "bin/tool", "lines": [3, 3],
                        "terms": ["-gt 9", "10"], "counterexample": "bin/tool 10", "false_claim": "Existing sizes are unchanged.",
                        "claim_terms": ["unchanged"]})}
for a in sys.argv[2:]:
    exec(a)
json.dump({"items": [i] if i is not None else []}, open(sys.argv[1], "w"))
PY
}
run() {  # NAME -> exit code; repo reset to base first
  git -C "$T/repo" checkout -q main 2>/dev/null; git -C "$T/repo" reset -q --hard "$base"; rm -rf "$T/o"
  "${PO[@]}" "$T/$1.json" --repo-dir "$T/repo" --out "$T/o" --run-id 4242 --author 'Some One <one@example.com>' >"$T/$1.log" 2>&1
}

it "a valid hand-over makes one commit on a fix/ branch with the patch, and the final key"
out good; run good; assert_eq 0 "$?"
br="$(cat "$T/o/branch.txt" 2>/dev/null)"
printf '%s' "$br" | grep -qE '^fix/treat-a-size-of-exactly-10-as-big-[0-9a-f]{6}$' && ok || bad "branch [$br]"
assert_eq "$base" "$(git -C "$T/repo" rev-parse "$br~1")"
git -C "$T/repo" show "$br:bin/tool" | grep -q -- '-gt 9' && ok || bad "patch not committed"
assert_eq "Some One" "$(git -C "$T/repo" log -1 --format=%an "$br")"
python3 -c '
import json,sys; k=json.load(open(sys.argv[1])); sha=sys.argv[2]
assert k["id"]=="probe-4242" and k["planted_sha"]==sha and k["pr"] is None and k["loud"] is False and k["file"]=="bin/tool", k
' "$T/o/key.json" "$(git -C "$T/repo" rev-parse "$br")" && ok || bad "key: $(cat "$T/o/key.json")"
assert_eq "fix(tool): treat a size of exactly 10 as big" "$(cat "$T/o/title.txt")"
grep -q 'Existing sizes are unchanged' "$T/o/body.md" && ok || bad "body"

it "no open_probe item, or two, is refused"
out none 'i = None'; run none; assert_eq 1 "$?"
out two; python3 -c 'import json,sys; d=json.load(open(sys.argv[1])); d["items"].append(d["items"][0]); json.dump(d,open(sys.argv[1],"w"))' "$T/two.json"; run two; assert_eq 1 "$?"
it "a patch touching a workflow, an agent rules file, a test, or a file that does not exist is refused"
for spec in ".github/workflows/x.yml:s/x/y/" "AGENTS.md:s/rules/none/" "bin/tool.test.sh:s/big/small/"; do
  f="${spec%%:*}"; p="$(patch_for "$f" "${spec#*:}")"
  out prot "i['patch'] = '''$p'''" "i['key'] = i['key'].replace('bin/tool', '$f').replace('[3, 3]', '[1, 1]')"; run prot
  [ "$?" -eq 1 ] && grep -q "touches $f, which a probe may not" "$T/prot.log" && ok || bad "$f: $(cat "$T/prot.log")"
done
out ghost "i['patch'] = i['patch'].replace('bin/tool', 'bin/ghost')" "i['key'] = i['key'].replace('bin/tool', 'bin/ghost')"; run ghost; assert_eq 1 "$?"
it "more than 3 files, or more than 80 changed lines, is refused"
git -C "$T/repo" checkout -q "$base" -- .; for f in other f1 f2 f3; do printf 'y\n' >> "$T/repo/bin/$f"; done
four="$(git -C "$T/repo" diff)"; git -C "$T/repo" checkout -q "$base" -- .
out four "i['patch'] = '''$four'''" "i['key'] = i['key'].replace('bin/tool', 'bin/f1').replace('[3, 3]', '[1, 1]')"; run four
[ "$?" -eq 1 ] && grep -q 'touches 4 files' "$T/four.log" && ok || bad "four: $(cat "$T/four.log")"
git -C "$T/repo" checkout -q "$base" -- .; for f in other f1 f2; do printf 'y\n' >> "$T/repo/bin/$f"; done
three="$(git -C "$T/repo" diff)"; git -C "$T/repo" checkout -q "$base" -- .
out three "i['patch'] = '''$three'''" "i['key'] = i['key'].replace('bin/tool', 'bin/f1').replace('[3, 3]', '[1, 1]')"; run three; assert_eq 0 "$?"
git -C "$T/repo" checkout -q "$base" -- .; seq 1 90 >> "$T/repo/bin/other"; big="$(git -C "$T/repo" diff)"; git -C "$T/repo" checkout -q "$base" -- .
out big "i['patch'] = '''$big'''" "i['key'] = i['key'].replace('bin/tool', 'bin/other').replace('[3, 3]', '[2, 2]')"; run big; assert_eq 1 "$?"
it "a word that gives the probe away, in any field, is refused"
for f in title body commit_message; do out blind "i['$f'] = i['$f'] + ' (a probe)'"; run blind; [ "$?" -eq 1 ] && ok || bad "$f with 'probe' accepted"; done
out blindp "i['patch'] = i['patch'].replace('-gt 9', '-gt 9  # planted')"; run blindp; assert_eq 1 "$?"
it "AI attribution, or a title that is not a Conventional Commit, is refused"
out attr "i['commit_message'] += '\n\nCo-Authored-By: Claude <noreply@anthropic.com>'"; run attr; assert_eq 1 "$?"
out ttl "i['title'] = 'Treat 10 as big'"; run ttl; assert_eq 1 "$?"
it "a key that does not match the patch, or with a wrong type, is refused"
out kfile "i['key'] = i['key'].replace('bin/tool', 'bin/other')"; run kfile; assert_eq 1 "$?"
before="$(git -C "$T/repo" for-each-ref --format='%(refname:short)' refs/heads/ | sort)"
out klines "i['key'] = i['key'].replace('[3, 3]', '[3, 40]')"; run klines; assert_eq 1 "$?"
it "a refusal after the branch was made leaves main checked out, unchanged, and adds no branch"
assert_eq "main $base" "$(git -C "$T/repo" rev-parse --abbrev-ref HEAD) $(git -C "$T/repo" rev-parse HEAD)"
assert_eq "" "$(git -C "$T/repo" status --porcelain)"
assert_eq "$before" "$(git -C "$T/repo" for-each-ref --format='%(refname:short)' refs/heads/ | sort)"
out kloud "i['key'] = i['key'].replace('false, \"file\"', '\"no\", \"file\"')"; run kloud; assert_eq 1 "$?"
out kjson "i['key'] = '{not json'"; run kjson; assert_eq 1 "$?"
it "a patch that does not apply is refused, and the repository is left on main, unchanged"
out noapply "i['patch'] = i['patch'].replace('-gt 10', '-gt 77')"; run noapply; assert_eq 1 "$?"
assert_eq "main $base" "$(git -C "$T/repo" rev-parse --abbrev-ref HEAD) $(git -C "$T/repo" rev-parse HEAD)"
assert_eq "" "$(git -C "$T/repo" status --porcelain)"
it "a refusal says why"
grep -q 'probe-open: ' "$T/noapply.log" && ok || bad "no reason: $(cat "$T/noapply.log")"

echo; echo "passed=$pass failed=$fail"
[ "$fail" -eq 0 ]
