#!/usr/bin/env bash
# Tests for bin/refusal-improve: rules for the agents' refused shell calls, added to their
# prompts; allowlists never edited; the rules already on main measured. A stand-in store answers
# agent_refused_commands and agent_health from timed events; a sandbox repository holds the
# workflow sources.
#   bash bin/refusal-improve.test.sh
set -u
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
pass=0; fail=0; CURRENT=""
it() { CURRENT="$1"; }
ok()  { pass=$((pass+1)); printf '  ok   %s\n' "$CURRENT"; }
bad() { fail=$((fail+1)); printf '  FAIL %s\n       %s\n' "$CURRENT" "$1"; }
assert_eq() { [ "$1" = "$2" ] && ok || bad "expected [$1] got [$2]"; }
has() { printf '%s' "$1" | grep -qF -- "$2" && ok || bad "missing [$2] in: $(printf '%s' "$1" | head -c 700)"; }
lacks() { printf '%s' "$1" | grep -qF -- "$2" && bad "found [$2]" || ok; }
T="$(mktemp -d "${TMPDIR:-/tmp}/refusal-improve.XXXXXX")"
cat > "$T/server.py" <<'PY'
# Answers agent_refused_commands and agent_health from events.json: {"refused": [{agent, command,
# at}], "runs": [{agent, at}]}, counting the events at or after the body's since, as the store's
# functions count sessions started since then. Logs each call's body.
import http.server, json, sys
log, events = sys.argv[1], sys.argv[2]
class H(http.server.BaseHTTPRequestHandler):
    def do_POST(self):
        body = json.loads(self.rfile.read(int(self.headers.get("Content-Length", 0))) or b"{}")
        with open(log, "a") as f:
            f.write(json.dumps({"path": self.path, "body": body}) + "\n")
        ev = json.load(open(events))
        if ev.get("fail"):
            self.send_response(500); self.end_headers(); self.wfile.write(b'{"message": "no"}'); return
        since = body.get("since", "")
        if self.path.endswith("/agent_refused_commands"):
            counts = {}
            for e in ev["refused"]:
                if e["at"] >= since:
                    k = (e["agent"], e["command"]); counts[k] = counts.get(k, 0) + 1
            out = [{"repository": "o/r", "agent": a, "tool": "Bash", "command": c, "times": n} for (a, c), n in counts.items()]
            out = sorted(out, key=lambda r: -r["times"])[:body.get("max_rows", 10)]
        elif self.path.endswith("/agent_health"):
            runs = {}
            for e in ev["runs"]:
                if e["at"] >= since:
                    runs[e["agent"]] = runs.get(e["agent"], 0) + 1
            out = [{"repository": "o/r", "agent": a, "runs": n, "calls": 10 * n, "refused": 0, "errors": 0} for a, n in runs.items()]
        else:
            self.send_response(404); self.end_headers(); self.wfile.write(b"[]"); return
        self.send_response(200); self.end_headers(); self.wfile.write(json.dumps(out).encode())
    def log_message(self, *a): pass
s = http.server.HTTPServer(("127.0.0.1", 0), H)
open(log + ".port", "w").write(str(s.server_port))
s.serve_forever()
PY
echo '{"refused": [], "runs": []}' > "$T/events.json"
python3 -I "$T/server.py" "$T/log" "$T/events.json" & srv=$!
trap 'kill "$srv" 2>/dev/null; [ -n "${KEEP:-}" ] || rm -rf "$T"' EXIT
for _ in $(seq 300); do [ -s "$T/log.port" ] && break; sleep 0.1; done
[ -s "$T/log.port" ] || { echo "the stand-in store did not start in 30 seconds"; exit 1; }
URL="http://127.0.0.1:$(cat "$T/log.port")"

