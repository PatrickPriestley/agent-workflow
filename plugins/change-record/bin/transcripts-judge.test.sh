#!/usr/bin/env bash
# Tests for transcripts judge and transcripts report (record
# docs/changes/2026-11-09-skill-transcripts.md, R10, R11 and C3): the Haiku judge's two
# questions with three votes, malformed and refused answers not counted, votes and prompts kept
# per session, redaction of what a judge sees, the agreement judge against a stand-in for
# OpenCode, scores and votes to the store with the read key, and the report from known rows,
# labels and transcripts (record docs/changes/2026-11-11-grading-trust.md, R4 and R5).
# Stand-ins for `claude` and `opencode` answer from what the prompt holds. Fixtures use made-up
# addresses and tokens only. Needs bash, git and python3. TRANSCRIPTS_LIVE_JUDGE=1 also runs
# the real Haiku judge on the two known-answer sessions (needs `claude` logged in).
set -u
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
T="$here/transcripts"; STANDIN="$here/../store/stand-in.py"; RFIX="$here/../grade/fixtures/report"
REAL_PATH="$PATH"
# The real path, not a link to it: on macOS the temporary folder is /var/..., a link to /private/var/...,
# and git and python name the real one.
TMPROOT="$(cd "$(mktemp -d)" && pwd -P)"; PIDS=""
trap 'for p in $PIDS; do kill $p 2>/dev/null; done; rm -rf "$TMPROOT"' EXIT
# await_port FILE: wait for a stand-in to write its port; say so when it is slow or never does.
await_port() {
  local t=$SECONDS
  for _ in $(seq 600); do [ -s "$1" ] && break; sleep 0.05; done
  [ -s "$1" ] || echo "the stand-in wrote no port to $1 in $((SECONDS - t))s" >&2
  [ $((SECONDS - t)) -lt 5 ] || echo "the stand-in took $((SECONDS - t))s to listen" >&2
}
pass=0; fail=0; CURRENT=""
it() { CURRENT="$1"; }
ok()  { pass=$((pass+1)); printf '  ok   %s\n' "$CURRENT"; }
bad() { fail=$((fail+1)); printf '  FAIL %s\n       %s\n' "$CURRENT" "$1"; }
assert_eq()  { [ "$1" = "$2" ] && ok || bad "expected [$1] got [$2]"; }
has()  { printf '%s' "$1" | grep -qF -- "$2" && ok || bad "missing [$2] in: $(printf '%s' "$1" | head -c 900)"; }
lacks() { printf '%s' "$1" | grep -qF -- "$2" && bad "unexpected [$2] in: $(printf '%s' "$1" | head -c 900)" || ok; }

unset CLAUDE_CODE_REMOTE CLAUDE_CODE_REMOTE_SESSION_ID CLAUDE_CODE_CONTAINER_ID AGENT_TRANSCRIPTS AGENT_TRANSCRIPTS_PARENT AGENT_TRANSCRIPTS_URL
export no_proxy="127.0.0.1,localhost" NO_PROXY="127.0.0.1,localhost"
export XDG_CONFIG_HOME="$TMPROOT/config"; mkdir -p "$XDG_CONFIG_HOME/agent-transcripts"
printf 'machine-J\n' > "$XDG_CONFIG_HOME/agent-transcripts/machine-id"
READKEY="read-key-made-up-0003"
EMAIL="jane.doe@example.org"; TOKEN="abcdefghijklmnopqrstuv0123"

# ---- stand-ins for the two judges --------------------------------------------------------
# Each logs its call (argv, stdin, cwd, the variables that matter) to $FAKELOG and answers from
# the prompt: Decisions pass when they hold "Rejected", Outcome passes when it quotes a "$ "
# command. FAKE_SCRIPT, a comma list, overrides the answer call by call (see the modes below).
FAKEBIN="$TMPROOT/fakebin"; mkdir -p "$FAKEBIN"; FAKELOG="$TMPROOT/fake.log"; COUNTER="$TMPROOT/fake.n"
cat > "$FAKEBIN/judge.py" <<'PY'
import json, os, re, sys
kind = os.path.basename(sys.argv[0])
argv = sys.argv[1:]
prompt = sys.stdin.read() if kind == "claude" else (argv[-1] if argv else "")
cn = os.environ["FAKE_COUNTER"]
n = int(open(cn).read()) if os.path.exists(cn) else 0
open(cn, "w").write(str(n + 1))
script = [s for s in os.environ.get("FAKE_SCRIPT", "").split(",") if s]
mode = script[n] if n < len(script) else "content"
with open(os.environ["FAKELOG"], "a") as f:
    f.write(json.dumps({"kind": kind, "argv": argv, "prompt": prompt, "cwd": os.getcwd(), "mode": mode,
                        "AGENT_TRANSCRIPTS": os.environ.get("AGENT_TRANSCRIPTS"),
                        "OPENCODE_CONFIG_CONTENT": os.environ.get("OPENCODE_CONFIG_CONTENT"),
                        "OPENCODE_DISABLE_PROJECT_CONFIG": os.environ.get("OPENCODE_DISABLE_PROJECT_CONFIG")}) + "\n")
def section(tag):
    m = re.search(r"<%s>(.*?)</%s>" % (tag, tag), prompt, re.S)
    return m.group(1) if m else ""
if "<decisions>" in prompt:
    v = "pass" if "Rejected" in section("decisions") else "fail"
else:
    v = "pass" if re.search(r"^\s*\$ ", section("outcome"), re.M) else "fail"
js = json.dumps({"verdict": v, "reason": "the stand-in read the section"})
answers = {"content": js, "fenced": "```json\n" + js + "\n```", "prosejson": "I think so.\n" + js,
           "badverdict": json.dumps({"verdict": "maybe", "reason": "x"}), "malformed": "It passes, mostly.",
           "empty": "", "twojson": js + "\n" + js, "extrakeys": json.dumps({"verdict": v, "reason": "r", "score": 1})}
if kind == "opencode":
    if mode == "refused":
        print("I can't help with that.")
    elif mode == "error":
        print("Error: model not found", file=sys.stderr); sys.exit(1)
    else:
        print(answers.get(mode, js))
    sys.exit(0)
