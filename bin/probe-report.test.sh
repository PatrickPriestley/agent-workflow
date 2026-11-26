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
import datetime as dt, http.server, json, sys
log, answers = sys.argv[1], sys.argv[2]
class H(http.server.BaseHTTPRequestHandler):
    def do_POST(self):
        body = self.rfile.read(int(self.headers.get("Content-Length", 0))).decode()
        with open(log, "a") as f:
            f.write(json.dumps({"path": self.path, "apikey": self.headers.get("apikey"), "body": json.loads(body or "null")}) + "\n")
        known, b = json.load(open(answers)), json.loads(body or "null")
        # an answer for PATH@DAYS is given when the body's since is DAYS days back
        since = b.get("since") if isinstance(b, dict) else None
        age = round((dt.datetime.now(dt.timezone.utc) - dt.datetime.fromisoformat(since)).total_seconds() / 86400) if since else None
        a = known.get(f"{self.path}@{age}") or known.get(self.path, {"status": 404, "body": []})
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
HEALTH='[{"agent": "verify-pr-claims", "runs": 2, "calls": 40, "refused": 12, "errors": 1},
         {"agent": "ci-diagnosis", "runs": 5, "calls": 80, "refused": 15, "errors": 0}]'
REFUSED='[{"agent": "ci-diagnosis", "tool": "Bash", "command": "bash bin/probe-store.test.sh", "times": 4},
          {"agent": "verify-pr-claims", "tool": "Bash", "command": "source <(grep `x` bin/a|b)", "times": 2}]'
USAGE='[{"skill": "change-record:change", "plugin": "change-record", "sessions": 1, "sessions_all": 6, "local": 2, "cloud": 4, "agent": 0, "dispatch": 0},
        {"skill": "claude-api", "plugin": null, "sessions": 0, "sessions_all": 1, "local": 0, "cloud": 1, "agent": 0, "dispatch": 0}]'
EFFORT='[{"who": "ci-diagnosis", "sessions": 5, "measured": 4, "calls": 40, "input_tokens": 40, "output_tokens": 8000, "cache_read_tokens": 360, "cache_write_tokens": 0, "tool_calls": 60, "text_chars": 4000, "posted_chars": 6000, "cost_usd": 2.0, "costed": 4},
        {"who": "local", "sessions": 2, "measured": 2, "calls": 30, "input_tokens": 10, "output_tokens": 3000, "cache_read_tokens": 0, "cache_write_tokens": 0, "tool_calls": 20, "text_chars": 900, "posted_chars": 0, "cost_usd": null, "costed": 0},
        {"who": "triage", "sessions": 1, "measured": 1, "calls": 1, "input_tokens": 1, "output_tokens": 1, "cache_read_tokens": 0, "cache_write_tokens": 0, "tool_calls": 1, "text_chars": 1, "posted_chars": 1, "cost_usd": 0.1, "costed": 1},
        {"who": "verify-pr-claims", "sessions": 2, "measured": 0, "calls": 0, "input_tokens": 0, "output_tokens": 0, "cache_read_tokens": 0, "cache_write_tokens": 0, "tool_calls": 0, "text_chars": 0, "posted_chars": 0, "cost_usd": null, "costed": 0}]'
WEEK='[]'; FIVE='[]'
GRADES='[{"skill": "change-record:change", "step": "red-first", "sessions": 9, "pass": 5, "fail": 3, "not_applicable": 1, "last_graded": "2020-01-02T00:00:00+00:00"},
         {"skill": "change-record:change", "step": "tier-declared", "sessions": 9, "pass": 9, "fail": 0, "not_applicable": 0, "last_graded": "2020-01-02T00:00:00+00:00"}]'
