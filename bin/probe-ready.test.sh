#!/usr/bin/env bash
# Tests for bin/probe-ready: which open probes are ready to score, and which planter run holds
# each one's key. GitHub is a stub `gh` that answers `gh api PATH` from fixture files.
#   bash bin/probe-ready.test.sh
set -u
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
pass=0; fail=0; CURRENT=""
it() { CURRENT="$1"; }
ok()  { pass=$((pass+1)); printf '  ok   %s\n' "$CURRENT"; }
bad() { fail=$((fail+1)); printf '  FAIL %s\n       %s\n' "$CURRENT" "$1"; }
assert_eq() { [ "$1" = "$2" ] && ok || bad "expected [$1] got [$2]"; }
T="$(mktemp -d "${TMPDIR:-/tmp}/probe-ready.XXXXXX")"; [ -n "${KEEP:-}" ] || trap 'rm -rf "$T"' EXIT

mkdir -p "$T/bin" "$T/api"
cat > "$T/bin/gh" <<'STUB'
#!/usr/bin/env bash
# gh api [flags] PATH: the fixture for PATH without its query, with / as _, or [] when none.
printf '%s\n' "$*" >> "$STUB_LOG"
[ "$1" = api ] || { echo "stub gh: only api" >&2; exit 1; }
shift; path=""
for a in "$@"; do case "$a" in -*) ;; *) path="$a" ;; esac; done
f="$STUB_API/$(printf '%s' "${path%%\?*}" | tr '/' '_').json"
[ -f "$f" ] && cat "$f" || echo '[]'
STUB
chmod +x "$T/bin/gh"
R=o/r
api() { printf '%s' "$2" > "$T/api/$(printf '%s' "$1" | tr '/' '_').json"; }  # PATH JSON
pr() {  # NUMBER BRANCH CREATED [LABEL] -> a pull request object
  printf '{"number": %s, "created_at": "%s", "head": {"ref": "%s", "sha": "h%s"}, "labels": [{"name": "%s"}]}' "$1" "$3" "$2" "$1" "${4:-hold}"
}
run() {  # ID CREATED UPDATED [STATUS] [CONCLUSION]
  printf '{"id": %s, "created_at": "%s", "updated_at": "%s", "status": "%s", "conclusion": "%s"}' "$1" "$2" "$3" "${4:-completed}" "${5:-success}"
}
setup() {  # a clean slate: one ready probe, #69, planted by run 500
  rm -f "$T/api/"*
  api "repos/$R/pulls" "[$(pr 69 feat/a 2026-11-25T16:47:25Z), $(pr 70 fix/real 2026-11-25T16:45:00Z none)]"
  api "repos/$R/actions/workflows/probe-plant.lock.yml/runs" \
    "{\"workflow_runs\": [$(run 400 2026-11-25T14:04:02Z 2026-11-25T14:11:36Z), $(run 500 2026-11-25T16:41:51Z 2026-11-25T16:48:13Z), $(run 600 2026-11-25T18:00:00Z 2026-11-25T18:06:00Z)]}"
  api "repos/$R/actions/runs" '{"workflow_runs": []}'
  api "repos/$R/issues/69/comments" '[{"body": "Verify PR claims: matches 1"}]'
}
ready() {  # [extra args] -> $rc, stdout in $T/out, stderr in $T/err
  : > "$T/gh.log"
  PATH="$T/bin:$PATH" STUB_LOG="$T/gh.log" STUB_API="$T/api" \
    python3 -I "$here/probe-ready" --repo "$R" --now "${NOW:-2026-11-25T17:30:00Z}" "$@" > "$T/out" 2> "$T/err"; rc=$?
}