out = {"type": "result", "subtype": "success", "is_error": False, "stop_reason": "end_turn", "terminal_reason": "completed",
       "result": answers.get(mode, js), "modelUsage": {"claude-haiku-5-5": {"outputTokens": 20}}}
rc = 0
if mode == "refused":
    out.update(is_error=True, stop_reason="refusal", terminal_reason="api_error",
               result="API Error: Haiku 5.5 can't help with this. Start a new session to continue.")
    rc = 1
elif mode == "error":
    out.update(is_error=True, stop_reason="stop_sequence", terminal_reason="api_error", result="", modelUsage={})
    rc = 1
elif mode == "iserror":  # a well-formed answer, but the run says it failed
    out.update(is_error=True, terminal_reason="api_error")
    rc = 1
elif mode == "sonnet":
    out["modelUsage"] = {"claude-sonnet-5-5": {"outputTokens": 20}}
print(json.dumps(out))
sys.exit(rc)
PY
# judge.py reads which judge it stands in for from argv[0]
cat > "$FAKEBIN/claude" <<EOF
#!/bin/sh
exec python3 -c 'import sys; sys.argv[0]="claude"; exec(open("$FAKEBIN/judge.py").read())' "\$@"
EOF
cat > "$FAKEBIN/opencode" <<EOF
#!/bin/sh
exec python3 -c 'import sys; sys.argv[0]="opencode"; exec(open("$FAKEBIN/judge.py").read())' "\$@"
EOF
chmod +x "$FAKEBIN/claude" "$FAKEBIN/opencode"
export PATH="$FAKEBIN:$REAL_PATH" FAKELOG FAKE_COUNTER="$COUNTER"; : > "$FAKELOG"
# py: the inline checks; on the base a file they read is missing, which is a failed assertion, not a crash
py() { python3 "$@" 2>/dev/null; }
calls() { [ -f "$FAKELOG" ] && wc -l < "$FAKELOG" | tr -d ' ' || echo 0; }

# ---- a repository with three records -----------------------------------------------------
REPO="$TMPROOT/checkout"; mkdir -p "$REPO/docs/changes" "$REPO/tests"
record() {  # id decisions outcome
cat <<EOF
---
id: $1
tier: 1
status: done
requester: A Requester
---
# x

## Goal
x

## Probed facts
- Verified against the real system: x

## Decisions
$2

## Tasks
1. x

## Checks
x

## Outcome
$3
EOF
}
GOOD_DEC='- The flag is --shout. Rejected: an environment variable, because a flag shows in --help.'
GOOD_OUT="Ran it, for $EMAIL:

    \$ python3 greet.py --shout ann
    HELLO, ANN!
    \$ curl -H 'Authorization: Bearer $TOKEN' https://x.example.org/ok
    ok"
(
  cd "$REPO" && git init -q -b main && git config user.email t@example.com && git config user.name t
  git config core.hooksPath /dev/null
  printf 'def greet(n):\n    return n\n' > greet.py; printf 'import unittest\n' > tests/test_greet.py
  git add -A && git commit -qm init
  record 2026-11-10-good "$GOOD_DEC" "$GOOD_OUT" > docs/changes/2026-11-10-good.md
  record 2026-11-10-bad "- Use argparse for the flag." "All tests pass." > docs/changes/2026-11-10-bad.md
  record 2026-11-10-bare "- Parse the flag by hand. Rejected: argparse." "All tests pass." > docs/changes/2026-11-10-bare.md
  record 2026-11-10-empty "" "" | sed 's/^status: done/status: approved/' > docs/changes/2026-11-10-empty.md
  printf 'def greet(n):\n    return n.upper()\n' > greet.py
  git add -A && git commit -qm "feat: shout"
)
A="$(git -C "$REPO" rev-parse HEAD~1)"; C="$(git -C "$REPO" rev-parse HEAD)"

GEN="$TMPROOT/gen.py"; cat > "$GEN" <<'PY'
import json, sys
path, sid, cwd, hour = sys.argv[1:]
out, n = [], 0
for raw in sys.stdin:
    if not raw.strip():
        continue
    e = json.loads(raw)
    n += 1
    base = {"sessionId": sid, "timestamp": "2026-11-10T%s:%02d:%02d.000Z" % ((hour,) + divmod(n, 60)), "cwd": cwd, "gitBranch": "x"}
    if e[0] == "call":
        base.update(type="assistant", message={"role": "assistant", "content": [{"type": "tool_use", "id": e[1], "name": e[2], "input": e[3]}]})
    elif e[0] == "result":
        base.update(type="user", message={"role": "user", "content": [{"tool_use_id": e[1], "type": "tool_result", "content": e[2]}]})
    else:
        base.update(type="assistant", message={"role": "assistant", "content": [{"type": "text", "text": e[1]}]})
    out.append(json.dumps(base, separators=(",", ":")))