answers() {  # LOOPS_STATUS PROBES_STATUS [HEALTH_STATUS]
  printf '{"/rest/v1/rpc/probe_report_loops": {"status": %s, "body": %s}, "/rest/v1/rpc/probe_report_probes": {"status": %s, "body": %s},
           "/rest/v1/rpc/agent_health": {"status": %s, "body": %s}, "/rest/v1/rpc/agent_refused_commands": {"status": 200, "body": %s},
           "/rest/v1/rpc/skill_usage": {"status": 200, "body": %s}, "/rest/v1/rpc/skill_grades": {"status": 200, "body": %s},
           "/rest/v1/rpc/session_effort": {"status": 200, "body": %s}, "/rest/v1/rpc/session_effort@7": {"status": 200, "body": %s},
           "/rest/v1/rpc/session_effort@35": {"status": 200, "body": %s}}' \
    "$1" "$LOOPS" "$2" "$PROBES" "${3:-200}" "$HEALTH" "$REFUSED" "$USAGE" "$GRADES" "$EFFORT" "$WEEK" "$FIVE" > "$T/answers.json"
}
answers 200 200
python3 -I "$T/server.py" "$T/log" "$T/answers.json" & srv=$!
trap 'kill "$srv" 2>/dev/null; [ -n "${KEEP:-}" ] || rm -rf "$T"' EXIT
for _ in $(seq 300); do [ -s "$T/log.port" ] && break; sleep 0.1; done
[ -s "$T/log.port" ] || { echo "the stand-in server did not start in 30 seconds"; exit 1; }
URL="http://127.0.0.1:$(cat "$T/log.port")"
report() {  # args... (with --repo o/r unless ALL=1) -> $rc, stdout in $T/out, stderr in $T/err
  : > "$T/log"; local only=(--repo o/r); [ -z "${ALL:-}" ] || only=()  # ALL=1: every repository
  env AGENT_TRANSCRIPTS_URL="${U-$URL}" AGENT_TRANSCRIPTS_INSERT_KEY="${K-sb_publishable_test}" \
    "${PR[@]}" ${only[@]+"${only[@]}"} "$@" > "$T/out" 2> "$T/err"; rc=$?
}