events() {  # python expressions building the events file: R(agent, command, at), N(agent, at)
  python3 -I - "$T/events.json" "$@" <<'PY'
import json, sys
ev = {"refused": [], "runs": []}
R = lambda a, c, at: ev["refused"].append({"agent": a, "command": c, "at": at})
N = lambda a, at: ev["runs"].append({"agent": a, "at": at})
for x in sys.argv[2:]:
    eval(x)
json.dump(ev, open(sys.argv[1], "w"))
PY
}
source_md() {  # NAME -> a workflow source with frontmatter, an allowlist and a prompt
  printf -- '---\nname: %s\ntools:\n  bash:\n    - "cat:*"\n---\n\n# Do the work\n\n## Assigned commands\n\nRead files.\n' "$1"
}
repo() {  # a fresh sandbox repository, two agent sources and one that is not an agent's
  R="$T/repo"; rm -rf "$R"; mkdir -p "$R/.github/workflows"
  git -C "$R" init -q -b main; git -C "$R" config user.email t@t; git -C "$R" config user.name t
  source_md "CI diagnosis" > "$R/.github/workflows/ci-diagnose.md"
  source_md "Verify PR claims" > "$R/.github/workflows/verify.md"
  printf 'name: test\non: push\n' > "$R/.github/workflows/test.yml"
  git -C "$R" add -A; GIT_COMMITTER_DATE=2026-10-01T00:00:00Z git -C "$R" commit -q -m base
}
improve() {  # [args] -> $rc; stdout in $T/out, stderr in $T/err, the body in $T/body.md
  : > "$T/log"; rm -f "$T/body.md"
  AGENT_TRANSCRIPTS_URL="${U-$URL}" AGENT_TRANSCRIPTS_INSERT_KEY="${K-sb_publishable_test}" \
    python3 -I "$here/refusal-improve" --repo o/r --root "$R" --now "${NOW:-2026-11-26T00:00:00Z}" --body "$T/body.md" "$@" \
    > "$T/out" 2> "$T/err"; rc=$?
}
CD=.github/workflows/ci-diagnose.md
D1=2026-11-10T00:00:00Z; D2=2026-11-20T00:00:00Z
standard() {
  events "R('ci-diagnosis', 'cat a | head', '$D1')" "R('ci-diagnosis', 'ls x && cat y', '$D2')" \
         "R('ci-diagnosis', 'safeoutputs add_comment {}', '$D2')" "R('ci-diagnosis', 'git -C x log', '$D1')" \
         "R('ci-diagnosis', 'git -C x log', '$D2')" "R('verify-pr-claims', 'cd /home/runner', '$D2')" \
         "R('nobody-here', 'cat a | head', '$D2')" "R('nobody-here', 'cat b | head', '$D2')" \
         "N('ci-diagnosis', '$D1')" "N('ci-diagnosis', '$D2')"
}

it "without --write: it says which sources it would change, and changes none"
repo; standard; before="$(cat "$R/$CD")"; improve; assert_eq 0 "$rc"
assert_eq "$CD" "$(cat "$T/out")"; assert_eq "$before" "$(cat "$R/$CD")"
body="$(cat "$T/body.md")"
has "$body" "## Rules added to the agents' prompts"
has "$body" "| ci-diagnosis | 2 | \`cat a \\| head\` | Every command in a call must be one of your assigned commands"
it "it reads the repository's refusals of the last 28 days, with the publishable key, and calls no model"
python3 -I -c '
import json, sys
calls = [json.loads(l) for l in open(sys.argv[1])]
first = calls[0]
assert first["path"] == "/rest/v1/rpc/agent_refused_commands", first
assert first["body"]["repo"] == "o/r" and first["body"]["since"].startswith("2026-10-29"), first
assert all(c["path"] in ("/rest/v1/rpc/agent_refused_commands", "/rest/v1/rpc/agent_health") for c in calls), calls
' "$T/log" && ok || bad "$(cat "$T/log")"
has "$body" "no model is involved"

it "--write adds a rule per kind refused at least twice, at the end of the prompt, and leaves the rest as it was"
repo; standard; before="$(cat "$R/$CD")"; improve --write; assert_eq "0 $CD" "$rc $(cat "$T/out")"
after="$(cat "$R/$CD")"
assert_eq "$before" "$(printf '%s\n' "$after" | head -n "$(printf '%s\n' "$before" | wc -l)")"
has "$after" "## Shell calls"; has "$after" "<!-- rule: compound -->"
lacks "$after" "<!-- rule: safeoutputs -->"   # refused once only
lacks "$after" "git -C"                       # an allowlist candidate, never a rule
assert_eq 1 "$(grep -c 'BEGIN refusal-improver' "$R/$CD")"
it "the frontmatter and the allowlist are never touched"
assert_eq "$(sed -n '1,/^---$/p' <<< "$before" | head -6)" "$(head -6 "$R/$CD")"
it "a refusal the prompt cannot fix is listed for a person, and edits nothing"
has "$(cat "$T/body.md")" "## For you to decide: allowlist candidates"
has "$(cat "$T/body.md")" "| ci-diagnosis | program | 2 | \`git -C x log\` |"
it "verify, refused once for cd, is not changed; an agent with no source here is said so"
assert_eq "$(source_md "Verify PR claims")" "$(cat "$R/.github/workflows/verify.md")"
has "$(cat "$T/err")" "nobody-here has refused calls but no workflow source"
it "running again adds nothing, and names no file"
improve --write; assert_eq "0 " "$rc $(cat "$T/out")"; assert_eq "$after" "$(cat "$R/$CD")"
it "--min 1 adds the rarer rules too, into the same section, in their fixed order"
improve --write --min 1; assert_eq 0 "$rc"
assert_eq 1 "$(grep -c 'BEGIN refusal-improver' "$R/$CD")"
assert_eq "compound safeoutputs" "$(grep -o 'rule: [a-z]*' "$R/$CD" | cut -d' ' -f2 | tr '\n' ' ' | sed 's/ $//')"
has "$(cat "$R/.github/workflows/verify.md")" "<!-- rule: cd -->"
it "a section that is not one BEGIN and one END stops it, and the file is left as it was"
printf '<!-- BEGIN refusal-improver: bin/refusal-improve keeps this section; it adds rules and removes none -->\n' >> "$R/.github/workflows/verify.md"
v="$(cat "$R/.github/workflows/verify.md")"; improve --write --min 1; assert_eq 1 "$rc"
has "$(cat "$T/err")" "not one BEGIN line followed by one END line"
assert_eq "$v" "$(cat "$R/.github/workflows/verify.md")"