open(path, "w").write("\n".join(out) + "\n")
PY
W="$TMPROOT/sessions"; mkdir -p "$W"
# session SID HOUR RECORD CODE?: a made-up session that writes RECORD (or none), runs a failing
# test, then writes greet.py when CODE is yes, and runs its program
session() {
  { [ "$3" = none ] || printf '["call","w1","Write",{"file_path":"%s","content":"x"}]\n["result","w1","File created successfully",false]\n' "$REPO/docs/changes/$3"
    printf '["call","r1","Bash",{"command":"python3 -m unittest"}]\n["result","r1","FAILED (failures=1)",false]\n'
    [ "$4" = yes ] && printf '["call","c1","Write",{"file_path":"%s","content":"x"}]\n["result","c1","ok",false]\n' "$REPO/greet.py"
    printf '["call","p1","Bash",{"command":"python3 greet.py --shout ann"}]\n["result","p1","HELLO, ANN!",false]\n'
  } | python3 "$GEN" "$W/$1.jsonl" "$1" "$REPO" "$2"
}
J1=d1000000-0000-0000-0000-000000000001; J2=d2000000-0000-0000-0000-000000000002
J3=d3000000-0000-0000-0000-000000000003; J4=d4000000-0000-0000-0000-000000000004
J5=d5000000-0000-0000-0000-000000000005; J6=d6000000-0000-0000-0000-000000000006
session $J1 11 2026-11-10-good.md yes; session $J2 12 2026-11-10-bad.md yes
session $J3 13 2026-11-10-good.md no;  session $J4 14 none yes
session $J5 10 2026-11-10-empty.md yes; session $J6 09 2026-11-10-bare.md yes
# fresh AR SID...: an archive holding these sessions, stopped at commits A then C, graded
fresh() {
  local ar="$1"; shift
  for s in "$@"; do
    (cd "$TMPROOT" && AGENT_TRANSCRIPTS="$ar" "$T" archive --transcript "$W/$s.jsonl" < /dev/null > /dev/null 2>&1)
    python3 - "$ar/sessions/$s.json" "$A" "$C" <<'PY'
import json, sys
p, first, last = sys.argv[1:]
e = json.load(open(p)); e["first_stop"] = {"branch": "x", "commit": first}; e["last_stop"] = {"branch": "x", "commit": last}
json.dump(e, open(p, "w"), indent=2)
PY
  done
  (cd "$TMPROOT" && AGENT_TRANSCRIPTS="$ar" "$T" grade --repo-dir "$REPO" > /dev/null 2>&1)
}
judge() { (cd "$TMPROOT" && "$T" judge "$@" 2>&1); }
# jq-like helpers: jv FILE QUESTION -> the question's verdict; jst FILE QUESTION -> vote statuses
jv()  { python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["questions"][sys.argv[2]]["verdict"])' "$1" "$2" 2>/dev/null || echo none; }
jst() { python3 -c 'import json,sys; print(" ".join(v["status"] for v in json.load(open(sys.argv[1]))["questions"][sys.argv[2]]["votes"]))' "$1" "$2" 2>/dev/null || echo none; }
sv()  { python3 -c 'import json,sys; r=[x for x in json.load(open(sys.argv[1])) if x["step"]==sys.argv[2]]; print(r[0]["verdict"] if r else "none")' "$1" "$2" 2>/dev/null || echo no-file; }

echo "R10: the Haiku judge, three votes per question, sessions that changed code only"
AR="$TMPROOT/ar"; fresh "$AR" $J1 $J2 $J3 $J4 $J5
out="$(AGENT_TRANSCRIPTS="$AR" judge "$AR" --repo-dir "$REPO")"; rc=$?
it "judge exits 0"
assert_eq 0 "$rc"
it "a record with a rejected alternative and quoted runs gets pass on both questions (the known answer)"
assert_eq "pass pass" "$(jv "$AR/judges/$J1.claude.json" decisions-alternative) $(jv "$AR/judges/$J1.claude.json" outcome-real-output)"
it "a record with neither gets fail on both"
assert_eq "fail fail" "$(jv "$AR/judges/$J2.claude.json" decisions-alternative) $(jv "$AR/judges/$J2.claude.json" outcome-real-output)"
it "each question got three votes, each counted"
assert_eq "vote vote vote" "$(jst "$AR/judges/$J1.claude.json" decisions-alternative)"
it "a session that wrote no code is not judged, nor one with no record"
assert_eq "no no" "$([ -e "$AR/judges/$J3.claude.json" ] && echo yes || echo no) $([ -e "$AR/judges/$J4.claude.json" ] && echo yes || echo no)"
it "the summary says why they were not judged"
has "$out" "d3000000 not judged: no code written"
has "$out" "d4000000 not judged: no record"
it "a record not done, with empty Decisions, is decided without a judge: Decisions fail, Outcome not applicable"
assert_eq "fail not_applicable" "$(jv "$AR/judges/$J5.claude.json" decisions-alternative) $(jv "$AR/judges/$J5.claude.json" outcome-real-output)"
assert_eq "fail not_applicable" "$(sv "$AR/scores/$J5.judge.json" decisions-alternative) $(sv "$AR/scores/$J5.judge.json" outcome-real-output)"
it "twelve calls: two sessions, two questions, three votes"
assert_eq 12 "$(calls)"
it "each call is a fresh Haiku session with no tools, no saved session and no settings"
assert_eq "12" "$(py -c '
import json,sys
n=0
for l in open(sys.argv[1]):
    a=json.loads(l)["argv"]
    n += all(x in a for x in ("-p","--no-session-persistence","--output-format")) and a[a.index("--model")+1]=="haiku" and a[a.index("--tools")+1]=="" and a[a.index("--setting-sources")+1]==""
print(n)' "$FAKELOG")"
it "the judge runs outside the repository and without the archive variable, so its session is not captured"
assert_eq "False None" "$(py -c '
import json,sys
r=[json.loads(l) for l in open(sys.argv[1])]
print(any(x["cwd"].startswith(sys.argv[2]) for x in r), r[0]["AGENT_TRANSCRIPTS"])' "$FAKELOG" "$REPO")"
it "the Decisions prompt holds the record's Decisions"
has "$(cat "$FAKELOG" 2>/dev/null)" "Rejected: an environment variable"
it "the Outcome prompt lists the commands the session ran"
has "$(sed -n 4p "$FAKELOG")" 'python3 greet.py --shout ann'
it "nothing a judge sees is unredacted: no address, no token"
lacks "$(cat "$FAKELOG" 2>/dev/null)" "$EMAIL"
lacks "$(cat "$FAKELOG" 2>/dev/null)" "$TOKEN"
it "the redaction placeholders are what it sees instead"
has "$(cat "$FAKELOG" 2>/dev/null)" "<redacted:email>"
it "the prompt and votes are kept per session, redacted too"
p="$(py -c 'import json,sys; q=json.load(open(sys.argv[1]))["questions"]["outcome-real-output"]; print(q["prompt_sha256"], len(q["votes"]), q["votes"][0]["answer"][:12]); print(q["prompt"])' "$AR/judges/$J1.claude.json")"
has "$p" " 3 {\"verdict\": "
has "$p" "HELLO, ANN!"
lacks "$(cat "$AR"/judges/*.json 2>/dev/null)" "$EMAIL"
it "score rows: one per question, the judge as grader, the skill's name"
assert_eq "pass pass judge/1:haiku" "$(sv "$AR/scores/$J1.judge.json" decisions-alternative) $(sv "$AR/scores/$J1.judge.json" outcome-real-output) $(py -c 'import json,sys; print(json.load(open(sys.argv[1]))[0]["grader"])' "$AR/scores/$J1.judge.json")"
it "grade's own rows are left as they were"
assert_eq 7 "$(py -c 'import json,sys; print(len(json.load(open(sys.argv[1]))))' "$AR/scores/$J1.json")"
it "judging again judges nothing already judged"
before="$(calls)"; out="$(judge "$AR" --repo-dir "$REPO")"
assert_eq "$before" "$(calls)"
has "$out" "already judged"