it "it calls the seven report functions with the insert key, and nothing else"
report; assert_eq 0 "$rc"
assert_eq "/rest/v1/rpc/probe_report_loops /rest/v1/rpc/probe_report_probes /rest/v1/rpc/agent_health /rest/v1/rpc/agent_refused_commands /rest/v1/rpc/skill_usage /rest/v1/rpc/skill_grades /rest/v1/rpc/session_effort /rest/v1/rpc/session_effort /rest/v1/rpc/session_effort" "$(python3 -I -c 'import json,sys; print(" ".join(json.loads(l)["path"] for l in open(sys.argv[1])))' "$T/log")"
assert_eq "sb_publishable_test" "$(python3 -I -c 'import json,sys; print(" ".join(sorted({json.loads(l)["apikey"] for l in open(sys.argv[1])})))' "$T/log")"
assert_eq '{"max_rows": 12, "repo": "o/r"}' "$(python3 -I -c 'import json,sys; print(json.dumps([json.loads(l) for l in open(sys.argv[1])][1]["body"]))' "$T/log")"
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
it "agent health: runs, calls, the share of calls refused, worst first, and the commands refused most"
has "$out" "## Agent health, last 7 days"
has "$out" "| ci-diagnosis | 5 | 80 | 15 (19%) | 0 |"
has "$out" "| verify-pr-claims | 2 | 40 | 12 (30%) | 1 |"
lci="$(printf '%s\n' "$out" | grep -n '| ci-diagnosis | 5 |' | head -1 | cut -d: -f1)"; lvp="$(printf '%s\n' "$out" | grep -n '| verify-pr-claims | 2 |' | head -1 | cut -d: -f1)"
[ -n "$lci" ] && [ -n "$lvp" ] && [ "$lvp" -lt "$lci" ] && ok || bad "not the highest refused share first"
has "$out" "| ci-diagnosis | Bash | \`bash bin/probe-store.test.sh\` | 4 |"
has "$out" "| verify-pr-claims | Bash | \`source <(grep 'x' bin/a\\|b)\` | 2 |"
it "since is the last 7 days, and --days changes it"
python3 -I -c '
import json, sys, datetime as dt
calls = [json.loads(l) for l in open(sys.argv[1])]
since = dt.datetime.fromisoformat(calls[2]["body"]["since"])
age = dt.datetime.now(dt.timezone.utc) - since
assert dt.timedelta(days=6, hours=23) < age < dt.timedelta(days=7, hours=1), age
assert calls[3]["body"]["since"] == calls[2]["body"]["since"] == calls[4]["body"]["since"] and calls[3]["body"]["max_rows"] == 50
assert calls[5]["body"] == calls[0]["body"] == {"repo": "o/r"}, calls[5]
assert all(c["body"]["repo"] == "o/r" for c in calls), calls
' "$T/log" && ok || bad "$(cat "$T/log")"
report --days 30; has "$(cat "$T/out")" "## Agent health, last 30 days"
python3 -I -c '
import json, sys, datetime as dt
since = dt.datetime.fromisoformat([json.loads(l) for l in open(sys.argv[1])][2]["body"]["since"])
age = dt.datetime.now(dt.timezone.utc) - since
assert dt.timedelta(days=29, hours=23) < age < dt.timedelta(days=30, hours=1), age
' "$T/log" && ok || bad "--days 30 did not move since"
report --max 3 --max 4; assert_eq 2 "$rc"
report --days 0; assert_eq 2 "$rc"; report --days 400; assert_eq 2 "$rc"
it "skills and plugins: use per skill, by where it ran, and grades per step with their age"
has "$out" "## Skills and plugins"
has "$out" "| change-record:change | change-record | 1 | 6 | 2 | 4 | 0 | 0 |"
has "$out" "| claude-api | (none) | 0 | 1 | 0 | 1 | 0 | 0 |"
has "$out" "| change-record:change | red-first | 9 | 5 (62%) | 3 | 1 |"
has "$out" "| change-record:change | tier-declared | 9 | 9 (100%) | 0 | 0 |"
has "$out" "last graded 2020-01-02"
printf "%s" "$out" | grep -qi "grading runs by hand" && ok || bad "no note that grading is by hand"
it "no agent run, and no skill used, are said plainly"
HEALTH='[]'; REFUSED='[]'; USAGE='[]'; GRADES='[]'; answers 200 200; report; o="$(cat "$T/out")"
has "$o" "No agent ran in the last 7 days."; has "$o" "No session has used a skill yet."
HEALTH='[{"agent": "verify-pr-claims", "runs": 2, "calls": 40, "refused": 6, "errors": 1}]'; REFUSED='[]'
USAGE='[{"skill": "claude-api", "plugin": null, "sessions": 0, "sessions_all": 1, "local": 0, "cloud": 1, "agent": 0, "dispatch": 0}]'
GRADES='[]'; answers 200 200; report; has "$(cat "$T/out")" "No command was refused."; has "$(cat "$T/out")" "No skill has been graded yet."
answers 200 200
it "suggested changes: refused calls grouped by what the agent tried, each with one candidate change, most first"
REFUSED='[{"agent": "ci-diagnosis", "tool": "Bash", "command": "cd /x && ls", "times": 2},
          {"agent": "ci-diagnosis", "tool": "Bash", "command": "cat a.json | head", "times": 1},
          {"agent": "ci-diagnosis", "tool": "Bash", "command": "export TMPDIR=/t; bash x.sh", "times": 1},
          {"agent": "ci-diagnosis", "tool": "Bash", "command": "bash /tmp/gh-aw/agent/ci/head/bin/new.test.sh", "times": 1},
          {"agent": "verify-pr-claims", "tool": "Bash", "command": "safeoutputs add_comment {}", "times": 1},
          {"agent": "verify-pr-claims", "tool": "Bash", "command": "cd /home/runner/work", "times": 1},
          {"agent": "property-scout", "tool": "Bash", "command": "python3 -m venv /tmp/v", "times": 1},
          {"agent": "property-scout", "tool": "Bash", "command": "python3 -m venv /tmp/w", "times": 1},
          {"agent": "verify-pr-claims", "tool": "Bash", "command": "bash bin/commit-gate run commit-msg /tmp/m", "times": 1},
          {"agent": "verify-pr-claims", "tool": "Bash", "command": "bash /tmp/gh-aw/agent/verify/check.sh", "times": 1}]'
