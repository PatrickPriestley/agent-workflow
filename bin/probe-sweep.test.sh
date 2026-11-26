#!/usr/bin/env bash
# Tests for bin/probe-sweep: delete closed probes' branches, close probes left open, and close
# gh-aw's issues past their expiry; and touch nothing else. GitHub is a stub `gh`.
#   bash bin/probe-sweep.test.sh
set -u
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
pass=0; fail=0; CURRENT=""
it() { CURRENT="$1"; }
ok()  { pass=$((pass+1)); printf '  ok   %s\n' "$CURRENT"; }
bad() { fail=$((fail+1)); printf '  FAIL %s\n       %s\n' "$CURRENT" "$1"; }
assert_eq() { [ "$1" = "$2" ] && ok || bad "expected [$1] got [$2]"; }
has() { printf '%s' "$1" | grep -qF -- "$2" && ok || bad "missing [$2] in: $(printf '%s' "$1" | head -c 600)"; }
T="$(mktemp -d "${TMPDIR:-/tmp}/probe-sweep.XXXXXX")"; [ -n "${KEEP:-}" ] || trap 'rm -rf "$T"' EXIT

mkdir -p "$T/bin" "$T/api"
cat > "$T/bin/gh" <<'STUB'
#!/usr/bin/env bash
# gh api [-X METHOD] [-f k=v]... PATH. A GET answers the fixture for PATH (query included, with
# / ? & = as _); a ref with no fixture is a 404. Any other method is logged and answers {},
# or fails when its line matches STUB_FAIL.
[ "$1" = api ] || { echo "stub gh: only api" >&2; exit 1; }
shift; method=GET; fields=""; path=""
while [ $# -gt 0 ]; do
  case "$1" in
    -X) method="$2"; shift 2 ;;
    -f) fields="$fields $2"; shift 2 ;;
    *) path="$1"; shift ;;
  esac
done
if [ "$method" != GET ]; then
  line="$method $path$fields"; printf '%s\n' "$line" >> "$STUB_LOG"
  if [ -n "${STUB_FAIL:-}" ] && printf '%s' "$line" | grep -q -- "$STUB_FAIL"; then echo "gh: HTTP 422" >&2; exit 1; fi
  echo '{}'; exit 0
fi
f="$STUB_API/$(printf '%s' "$path" | tr '/?&=' '____').json"
if [ -f "$f" ]; then cat "$f"
elif printf '%s' "$path" | grep -q '/git/ref/'; then echo "gh: Not Found (HTTP 404)" >&2; exit 1
else echo '[]'; fi
STUB
chmod +x "$T/bin/gh"
R=o/r
api() { printf '%s' "$2" > "$T/api/$(printf '%s' "$1" | tr '/?&=' '____').json"; }  # PATH JSON
OPEN="repos/$R/pulls?state=open&per_page=100"
CLOSED="repos/$R/pulls?state=closed&sort=updated&direction=desc&per_page=100"
ISSUES="repos/$R/issues?state=open&labels=agentic-workflows&per_page=100"
sha() { printf '%040d' "$1"; }
pr() {  # NUMBER BRANCH CREATED [CLOSED] [LABEL] [MERGED] [HEADREPO] -> a pull request object
  printf '{"number": %s, "created_at": "%s", "closed_at": %s, "merged_at": %s, "head": {"ref": "%s", "sha": "%s", "repo": {"full_name": "%s"}}, "labels": [{"name": "%s"}]}' \
    "$1" "$3" "${4:-null}" "${6:-null}" "$2" "$(sha "$1")" "${7:-o/r}" "${5:-hold}"
}
ref() { api "repos/$R/git/ref/heads/$1" "{\"object\": {\"sha\": \"$2\"}}"; }  # BRANCH SHA
issue() {  # NUMBER BODY [USER] [PULL]
  local pull=""; [ -z "${4:-}" ] || pull=', "pull_request": {}'
  printf '{"number": %s, "user": {"login": "%s"}, "body": "%s"%s}' "$1" "${3:-github-actions[bot]}" "$2" "$pull"
}
B1=feat/skip-vendor-node-modules-08162e
setup() {  # one closed probe, #68, closed two days ago, its branch where it was
  rm -f "$T/api/"*
  api "$OPEN" '[]'; api "$ISSUES" '[]'
  api "$CLOSED" "[$(pr 68 $B1 2026-11-20T00:00:00Z '"2026-11-24T00:00:00Z"')]"
  ref $B1 "$(sha 68)"
}
sweep() {  # [extra args] -> $rc; stdout in $T/out, stderr in $T/err, writes in $T/gh.log
  : > "$T/gh.log"
  PATH="$T/bin:$PATH" STUB_LOG="$T/gh.log" STUB_API="$T/api" STUB_FAIL="${FAILS:-}" \
    python3 -I "$here/probe-sweep" --repo "$R" --now "${NOW:-2026-11-26T00:00:00Z}" "$@" > "$T/out" 2> "$T/err"; rc=$?
}
writes() { cat "$T/gh.log"; }