echo "R10: a malformed or refused answer is recorded as such and not counted"
AR2="$TMPROOT/ar2"; fresh "$AR2" $J1; rm -f "$COUNTER"; : > "$FAKELOG"
FAKE_SCRIPT="content,fenced,prosejson,content,badverdict,refused" judge "$AR2" --repo-dir "$REPO" > /dev/null
it "a JSON answer, alone or in one fence, counts; prose around it does not"
assert_eq "vote vote malformed" "$(jst "$AR2/judges/$J1.claude.json" decisions-alternative)"
it "two counted votes of three agree: the verdict stands"
assert_eq pass "$(jv "$AR2/judges/$J1.claude.json" decisions-alternative)"
it "a verdict outside pass and fail is malformed; a refusal is refused"
assert_eq "vote malformed refused" "$(jst "$AR2/judges/$J1.claude.json" outcome-real-output)"
it "one counted vote is no verdict: undecided, and no score row"
assert_eq "undecided none" "$(jv "$AR2/judges/$J1.claude.json" outcome-real-output) $(sv "$AR2/scores/$J1.judge.json" outcome-real-output)"
AR3="$TMPROOT/ar3"; fresh "$AR3" $J1; rm -f "$COUNTER"
FAKE_SCRIPT="refused,malformed,extrakeys,error,sonnet,twojson" judge "$AR3" --repo-dir "$REPO" > /dev/null
it "an object with keys besides verdict and reason is malformed"
assert_eq "refused malformed malformed" "$(jst "$AR3/judges/$J1.claude.json" decisions-alternative)"
it "an error, a model that is not Haiku and two answers in one are not votes"
assert_eq "error error malformed" "$(jst "$AR3/judges/$J1.claude.json" outcome-real-output)"
it "with no verdict on either question there are no score rows"
assert_eq "undecided undecided none none" "$(jv "$AR3/judges/$J1.claude.json" decisions-alternative) $(jv "$AR3/judges/$J1.claude.json" outcome-real-output) $(sv "$AR3/scores/$J1.judge.json" decisions-alternative) $(sv "$AR3/scores/$J1.judge.json" outcome-real-output)"
it "the refusal's text is kept for the audit"
has "$(cat "$AR3/judges/$J1.claude.json" 2>/dev/null)" "can't help with this"
AR9="$TMPROOT/ar9"; fresh "$AR9" $J1; rm -f "$COUNTER"
FAKE_SCRIPT="iserror,iserror,content" judge "$AR9" --repo-dir "$REPO" > /dev/null
it "a well-formed answer from a run that failed is an error, not a vote"
assert_eq "error error vote" "$(jst "$AR9/judges/$J1.claude.json" decisions-alternative)"

echo "C3: at most --limit sessions per run, newest first"
AR4="$TMPROOT/ar4"; fresh "$AR4" $J1 $J2; rm -f "$COUNTER"
out="$(judge "$AR4" --repo-dir "$REPO" --limit 1)"
it "one session judged, the newer"
assert_eq "no yes" "$([ -e "$AR4/judges/$J1.claude.json" ] && echo yes || echo no) $([ -e "$AR4/judges/$J2.claude.json" ] && echo yes || echo no)"
out="$(judge "$AR4" --repo-dir "$REPO" --limit 1)"
it "the next run takes the other"
assert_eq yes "$([ -e "$AR4/judges/$J1.claude.json" ] && echo yes || echo no)"
AR8="$TMPROOT/ar8"; fresh "$AR8" $J1 $J2; judge "$AR8" --repo-dir "$REPO" --limit 1 > /dev/null
out="$(judge "$AR8" --repo-dir "$REPO" --judge opencode)"
it "the agreement judge takes only sessions the Haiku judge judged"
assert_eq "no yes" "$([ -e "$AR8/judges/$J1.opencode.json" ] && echo yes || echo no) $([ -e "$AR8/judges/$J2.opencode.json" ] && echo yes || echo no)"
has "$out" "d1000000 not judged: the Haiku judge has not judged this record"
it "the default limit is 20"
has "$("$T" judge --help 2>&1)" "20"

echo "R10: one transcript and one record, printed"
rm -f "$COUNTER"
cp "$W/$J1.jsonl" "$W/named-otherwise.jsonl"
out="$(judge --transcript "$W/named-otherwise.jsonl" --record "$REPO/docs/changes/2026-11-10-good.md")"; rc=$?
it "exits 0 and prints each prompt, the three votes and the verdict"
assert_eq 0 "$rc"
has "$out" "<decisions>"
has "$out" "vote 3: pass"
has "$out" "verdict: pass"
lacks "$out" "$TOKEN"
it "it names the session by the transcript's sessionId, not the file name"
has "$out" "d1000000 decisions-alternative pass"