it "an open probe, old enough, with nothing running and no score, is ready, with the run that planted it"
setup; ready; assert_eq 0 "$rc"
assert_eq '{"pr": 69, "key_run": 500}' "$(cat "$T/out")"
it "a pull request without the hold label is never a probe"
grep -q '70' "$T/out" && bad "listed #70" || ok
it "a probe younger than 30 minutes waits"
setup; NOW=2026-11-25T17:10:00Z ready; assert_eq "0 " "$rc $(cat "$T/out")"
grep -q '#69: opened 22 minutes ago' "$T/err" && ok || bad "$(cat "$T/err")"
it "a probe with a run still going on its branch waits"
setup; api "repos/$R/actions/runs" "{\"workflow_runs\": [$(run 9 2026-11-25T17:20:00Z 2026-11-25T17:21:00Z in_progress '')]}"
ready; assert_eq "0 " "$rc $(cat "$T/out")"
grep -q '#69: 1 run still going' "$T/err" && ok || bad "$(cat "$T/err")"
grep -qF "repos/$R/actions/runs?branch=feat/a" "$T/gh.log" && ok || bad "did not ask for the branch's runs: $(cat "$T/gh.log")"
it "a queued or waiting run counts as going too; a finished one does not"
for st in queued waiting requested pending; do
  setup; api "repos/$R/actions/runs" "{\"workflow_runs\": [$(run 9 2026-11-25T17:20:00Z 2026-11-25T17:21:00Z $st '')]}"
  ready; assert_eq "" "$(cat "$T/out")"
done
setup; api "repos/$R/actions/runs" "{\"workflow_runs\": [$(run 9 2026-11-25T17:20:00Z 2026-11-25T17:21:00Z completed failure)]}"
ready; assert_eq '{"pr": 69, "key_run": 500}' "$(cat "$T/out")"
it "a probe already scored is not scored again"
setup; api "repos/$R/issues/69/comments" '[{"body": "### Probe probe-500: dropped-alternative, silent\n\n| Loop | Verdict |"}]'
ready; assert_eq "" "$(cat "$T/out")"
grep -q '#69: already scored' "$T/err" && ok || bad "$(cat "$T/err")"
it "the planter run is the one that was running when the probe opened; with none, or two, it is skipped"
setup; api "repos/$R/actions/workflows/probe-plant.lock.yml/runs" "{\"workflow_runs\": [$(run 400 2026-11-25T14:04:02Z 2026-11-25T14:11:36Z)]}"
ready; assert_eq "" "$(cat "$T/out")"; grep -q '#69: no planter run' "$T/err" && ok || bad "$(cat "$T/err")"
setup; api "repos/$R/actions/workflows/probe-plant.lock.yml/runs" "{\"workflow_runs\": [$(run 500 2026-11-25T16:41:51Z 2026-11-25T16:48:13Z), $(run 501 2026-11-25T16:42:00Z 2026-11-25T16:49:00Z)]}"
ready; assert_eq "" "$(cat "$T/out")"; grep -q '#69: 2 planter runs' "$T/err" && ok || bad "$(cat "$T/err")"
it "a planter run that did not succeed holds no key"
setup; api "repos/$R/actions/workflows/probe-plant.lock.yml/runs" "{\"workflow_runs\": [$(run 500 2026-11-25T16:41:51Z 2026-11-25T16:48:13Z completed failure)]}"
ready; assert_eq "" "$(cat "$T/out")"
it "several ready probes are each listed, one JSON line each"
setup; api "repos/$R/pulls" "[$(pr 69 feat/a 2026-11-25T16:47:25Z), $(pr 68 feat/b 2026-11-25T14:11:00Z)]"
ready; assert_eq '{"pr": 69, "key_run": 500}
{"pr": 68, "key_run": 400}' "$(cat "$T/out")"
it "a GitHub error stops it, rather than reading as no probes"
setup; cat > "$T/bin/gh.fail" <<'STUB'
#!/usr/bin/env bash
echo '[]'; echo "HTTP 502" >&2; exit 1  # an empty answer, but a failure: not "no probes"
STUB
chmod +x "$T/bin/gh.fail"; mv "$T/bin/gh" "$T/bin/gh.ok"; mv "$T/bin/gh.fail" "$T/bin/gh"
ready; assert_eq 1 "$rc"; mv "$T/bin/gh" "$T/bin/gh.fail"; mv "$T/bin/gh.ok" "$T/bin/gh"
it "a bad repository or time is a usage error"
setup; PATH="$T/bin:$PATH" STUB_LOG=/dev/null STUB_API="$T/api" python3 -I "$here/probe-ready" --repo 'a b' >/dev/null 2>&1; assert_eq 2 "$?"
NOW=yesterday ready; assert_eq 2 "$rc"

it "this test runs in CI"
grep -qF 'bash bin/probe-ready.test.sh' "$here/../.github/workflows/test.yml" && ok || bad "not in test.yml"

echo; echo "passed=$pass failed=$fail"
[ "$fail" -eq 0 ]
