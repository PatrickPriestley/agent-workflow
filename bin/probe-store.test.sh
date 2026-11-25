#!/usr/bin/env bash
# Tests for bin/probe-store: it inserts a scored probe (one probe_runs row, one probe_verdicts
# row per loop) into the transcript store with the insert-only key. A local stand-in server
# records each request and answers what each case asks of it.
#   bash bin/probe-store.test.sh
set -u
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PS=(python3 -I "$here/probe-store"); D="$here/testdata/probes"
pass=0; fail=0; CURRENT=""
it() { CURRENT="$1"; }
ok()  { pass=$((pass+1)); printf '  ok   %s\n' "$CURRENT"; }
bad() { fail=$((fail+1)); printf '  FAIL %s\n       %s\n' "$CURRENT" "$1"; }
assert_eq() { [ "$1" = "$2" ] && ok || bad "expected [$1] got [$2]"; }
T="$(mktemp -d "${TMPDIR:-/tmp}/probe-store.XXXXXX")"
cat > "$T/server.py" <<'PY'
import http.server, json, os, sys
log, answers = sys.argv[1], sys.argv[2]
class H(http.server.BaseHTTPRequestHandler):
    def do_POST(self):
        body = self.rfile.read(int(self.headers.get("Content-Length", 0))).decode()
        with open(log, "a") as f:
            f.write(json.dumps({"path": self.path, "apikey": self.headers.get("apikey"),
                                "prefer": self.headers.get("Prefer"), "body": json.loads(body)}) + "\n")
        status = json.load(open(answers)).get(self.path.split("?")[0], 201)
        self.send_response(status); self.end_headers()
        if status >= 400:
            self.wfile.write(b'{"code":"23505","message":"duplicate key"}' if status == 409 else b'{"message":"boom"}')
    def log_message(self, *a): pass
s = http.server.HTTPServer(("127.0.0.1", 0), H)
open(log + ".port", "w").write(str(s.server_port))
s.serve_forever()
PY
printf '{}' > "$T/answers.json"
python3 -I "$T/server.py" "$T/log" "$T/answers.json" & srv=$!
trap 'kill "$srv" 2>/dev/null; [ -n "${KEEP:-}" ] || rm -rf "$T"' EXIT
for _ in $(seq 50); do [ -s "$T/log.port" ] && break; sleep 0.1; done
URL="http://127.0.0.1:$(cat "$T/log.port")"

# The rows probe-score writes for the #45 known answer, and its key.
python3 -I "$here/probe-score" "$D/45/key.json" "$D/45/evidence.json" > "$T/rows.jsonl"
store() {  # args... -> $rc, output in $T/out; fresh log
  : > "$T/log"
  env AGENT_TRANSCRIPTS_URL="${U-$URL}" AGENT_TRANSCRIPTS_INSERT_KEY="${K-sb_publishable_test}" \
    "${PS[@]}" "$@" > "$T/out" 2>&1; rc=$?
}
std=("$D/45/key.json" "$T/rows.jsonl" --scorer-run 777 --repo PatrickPriestley/agent-workflow)
q() { python3 -I -c "$1" "$T/log"; }

it "a scored probe is one probe_runs row, then its verdicts in one request, with the insert key"
store "${std[@]}"; assert_eq 0 "$rc"
assert_eq "/rest/v1/probe_runs /rest/v1/probe_verdicts" "$(q 'import json,sys; print(" ".join(json.loads(l)["path"] for l in open(sys.argv[1])))')"
assert_eq "sb_publishable_test sb_publishable_test" "$(q 'import json,sys; print(" ".join(json.loads(l)["apikey"] for l in open(sys.argv[1])))')"
q '
import json, sys
run, ver = [json.loads(l) for l in open(sys.argv[1])]
r = run["body"]
k = json.load(open("'"$D/45/key.json"'"))
assert r["probe_id"] == k["id"] and r["scorer_run"] == 777 and r["pr"] == k["pr"] and r["repository"] == "PatrickPriestley/agent-workflow", r
assert r["file"] == k["file"] and [r["first_line"], r["last_line"]] == k["lines"] and r["planted_sha"] == k["planted_sha"], r
assert r["kind"] == k["kind"] and r["loud"] is k["loud"], r
v = ver["body"]
assert isinstance(v, list) and len(v) == 8 and all(x["probe_id"] == k["id"] and x["scorer_run"] == 777 for x in v), v
assert set(r) == {"probe_id","scorer_run","pr","repository","kind","loud","file","first_line","last_line","planted_sha","caught","ran"}, sorted(r)
assert set(v[0]) == {"probe_id","scorer_run","loop","verdict","evidence"}, sorted(v[0])
' && ok || bad "rows: $(cat "$T/log")"
it "caught and ran are counted as the score line counts them"
assert_eq "$(python3 -I "$here/probe-score" --markdown "$D/45/key.json" "$D/45/evidence.json" | sed -n 's/.*Caught by \([0-9]*\) of the \([0-9]*\) loops.*/\1 \2/p')" \
  "$(q 'import json,sys; r=json.loads(open(sys.argv[1]).readline())["body"]; print(r["caught"], r["ran"])')"