echo "C3: the agreement judge, opencode-go/kimi-k3.1-pro, against a stand-in"
rm -f "$COUNTER"; : > "$FAKELOG"
out="$(judge "$AR" --repo-dir "$REPO" --judge opencode)"; rc=$?
it "exits 0 and judges the sessions the Haiku judge judged, and only those"
assert_eq "0 yes yes no" "$rc $([ -e "$AR/judges/$J1.opencode.json" ] && echo yes) $([ -e "$AR/judges/$J2.opencode.json" ] && echo yes) $([ -e "$AR/judges/$J3.opencode.json" ] && echo yes || echo no)"
it "it runs opencode with the Kimi model and an agent that may use no tool"
r="$(head -1 "$FAKELOG")"
has "$r" '"run"'
has "$r" '"opencode-go/kimi-k3.1-pro"'
has "$r" '\"*\": \"deny\"'
has "$r" '"OPENCODE_DISABLE_PROJECT_CONFIG": "1"'
it "redacted as well"
lacks "$(cat "$FAKELOG" 2>/dev/null)" "$TOKEN"
it "it writes no score rows: it is the check, not the judge"
assert_eq "decisions-alternative:judge/1:haiku outcome-real-output:judge/1:haiku" "$(py -c 'import json,sys; print(" ".join(sorted(r["step"] + ":" + r["grader"] for r in json.load(open(sys.argv[1])))))' "$AR/scores/$J1.judge.json")"
it "the report states the agreement rate"
has "$(cd "$TMPROOT" && "$T" report "$AR" 2>&1)" "agree on 4 of 4 judgments (100%), over 2 sessions judged by both"
it "a refused or failed answer from it is not a vote either"
AR5="$TMPROOT/ar5"; fresh "$AR5" $J1; judge "$AR5" --repo-dir "$REPO" > /dev/null; rm -f "$COUNTER"
FAKE_SCRIPT="refused,error,content,content,content,content" judge "$AR5" --repo-dir "$REPO" --judge opencode > /dev/null
assert_eq "refused error vote" "$(jst "$AR5/judges/$J1.opencode.json" decisions-alternative)"
it "if it ran but no answer counted, the report says so rather than that it has not run"
AR10="$TMPROOT/ar10"; fresh "$AR10" $J1; judge "$AR10" --repo-dir "$REPO" > /dev/null; rm -f "$COUNTER"
FAKE_SCRIPT="malformed,malformed,malformed,malformed,malformed,malformed" judge "$AR10" --repo-dir "$REPO" --judge opencode > /dev/null
r="$(cd "$TMPROOT" && "$T" report "$AR10" 2>&1)"
has "$r" "The agreement judge ran on 1 sessions, but no question got a verdict from both judges"
lacks "$r" "has not run yet"

echo "R11, and grading-trust R4 and R5: the report from known score rows, labels and transcripts"
# report DIR: the report on a folder, with the label files kept in it
report() { local d="$1"; shift; (cd "$TMPROOT" && "$T" report "$d" --labels "$d/labels" "$@"); }
# copy NAME: a copy of the report fixtures to change
copy() { rm -rf "$TMPROOT/$1"; cp -R "$RFIX" "$TMPROOT/$1"; mkdir -p "$TMPROOT/$1/labels" "$TMPROOT/$1/projects/made-up"; }
R1=a1000000-0000-0000-0000-000000000001; R3=b3000000-0000-0000-0000-000000000003; R4=b4000000-0000-0000-0000-000000000004
R5=c5000000-0000-0000-0000-000000000005
rep="$(report "$RFIX" 2>&1)"; rc=$?
it "exits 0 and matches the stored expected report"
diffout="$(diff <(printf '%s\n' "$rep") "$RFIX/expected.md" 2>/dev/null | head -30 || echo "expected.md is missing")"
assert_eq "0 " "$rc $diffout"
it "R4: a step covered by five labelled sessions has its measured error beside its pass rate"
has "$rep" "| tier-declared | fields/1 | 2 | 0 | 0 | 100% | 20% (1 of 5 wrong) |"
it "R4: a step covered by fewer than five is not yet checked, with how many cover it"
has "$rep" "| red-first | fields/1 | 1 | 1 | 0 | 50% | not yet checked (4 of 5 needed) |"
it "R4: sessions where label and grader both say not applicable do not count toward the five"
has "$rep" "| outcome-filled | fields/1 | 0 | 0 | not yet checked | 0 | 0 | 0 | 1 |"
it "R4: the judge's steps have no labels, and say so"
has "$rep" "| decisions-alternative | judge/1:haiku | 1 | 1 | 0 | 50% | not yet checked (no labels) |"
it "C4: every known false verdict is listed with its session"
has "$rep" "- red-first, false fail, b4000000 ($R4): the label says pass"
has "$rep" "- tier-declared, false pass, a1000000 ($R1): the label says fail"
it "R5: a failed step shows the session, the grader's reason and the rest of its evidence"
has "$rep" "#### red-first, a1000000 ($R1)"
has "$rep" "fields/1 says fail: no test ran before the code"
has "$rep" "test_runs_before_code 0; denied_test_runs 1"
it "R5: and the call it cites, with an excerpt of what the call wrote and what came back"
has "$rep" 'first_code_write (greet.py), **[5] Write** `c1` /work/made-up/greet.py:'
has "$rep" "        return n.upper() if shout else n"
it "R5: and the shell commands before it, with how each ended"
has "$rep" '- [3] `python3 -m unittest discover -s tests`: never answered'
it "R5: a failed step a label calls a pass is marked as a known false fail"
has "$rep" "this fail is a known false fail"
it "R5: a judge's failed step shows its votes"
has "$rep" "- vote 1, fail: No Decision names what it rejected."
it "R5: the excerpts are redacted as push redacts: no address, no token"
lacks "$rep" "$EMAIL"
lacks "$rep" "$TOKEN"
has "$rep" "Bearer <redacted:token>"
has "$rep" "as <redacted:email> asked"
it "R5: no line of the fixed table of advice remains, and no edit is proposed"
for old in "make the tier the first thing written" "say that the record is created only after a probe has run" \
  "say that no file outside docs/changes/ and the tests is" "require the failing test run's output to be seen" \
  "give the exact first line of the PR body to copy" "list the sections and frontmatter fields record-check requires" \
  "say that a record is not done until its Outcome holds" "ask for each Decision to name the alternative it rejected" \
  "ask for the Outcome to quote the commands run" "review this step against the failures below" "Proposed skill edits"; do
  lacks "$rep" "$old"
  lacks "$(cat "$here/../grade/report.py")" "$old"
