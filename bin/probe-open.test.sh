#!/usr/bin/env bash
# Tests for bin/probe-open: it checks what the planter agent handed over, applies its edits,
# and builds the probe's branch, commit and final answer key, refusing anything that is not
# a small, blind change.
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
# A longer script with a blank line and a line ending in spaces, which a diff copied by hand
# would most often break; edits do not care.
printf '#!/usr/bin/env bash\nset -u\n\nlimit=10   \nn="${1:-0}"\nif [ "$n" -gt "$limit" ]; then\n  echo big\nelse\n  echo small\nfi\n' > "$T/repo/bin/long"
printf 'one\r\ntwo\r\nthree\r\n' > "$T/repo/bin/crlf"
mkdir -p "$T/outside" && printf 'x\n' > "$T/outside/f" && ln -s "$T/outside" "$T/repo/ext"
printf 'x\n' > "$T/repo/bin/real" && ln -s real "$T/repo/bin/lnk" && ln -s .github "$T/repo/gh"
printf 'secret\n' > "$T/repo/.env" && printf '.env\n' > "$T/repo/.gitignore"
printf 'caf\351 x\n' > "$T/repo/bin/latin1"
git -C "$T/repo" init -q -b main && g add -A && g commit -qm base
base="$(git -C "$T/repo" rev-parse HEAD)"

# Agent output, as gh-aw writes it: {"items": [{"type": "open_probe", ...}]}. The default
# hand-over moves the limit from 10 to 9 (an off-by-one); each case overrides it in Python.
out() {  # NAME, then python statements on i (the item) and E (the edits list) -> $T/NAME.json
  local name="$1"; shift
  python3 - "$T/$name.json" "$@" <<'PY'
import json, sys
E = [{"path": "bin/tool", "old": "-gt 10", "new": "-gt 9"}]
i = {"type": "open_probe", "title": "fix(tool): treat a size of exactly 10 as big",
     "body": "The tool now calls 10 big, as the docs say.\n\nExisting sizes are unchanged.",
     "commit_message": "fix(tool): treat a size of exactly 10 as big\n\nExisting sizes are unchanged.",
     "key": json.dumps({"kind": "off-by-one", "loud": False, "file": "bin/tool", "lines": [3, 3],
                        "terms": ["-gt 9", "10"], "counterexample": "bin/tool 10", "false_claim": "Existing sizes are unchanged.",
                        "claim_terms": ["unchanged"]})}
for a in sys.argv[2:]:
    exec(a)
if i is not None and "edits" not in i:
    i["edits"] = json.dumps(E)
json.dump({"items": [i] if i is not None else []}, open(sys.argv[1], "w"))
PY
}
run() {  # NAME -> exit code; repo reset to base first
  git -C "$T/repo" checkout -q main 2>/dev/null; git -C "$T/repo" reset -q --hard "$base"; rm -rf "$T/o"
  "${PO[@]}" "$T/$1.json" --repo-dir "$T/repo" --out "$T/o" --run-id 4242 --author 'Some One <one@example.com>' >"$T/$1.log" 2>&1
}
refused() {  # NAME TEXT: exit 1 with TEXT in the reason
  run "$1"; local rc=$?
  [ "$rc" -eq 1 ] && grep -qF -- "$2" "$T/$1.log" && ok || bad "$1 (rc $rc): $(cat "$T/$1.log")"
}
key_at() { printf "i['key'] = i['key'].replace('bin/tool', '%s').replace('[3, 3]', '%s')" "$1" "$2"; }

it "a valid hand-over makes one commit on a fix/ branch with the edit, and the final key"
out good; run good; assert_eq 0 "$?"
br="$(cat "$T/o/branch.txt" 2>/dev/null)"
printf '%s' "$br" | grep -qE '^fix/treat-a-size-of-exactly-10-as-big-[0-9a-f]{6}$' && ok || bad "branch [$br]"
assert_eq "$base" "$(git -C "$T/repo" rev-parse "$br~1")"
assert_eq "bin/tool" "$(git -C "$T/repo" diff --name-only "$base" "$br")"
git -C "$T/repo" show "$br:bin/tool" | grep -q -- '-gt 9' && ok || bad "edit not committed"
assert_eq "Some One" "$(git -C "$T/repo" log -1 --format=%an "$br")"
python3 -c '
import json,sys; k=json.load(open(sys.argv[1])); sha=sys.argv[2]
assert k["id"]=="probe-4242" and k["planted_sha"]==sha and k["pr"] is None and k["loud"] is False and k["file"]=="bin/tool", k
' "$T/o/key.json" "$(git -C "$T/repo" rev-parse "$br")" && ok || bad "key: $(cat "$T/o/key.json")"
assert_eq "fix(tool): treat a size of exactly 10 as big" "$(cat "$T/o/title.txt")"
grep -q 'Existing sizes are unchanged' "$T/o/body.md" && ok || bad "body"