it "a loop that failed to run is not counted as having run"
printf '%s\n' '{"loop": "verify", "verdict": "caught", "evidence": "x"}' '{"loop": "property-scout", "verdict": "failed", "evidence": "y"}' > "$T/frows.jsonl"
store "$D/45/key.json" "$T/frows.jsonl" --scorer-run 778 --repo a/b; assert_eq 0 "$rc"
assert_eq "1 1" "$(q 'import json,sys; r=json.loads(open(sys.argv[1]).readline())["body"]; print(r["caught"], r["ran"])')"
it "the key's own words (terms, counterexample, false claim) are not sent"
grep -qE 'counterexample|false_claim|claim_terms|"terms"' "$T/log" && bad "sent: $(cat "$T/log")" || ok
it "a probe already stored (409) counts as stored, and its verdicts still go"
printf '{"/rest/v1/probe_runs": 409}' > "$T/answers.json"; store "${std[@]}"; assert_eq 0 "$rc"
assert_eq 2 "$(grep -c . "$T/log")"
printf '{"/rest/v1/probe_runs": 409, "/rest/v1/probe_verdicts": 409}' > "$T/answers.json"; store "${std[@]}"; assert_eq 0 "$rc"
grep -q 'already stored' "$T/out" && ok || bad "$(cat "$T/out")"
it "any other refusal fails, says what the store answered, and sends no verdicts after a refused run"
printf '{"/rest/v1/probe_runs": 500}' > "$T/answers.json"; store "${std[@]}"; assert_eq 1 "$rc"
assert_eq 1 "$(grep -c . "$T/log")"; grep -q '500' "$T/out" && ok || bad "$(cat "$T/out")"
printf '{"/rest/v1/probe_verdicts": 401}' > "$T/answers.json"; store "${std[@]}"; assert_eq 1 "$rc"
printf '{}' > "$T/answers.json"
it "the store must be https (or this machine), and both settings are needed"
U="http://example.com" store "${std[@]}"; assert_eq 2 "$rc"; grep -q 'https' "$T/out" && ok || bad "$(cat "$T/out")"
U="" store "${std[@]}"; assert_eq 2 "$rc"
K="" store "${std[@]}"; assert_eq 2 "$rc"
assert_eq 0 "$(grep -c . "$T/log")"
it "the key never appears in what it prints"
printf '{"/rest/v1/probe_runs": 500}' > "$T/answers.json"; store "${std[@]}"
grep -q 'sb_publishable_test' "$T/out" && bad "printed the key" || ok
printf '{}' > "$T/answers.json"
it "a bad scorer run, repository or rows file is a usage error"
store "$D/45/key.json" "$T/rows.jsonl" --scorer-run x --repo a/b; assert_eq 2 "$rc"
store "$D/45/key.json" "$T/rows.jsonl" --scorer-run 1 --repo 'a b'; assert_eq 2 "$rc"
printf 'not json\n' > "$T/badrows.jsonl"; store "$D/45/key.json" "$T/badrows.jsonl" --scorer-run 1 --repo a/b; assert_eq 2 "$rc"
assert_eq 0 "$(grep -c . "$T/log")"

it "this test runs in CI"
grep -qF 'bash bin/probe-store.test.sh' "$here/../.github/workflows/test.yml" && ok || bad "not in test.yml"

echo; echo "passed=$pass failed=$fail"
[ "$fail" -eq 0 ]