done
it "a row re-graded from fail to pass is no failed step"
lacks "$rep" "#### red-first, b3000000"
it "R4: a label whose transcript has since grown is stale: reported, and not counted"
copy stale; tail -1 "$TMPROOT/stale/projects/made-up/$R1.jsonl" >> "$TMPROOT/stale/projects/made-up/$R1.jsonl"
r="$(report "$TMPROOT/stale" 2>&1)"; rc=$?
has "$r" "stale label, made from a transcript of 9 lines"
has "$r" "| tier-declared | fields/1 | 2 | 0 | 0 | 100% | not yet checked (4 of 5 needed) |"
lacks "$r" "- tier-declared, false pass, a1000000"
has "$r" "4 sessions are counted"
assert_eq 0 "$rc"
it "R4: a malformed label file is named on stderr, listed, not counted, and the exit status is 1"
copy badlabel; python3 -c 'import sys; p=sys.argv[1]; s=open(p).read(); n=s.replace("tier-declared: fail", "tier-declared: failed"); assert n != s; open(p,"w").write(n)' "$TMPROOT/badlabel/labels/$R1.txt"
r="$(report "$TMPROOT/badlabel" 2>"$TMPROOT/badlabel.err")"; rc=$?
assert_eq 1 "$rc"
has "$(cat "$TMPROOT/badlabel.err")" "$R1.txt: tier-declared: unknown verdict 'failed' (pass, fail or na); the file is rejected"
has "$r" "$R1.txt is rejected: tier-declared: unknown verdict 'failed'"
has "$r" "not yet checked (4 of 5 needed) |"
has "$r" "4 sessions are counted, of 5 with a transcript here and 5 label files"
it "R4: with no label filled in, every step is not yet checked, and the report says no session is counted"
copy nolabel; for f in "$TMPROOT"/nolabel/labels/*.txt; do sed -E -e 's/^(labelled-by:).*/\1/' -e 's/^([a-z]+-[a-z-]+:) ?[a-z]+ \|.*/\1/' "$f" > "$f.new" && mv "$f.new" "$f"; done
r="$(report "$TMPROOT/nolabel" 2>&1)"; rc=$?
assert_eq 0 "$rc"
has "$r" "| tier-declared | fields/1 | 2 | 0 | 0 | 100% | not yet checked (0 of 5 needed) |"
has "$r" "0 sessions are counted"
has "$r" "not labelled yet, in 5 sessions"
lacks "$r" "% ("
it "R4: a labels folder that is not there is an error, not an unchecked report"
(report "$TMPROOT/nolabel" --labels "$TMPROOT/no-such-labels" > /dev/null 2>&1); assert_eq 2 "$?"
it "R4: a step the grader could not grade is not counted, and the reason is given"
copy cannot; python3 - "$TMPROOT/cannot/scores/$R5.json" <<'PY2'
import json, sys
p = sys.argv[1]; rows = json.load(open(p))
for r in rows:
    if r["step"] == "tier-declared":
        r["verdict"] = "not_applicable"; r["evidence"] = {"why": "the record cannot be read: no commit for the session", "error": "no commit for the session"}
json.dump(rows, open(p, "w"))
PY2
r="$(report "$TMPROOT/cannot" 2>&1)"
has "$r" "- tier-declared: the grader could not grade it (no commit for the session), in 1 session (c5000000)"
has "$r" "| tier-declared | fields/1 | 4 | 1 | not yet checked | 0 | 1 | 0 | 0 |"
it "R4: a row whose grader could not read what it needed is listed as no verdict, labels or no labels"
has "$r" "- tier-declared, fields/1: no commit for the session, in 1 session (c5000000): its not applicable there is no verdict"
has "$rep" "None: no row here says its grader could not read what it needed."
it "R5: a failed step whose transcript is not here names the calls and says they are not shown"
copy gone; rm "$TMPROOT/gone/projects/made-up/$R5.jsonl"
r="$(report "$TMPROOT/gone" 2>&1)"
has "$r" 'The transcript is not here, so the calls are named and not shown: first_code_write `c1`.'
it "R5: a cited call the transcript does not hold is said to be missing, not left out"
copy nocall; sed 's/"id":"c1"/"id":"c9"/' "$TMPROOT/nocall/projects/made-up/$R5.jsonl" > "$TMPROOT/nocall/x" && mv "$TMPROOT/nocall/x" "$TMPROOT/nocall/projects/made-up/$R5.jsonl"
r="$(report "$TMPROOT/nocall" 2>&1)"
has "$r" 'first_code_write (greet.py), `c1`: not among the calls of the transcript here.'
it "R5: a denied command before the cited call is shown as denied"
copy denied; python3 - "$TMPROOT/denied/projects/made-up/$R1.jsonl" <<'PY2'
import json, sys
p = sys.argv[1]; lines = open(p).read().splitlines()
r1 = next(i for i, l in enumerate(lines) if '"id":"r1"' in l)
d = json.loads(lines[r1]); d["type"] = "user"
d["message"] = {"role": "user", "content": [{"tool_use_id": "r1", "type": "tool_result", "content": "Permission to use Bash has been denied.", "is_error": True}]}
lines.insert(r1 + 1, json.dumps(d, separators=(",", ":")))
open(p, "w").write("\n".join(lines) + "\n")
PY2
has "$(report "$TMPROOT/denied" 2>&1)" '- [3] `python3 -m unittest discover -s tests`: denied or refused'
it "R4: a not applicable where the label says pass is a false n/a, and counts as wrong"
copy falsena; sed 's/^change-line: na .*/change-line: pass | made up: its last message opens with the Change: line/' "$TMPROOT/falsena/labels/$R4.txt" > "$TMPROOT/falsena/x" && mv "$TMPROOT/falsena/x" "$TMPROOT/falsena/labels/$R4.txt"
r="$(report "$TMPROOT/falsena" 2>&1)"
has "$r" "| change-line | fields/1 | 4 | 1 | not yet checked | 0 | 0 | 1 | 0 |"
has "$r" "- change-line, false n/a, b4000000 ($R4): the label says pass"
it "R5: every text the report takes from a row, a label, a vote or a transcript is redacted"
# leak: the address or the token put into each such text of a copy, and the labels' hashes made to match again
copy leak; python3 - "$TMPROOT/leak" "$EMAIL" "$TOKEN" <<'PY2'
import glob, hashlib, json, os, sys
d, email, token = sys.argv[1:]
def edit(path, fn):
    out = []
    for raw in open(path).read().splitlines():
        o = json.loads(raw); fn(o); out.append(json.dumps(o, separators=(",", ":")))
    open(path, "w").write("\n".join(out) + "\n")
def blocks(o):
    c = o["message"]["content"]
    return c if isinstance(c, list) else []
def a1(o):  # the cited Write's content and result; a shell command after the code
    for b in blocks(o):
        if b.get("id") == "c1":
            b["input"]["content"] = "# for " + email + "\n" + b["input"]["content"]
        if b.get("tool_use_id") == "c1":
            b["content"] = "File created successfully, and " + email + " was told"