LOOPS='[{"loop": "verify", "probes": 3, "caught": 1, "missed": 2, "not_run": 0, "failed": 0, "no_data": 0, "judge": 0},
        {"loop": "property-scout", "probes": 3, "caught": 1, "missed": 0, "not_run": 0, "failed": 1, "no_data": 0, "judge": 1},
        {"loop": "tests", "probes": 3, "caught": 0, "missed": 3, "not_run": 0, "failed": 0, "no_data": 0, "judge": 0}]'
GRADES='[{"skill": "change-record:change", "step": "red-first", "sessions": 7, "pass": 4, "fail": 2, "not_applicable": 1, "last_graded": "2020-01-02T00:00:00+00:00"},
         {"skill": "change-record:change", "step": "code-quality", "sessions": 2, "pass": 1, "fail": 1, "not_applicable": 0, "last_graded": "2020-01-02T00:00:00+00:00"},
         {"skill": "change-record:change", "step": "tier-declared", "sessions": 7, "pass": 7, "fail": 0, "not_applicable": 0, "last_graded": "2020-01-02T00:00:00+00:00"}]'
answers 200 200; report; o="$(cat "$T/out")"
has "$o" "## Suggested changes"
grep -qi 'no model' "$T/out" && ok || bad "does not say how they were found"
sug="$(printf '%s\n' "$o" | sed -n '/^## Suggested changes/,$p')"
has "$sug" "| ci-diagnosis | 3 refused calls were compound commands (\`&&\`, \`;\`, pipes, \`\$(...)\`), such as \`cd /x && ls\` |"
has "$sug" "one plain command per call"
has "$sug" "| ci-diagnosis | 1 refused call set an environment variable in the command, such as \`export TMPDIR=/t; bash x.sh\` |"
has "$sug" "| ci-diagnosis | 1 refused call ran a test file not on main's allowlist, such as \`bash /tmp/gh-aw/agent/ci/head/bin/new.test.sh\` |"
has "$sug" "| verify-pr-claims | 1 refused call ran \`bin/commit-gate\`, a tool not on its allowlist, such as \`bash bin/commit-gate run commit-msg /tmp/m\` |"
has "$sug" 'Allow `bash bin/commit-gate:*`'
has "$sug" "| verify-pr-claims | 1 refused call ran a script of its own, such as \`bash /tmp/gh-aw/agent/verify/check.sh\` |"
has "$sug" "not scripts it writes"
printf '%s' "$sug" | grep -q 'Allow `bash`' && bad "suggested allowing bash itself" || ok
has "$sug" "bin/agent-allowlists-sync"
has "$sug" "| verify-pr-claims | 1 refused call ran the \`safeoutputs\` command, such as \`safeoutputs add_comment {}\` |"
has "$sug" "| verify-pr-claims | 1 refused call began with \`cd\`, such as \`cd /home/runner/work\` |"
has "$sug" "| property-scout | 2 refused calls ran \`python3\`, not on its allowlist, such as \`python3 -m venv /tmp/v\` |"
l4="$(printf '%s\n' "$sug" | grep -n '3 refused calls' | cut -d: -f1)"; l2="$(printf '%s\n' "$sug" | grep -n '2 refused calls' | cut -d: -f1)"
[ -n "$l4" ] && [ -n "$l2" ] && [ "$l4" -lt "$l2" ] && ok || bad "refusals not most first"
lpy="$(printf '%s\n' "$sug" | grep -n 'ran `python3`' | cut -d: -f1)"; lenv="$(printf '%s\n' "$sug" | grep -n 'set an environment variable' | cut -d: -f1)"
[ -n "$lpy" ] && [ -n "$lenv" ] && [ "$lpy" -lt "$lenv" ] && ok || bad "a larger group of a later agent is not listed first"
it "suggested changes: a review loop that missed or failed probes, and a judge waiting; not tests missing silent probes"
has "$sug" "| verify | missed 2 of the 3 probes it ran on |"
has "$sug" "| property-scout | failed to run on 1 probe |"
has "$sug" "| property-scout | 1 verdict waits for a judge |"
printf '%s' "$sug" | grep -q '^| tests |' && bad "suggested something for tests missing silent probes" || ok
it "suggested changes: a skill step under 80% over at least 3 graded sessions, and old grading"
has "$sug" "| change-record:change | step red-first passes 4 of 6 graded sessions (67%) |"
printf '%s' "$sug" | grep -q 'code-quality' && bad "flagged a step with only 2 graded sessions" || ok
printf '%s' "$sug" | grep -q 'tier-declared' && bad "flagged a step at 100%" || ok
has "$sug" "| grading | last ran 2020-01-02"
it "suggested changes: none when nothing calls for one"
LOOPS='[{"loop": "verify", "probes": 2, "caught": 2, "missed": 0, "not_run": 0, "failed": 0, "no_data": 0, "judge": 0}]'
REFUSED='[]'; GRADES='[]'; answers 200 200; report
has "$(cat "$T/out")" "Nothing to suggest this week."
LOOPS='[{"loop": "verify", "probes": 2, "caught": 2, "missed": 0, "not_run": 0, "failed": 0, "no_data": 0, "judge": 0}]'
answers 200 200
it "the health functions failing fails the report too"
answers 200 200 500; report; assert_eq 1 "$rc"; answers 200 200
it "--max sets how many probes are listed, within 1 to 100"
report --max 3; assert_eq '{"max_rows": 3, "repo": "o/r"}' "$(python3 -I -c 'import json,sys; print(json.dumps([json.loads(l) for l in open(sys.argv[1])][1]["body"]))' "$T/log")"
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