it "a closed probe's branch, still at its commit, a day after it closed, is deleted"
setup; sweep; assert_eq 0 "$rc"
assert_eq "DELETE repos/o/r/git/refs/heads/$B1" "$(writes)"
has "$(cat "$T/out")" "deleted $B1, the branch of closed probe #68"
it "--dry-run says the same and writes nothing"
setup; sweep --dry-run; assert_eq "0 " "$rc $(writes)"; has "$(cat "$T/out")" "would delete $B1"
it "within a day of closing, the branch waits"
setup; NOW=2026-11-24T20:00:00Z sweep; assert_eq "0 " "$rc $(writes)"; has "$(cat "$T/err")" "closed less than a day ago"
it "a branch that has moved since the probe closed is kept"
setup; ref $B1 "$(sha 99)"; sweep; assert_eq "" "$(writes)"; has "$(cat "$T/err")" "has moved"
it "a branch already deleted is no error"
setup; rm "$T/api/"*git_ref*; sweep; assert_eq "0 " "$rc $(writes)"
it "a branch an open pull request uses is kept"
setup; api "$OPEN" "[$(pr 70 $B1 2026-11-25T00:00:00Z null none)]"; sweep; assert_eq "" "$(writes)"; has "$(cat "$T/err")" "open pull request"
it "never a merged pull request's branch, one without hold, one not named like a probe's, or one from a fork"
for p in "$(pr 68 $B1 2026-11-20T00:00:00Z '"2026-11-24T00:00:00Z"' hold '"2026-11-24T00:00:00Z"')" \
         "$(pr 68 $B1 2026-11-20T00:00:00Z '"2026-11-24T00:00:00Z"' none)" \
         "$(pr 68 feat/real-work 2026-11-20T00:00:00Z '"2026-11-24T00:00:00Z"')" \
         "$(pr 68 main 2026-11-20T00:00:00Z '"2026-11-24T00:00:00Z"')" \
         "$(pr 68 $B1 2026-11-20T00:00:00Z '"2026-11-24T00:00:00Z"' hold null someone/fork)"; do
  setup; api "$CLOSED" "[$p]"; ref feat/real-work "$(sha 68)"; ref main "$(sha 68)"; sweep; assert_eq "0 " "$rc $(writes)"
done

it "a probe open 14 days is closed, with a comment saying it was not scored; younger ones are left"
setup; api "$CLOSED" '[]'
api "$OPEN" "[$(pr 80 feat/old-one-a1b2c3 2026-11-11T00:00:00Z), $(pr 81 feat/new-one-d4e5f6 2026-11-20T00:00:00Z), $(pr 82 feat/real-work 2026-11-01T00:00:00Z)]"
sweep; assert_eq 0 "$rc"
assert_eq "POST repos/o/r/issues/80/comments body=Closed by probe-sweep: this probe was open 15 days and was not scored. Probes are never merged.
PATCH repos/o/r/pulls/80 state=closed" "$(writes)"
has "$(cat "$T/out")" "closed #80: open 15 days, not scored"
it "--stale-days changes when"
sweep --stale-days 5; assert_eq 2 "$(grep -c '^PATCH' "$T/gh.log")"
sweep --stale-days 0; assert_eq 2 "$rc"; sweep --stale-days x; assert_eq 2 "$rc"

it "gh-aw's issues past their expiry are closed as not planned; others are left"
setup; api "$CLOSED" '[]'
api "$ISSUES" "[$(issue 57 'x <!-- gh-aw-expires: 2026-11-25T11:44:19.166Z --> y'), $(issue 25 '<!-- gh-aw-expires: 2026-12-22T11:58:09.704Z -->'), $(issue 61 'no expiry'), $(issue 62 '<!-- gh-aw-expires: 2026-11-01T00:00:00Z -->' someone), $(issue 63 '<!-- gh-aw-expires: 2026-11-01T00:00:00Z -->' 'github-actions[bot]' pr), $(issue 64 '<!-- gh-aw-expires: soon -->')]"
sweep; assert_eq 0 "$rc"
assert_eq "POST repos/o/r/issues/57/comments body=Closed by probe-sweep: gh-aw set this issue to expire on 2026-11-25.
PATCH repos/o/r/issues/57 state=closed state_reason=not_planned" "$(writes)"
has "$(cat "$T/out")" "closed issue #57: gh-aw's expiry 2026-11-25 has passed"

it "a failed change is said, does not stop the others, and fails the run"
setup; api "$ISSUES" "[$(issue 57 '<!-- gh-aw-expires: 2026-11-25T11:44:19.166Z -->')]"
FAILS='^DELETE' sweep; assert_eq 1 "$rc"; has "$(cat "$T/err")" "failed: deleted $B1"
grep -q '^PATCH repos/o/r/issues/57' "$T/gh.log" && ok || bad "stopped after the failure: $(writes)"
it "GitHub failing to answer fails the run before anything is changed"
setup; printf 'not json' > "$T/api/$(printf '%s' "$ISSUES" | tr '/?&=' '____').json"; sweep; assert_eq "1 " "$rc $(writes)"
it "a full page is warned about"
setup; api "$OPEN" "[$(for i in $(seq 1 100); do printf '%s{"number": %s, "head": {"ref": "x"}, "labels": []}' "$([ "$i" -gt 1 ] && echo ,)" "$i"; done)]"
sweep; has "$(cat "$T/err")" "open pull requests: a full page"
it "the repository must be owner/name, and an argument it does not know is refused"
for a in "--repo o" "--repo o/r/x" "--repo o/r --what" "--repo o/r --dry-run --dry-run"; do
  : > "$T/gh.log"; PATH="$T/bin:$PATH" STUB_LOG="$T/gh.log" STUB_API="$T/api" python3 -I "$here/probe-sweep" $a > /dev/null 2>&1; assert_eq "2 " "$? $(writes)"
done

it "this test runs in CI"
grep -qF 'bash bin/probe-sweep.test.sh' "$here/../.github/workflows/test.yml" && ok || bad "not in test.yml"

echo; echo "passed=$pass failed=$fail"
[ "$fail" -eq 0 ]