def b4(o):  # the cited Edit's new text; the result of a shell command before it
    for b in blocks(o):
        if b.get("id") == "c1":
            b["input"]["new_string"] += "  # " + email
        if b.get("tool_use_id") == "r1":
            b["content"] += ", mailed to " + email
def c5(o):  # the cited call made a shell command
    for b in blocks(o):
        if b.get("id") == "c1":
            b["name"], b["input"] = "Bash", {"command": "curl -H 'Authorization: Bearer " + token + "' https://x.example.org > greet.py"}
t = lambda s: os.path.join(d, "projects", "made-up", s + "-0000-0000-0000-00000000000" + s[1] + ".jsonl")
edit(t("a1000000"), a1); edit(t("b4000000"), b4); edit(t("c5000000"), c5)
with open(t("a1000000"), "a") as f:
    f.write(json.dumps({"sessionId": "a1000000-0000-0000-0000-000000000001", "type": "assistant", "cwd": "/work/made-up", "message": {
        "role": "assistant", "content": [{"type": "tool_use", "id": "z9", "name": "Bash", "input": {"command": "echo after-the-code"}}]}}) + "\n")
for p in glob.glob(os.path.join(d, "scores", "*.json")):
    rows = json.load(open(p))
    for r in rows:
        if r["verdict"] == "fail" and r["step"] == "change-line":
            r["evidence"]["why"] += ", written for " + email
            r["evidence"]["source"] = "pull request by " + email
    json.dump(rows, open(p, "w"))
p = os.path.join(d, "judges", "b3000000-0000-0000-0000-000000000003.claude.json"); j = json.load(open(p))
j["questions"]["decisions-alternative"]["votes"][2] = {"vote": 3, "status": "malformed", "detail": "no JSON, but " + email, "verdict": None, "reason": None}
json.dump(j, open(p, "w"))
for p in glob.glob(os.path.join(d, "labels", "*.txt")):
    sid = os.path.basename(p)[:-4]; data = open(os.path.join(d, "projects", "made-up", sid + ".jsonl"), "rb").read()
    out = []
    for ln in open(p).read().splitlines():
        if ln.startswith("transcript:"):
            ln = "transcript: sha256:%s lines:%d" % (hashlib.sha256(data).hexdigest(), len(data.splitlines()))
        if ln.startswith("red-first: pass | made up: run-tests.sh"):
            ln += ", as " + email + " saw"
        out.append(ln)
    open(p, "w").write("\n".join(out) + "\n")