it "--repo names the repository in the heading; a repo that is not owner/name is refused before any call"
report; has "$(cat "$T/out")" "## Review loops against planted bugs: o/r"
grep -q '^| Repository' "$T/out" && bad "a Repository column in one repository's report" || ok
for r in "o" "o/r/x" "o/r;x" "" "../o/r x"; do ALL=1 report --repo "$r"; assert_eq "2 0" "$rc $(grep -c . "$T/log")"; done
report --repo o/r; assert_eq 2 "$rc"  # given twice
ALL=1 report --repo Some.Owner/some_repo-2; assert_eq 0 "$rc"; has "$(cat "$T/out")" "planted bugs: Some.Owner/some_repo-2"

it "without --repo: every repository, none named in the call, a Repository column first in each table"
LOOPS='[{"repository": "a/one", "loop": "verify", "probes": 2, "caught": 1, "missed": 1, "not_run": 0, "failed": 0, "no_data": 0, "judge": 0},
        {"repository": "b/two", "loop": "verify", "probes": 3, "caught": 3, "missed": 0, "not_run": 0, "failed": 0, "no_data": 0, "judge": 0}]'
PROBES='[{"repository": "b/two", "probe_id": "probe-9", "pr": 4, "kind": "k", "loud": false, "file": "f", "caught": 1, "ran": 2, "scored_at": "2026-11-25T17:09:30+00:00"}]'
HEALTH='[{"repository": "a/one", "agent": "verify-pr-claims", "runs": 1, "calls": 10, "refused": 1, "errors": 0},
         {"repository": "b/two", "agent": "verify-pr-claims", "runs": 2, "calls": 10, "refused": 5, "errors": 0}]'
REFUSED='[{"repository": "b/two", "agent": "verify-pr-claims", "tool": "Bash", "command": "cd x", "times": 2},
          {"repository": "a/one", "agent": "verify-pr-claims", "tool": "Bash", "command": "cd y", "times": 1}]'
USAGE='[{"repository": "a/one", "skill": "s", "plugin": null, "sessions": 1, "sessions_all": 1, "local": 1, "cloud": 0, "agent": 0, "dispatch": 0}]'
GRADES='[{"repository": "b/two", "skill": "s", "step": "red-first", "sessions": 4, "pass": 1, "fail": 3, "not_applicable": 0, "last_graded": "2020-01-02T00:00:00+00:00"},
         {"repository": null, "skill": "s", "step": "tier-declared", "sessions": 1, "pass": 1, "fail": 0, "not_applicable": 0, "last_graded": "2020-01-02T00:00:00+00:00"}]'
