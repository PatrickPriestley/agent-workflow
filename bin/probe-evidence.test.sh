#!/usr/bin/env bash
# Tests for bin/probe-evidence, against a stand-in gh that serves canned API responses.
#   bash bin/probe-evidence.test.sh
set -u
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PE=(python3 -I "$here/probe-evidence")
pass=0; fail=0; CURRENT=""
it() { CURRENT="$1"; }
ok()  { pass=$((pass+1)); printf '  ok   %s\n' "$CURRENT"; }
bad() { fail=$((fail+1)); printf '  FAIL %s\n       %s\n' "$CURRENT" "$1"; }
assert_eq() { [ "$1" = "$2" ] && ok || bad "expected [$1] got [$2]"; }
T="$(mktemp -d "${TMPDIR:-/tmp}/probe-evidence.XXXXXX")"; trap 'rm -rf "$T"' EXIT
mkdir -p "$T/bin" "$T/api"

# The stand-in: "gh api PATH" prints $T/api/<PATH with / and ? and & turned into _>, and logs it.
cat > "$T/bin/gh" <<'STUB'
#!/usr/bin/env bash
[ "$1" = api ] || { echo "stub gh: only api" >&2; exit 2; }
printf '%s\n' "$2" >> "$GH_LOG"
f="$GH_API/$(printf '%s' "$2" | tr '/?&=' '____')"
[ -f "$f" ] && cat "$f" || { [ -n "${GH_EMPTY_MISSING:-}" ] && echo '[]' || { echo "stub gh: no $f" >&2; exit 1; }; }
STUB
chmod +x "$T/bin/gh"
put() { printf '%s' "$2" > "$T/api/$(printf '%s' "$1" | tr '/?&=' '____')"; }
R=repos/o/r
put "$R/pulls/9" '{"number":9,"head":{"sha":"aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"}}'
put "$R/actions/runs?head_sha=aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa&per_page=100" '{"workflow_runs":[
 {"name":"test","conclusion":"failure","run_number":5,"event":"pull_request"},
 {"name":"test","conclusion":"success","run_number":6,"event":"pull_request"},
 {"name":"properties","conclusion":"success","run_number":3,"event":"pull_request"},
 {"name":"mutation","conclusion":null,"run_number":2,"event":"pull_request"}]}'
put "$R/actions/runs?head_sha=bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb&per_page=100" '{"workflow_runs":[
 {"name":"test","conclusion":"failure","run_number":4,"event":"pull_request"}]}'
put "$R/pulls/9/comments?per_page=100&page=1" '[{"path":"bin/x","line":12,"original_line":12,"body":"inline one","user":{"login":"github-actions[bot]"}}]'
put "$R/pulls/9/comments?per_page=100&page=2" '[]'
put "$R/issues/9/comments?per_page=100&page=1" "$(python3 -c 'import json; print(json.dumps([{"body":"c%d"%i,"user":{"login":"u"}} for i in range(100)]))')"
put "$R/issues/9/comments?per_page=100&page=2" '[{"body":"last","user":{"login":"github-actions[bot]"}}]'
put "$R/issues/9/comments?per_page=100&page=3" '[]'
run() { PATH="$T/bin:$PATH" GH_API="$T/api" GH_LOG="$T/gh.log" "${PE[@]}" "$@"; }

it "collects the head, each workflow's latest conclusion, and every comment"
: > "$T/gh.log"; js="$(run 9 --repo o/r)"; assert_eq 0 "$?"
assert_eq "9 aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa" "$(printf '%s' "$js" | python3 -c 'import json,sys; d=json.load(sys.stdin); print(d["pr"], d["head"])')"
assert_eq success "$(printf '%s' "$js" | python3 -c 'import json,sys; print(json.load(sys.stdin)["checks"]["test"])')"
it "a workflow still running has no conclusion yet, so it is left out"
assert_eq absent "$(printf '%s' "$js" | python3 -c 'import json,sys; print(json.load(sys.stdin)["checks"].get("mutation","absent"))')"
it "comments are read page by page, all 101 of them, and inline comments keep path and lines"
assert_eq 101 "$(printf '%s' "$js" | python3 -c 'import json,sys; print(len(json.load(sys.stdin)["comments"]))')"
assert_eq "bin/x 12 12" "$(printf '%s' "$js" | python3 -c 'import json,sys; c=json.load(sys.stdin)["review_comments"][0]; print(c["path"], c["line"], c["original_line"])')"
it "--sha reads the checks at that commit (the planted one), not the head"
js2="$(run 9 --repo o/r --sha bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb)"
assert_eq failure "$(printf '%s' "$js2" | python3 -c 'import json,sys; print(json.load(sys.stdin)["checks"]["test"])')"
it "the output is what bin/probe-score reads"
printf '%s' "$js2" > "$T/ev.json"
python3 -I "$here/probe-score" "$here/testdata/probes/45/key.json" "$T/ev.json" >/dev/null && ok || bad "probe-score refused it"
it "a failed API call, a bad pull request number or a bad sha is an error, with nothing printed"
out="$(PATH="$T/bin:$PATH" GH_API="$T/none" GH_LOG="$T/gh.log" "${PE[@]}" 9 --repo o/r 2>/dev/null)"; rc=$?
[ "$rc" -ne 0 ] && [ -z "$out" ] && ok || bad "rc=$rc out=$out"
run nine --repo o/r >/dev/null 2>&1; assert_eq 2 "$?"
run 9 --repo o/r --sha zz >/dev/null 2>&1; assert_eq 2 "$?"
run 9 --repo 'o/r;x' >/dev/null 2>&1; assert_eq 2 "$?"

echo; echo "passed=$pass failed=$fail"
[ "$fail" -eq 0 ]
