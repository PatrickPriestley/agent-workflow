#!/usr/bin/env bash
# Tests for bin/probe-report: the week's probe report, read from the store's two report
# functions with the publishable key, as markdown for a run summary. A local stand-in server
# answers the functions' calls.
#   bash bin/probe-report.test.sh
set -u
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PR=(python3 -I "$here/probe-report")
pass=0; fail=0; CURRENT=""
it() { CURRENT="$1"; }
ok()  { pass=$((pass+1)); printf '  ok   %s\n' "$CURRENT"; }
bad() { fail=$((fail+1)); printf '  FAIL %s\n       %s\n' "$CURRENT" "$1"; }
assert_eq() { [ "$1" = "$2" ] && ok || bad "expected [$1] got [$2]"; }
has() { printf '%s' "$1" | grep -qF -- "$2" && ok || bad "missing [$2] in: $(printf '%s' "$1" | head -c 400)"; }
T="$(mktemp -d "${TMPDIR:-/tmp}/probe-report.XXXXXX")"
cat > "$T/server.py" <<'PY'
import http.server, json, sys
log, answers = sys.argv[1], sys.argv[2]
class H(http.server.BaseHTTPRequestHandler):
    def do_POST(self):
        body = self.rfile.read(int(self.headers.get("Content-Length", 0))).decode()
        with open(log, "a") as f:
            f.write(json.dumps({"path": self.path, "apikey": self.headers.get("apikey"), "body": json.loads(body or "null")}) + "\n")
        a = json.load(open(answers)).get(self.path, {"status": 404, "body": []})
        self.send_response(a["status"])
        if a["status"] in (301, 302, 307, 308):
            self.send_header("Location", "http://127.0.0.1:%d/redirected" % self.server.server_port)
        self.end_headers()
        self.wfile.write(json.dumps(a["body"] if a["status"] < 400 else {"message": "refused for " + str(self.headers.get("apikey"))}).encode())
    def do_GET(self):
        with open(log, "a") as f:
            f.write(json.dumps({"path": self.path}) + "\n")
        self.send_response(200); self.end_headers()
    def log_message(self, *a): pass
s = http.server.HTTPServer(("127.0.0.1", 0), H)
open(log + ".port", "w").write(str(s.server_port))
s.serve_forever()
PY
LOOPS='[{"loop": "verify", "probes": 2, "caught": 2, "missed": 0, "not_run": 0, "failed": 0, "no_data": 0, "judge": 0},
        {"loop": "property-scout", "probes": 2, "caught": 1, "missed": 0, "not_run": 0, "failed": 1, "no_data": 0, "judge": 0},
        {"loop": "ci-fix", "probes": 2, "caught": 0, "missed": 0, "not_run": 2, "failed": 0, "no_data": 0, "judge": 0},
        {"loop": "tests", "probes": 2, "caught": 0, "missed": 2, "not_run": 0, "failed": 0, "no_data": 0, "judge": 0}]'
PROBES='[{"probe_id": "probe-2", "pr": 69, "kind": "dropped-alternative", "loud": false, "file": "bin/commit-gate", "caught": 4, "ran": 6, "scored_at": "2026-11-25T17:09:30+00:00"},
         {"probe_id": "probe-1", "pr": 68, "kind": "off|by\none", "loud": true, "file": "bin/pr-size", "caught": 2, "ran": 5, "scored_at": "2026-11-25T14:31:55+00:00"}]'
answers() {  # LOOPS_STATUS PROBES_STATUS
  printf '{"/rest/v1/rpc/probe_report_loops": {"status": %s, "body": %s}, "/rest/v1/rpc/probe_report_probes": {"status": %s, "body": %s}}' \
    "$1" "$LOOPS" "$2" "$PROBES" > "$T/answers.json"
}
answers 200 200
python3 -I "$T/server.py" "$T/log" "$T/answers.json" & srv=$!
trap 'kill "$srv" 2>/dev/null; [ -n "${KEEP:-}" ] || rm -rf "$T"' EXIT
for _ in $(seq 300); do [ -s "$T/log.port" ] && break; sleep 0.1; done
[ -s "$T/log.port" ] || { echo "the stand-in server did not start in 30 seconds"; exit 1; }
URL="http://127.0.0.1:$(cat "$T/log.port")"
report() {  # args... -> $rc, stdout in $T/out, stderr in $T/err
  : > "$T/log"
  env AGENT_TRANSCRIPTS_URL="${U-$URL}" AGENT_TRANSCRIPTS_INSERT_KEY="${K-sb_publishable_test}" \
    "${PR[@]}" "$@" > "$T/out" 2> "$T/err"; rc=$?
}