answers 200 200; ALL=1 report; assert_eq 0 "$rc"; o="$(cat "$T/out")"
python3 -I -c '
import json, sys
calls = [json.loads(l) for l in open(sys.argv[1])]
assert not any("repo" in c["body"] for c in calls), calls
' "$T/log" && ok || bad "named a repo: $(cat "$T/log")"
has "$o" "## Review loops against planted bugs
"; has "$o" "5 probes scored"
has "$o" "| Repository | Loop | Caught | Ran on | Missed | Not run | Failed | Judge |"
has "$o" "|---|---|---|---|---|---|---|---|"
has "$o" "| a/one | verify | 1 of 2 (50%) | 2 | 1 | 0 | 0 | 0 |"; has "$o" "| b/two | verify | 3 of 3 (100%) | 3 | 0 | 0 | 0 | 0 |"
has "$o" "| Repository | Probe | PR | Kind | Planted | File | Caught |"; has "$o" "| b/two | probe-9 | #4 |"
has "$o" "| b/two | verify-pr-claims | 2 | 10 | 5 (50%) | 0 |"; has "$o" "| a/one | verify-pr-claims | 1 | 10 | 1 (10%) | 0 |"
has "$o" "| b/two | verify-pr-claims | Bash | \`cd x\` | 2 |"
has "$o" "| a/one | s | (none) | 1 | 1 | 1 | 0 | 0 | 0 |"
has "$o" "| b/two | s | red-first | 4 | 1 (25%) | 3 | 0 |"; has "$o" "| (none) | s | tier-declared | 1 |"
it "without --repo, each suggestion names its repository, and one agent in two is two suggestions"
sug="$(printf '%s\n' "$o" | sed -n '/^## Suggested changes/,$p')"
has "$sug" "| Repository | Where | What the data shows | Candidate change |"
has "$sug" "| a/one | verify | missed 1 of the 2 probes it ran on |"
has "$sug" "| b/two | s | step red-first passes 1 of 4 graded sessions (25%) |"
has "$sug" "| (all) | grading | last ran 2020-01-02"
has "$sug" "| b/two | verify-pr-claims | 2 refused calls began with \`cd\`"; has "$sug" "| a/one | verify-pr-claims | 1 refused call began with \`cd\`"