it "edits keep every other byte: blank lines and trailing spaces nearby are untouched"
out long "E = [{'path': 'bin/long', 'old': '1:-0', 'new': '1:-1'}]" "$(key_at bin/long '[5, 5]')"; run long; assert_eq 0 "$?"
expect="$(git -C "$T/repo" show "$base:bin/long" | sed 's/1:-0/1:-1/')"
assert_eq "$expect" "$(git -C "$T/repo" show "$(cat "$T/o/branch.txt"):bin/long")"
assert_eq "1	1	bin/long" "$(git -C "$T/repo" diff --numstat "$base" "$(cat "$T/o/branch.txt")")"
it "several edits to one file apply in order"
out seq "E = [{'path': 'bin/long', 'old': 'echo big', 'new': 'echo large'}, {'path': 'bin/long', 'old': 'echo large', 'new': 'echo huge'}]" "$(key_at bin/long '[7, 7]')"; run seq; assert_eq 0 "$?"
git -C "$T/repo" show "$(cat "$T/o/branch.txt"):bin/long" | grep -qx '  echo huge' && ok || bad "edits not applied in order"
it "an edit whose old text is missing, or appears twice, is refused"
out missing "E[0]['old'] = '-gt 77'"; refused missing "not found"
out twice "E = [{'path': 'bin/long', 'old': 'echo', 'new': 'printf'}]" "$(key_at bin/long '[7, 7]')"; refused twice "appears 2 times"
out same "E[0]['new'] = E[0]['old']"; refused same "changes nothing"