it "it calls the two report functions with the insert key, and nothing else"
report; assert_eq 0 "$rc"
assert_eq "/rest/v1/rpc/probe_report_loops /rest/v1/rpc/probe_report_probes" "$(python3 -I -c 'import json,sys; print(" ".join(json.loads(l)["path"] for l in open(sys.argv[1])))' "$T/log")"
assert_eq "sb_publishable_test sb_publishable_test" "$(python3 -I -c 'import json,sys; print(" ".join(json.loads(l)["apikey"] for l in open(sys.argv[1])))' "$T/log")"
assert_eq '{"max_rows": 12}' "$(python3 -I -c 'import json,sys; print(json.dumps([json.loads(l) for l in open(sys.argv[1])][1]["body"]))' "$T/log")"
it "the loop table gives each loop's catches of the probes it ran on, worst first, and says which did not run"
out="$(cat "$T/out")"
has "$out" "| Loop | Caught | Ran on | Missed | Not run | Failed | Judge |"
has "$out" "| verify | 2 of 2 (100%) | 2 | 0 | 0 | 0 | 0 |"
has "$out" "| property-scout | 1 of 1 (100%) | 1 | 0 | 0 | 1 | 0 |"
has "$out" "| tests | 0 of 2 (0%) | 2 | 2 | 0 | 0 | 0 |"
has "$out" "| ci-fix | none ran | 0 | 0 | 2 | 0 | 0 |"
assert_eq "tests property-scout verify ci-fix" "$(printf '%s\n' "$out" | sed -n 's/^| \([a-z-]*\) | .* |$/\1/p' | grep -vE '^(probe|Loop)' | head -4 | tr '\n' ' ' | sed 's/ $//')"
it "the header counts the probes; the probe list is newest first, its cells escaped"
has "$out" "2 probes scored"
has "$out" "| #69 | dropped-alternative | silent | \`bin/commit-gate\` | 4 of 6 |"
has "$out" '| #68 | off\|by one | loud | `bin/pr-size` | 2 of 5 |'
l69="$(printf '%s\n' "$out" | grep -n '| #69 |' | cut -d: -f1)"; l68="$(printf '%s\n' "$out" | grep -n '| #68 |' | cut -d: -f1)"
[ -n "$l69" ] && [ -n "$l68" ] && [ "$l69" -lt "$l68" ] && ok || bad "not newest first: #69 at [$l69], #68 at [$l68]"
it "--max sets how many probes are listed, within 1 to 100"
report --max 3; assert_eq '{"max_rows": 3}' "$(python3 -I -c 'import json,sys; print(json.dumps([json.loads(l) for l in open(sys.argv[1])][1]["body"]))' "$T/log")"
report --max 0; assert_eq 2 "$rc"; report --max 101; assert_eq 2 "$rc"; report --max x; assert_eq 2 "$rc"
it "no probe scored yet is said plainly"
LOOPS='[]' PROBES='[]' answers 200 200; LOOPS='[]'; PROBES='[]'; answers 200 200; report; assert_eq 0 "$rc"
has "$(cat "$T/out")" "No probe has been scored yet."
LOOPS='[{"loop": "verify", "probes": 2, "caught": 2, "missed": 0, "not_run": 0, "failed": 0, "no_data": 0, "judge": 0}]'
it "a refusal fails, shows the answer without the key, and a redirect is not followed"
answers 500 200; report; assert_eq 1 "$rc"; has "$(cat "$T/err")" "refused for"
grep -q 'sb_publishable_test' "$T/err" "$T/out" && bad "printed the key" || ok
answers 302 200; report; assert_eq 1 "$rc"; grep -q redirected "$T/log" && bad "followed the redirect" || ok
answers 200 200
it "the store must be https (or this machine), and both settings are needed"
U="http://example.com" report; assert_eq 2 "$rc"; U="" report; assert_eq 2 "$rc"; K="" report; assert_eq 2 "$rc"
assert_eq 0 "$(grep -c . "$T/log")"

it "this test runs in CI"
grep -qF 'bash bin/probe-report.test.sh' "$here/../.github/workflows/test.yml" && ok || bad "not in test.yml"

echo; echo "passed=$pass failed=$fail"
[ "$fail" -eq 0 ]