it "cost and effort: per run, over the sessions with counts, agents first; a source has no cost"
answers 200 200; report --days 30; o="$(cat "$T/out")"   # 30: the 7 and 35 day answers are the trend's
has "$o" "## Cost and effort, last 30 days"
has "$o" "| Agent or source | Runs | Cost | Model calls | Output tokens | Input tokens | Tool calls | Written | Posted |"
has "$o" "| ci-diagnosis | 4 of 5 | \$0.50 | 10.0 | 2,000 | 100 | 15.0 | 1,000 | 1,500 |"
has "$o" "| local | 2 | - | 15.0 | 1,500 | 5 | 10.0 | 450 | 0 |"
printf '%s' "$o" | grep -q '^| verify-pr-claims | 0' && bad "listed an agent with no counted run" || ok
lci="$(printf '%s\n' "$o" | grep -n '^| ci-diagnosis | 4 of 5' | cut -d: -f1)"; llo="$(printf '%s\n' "$o" | grep -n '^| local | 2 |' | cut -d: -f1)"
ltr="$(printf '%s\n' "$o" | grep -n '^| triage | 1 |' | cut -d: -f1)"
[ -n "$lci" ] && [ -n "$llo" ] && [ -n "$ltr" ] && [ "$lci" -lt "$llo" ] && [ "$ltr" -lt "$llo" ] && ok || bad "agents not first"
python3 -I -c '
import json, sys
calls = [json.loads(l) for l in open(sys.argv[1])]
e = [c["body"] for c in calls if c["path"] == "/rest/v1/rpc/session_effort"]
assert len(e) == 3 and all(b["repo"] == "o/r" for b in e) and e[0]["since"] == calls[2]["body"]["since"], e
' "$T/log" && ok || bad "$(cat "$T/log")"
it "cost and effort: none counted yet is said plainly"
EFFORT='[]'; answers 200 200; report --days 30; has "$(cat "$T/out")" "No session with effort counts yet"
it "suggested changes: an agent whose cost or posting per run rose by half, the last 7 days against the 28 before"
EFFORT='[]'
WEEK='[{"who": "ci-diagnosis", "sessions": 3, "measured": 3, "calls": 30, "input_tokens": 0, "output_tokens": 3000, "cache_read_tokens": 0, "cache_write_tokens": 0, "tool_calls": 30, "text_chars": 0, "posted_chars": 3000, "cost_usd": 3.0, "costed": 3},
       {"who": "verify-pr-claims", "sessions": 3, "measured": 3, "calls": 30, "input_tokens": 0, "output_tokens": 3000, "cache_read_tokens": 0, "cache_write_tokens": 0, "tool_calls": 30, "text_chars": 0, "posted_chars": 300, "cost_usd": null, "costed": 0},
       {"who": "local", "sessions": 3, "measured": 3, "calls": 30, "input_tokens": 0, "output_tokens": 9000, "cache_read_tokens": 0, "cache_write_tokens": 0, "tool_calls": 30, "text_chars": 0, "posted_chars": 0, "cost_usd": null, "costed": 0},
       {"who": "property-scout", "sessions": 2, "measured": 2, "calls": 30, "input_tokens": 0, "output_tokens": 9000, "cache_read_tokens": 0, "cache_write_tokens": 0, "tool_calls": 30, "text_chars": 0, "posted_chars": 0, "cost_usd": 9.0, "costed": 2}]'
FIVE='[{"who": "ci-diagnosis", "sessions": 7, "measured": 7, "calls": 50, "input_tokens": 0, "output_tokens": 7000, "cache_read_tokens": 0, "cache_write_tokens": 0, "tool_calls": 50, "text_chars": 0, "posted_chars": 5000, "cost_usd": 5.0, "costed": 7},
       {"who": "verify-pr-claims", "sessions": 7, "measured": 7, "calls": 50, "input_tokens": 0, "output_tokens": 5000, "cache_read_tokens": 0, "cache_write_tokens": 0, "tool_calls": 50, "text_chars": 0, "posted_chars": 700, "cost_usd": null, "costed": 0},
       {"who": "local", "sessions": 7, "measured": 7, "calls": 50, "input_tokens": 0, "output_tokens": 10000, "cache_read_tokens": 0, "cache_write_tokens": 0, "tool_calls": 50, "text_chars": 0, "posted_chars": 0, "cost_usd": null, "costed": 0},
       {"who": "property-scout", "sessions": 6, "measured": 6, "calls": 50, "input_tokens": 0, "output_tokens": 10000, "cache_read_tokens": 0, "cache_write_tokens": 0, "tool_calls": 50, "text_chars": 0, "posted_chars": 0, "cost_usd": 10.0, "costed": 6}]'
answers 200 200; report; sug="$(sed -n '/^## Suggested changes/,$p' "$T/out")"
has "$sug" "| ci-diagnosis | cost per run rose from \$0.50 to \$1.00, the last 7 days against the 28 before |"
has "$sug" "| ci-diagnosis | posted characters per run rose from 500 to 1,000, the last 7 days against the 28 before |"
has "$sug" "how long its comment should be"
has "$sug" "| verify-pr-claims | output tokens per run rose from 500 to 1,000"
printf '%s' "$sug" | grep -q '^| local |' && bad "a source is not an agent to change" || ok
printf '%s' "$sug" | grep -q '^| property-scout |' && bad "flagged an agent with fewer than 3 runs this week" || ok
WEEK='[]'; FIVE='[]'; answers 200 200

it "this test runs in CI"
grep -qF 'bash bin/probe-report.test.sh' "$here/../.github/workflows/test.yml" && ok || bad "not in test.yml"

echo; echo "passed=$pass failed=$fail"
[ "$fail" -eq 0 ]