it "no open_probe item, or two, or edits that are not a list of path/old/new, is refused"
out none 'i = None'; refused none "expected one open_probe item, found 0"
out two; python3 -c 'import json,sys; d=json.load(open(sys.argv[1])); d["items"].append(d["items"][0]); json.dump(d,open(sys.argv[1],"w"))' "$T/two.json"; refused two "found 2"
out ejson "i['edits'] = '[{not json'"; refused ejson "edits is not JSON"
out eshape "i['edits'] = json.dumps([{'path': 'bin/tool', 'old': 'x'}])"; refused eshape "each edit needs path, old and new"
out eempty "i['edits'] = '[]'"; refused eempty "no edits"
it "an edit to a workflow, an agent rules file, a test, or a file that does not exist is refused"
out wf "E = [{'path': '.github/workflows/x.yml', 'old': 'x', 'new': 'y'}]" "$(key_at .github/workflows/x.yml '[1, 1]')"; refused wf "touches .github/workflows/x.yml, which a probe may not"
out ag "E = [{'path': 'AGENTS.md', 'old': 'rules', 'new': 'none'}]" "$(key_at AGENTS.md '[1, 1]')"; refused ag "touches AGENTS.md, which a probe may not"
out tst "E = [{'path': 'bin/tool.test.sh', 'old': 'big', 'new': 'small'}]" "$(key_at bin/tool.test.sh '[2, 2]')"; refused tst "touches bin/tool.test.sh, which a probe may not"
out ghost "E = [{'path': 'bin/ghost', 'old': 'x', 'new': 'y'}]" "$(key_at bin/ghost '[1, 1]')"; refused ghost "bin/ghost, which does not exist"
out escape "E = [{'path': '../outside', 'old': 'x', 'new': 'y'}]" "$(key_at ../outside '[1, 1]')"; refused escape "not a plain path in the repository"
out link "E = [{'path': 'ext/f', 'old': 'x', 'new': 'y'}]" "$(key_at ext/f '[1, 1]')"; refused link "not a plain path in the repository"
[ "$(cat "$T/outside/f")" = x ] && ok || bad "wrote through the symlink"
out dotgit "E = [{'path': '.git/config', 'old': '[core]', 'new': '[core]x'}]" "$(key_at .git/config '[1, 1]')"; refused dotgit "not a plain path in the repository"
git -C "$T/repo" config --get core.bare >/dev/null && ok || bad ".git/config was changed"
out bslash "E = [{'path': 'bin\\\\tool', 'old': 'x', 'new': 'y'}]" "$(key_at 'bin\\\\tool' '[1, 1]')"; refused bslash "not a plain path in the repository"
out lnk "E = [{'path': 'bin/lnk', 'old': 'x', 'new': 'y'}]" "$(key_at bin/lnk '[1, 1]')"; refused lnk "not a plain path in the repository"
[ "$(cat "$T/repo/bin/real")" = x ] && ok || bad "wrote through bin/lnk"
out ghl "E = [{'path': 'gh/workflows/x.yml', 'old': 'x', 'new': 'y'}]" "$(key_at gh/workflows/x.yml '[1, 1]')"; refused ghl "not a plain path in the repository"
it "an edit to a file git does not track (an ignored .env) is refused and the file left alone"
out env "E = [{'path': '.env', 'old': 'secret', 'new': 'public'}]" "$(key_at .env '[1, 1]')"; refused env ".env, which git does not track"
assert_eq "secret" "$(cat "$T/repo/.env")"
it "a file that is not UTF-8 text is refused cleanly, back on main with no branch"
before="$(git -C "$T/repo" for-each-ref --format='%(refname:short)' refs/heads/ | sort)"
out latin "E = [{'path': 'bin/latin1', 'old': 'x', 'new': 'y'}]" "$(key_at bin/latin1 '[1, 1]')"; refused latin "cannot read bin/latin1 as UTF-8 text"
assert_eq "main $before" "$(git -C "$T/repo" rev-parse --abbrev-ref HEAD) $(git -C "$T/repo" for-each-ref --format='%(refname:short)' refs/heads/ | sort)"
it "an edit keeps CRLF line endings: the diff is one line"
out crlf "E = [{'path': 'bin/crlf', 'old': 'two', 'new': 'TWO'}]" "$(key_at bin/crlf '[2, 2]')"; run crlf; assert_eq 0 "$?"
assert_eq "1	1	bin/crlf" "$(git -C "$T/repo" diff --numstat "$base" "$(cat "$T/o/branch.txt" 2>/dev/null)")"
it "uncommitted changes in the checkout are refused and left in place"
run good >/dev/null; git -C "$T/repo" checkout -q main; git -C "$T/repo" reset -q --hard "$base"; printf 'mine\n' >> "$T/repo/bin/other"
"${PO[@]}" "$T/good.json" --repo-dir "$T/repo" --out "$T/o2" --run-id 4242 --author 'Some One <one@example.com>' >"$T/dirty.log" 2>&1; assert_eq 1 "$?"
grep -q 'uncommitted changes' "$T/dirty.log" && ok || bad "$(cat "$T/dirty.log")"
assert_eq "other
mine" "$(cat "$T/repo/bin/other")"
it "more than 3 files, or more than 80 changed lines, is refused; 3 files is fine"
out four "E = [{'path': 'bin/' + f, 'old': 'x' if f != 'other' else 'other', 'new': 'y'} for f in ('other', 'f1', 'f2', 'f3')]" "$(key_at bin/f1 '[1, 1]')"; refused four "touches 4 files"
out three "E = [{'path': 'bin/' + f, 'old': 'x' if f != 'other' else 'other', 'new': 'y'} for f in ('other', 'f1', 'f2')]" "$(key_at bin/f1 '[1, 1]')"; run three; assert_eq 0 "$?"
out big "E = [{'path': 'bin/other', 'old': 'other', 'new': chr(10).join(str(n) for n in range(90))}]" "$(key_at bin/other '[2, 2]')"; refused big "changes 91 lines; at most 80"
it "a word that gives the probe away, in any field or edit, is refused"
for f in title body commit_message; do out blind "i['$f'] = i['$f'] + ' (a probe)'"; refused blind "gives the probe away"; done
out blinde "E[0]['new'] = '-gt 9  # planted'"; refused blinde "edits gives the probe away"
it "AI attribution, or a title that is not a Conventional Commit, is refused"
out attr "i['commit_message'] += '\n\nCo-Authored-By: Claude <noreply@anthropic.com>'"; refused attr "carries AI attribution"
out ttl "i['title'] = 'Treat 10 as big'"; refused ttl "Conventional Commits"
it "a key that does not match the edits, or with a wrong type, is refused"
out kfile "$(key_at bin/other '[3, 3]')"; refused kfile "key.file bin/other is not among the files edited"
out klines "i['key'] = i['key'].replace('[3, 3]', '[3, 40]')"; refused klines "past the end of bin/tool"
out kloud "i['key'] = i['key'].replace('false, \"file\"', '\"no\", \"file\"')"; refused kloud "key.loud"
out kjson "i['key'] = '{not json'"; refused kjson "key is not JSON"
it "a refusal after edits were made leaves main checked out, unchanged, and adds no branch"
before="$(git -C "$T/repo" for-each-ref --format='%(refname:short)' refs/heads/ | sort)"
out late "i['key'] = i['key'].replace('[3, 3]', '[3, 40]')"; run late; assert_eq 1 "$?"
assert_eq "main $base" "$(git -C "$T/repo" rev-parse --abbrev-ref HEAD) $(git -C "$T/repo" rev-parse HEAD)"
assert_eq "" "$(git -C "$T/repo" status --porcelain)"
assert_eq "$before" "$(git -C "$T/repo" for-each-ref --format='%(refname:short)' refs/heads/ | sort)"

echo; echo "passed=$pass failed=$fail"
[ "$fail" -eq 0 ]