PY2
r="$(report "$TMPROOT/leak" 2>&1)"
lacks "$r" "$EMAIL"
lacks "$r" "$TOKEN"
it "the leak fixture did put them where the report reads: each place shows its placeholder"
has "$r" "    # for <redacted:email>"
has "$r" "    File created successfully, and <redacted:email> was told"
has "$r" "    +     return n.title()  # <redacted:email>"
has "$r" "and ends \`done, mailed to <redacted:email>\`"
has "$r" "    curl -H 'Authorization: Bearer <redacted:token>' https://x.example.org > greet.py"
has "$r" "says fail: the PR description opens with 'Summary', written for <redacted:email>"
has "$r" "source pull request by <redacted:email>."
has "$r" "edited, as <redacted:email> saw); the grader says fail"
has "$r" "edited, as <redacted:email> saw): this fail is a known false fail."
has "$r" "5 sessions are counted"
it "R5: a vote that was not counted is shown as not counted, with why"
has "$r" "- vote 3, not counted (malformed): no JSON, but <redacted:email>"
it "R5: only the shell commands before the cited call are listed"
lacks "$r" "after-the-code"
it "with no session judged by both, the report says the agreement check has not run yet"
copy noag; rm -f "$TMPROOT"/noag/judges/*.opencode.json
has "$(report "$TMPROOT/noag" 2>&1)" "The agreement check has not run yet"
it "a pair judged on two different records is not compared"
copy other; OTH="$TMPROOT/other"
python3 -c 'import json,sys; p=sys.argv[1]; j=json.load(open(p)); j["record_sha256"]="cd"*32; json.dump(j,open(p,"w"))' "$OTH/judges/$R4.opencode.json" 2>/dev/null
has "$(report "$OTH" 2>&1)" "agree on 1 of 2 judgments (50%), over 1 sessions judged by both"
it "a step a newer grader passed is no failed step, whatever an older grader said"
python3 - "$OTH/scores/$R1.json" 2>/dev/null <<'PY2'
import json, sys
p = sys.argv[1]; rows = json.load(open(p))
r = dict([x for x in rows if x["step"] == "red-first"][0], grader="fields/2", verdict="pass", graded_at="2026-11-11T00:00:00+00:00")
json.dump(rows + [r], open(p, "w"))
PY2
r="$(report "$OTH" 2>&1)"
lacks "$r" "#### red-first, a1000000"
it "R4: each grader's error is measured on its own rows"
has "$r" "| red-first | fields/2 | 1 | 1 | not yet checked | 0 | 1 | 0 | 0 |"
has "$r" "| red-first | fields/1 | 4 | 1 | not yet checked | 1 | 0 | 0 | 1 |"
it "a folder with no score rows is an error"
mkdir -p "$TMPROOT/empty"; (cd "$TMPROOT" && "$T" report "$TMPROOT/empty" > /dev/null 2>&1); assert_eq 1 "$?"

echo "session-quality R1 to R3: what each session took and which skills were used, from the transcripts"
CFIX="$here/../grade/fixtures/counts"
rep="$(cd "$TMPROOT" && "$T" report "$CFIX" 2>&1)"; rc=$?
it "R2: a folder with no scores still gives the counts and the coverage, and exits 0"
assert_eq 0 "$rc"
diffout="$(diff <(printf '%s\n' "$rep") "$CFIX/expected.md" 2>/dev/null | head -30 || echo "expected.md is missing")"
assert_eq "" "$diffout"
it "R1: a message written on three lines is counted once (500 output tokens, not 1220)"
has "$rep" "| d1000000 | 500 | 3 | 2 | 3 | 62 | 21 | 1 | 10 |"
it "R1: a line the harness wrote, a notification and a compaction summary are not turns from a person"
has "$rep" "| Turns from a person after the first | 3 | 0 | 0 (d2000000) | 1 (d1000000) |"
it "R1: a subagent's line kept inline adds nothing, and a transcript with no usage shows - for tokens"
has "$rep" "| d3000000 | - | 1 | 0 | 1 | 21 | 21 | 0 | 0.3 |"
it "R3: a skill file read through the shell counts as the skill used, though the index entry lists none"
has "$rep" "| change-record:change | 2 |"
has "$rep" "Of 3 sessions here, 2 used a skill and 1 used none."
it "R1: a session with rows and no transcript here is said so, and counted in neither table"
rm -rf "$TMPROOT/cnt"; cp -R "$RFIX" "$TMPROOT/cnt"; rm "$TMPROOT/cnt/projects/made-up/b4000000-0000-0000-0000-000000000004.jsonl"
r="$(report "$TMPROOT/cnt" 2>/dev/null)"
has "$r" "4 of 5 sessions have a transcript here"
lacks "$r" "| b4000000 | - |"
has "$r" "| Tool calls | 1 | 3 | 3 (b3000000) | 3 (b3000000) |"
it "R3: coverage still counts that session, from its index entry"
has "$r" "Of 5 sessions here, 4 used a skill and 1 used none."
it "R1: a skill version with no transcript here at all gets no empty table"
rm "$TMPROOT/cnt/projects/made-up/b3000000-0000-0000-0000-000000000003.jsonl"
r="$(report "$TMPROOT/cnt" 2>/dev/null)"
has "$r" "3 of 5 sessions have a transcript here"
lacks "$r" "| Tool calls | 0 |"
has "$r" "| Tool calls | 2 | 3.5 | 3 (a2000000) | 4 (a1000000) |"
it "R1: a transcript with a line that is not JSON is left out of the counts, and the report says so"
rm -rf "$TMPROOT/cnt2"; cp -R "$CFIX" "$TMPROOT/cnt2"; printf '{"sessionId":"d3\n' >> "$TMPROOT/cnt2/projects/made-up/d3000000-0000-0000-0000-000000000003.jsonl"
r="$(cd "$TMPROOT" && "$T" report "$TMPROOT/cnt2" 2>/dev/null)"
has "$r" "2 of 3 sessions have a transcript here that can be read (1 holds a line that is not JSON)."
lacks "$r" "| d3000000 |"
it "an empty folder is still refused: there is nothing to report"
mkdir -p "$TMPROOT/empty2"; out="$(cd "$TMPROOT" && "$T" report "$TMPROOT/empty2" 2>&1)"; rc=$?
assert_eq 1 "$rc"; has "$out" "no score rows in"

echo "R11: scores and votes to the store, with the read key only"
PORTF="$TMPROOT/port"; SLOG="$TMPROOT/store.log"; : > "$SLOG"
python3 "$STANDIN" "$PORTF" "$SLOG" "$READKEY" & PIDS="$PIDS $!"
await_port "$PORTF"
URL="http://127.0.0.1:$(cat "$PORTF")"
AR6="$TMPROOT/ar6"; fresh "$AR6" $J1; rm -f "$COUNTER"; : > "$FAKELOG"
out="$(AGENT_TRANSCRIPTS_URL="$URL" judge "$AR6" --repo-dir "$REPO" --store)"; rc=$?
it "with no read key, --store stops before any judge runs"
assert_eq "2 0" "$rc $(calls)"
has "$out" "read-key"
printf '%s\n' "$READKEY" > "$XDG_CONFIG_HOME/agent-transcripts/read-key"; chmod 600 "$XDG_CONFIG_HOME/agent-transcripts/read-key"
out="$(AGENT_TRANSCRIPTS_URL="$URL" judge "$AR6" --repo-dir "$REPO" --store)"; rc=$?
it "with it, the score rows go to scores and the six votes to judge_votes, with the read key"
assert_eq "0 2 6 True" "$rc $(py -c '
import json,sys
r=[json.loads(l) for l in open(sys.argv[1])]
s=[x for x in r if x["path"]=="/rest/v1/scores"]; v=[x for x in r if x["path"]=="/rest/v1/judge_votes"]
print(len(s), len(v), all(x["apikey"]==sys.argv[2] for x in s+v))' "$SLOG" "$READKEY")"
it "each stored vote carries its prompt, status and answer, redacted"
vrow="$(py -c 'import json,sys; r=[json.loads(l) for l in open(sys.argv[1]) if "judge_votes" in l]; print(r[0]["body"])' "$SLOG")"
has "$vrow" '"status":"vote"'
has "$vrow" '"prompt_sha256"'
lacks "$(cat "$SLOG" 2>/dev/null)" "$TOKEN"
it "the report reads the store's rows with the read key"
has "$(cd "$TMPROOT" && AGENT_TRANSCRIPTS_URL="$URL" "$T" report "$TMPROOT/empty" --store 2>&1)" "| decisions-alternative | judge/1:haiku | 1 | 0 | 0 | 100% |"

if [ "${TRANSCRIPTS_LIVE_JUDGE:-}" = 1 ]; then
  echo "R10, live: the real Haiku judge on the two known-answer sessions"
  export PATH="$REAL_PATH"
  AR7="$TMPROOT/ar7"; fresh "$AR7" $J1 $J2 $J6
  judge "$AR7" --repo-dir "$REPO" --verbose
  it "the real judge gives the known answers"
  assert_eq "pass pass fail fail" "$(jv "$AR7/judges/$J1.claude.json" decisions-alternative) $(jv "$AR7/judges/$J1.claude.json" outcome-real-output) $(jv "$AR7/judges/$J2.claude.json" decisions-alternative) $(jv "$AR7/judges/$J2.claude.json" outcome-real-output)"
  it "a rejected alternative named with no reason fails, every vote agreeing"
  assert_eq "fail vote vote vote" "$(jv "$AR7/judges/$J6.claude.json" decisions-alternative) $(jst "$AR7/judges/$J6.claude.json" decisions-alternative)"
  assert_eq "fail fail fail" "$(py -c 'import json,sys; print(" ".join(v["verdict"] for v in json.load(open(sys.argv[1]))["questions"]["decisions-alternative"]["votes"]))' "$AR7/judges/$J6.claude.json")"
fi

echo
echo "transcripts judge and report: $pass passed, $fail failed"
[ "$fail" -eq 0 ]