it "a rule on main is measured: fewer refusals per run since it landed"
repo; events "R('ci-diagnosis', 'cat a | head', '$D1')"; improve --write --min 1; git -C "$R" add -A
GIT_COMMITTER_DATE=2026-11-12T00:00:00Z git -C "$R" commit -q -m "rules"
events "R('ci-diagnosis', 'cat a | head', '2026-11-01T00:00:00Z')" "R('ci-diagnosis', 'cat b | head', '2026-11-02T00:00:00Z')" \
       "N('ci-diagnosis', '2026-11-01T00:00:00Z')" "N('ci-diagnosis', '2026-11-02T00:00:00Z')" \
       "N('ci-diagnosis', '2026-11-15T00:00:00Z')" "N('ci-diagnosis', '2026-11-16T00:00:00Z')" "N('ci-diagnosis', '2026-11-17T00:00:00Z')"
improve; assert_eq 0 "$rc"
has "$(cat "$T/body.md")" "| ci-diagnosis | compound | 2026-11-12 | 2 in 2 runs | 0 in 3 runs | fewer |"
it "no better since it landed is said so"
events "R('ci-diagnosis', 'cat a | head', '2026-11-01T00:00:00Z')" "N('ci-diagnosis', '2026-11-01T00:00:00Z')" \
       "R('ci-diagnosis', 'cat c | head', '2026-11-15T00:00:00Z')" "R('ci-diagnosis', 'cat d | head', '2026-11-16T00:00:00Z')" \
       "N('ci-diagnosis', '2026-11-15T00:00:00Z')" "N('ci-diagnosis', '2026-11-16T00:00:00Z')" "N('ci-diagnosis', '2026-11-17T00:00:00Z')"
improve; has "$(cat "$T/body.md")" "| 1 in 1 runs | 2 in 3 runs | no better"
it "too few runs since is said so, not judged"
events "R('ci-diagnosis', 'cat a | head', '2026-11-01T00:00:00Z')" "N('ci-diagnosis', '2026-11-01T00:00:00Z')" "N('ci-diagnosis', '2026-11-15T00:00:00Z')"
improve; has "$(cat "$T/body.md")" "too few runs since to tell"
it "a rule merged from a branch counts from the merge into main, not from the branch's commit"
repo; events "R('ci-diagnosis', 'cat a | head', '$D1')"; git -C "$R" checkout -q -b chore/rules
improve --write --min 1; git -C "$R" add -A; GIT_COMMITTER_DATE=2026-11-05T00:00:00Z git -C "$R" commit -q -m rules
git -C "$R" checkout -q main; GIT_COMMITTER_DATE=2026-11-12T00:00:00Z git -C "$R" merge -q --no-ff -m merge chore/rules
events "R('ci-diagnosis', 'cat a | head', '2026-11-01T00:00:00Z')" "N('ci-diagnosis', '2026-11-01T00:00:00Z')"
improve; has "$(cat "$T/body.md")" "| ci-diagnosis | compound | 2026-11-12 |"
it "a rule only in the working tree, not yet on main, is not measured"
repo; events "R('ci-diagnosis', 'cat a | head', '$D1')" "R('ci-diagnosis', 'cat b | head', '$D1')"; improve --write
lacks "$(cat "$T/body.md")" "## Rules already in place"

it "nothing refused says so"
repo; events; improve; assert_eq "0 " "$rc $(cat "$T/out")"; has "$(cat "$T/body.md")" "No refused calls to act on."
it "a store that fails fails the run and changes nothing"
repo; echo '{"fail": true, "refused": [], "runs": []}' > "$T/events.json"; before="$(cat "$R/$CD")"
improve --write; assert_eq 1 "$rc"; assert_eq "$before" "$(cat "$R/$CD")"
it "usage: the repository, the numbers and the store's settings are checked first"
repo; standard
for a in "--days 0" "--min 0" "--days x" "--what" "--write --write"; do improve $a; assert_eq "2 0" "$rc $(grep -c . "$T/log")"; done
U="http://example.com" improve; assert_eq 2 "$rc"; K="" improve; assert_eq 2 "$rc"

it "this test runs in CI"
grep -qF 'bash bin/refusal-improve.test.sh' "$here/../.github/workflows/test.yml" && ok || bad "not in test.yml"

echo; echo "passed=$pass failed=$fail"
[ "$fail" -eq 0 ]
