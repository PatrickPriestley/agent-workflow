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
# a suite that cannot make its temporary folder must not go on: TMPROOT would be the folder it was started in
TMPROOT="$(mktemp -d)" && TMPROOT="$(cd "$TMPROOT" && pwd -P)" || { echo "cannot make a temporary folder" >&2; exit 1; }
PIDS=""
trap 'for p in $PIDS; do kill $p 2>/dev/null; done; rm -rf "$TMPROOT" ${VROOT:+"$VROOT"}' EXIT
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
if kind == "claude" and ("stream-json" in argv or "probe.sh" in prompt):
    # judge --review. A reviewer (stream-json) or its sandbox check (the prompt names probe.sh). It logs
    # what it was started with and the git state of its folder to $FAKELOG.review, then does as told:
    #   FAKE_SANDBOX  holds (default): only the files a sandbox allows appear; writes: the write outside
    #                 goes through; reads: the repository is read; norun: probe.sh is not run
    #   FAKE_REVIEW   ok (default): copies $FAKE_REVIEW_DIR/.review here and answers with its answer.json;
    #                 noanswer, error, slow (sleeps 30 s first). FAKE_REVIEW_CMD: a command it "ran".
    #   FAKE_SERVED   the model that answered, when it is not the one asked for
    import shutil, subprocess, time
    def git(*a):
        return subprocess.run(["git", *a], capture_output=True, text=True).stdout.strip()
    asked = argv[argv.index("--model") + 1] if "--model" in argv else "none"
    with open(os.environ["FAKELOG"] + ".review", "a") as f:
        f.write(json.dumps({"argv": argv, "prompt": prompt, "cwd": os.getcwd(), "check": "probe.sh" in prompt,
                            "settings": open(argv[argv.index("--settings") + 1]).read() if "--settings" in argv else None,
                            "remotes": git("remote"), "refs": git("for-each-ref"), "commits": git("rev-list", "--all", "--count"),
                            "head": git("rev-parse", "HEAD"),
                            "later": subprocess.run(["git", "cat-file", "-e", os.environ.get("FAKE_LATER", "x")], capture_output=True).returncode == 0,
                            "env": {k: os.environ.get(k) for k in ("AGENT_TRANSCRIPTS", "CLAUDE_CODE_SESSION_ID", "SECRET_FROM_CALLER")}}) + "\n")
    if "probe.sh" in prompt:
        how = os.environ.get("FAKE_SANDBOX", "holds")
        src = open("probe.sh").read()
        if how == "holds":
            for name in re.findall(r"(?:inside|done)-[0-9a-f]+", src):
                open(name, "w").write("ok\n")
        elif how in ("writes", "reads"):
            subprocess.run(["bash", "probe.sh"], capture_output=True)
            for name in re.findall(r"read-[0-9a-f]+" if how == "writes" else r"\.\./outside-[0-9a-f]+", src):
                if os.path.exists(name):
                    os.remove(name)
        print(json.dumps({"type": "result", "is_error": False, "result": "ran it", "modelUsage": {"claude-%s-5-5" % asked: {}}}))
        sys.exit(0)
    how = os.environ.get("FAKE_REVIEW", "ok")
    if how == "slow":
        time.sleep(30)
    src = os.environ.get("FAKE_REVIEW_DIR", "")
    if how == "ok" and os.path.isdir(os.path.join(src, ".review")):
        shutil.copytree(os.path.join(src, ".review"), ".review", symlinks=True)
    print(json.dumps({"type": "system", "subtype": "init", "model": "claude-%s-5-5" % asked}))
    print(json.dumps({"type": "assistant", "message": {"content": [{"type": "tool_use", "name": "Bash",
                      "input": {"command": os.environ.get("FAKE_REVIEW_CMD", "git diff")}}]}}))
    answer = open(os.path.join(src, "answer.json")).read() if how in ("ok", "slow") else "I could not finish."
    print(json.dumps({"type": "result", "subtype": "success", "is_error": how == "error", "result": answer, "num_turns": 9,
                      "total_cost_usd": 0.3, "modelUsage": {"claude-%s-5-5" % os.environ.get("FAKE_SERVED", asked): {"outputTokens": 900}}}), flush=True)
    sys.exit(1 if how == "error" else 0)
def section(tag):
    m = re.search(r"<%s>(.*?)</%s>" % (tag, tag), prompt, re.S)
    return m.group(1) if m else ""
asked = argv[argv.index("--model") + 1] if "--model" in argv else "haiku"
v = "pass"
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
if os.environ.get("FAKE_ANSWER_FILE"):  # judge --repeats: the answer is whatever the test wrote there
    answers["content"] = js = open(os.environ["FAKE_ANSWER_FILE"]).read()
out = {"type": "result", "subtype": "success", "is_error": False, "stop_reason": "end_turn", "terminal_reason": "completed",
       "result": answers.get(mode, js), "modelUsage": {"claude-%s-5-5" % asked: {"outputTokens": 20}}, "total_cost_usd": 0.015}
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
elif mode in ("sonnet", "haiku"):  # served by another model than the one asked for
    out["modelUsage"] = {"claude-%s-5-5" % mode: {"outputTokens": 20}}
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
# at HOUR[:MIN[:SEC]] git-args...: a git command whose commit is made at that time (half past, with no
# MIN) on the day of the made-up sessions (2026-11-10), which start on the hour: a session's own
# commits are those made after it began
at() { local t="$1"; shift; case "$t" in *:*:*) ;; *:*) t="$t:00" ;; *) t="$t:30:00" ;; esac
       GIT_AUTHOR_DATE="2026-11-10T${t}Z" GIT_COMMITTER_DATE="2026-11-10T${t}Z" git "$@"; }
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
  git add -A && at 10 commit -qm init
  record 2026-11-10-good "$GOOD_DEC" "$GOOD_OUT" > docs/changes/2026-11-10-good.md
  record 2026-11-10-bad "- Use argparse for the flag." "All tests pass." > docs/changes/2026-11-10-bad.md
  record 2026-11-10-bare "- Parse the flag by hand. Rejected: argparse." "All tests pass." > docs/changes/2026-11-10-bare.md
  record 2026-11-10-empty "" "" | sed 's/^status: done/status: approved/' > docs/changes/2026-11-10-empty.md
  printf 'def greet(n):\n    return n.upper()\n' > greet.py
  git add -A && at 11 commit -qm "feat: shout"
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
it "R5, the texts it missed (record 2026-11-15-report-redaction): a row's skill name, an evidence key and a call's tool name are redacted too"
copy leak2; python3 - "$TMPROOT/leak2" "$EMAIL" "$TOKEN" <<'PY2'
import glob, json, os, sys
d, email, token = sys.argv[1:]
for p in glob.glob(os.path.join(d, "scores", "c5000000*.json")):
    rows = json.load(open(p))
    for r in rows:
        r["skill"] = "change, Bearer " + token
        if isinstance(r.get("evidence"), dict):
            r["evidence"]["note for " + email] = "x"
    json.dump(rows, open(p, "w"))
p = glob.glob(os.path.join(d, "projects", "made-up", "a1000000*.jsonl"))[0]
out = []
for raw in open(p).read().splitlines():
    o = json.loads(raw); c = (o.get("message") or {}).get("content")
    for b in c if isinstance(c, list) else []:
        if b.get("type") == "tool_use" and b.get("id") == "c1":
            b["name"] = "Write_" + email
    out.append(json.dumps(o, separators=(",", ":")))
open(p, "w").write("\n".join(out) + "\n")
# two texts no line of the report redacts by itself: a grader's name, and a skill's name in an index entry
p = glob.glob(os.path.join(d, "scores", "b4000000*.json"))[0]; rows = json.load(open(p))
for r in rows:
    r["grader"] += " run by " + email
json.dump(rows, open(p, "w"))
p = glob.glob(os.path.join(d, "sessions", "a2000000*.json"))[0]; e = json.load(open(p))
e["skills"] = [{"name": "notes-of-" + email + ":skill", "how": "skill", "blob": None}]; json.dump(e, open(p, "w"))
PY2
r="$(report "$TMPROOT/leak2" 2>&1)"
lacks "$r" "$EMAIL"; lacks "$r" "$TOKEN"
has "$r" "run by <redacted:email> |"; has "$r" "<redacted:email>:skill | 1 |"
has "$r" "## change, Bearer <redacted:token>, blob"
has "$r" "note for <redacted:email> x"
has "$r" "] <redacted:email>** \`c1\`"   # the address takes the Write_ before it: _ is a letter of an address
it "and so is the page a folder with no score rows gets"
copy norows; rm -rf "$TMPROOT/norows/scores"; cp "$TMPROOT/leak2"/sessions/a2000000*.json "$TMPROOT/norows/sessions/"
r="$(report "$TMPROOT/norows" 2>&1)"; has "$r" "No score rows here"; lacks "$r" "$EMAIL"; has "$r" "<redacted:email>:skill | 1 |"
it "a row whose evidence is not an object is reported like one with none: no traceback, and the report is printed"
copy odd; python3 - "$TMPROOT/odd" <<'PY2'
import glob, json, os, sys
for p in glob.glob(os.path.join(sys.argv[1], "scores", "c5000000*.json")):
    rows = json.load(open(p))
    for r in rows:
        if r["verdict"] == "fail":
            r["evidence"] = ["not", "an object"]
    json.dump(rows, open(p, "w"))
PY2
r="$(report "$TMPROOT/odd" 2>&1)"; rc=$?
lacks "$r" "Traceback"; has "$r" "# Change skill report"; has "$r" "says fail: it gives no reason"
assert_eq "0" "$rc"
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

echo "session-quality C2: the two rubric judges were taken out; the sheet names the session's own commits"
# More commits, each at a known time: D at 12:30, E at 14:30, F at 15:30, G at 17:30 on main; a side branch
# from F committed at 17:45 and merged into main at 18:30 after a commit of the session's own; and a
# branch from D with two commits a few seconds into 13:00.
(
  cd "$REPO"
  printf 'def greet(n):\n    try:\n        return n.upper()\n    except Exception:\n        pass\n' > greet.py
  at 12 commit -qam "feat: never fail"
  printf 'def shout(n):\n    return n.upper()\n' > shout.py; git add -A && at 14 commit -qm "feat: shout module"
  printf 'VALUE = 1\n' > table.py; git add -A && at 15 commit -qm "feat: table"
  printf 'def zeta(n):\n    return n\n' > zeta.py; git add -A && at 17 commit -qm "feat: zeta"
  git checkout -q -b side HEAD~1
  printf 'def other(n):\n    return n\n' > other.py; git add -A && at 17:45 commit -qm "feat: other, on a side branch"
  git checkout -q main
  printf 'def mine(n):\n    return n\n' > mine.py; git add -A && at 18 commit -qm "feat: mine"
  at 18 merge -q --no-ff side -m "chore: merge side"
  git checkout -q -b span HEAD~5
  printf 'def span(n):\n    return n\n' > span.py; git add -A && at 13:00:03 commit -qm "feat: span"
  printf 'def span(n):\n    return n or 0\n' > span.py; git add -A && at 13:00:04 commit -qm "fix: span"
  git checkout -q main
)
M="$(git -C "$REPO" rev-parse main)"; G="$(git -C "$REPO" rev-parse main~2)"; E="$(git -C "$REPO" rev-parse main~4)"
D="$(git -C "$REPO" rev-parse main~5)"; H="$(git -C "$REPO" rev-parse span)"
# talk SID HOUR TEXT: a session that runs a test, writes greet.py and says TEXT, its lines a second apart from HOUR:00:01
talk() {
  { printf '["call","r1","Bash",{"command":"python3 -m unittest"}]\n["result","r1","FAILED (failures=1)",false]\n'
    printf '["call","c1","Write",{"file_path":"%s","content":"x"}]\n["result","c1","ok",false]\n' "$REPO/greet.py"
    python3 -c 'import json,sys; print(json.dumps(["text", sys.argv[1]]))' "$3"
  } | python3 "$GEN" "$W/$1.jsonl" "$1" "$REPO" "$2"
}
# keep AR SID FIRST LAST: archive the session and set the commits at its first and last stop
keep() {
  (cd "$TMPROOT" && AGENT_TRANSCRIPTS="$1" "$T" archive --transcript "$W/$2.jsonl" < /dev/null > /dev/null 2>&1)
  python3 - "$1/sessions/$2.json" "$3" "$4" <<'PY'
import json, sys
p, first, last = sys.argv[1:]
e = json.load(open(p)); e["first_stop"] = {"branch": "x", "commit": first or None}; e["last_stop"] = {"branch": "x", "commit": last or None}
json.dump(e, open(p, "w"), indent=2)
PY
}
Q1=e1000000-0000-0000-0000-000000000001; Q3=e3000000-0000-0000-0000-000000000003; Q9=e9000000-0000-0000-0000-000000000009
QA=ea000000-0000-0000-0000-00000000000a; QB=eb000000-0000-0000-0000-00000000000b; QC=ec000000-0000-0000-0000-00000000000c
QD=ed000000-0000-0000-0000-00000000000d; QE=ee000000-0000-0000-0000-00000000000e
talk $Q1 11 "The --shout flag is in and the suite passes; write to $EMAIL if it breaks. Nothing else changed."
talk $Q3 13 "This session committed nothing at all, and no commit was recorded at any of its stops."
talk $Q9 12 "Two commits before the first stop, and the suite passes. Nothing else changed, and nothing waits on you."
talk $QA 10 "The repository's first commit holds the greeting and its test. Nothing else changed in this one."
talk $QB 21 "The commit this session ended on is not in the repository that is being read, as it happens."
talk $QC 19 "The work was already committed when this session began, and it wrote one file it did not commit."
talk $QD 18 "My module is in, and I merged the side branch into main. The suite passes and nothing else changed."
talk $QE 13 "The span module went in while this session was still writing, a few seconds after it began."
RA="$TMPROOT/rubric-ar"
keep "$RA" $Q1 "$A" "$C"; keep "$RA" $Q3 "" ""; keep "$RA" $Q9 "$E" "$E"; keep "$RA" $QA "$A" "$A"
keep "$RA" $QB "$A" "0000000000000000000000000000000000000000"; keep "$RA" $QC "$C" "$C"; keep "$RA" $QD "$M" "$M"; keep "$RA" $QE "$H" "$H"
: > "$FAKELOG"; rm -f "$COUNTER"
out="$(judge "$RA" --rubrics --repo-dir "$REPO")"; rc=$?
it "judge --rubrics asks nothing, exits 2 and says the rubric judges were taken out"
assert_eq "2 0" "$rc $(calls)"
has "$out" "judge --rubrics was taken out"
has "$out" "grade/rubrics/README.md"; lacks "$out" "usage:"
assert_eq "no" "$([ -e "$RA/rubrics" ] && echo yes || echo no)"
(cd "$TMPROOT" && "$T" sheet "$RA" --repo-dir "$REPO" --labels "$RA/labels" > /dev/null 2>&1)
sh() { cat "$RA/sheets/$1.md" 2>&1; }
OWN="git log --first-parent --no-merges"
it "the sheet asks no rubric question, and a new label file has no rubric line"
lacks "$(sh $Q1; cat "$RA/labels/$Q1.txt" 2>&1)" "code-quality"
lacks "$(sh $Q1; cat "$RA/labels/$Q1.txt" 2>&1)" "verbosity"
it "the sheet names the session's own commits: from the newest commit made before it began to its last"
has "$(sh $Q1)" "\`$OWN ${A:0:10}..${C:0:10}\`"
it "commits made before the session's first stop are its own, whatever commit that stop recorded"
has "$(sh $Q9)" "\`$OWN ${C:0:10}..${E:0:10}\`"
it "the base is on the session's own line: a newer commit that came in by a merge is not it"
has "$(sh $QD)" "\`$OWN ${G:0:10}..${M:0:10}\`"
it "a commit made after the session's first line is its own, though its last line is later still"
has "$(sh $QE)" "\`$OWN ${D:0:10}..${H:0:10}\`"
it "a session that began before the repository's first commit: the whole history is its own"
has "$(sh $QA)" "\`$OWN ${A:0:10}\` (the history begins with this session)"
it "a session whose last commit was made before it began, one with no commit, and one whose commit is not here have none to name"
has "$(sh $QC)" "No commit of this session's is known"
has "$(sh $Q3)" "No commit of this session's is known"
has "$(sh $QB)" "No commit of this session's is known"
lacks "$(sh $QC; sh $Q3; sh $QB)" "$OWN"
it "an index entry with no start time names no commits either, and the sheet is still written"
RB="$TMPROOT/rubric-notime"; keep "$RB" $Q1 "$A" "$C"
python3 - "$RB/sessions/$Q1.json" <<'PY'
import json, sys
e = json.load(open(sys.argv[1])); e["first_timestamp"] = None
json.dump(e, open(sys.argv[1], "w"), indent=2)
PY
(cd "$TMPROOT" && "$T" sheet "$RB" --repo-dir "$REPO" --labels "$RB/labels" > /dev/null 2>&1)
has "$(cat "$RB/sheets/$Q1.md" 2>&1)" "No commit of this session's is known"

(cd "$TMPROOT" && AGENT_TRANSCRIPTS="$RA" "$T" grade --repo-dir "$REPO" > /dev/null 2>&1)
r="$(report "$RA" 2>&1)"; rc=$?
it "C2: a label file may still carry a line for each rubric that was judged once: it loads and is counted for nothing"
assert_eq 0 "$rc"
printf 'code-quality: block | made-up: labelled while the rubric was asked\nverbosity: verbose | made-up: labelled while the rubric was asked\n' >> "$RA/labels/$Q1.txt"
sed -i.bak 's/^labelled-by:.*/labelled-by: A Labeller, 2026-11-12/; s/^red-first:.*/red-first: pass | made-up: a step labelled beside the two lines/' "$RA/labels/$Q1.txt"; rm -f "$RA/labels/$Q1.txt.bak"
r2="$(report "$RA" 2>&1)"; rc=$?
assert_eq 0 "$rc"
lacks "$r2" "code-quality"; lacks "$r2" "verbosity"
it "and its label is still checked: a word the rubric did not have, or a label with no reason, rejects the file"
sed -i.bak 's/^verbosity: verbose/verbosity: wordy/' "$RA/labels/$Q1.txt"; rm -f "$RA/labels/$Q1.txt.bak"
r2="$(report "$RA" 2>&1)"; rc=$?
assert_eq 1 "$rc"
has "$r2" "$Q1.txt: verbosity: unknown label 'wordy' (proportionate, verbose, terse or na)"
sed -i.bak 's/^verbosity: wordy.*/verbosity: verbose | made-up/; s/^code-quality: block.*/code-quality: block/' "$RA/labels/$Q1.txt"; rm -f "$RA/labels/$Q1.txt.bak"
has "$(report "$RA" 2>&1)" "$Q1.txt: code-quality: a label needs a one-line reason after |"
sed -i.bak 's/^code-quality: block.*/code-quality: fine | made-up/' "$RA/labels/$Q1.txt"; rm -f "$RA/labels/$Q1.txt.bak"
has "$(report "$RA" 2>&1)" "$Q1.txt: code-quality: unknown label 'fine' (approve, block or na)"
sed -i.bak 's/^code-quality: fine.*/code-quality: block | made-up/' "$RA/labels/$Q1.txt"; rm -f "$RA/labels/$Q1.txt.bak"
it "C2: rows the rubric judges left in the folder at an earlier run are not in the report, and change nothing in it"
py - "$RA/scores/$Q1.json" "$RA/scores/$Q1.rubrics.json" <<'PY'
import json, sys
row = json.load(open(sys.argv[1]))[0]
old = [dict(row, step="code-quality", grader="rubric/2:sonnet", verdict="fail", evidence={"label": "block", "why": "an earlier run", "partial": False, "votes": ["vote"] * 3}),
       dict(row, step="verbosity", grader="rubric/1:haiku", verdict="pass", evidence={"label": "proportionate", "why": "an earlier run", "partial": False, "votes": ["vote"] * 3})]
json.dump(old, open(sys.argv[2], "w"), indent=2)
PY
before="$(report "$RA" 2>&1)"
mv "$RA/scores/$Q1.rubrics.json" "$TMPROOT/held.json"; without="$(report "$RA" 2>&1)"; mv "$TMPROOT/held.json" "$RA/scores/$Q1.rubrics.json"
lacks "$before" "rubric/"; lacks "$before" "code-quality"; lacks "$before" "verbosity"
assert_eq "$without" "$before"
has "$before" "| red-first | fields/3 |"

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
it "the report on the store says how much the store holds, by redaction version (record 2026-11-15-user-level-capture, R8)"
# 250 chunks of one session under redaction 1 (more than one page of rows), then one chunk each of two sessions under 2
py - "$URL" <<'PYEOF'
import json, sys, urllib.request
def chunk(sid, n, size, redaction):
    return {"session_id": sid, "stream": "main", "chunk_id": "%064x" % (n + redaction * 1000), "start_id": "%064x" % n, "sender": "t",
            "generation": redaction, "number": n, "lines": 1, "bytes": size, "redaction": redaction, "data": ""}
rows = [chunk("s-one", n, 10_000, 1) for n in range(1, 251)] + [chunk("s-one", 1, 500_000, 2), chunk("s-two", 1, 1_240_000, 2)]
for i in range(0, len(rows), 100):
    req = urllib.request.Request(sys.argv[1] + "/rest/v1/chunks", data=json.dumps(rows[i:i + 100]).encode(),
                                 headers={"Content-Type": "application/json"}, method="POST")
    assert urllib.request.urlopen(req).status == 201
PYEOF
r="$(cd "$TMPROOT" && AGENT_TRANSCRIPTS_URL="$URL" "$T" report "$TMPROOT/empty" --store 2>&1)"
has "$r" "The store holds 2 sessions and 4.2 MB of redacted text: under redaction 1, 1 session and 2.5 MB; under redaction 2, 2 sessions and 1.7 MB."
assert_eq "# Change skill report" "$(printf '%s\n' "$r" | head -1)"
assert_eq "3" "$(printf '%s\n' "$r" | grep -n '^The store holds' | cut -d: -f1)"
it "without --store the report says nothing of the store"
lacks "$(cd "$TMPROOT" && "$T" report "$AR6" 2>&1)" "The store holds"

echo "a question left with no verdict is asked again, and --store sends what was judged before (record 2026-11-12-judge-asks-again)"
# sent TABLE: how many inserts into TABLE the stand-in has taken so far
sent() { py -c 'import json,sys; print(sum(1 for l in open(sys.argv[1]) if json.loads(l)["path"]=="/rest/v1/"+sys.argv[2] and json.loads(l)["method"]=="POST"))' "$SLOG" "$1"; }
qjson() { py -c 'import json,sys; print(json.dumps(json.load(open(sys.argv[1]))["questions"][sys.argv[2]], sort_keys=True))' "$1" "$2"; }
G1="$TMPROOT/again1"; fresh "$G1" $J1; rm -f "$COUNTER"; : > "$FAKELOG"
out="$(FAKE_SCRIPT="error,error,error,error,error,error" judge "$G1" --repo-dir "$REPO")"; rc=$?
it "a run in which every answer was an error leaves both questions undecided, says so and exits 1"
assert_eq "1 undecided undecided" "$rc $(jv "$G1/judges/$J1.claude.json" decisions-alternative) $(jv "$G1/judges/$J1.claude.json" outcome-real-output)"
has "$out" "${J1:0:8}: 6 of the judge's answers were errors; a question left with no verdict is asked again at the next run"
rm -f "$COUNTER"; : > "$FAKELOG"
out="$(judge "$G1" --repo-dir "$REPO")"; rc=$?
it "the next run asks that session again, and it has its verdicts"
assert_eq "0 6 pass pass" "$rc $(calls) $(jv "$G1/judges/$J1.claude.json" decisions-alternative) $(jv "$G1/judges/$J1.claude.json" outcome-real-output)"
lacks "$out" "already judged"
G2="$TMPROOT/again2"; fresh "$G2" $J1; rm -f "$COUNTER"; : > "$FAKELOG"
out="$(FAKE_SCRIPT="content,content,content,malformed,malformed,content" judge "$G2" --repo-dir "$REPO")"; rc=$?
it "answers that are not votes, with none an error, leave the question undecided and the run exits 0"
assert_eq "0 pass undecided" "$rc $(jv "$G2/judges/$J1.claude.json" decisions-alternative) $(jv "$G2/judges/$J1.claude.json" outcome-real-output)"
kept="$(qjson "$G2/judges/$J1.claude.json" decisions-alternative)"
rm -f "$COUNTER"; : > "$FAKELOG"
out="$(judge "$G2" --repo-dir "$REPO")"; rc=$?
it "the next run asks only the question with no verdict: three calls, and the other's votes are as they were"
assert_eq "0 3 pass" "$rc $(calls) $(jv "$G2/judges/$J1.claude.json" outcome-real-output)"
assert_eq "$kept" "$(qjson "$G2/judges/$J1.claude.json" decisions-alternative)"
lacks "$(cat "$FAKELOG")" "<decisions>"
it "a session with a verdict for every question is still not asked again"
before="$(calls)"; out="$(judge "$G2" --repo-dir "$REPO")"
assert_eq "$before" "$(calls)"
has "$out" "1 already judged"
it "the agreement judge is asked again the same way"
G3="$TMPROOT/again3"; fresh "$G3" $J1; rm -f "$COUNTER"; : > "$FAKELOG"
judge "$G3" --repo-dir "$REPO" > /dev/null
rm -f "$COUNTER"; : > "$FAKELOG"
FAKE_SCRIPT="error,error,error,content,content,content" judge "$G3" --repo-dir "$REPO" --judge opencode > /dev/null; rc=$?
assert_eq "1 undecided pass" "$rc $(jv "$G3/judges/$J1.opencode.json" decisions-alternative) $(jv "$G3/judges/$J1.opencode.json" outcome-real-output)"
rm -f "$COUNTER"; : > "$FAKELOG"
judge "$G3" --repo-dir "$REPO" --judge opencode > /dev/null; rc=$?
assert_eq "0 3 pass" "$rc $(calls) $(jv "$G3/judges/$J1.opencode.json" decisions-alternative)"
it "an error among the answers of a question that was decided is counted in its own run only"
G5="$TMPROOT/again5"; fresh "$G5" $J1; rm -f "$COUNTER"; : > "$FAKELOG"
out="$(FAKE_SCRIPT="content,content,error,malformed,malformed,content" judge "$G5" --repo-dir "$REPO")"; rc=$?
assert_eq "1 pass undecided" "$rc $(jv "$G5/judges/$J1.claude.json" decisions-alternative) $(jv "$G5/judges/$J1.claude.json" outcome-real-output)"
has "$out" "${J1:0:8}: 1 of the judge's answers were errors"
rm -f "$COUNTER"; : > "$FAKELOG"
out="$(judge "$G5" --repo-dir "$REPO")"; rc=$?
assert_eq "0 3 pass" "$rc $(calls) $(jv "$G5/judges/$J1.claude.json" outcome-real-output)"
lacks "$out" "were errors"

S1="$TMPROOT/later1"; fresh "$S1" $J1; rm -f "$COUNTER"; : > "$FAKELOG"
judge "$S1" --repo-dir "$REPO" > /dev/null
s0="$(sent scores)"; v0="$(sent judge_votes)"; : > "$FAKELOG"
out="$(AGENT_TRANSCRIPTS_URL="$URL" judge "$S1" --repo-dir "$REPO" --store)"; rc=$?
it "--store sends the rows of a session judged before without it, and asks no judge"
assert_eq "0 0 2 6" "$rc $(calls) $(( $(sent scores) - s0 )) $(( $(sent judge_votes) - v0 ))"
has "$out" "stored 8 rows"
it "the rows carry the time the session was judged, not the time they were sent"
assert_eq "True" "$(py -c '
import json,sys
doc=json.load(open(sys.argv[2])); rows=[json.loads(x["body"]) for x in map(json.loads, open(sys.argv[1])) if x["method"]=="POST"][-8:]
print(all((r.get("graded_at") or r.get("judged_at"))==doc["judged_at"] and r["session_id"]==doc["session_id"] for r in rows))' "$SLOG" "$S1/judges/$J1.claude.json")"
it "they are sent once: the next --store run sends nothing"
s1="$(sent scores)"; v1="$(sent judge_votes)"
out="$(AGENT_TRANSCRIPTS_URL="$URL" judge "$S1" --repo-dir "$REPO" --store)"; rc=$?
assert_eq "0 0 0" "$rc $(( $(sent scores) - s1 )) $(( $(sent judge_votes) - v1 ))"
PORTR="$TMPROOT/port-refuse"; RLOG="$TMPROOT/store-refuse.log"; : > "$RLOG"
python3 "$STANDIN" "$PORTR" "$RLOG" "$READKEY" --refuse judge_votes & PIDS="$PIDS $!"
await_port "$PORTR"
S2="$TMPROOT/later2"; fresh "$S2" $J1; rm -f "$COUNTER"; : > "$FAKELOG"
out="$(AGENT_TRANSCRIPTS_URL="http://127.0.0.1:$(cat "$PORTR")" judge "$S2" --repo-dir "$REPO" --store)"; rc=$?
it "a store that refuses part of a session's rows: exit 1, the rows kept"
assert_eq 1 "$rc"
has "$out" "its rows are kept in"
s0="$(sent scores)"; v0="$(sent judge_votes)"; : > "$FAKELOG"
out="$(AGENT_TRANSCRIPTS_URL="$URL" judge "$S2" --repo-dir "$REPO" --store)"; rc=$?
it "the next --store run sends all of them, and asks no judge"
assert_eq "0 0 2 6" "$rc $(calls) $(( $(sent scores) - s0 )) $(( $(sent judge_votes) - v0 ))"
S3="$TMPROOT/later3"; fresh "$S3" $J1; rm -f "$COUNTER"; : > "$FAKELOG"
n0="$(wc -l < "$SLOG" | tr -d ' ')"
FAKE_SCRIPT="content,content,content,malformed,malformed,content" AGENT_TRANSCRIPTS_URL="$URL" judge "$S3" --repo-dir "$REPO" --store > /dev/null
rm -f "$COUNTER"; : > "$FAKELOG"; sleep 1
out="$(AGENT_TRANSCRIPTS_URL="$URL" judge "$S3" --repo-dir "$REPO" --store)"; rc=$?
it "a question asked again is stored under its new time; the one kept is sent with its first time, which the store already has"
assert_eq "0 3" "$rc $(calls)"
has "$out" "stored 4 rows"
assert_eq "1 2" "$(py -c '
import json,sys
rows=[json.loads(x["body"]) for x in list(map(json.loads, open(sys.argv[1])))[int(sys.argv[2]):] if x["method"]=="POST" and x["path"]=="/rest/v1/judge_votes"]
print(len({r["judged_at"] for r in rows if r["question"]=="decisions-alternative"}), len({r["judged_at"] for r in rows if r["question"]=="outcome-real-output"}))' "$SLOG" "$n0")"
it "the agreement judge's verdicts are not scores: --store sends its votes only, later too"
S4="$TMPROOT/later4"; fresh "$S4" $J1; rm -f "$COUNTER"; : > "$FAKELOG"
judge "$S4" --repo-dir "$REPO" > /dev/null; judge "$S4" --repo-dir "$REPO" --judge opencode > /dev/null
s0="$(sent scores)"; v0="$(sent judge_votes)"
out="$(AGENT_TRANSCRIPTS_URL="$URL" judge "$S4" --repo-dir "$REPO" --judge opencode --store)"; rc=$?
assert_eq "0 0 6" "$rc $(( $(sent scores) - s0 )) $(( $(sent judge_votes) - v0 ))"

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

echo "judge --repeats: how much of a closing message is said twice (record 2026-11-15-checkable-judges, R1 and R6)"
RW="$TMPROOT/repeats"; mkdir -p "$RW"; BRIEF="$here/../grade/briefs/repeats.md"
R1=e1000000-0000-0000-0000-000000000001; R2=e2000000-0000-0000-0000-000000000002; R3=e3000000-0000-0000-0000-000000000003
# rsession ID HOUR CLOSING-FILE|none: a session that says "Starting.", runs one command and writes the closing message;
# with none it only runs the command and writes nothing
rsession() {
  python3 - "$RW/$1.jsonl" "$1" "$2" "$3" "$REPO" <<'PY'
import json, sys
path, sid, hour, closing, cwd = sys.argv[1:]
def line(minute, kind, content):
    return json.dumps({"sessionId": sid, "timestamp": "2026-11-10T%s:%02d:00.000Z" % (hour, minute), "cwd": cwd, "gitBranch": "x",
                       "type": kind, "message": {"role": kind, "content": content}})
rows = [line(0, "user", "Add --shout.")]
if closing != "none":
    rows.append(line(1, "assistant", [{"type": "text", "text": "Starting."}]))
rows += [line(2, "assistant", [{"type": "tool_use", "id": "t1", "name": "Bash", "input": {"command": "python3 greet.py --shout ann"}}]),
         line(3, "user", [{"type": "tool_result", "tool_use_id": "t1", "content": "HELLO, ANN!"}])]
if closing != "none":
    rows.append(line(4, "assistant", [{"type": "text", "text": open(closing).read()}]))
    rows.append(line(5, "assistant", [{"type": "text", "text": "  \n"}]))   # an empty text is not the closing message
open(path, "w").write("\n".join(rows) + "\n")
PY
}
cat > "$RW/closing.md" <<EOF
Done. The flag \`--shout\` works and **7 tests** pass.

I did not run a mutation tool.

## Description
\`--shout\` is added. Seven tests pass now.
Contact $EMAIL for the key.
EOF
rsession $R1 15 "$RW/closing.md"; rsession $R2 16 "$RW/closing.md"; rsession $R3 17 none
# the answer the stand-in gives: two pairs, one point said once, and one of each thing that does not count
cat > "$RW/answer.json" <<EOF
Here it is.
{"points": [
 {"first": "The flag \`--shout\` works", "again": "--shout is  added"},
 {"first": "7 tests pass", "again": "Seven tests pass now"},
 {"first": "I did not run a mutation tool", "again": null},
 {"first": "this quote is nowhere in the message", "again": null},
 {"first": "Done.", "again": "the flag was never added"},
 {"first": "Contact <redacted:email> for the key", "again": "contact <REDACTED:EMAIL> for the **key**"},
 {"first": "Contact $EMAIL for the key", "again": null},
 "not an object"
]}
EOF
RAR="$TMPROOT/rar"
for s in $R1 $R2 $R3; do (cd "$TMPROOT" && AGENT_TRANSCRIPTS="$RAR" "$T" archive --transcript "$RW/$s.jsonl" < /dev/null > /dev/null 2>&1); done
# run with an archive named in the environment, as a hook's shell has: the judge's own call must not inherit it
repeats() { (cd "$TMPROOT" && AGENT_TRANSCRIPTS="$RAR" FAKE_ANSWER_FILE="$RW/answer.json" "$T" judge --repeats "$@" 2>&1); }
rj() { py -c 'import json,sys; d=json.load(open(sys.argv[1])); print(eval(sys.argv[2], {"d": d}))' "$1" "$2"; }
# appendix NAME NEXT: the text indented under the record's heading "## NAME", up to "## NEXT", with the indent and
# the blank lines around it taken off: what the brief file must hold
appendix() {
  python3 - "$here/../../../docs/changes/2026-11-15-checkable-judges.md" "$1" "$2" <<'PY'
import sys
block = open(sys.argv[1]).read().split("\n## " + sys.argv[2], 1)[1].split("\n## " + sys.argv[3], 1)[0]
print("\n".join(l[4:] for l in block.splitlines()[1:] if l.startswith("    ") or not l.strip()).strip("\n"))
PY
}
pid() { python3 -c 'import hashlib,sys; print(hashlib.sha256((sys.argv[1]+"\n"+sys.argv[2]).encode()).hexdigest()[:6])' "$1" "$2"; }

it "R6: with neither --session nor --limit no call is made, and it says which two options choose the sessions"
rm -f "$COUNTER"; : > "$FAKELOG"; out="$(repeats "$RAR")"; rc=$?
assert_eq "2 0" "$rc $(calls)"; has "$out" "--session ID or --limit N"
it "R6: before any call it prints the sessions it will send, the calls and the most they can cost"
out="$(repeats "$RAR" --limit 1)"; rc=$?
assert_eq "0 1" "$rc $(calls)"
has "$out" "1 session to send to Claude Sonnet, 1 call, at most \$0.25: ${R2:0:8}"
it "--limit takes the newest sessions that have a closing message; one with none is not sent and says so"
has "$out" "${R3:0:8} not asked: the session wrote no message"
[ -f "$RAR/repeats/$R2.json" ] && [ ! -e "$RAR/repeats/$R1.json" ] && [ ! -e "$RAR/repeats/$R3.json" ] && ok || bad "$(ls "$RAR/repeats" 2>&1)"
it "R1: a known answer gives known numbers: points, pairs, quotes not found, same quote twice, the share"
F="$RAR/repeats/$R2.json"
assert_eq "counted 5 2 4 1 0.4" "$(rj "$F" '" ".join(str(d[k]) for k in ("status", "points", "said_again", "quotes_not_found", "same_quote_twice", "share"))')"
has "$out" "${R2:0:8} repeats: 2 of 5 points said again (0.40); 4 quotes not found, 1 pair that is one quote twice"
it "R1: each pair has the id made from its two quotes as compared, and keeps the quotes as given"
assert_eq "$(pid "the flag --shout works" "--shout is added") $(pid "7 tests pass" "seven tests pass now")" "$(rj "$F" '" ".join(p["id"] for p in d["pairs"])')"
assert_eq "The flag \`--shout\` works | --shout is  added" "$(rj "$F" 'd["pairs"][0]["first"] + " | " + d["pairs"][0]["again"]')"
it "R1: it keeps which message it took: its place in the transcript and its length"
assert_eq "4 $(python3 -c 'import sys; print(len(open(sys.argv[1]).read().replace(sys.argv[2], "<redacted:email>")))' "$RW/closing.md" "$EMAIL")" "$(rj "$F" 'str(d["message"]["entry"]) + " " + str(d["message"]["characters"])')"
it "R1: what the model was sent is the brief and then the closing message, redacted; the judge file holds no address either"
sent="$(py -c 'import json,sys; print(json.loads(open(sys.argv[1]).readlines()[-1])["prompt"], end="")' "$FAKELOG")"
assert_eq "$(cat "$BRIEF" 2>&1; sed "s/$EMAIL/<redacted:email>/" "$RW/closing.md")" "$sent"
lacks "$(cat "$F" 2>/dev/null)" "$EMAIL"
it "the brief is Appendix A of the record, word for word"
assert_eq "$(appendix "Appendix A" "Appendix B")" "$(cat "$BRIEF" 2>&1)"
it "the call: Sonnet, no tools, no settings, no saved session, a spending limit, in a folder of its own that is gone after, no archive in its environment"
assert_eq "True" "$(py -c '
import json,os,sys
c=json.loads(open(sys.argv[1]).readlines()[-1]); a=c["argv"]
def after(flag): return a[a.index(flag)+1]
print(after("--model")=="sonnet" and after("--tools")=="" and after("--setting-sources")=="" and "--no-session-persistence" in a
      and after("--max-budget-usd")=="0.25" and c["AGENT_TRANSCRIPTS"] is None
      and os.path.basename(c["cwd"]).startswith("transcripts-repeats-") and not os.path.exists(c["cwd"]) and c["cwd"] != sys.argv[2])' "$FAKELOG" "$TMPROOT")"
it "a session that has an answer for this brief and this message is not asked again; --again asks"
before="$(calls)"; out="$(repeats "$RAR" --session $R2)"; assert_eq "0 $before" "$? $(calls)"; has "$out" "1 already answered"
out="$(repeats "$RAR" --session $R2 --again)"; assert_eq "0 $((before + 1))" "$? $(calls)"
it "an answer that is not JSON, a refusal, an error, a run that failed and another model's answer are each kept as what they are, with no pair, and asked again next time"
for m in malformed refused error iserror haiku; do   # iserror: the answer is well formed, but the run says it failed
  out="$(FAKE_SCRIPT="$(printf 'content,%.0s' $(seq "$(calls)"))$m" repeats "$RAR" --session $R1)"; rc=$?
  want=$m; [ $m = haiku ] && want=error; [ $m = iserror ] && want=error
  assert_eq "1 $want 0 None" "$rc $(rj "$RAR/repeats/$R1.json" '" ".join(str(d[k]) for k in ("status", "said_again", "share"))')"
done
has "$out" "served by claude-haiku-5-5, not Sonnet"
before="$(calls)"; out="$(repeats "$RAR" --session $R1)"; assert_eq "0 $((before + 1)) counted" "$? $(calls) $(rj "$RAR/repeats/$R1.json" 'd["status"]')"
it "an answer whose points are not a list is malformed, not a session with no repeats"
printf '{"points": "none"}' > "$RW/odd.json"
out="$(cd "$TMPROOT" && FAKE_ANSWER_FILE="$RW/odd.json" "$T" judge --repeats "$RAR" --session $R1 --again 2>&1)"; assert_eq "1 malformed" "$? $(rj "$RAR/repeats/$R1.json" 'd["status"]')"
it "--transcript FILE... --out DIR judges transcript files into DIR, which is outside every working tree"
RO="$TMPROOT/rout"; out="$(repeats --transcript "$RW/$R1.jsonl" "$RW/$R3.jsonl" --out "$RO")"; rc=$?
assert_eq "0 counted 0.4" "$rc $(rj "$RO/repeats/$R1.json" 'd["status"] + " " + str(d["share"])')"; has "$out" "${R3:0:8} not asked: the session wrote no message"
it "a kept answer is for the message it was given: when the session has written a later one, it is asked again"
before="$(calls)"; out="$(repeats --transcript "$RW/$R1.jsonl" --out "$RO")"; assert_eq "0 $before" "$? $(calls)"; has "$out" "1 already answered"
cp "$RW/$R1.jsonl" "$RW/keep.jsonl"
printf '{"sessionId":"%s","timestamp":"2026-11-10T15:09:00.000Z","cwd":"%s","gitBranch":"x","type":"assistant","message":{"role":"assistant","content":[{"type":"text","text":"One more thing: the flag is documented."}]}}\n' "$R1" "$REPO" >> "$RW/$R1.jsonl"
out="$(repeats --transcript "$RW/$R1.jsonl" --out "$RO")"; assert_eq "0 $((before + 1))" "$? $(calls)"
assert_eq "6 39" "$(rj "$RO/repeats/$R1.json" 'str(d["message"]["entry"]) + " " + str(d["message"]["characters"])')"; mv "$RW/keep.jsonl" "$RW/$R1.jsonl"
it "--out must be outside every working tree, and --transcript needs it"
out="$(repeats --transcript "$RW/$R1.jsonl" --out "$REPO/out")"; assert_eq 2 "$?"; has "$out" "working tree"
out="$(repeats --transcript "$RW/$R1.jsonl")"; assert_eq 2 "$?"; has "$out" "--out DIR"
it "the record judge is as it was: it still runs with neither --session nor --limit"
RAR2="$TMPROOT/rar2"; fresh "$RAR2" $J1; out="$(judge "$RAR2" --repo-dir "$REPO")"; assert_eq 0 "$?"; has "$out" "judged 1 sessions"

echo "judge --review: the defects a reviewer that runs the code can show (record 2026-11-15-checkable-judges, R2, R3, R6, R7)"
# A repository: a base commit, the session's commit (a crash when no name is given), a later fix the
# reviewer must not see, and a line of its own that began after the session did.
VROOT="$(mktemp -d /var/tmp/transcripts-review-test.XXXXXX)" && VROOT="$(cd "$VROOT" && pwd -P)" || { echo "cannot make a folder under /var/tmp" >&2; exit 1; }
mkdir -p "$VROOT/home"; printf 'x\n' > "$VROOT/home/marker"
RV="$VROOT/rv"; mkdir -p "$RV"; (
  cd "$RV" && git init -q -b main && git config user.email t@example.com && git config user.name t && git config core.hooksPath /dev/null
  printf 'import sys\nprint("Hello, " + (sys.argv[1] if len(sys.argv) > 1 else "world") + "!")\n' > greet.py
  printf 'the same\n' > twin-a; printf 'the same\n' > twin-b
  git add -A && at 09 commit -qm init
  printf 'import sys\nargs = sys.argv[1:]\nnames = [a for a in args if a != "--shout"]\ntext = "Hello, " + names[0] + "!"\nprint(text.upper() if "--shout" in args else text)\n' > greet.py
  git add -A && at 10 commit -qm "feat: shout"
  printf 'the fix\n' > answer.txt; git add -A && at 12 commit -qm "fix: no name"
  git checkout -q --orphan side && git rm -rqf . && printf 'x\n' > side.txt && git add -A && at 10:40 commit -qm "a line of its own" && git checkout -q main
)
VB="$(git -C "$RV" rev-parse main~2)"; VL="$(git -C "$RV" rev-parse main~1)"; VLATER="$(git -C "$RV" rev-parse main)"; VO="$(git -C "$RV" rev-parse side)"
V1=f1000000-0000-0000-0000-000000000001; V2=f2000000-0000-0000-0000-000000000002; V3=f3000000-0000-0000-0000-000000000003
VAR="$VROOT/var"
# vsession ID COMMIT|none: a session begun at 10:00 whose last stop was at COMMIT
vsession() {
  rsession "$1" 10 "$RW/closing.md"
  (cd "$TMPROOT" && AGENT_TRANSCRIPTS="$VAR" "$T" archive --transcript "$RW/$1.jsonl" < /dev/null > /dev/null 2>&1)
  python3 - "$VAR/sessions/$1.json" "$2" <<'PY'
import json, sys
p, c = sys.argv[1:]
e = json.load(open(p)); e["first_stop"] = e["last_stop"] = {"branch": "main", "commit": None if c == "none" else c}
json.dump(e, open(p, "w"), indent=2)
PY
}
vsession $V1 "$VL"; vsession $V2 none; vsession $V3 "$VO"
# What the stand-in reviewer leaves: one script of each sort, and an answer that names six of them.
FRD="$TMPROOT/reviewer"; mkdir -p "$FRD/.review"
crash='python3 greet.py %s 2>&1 | tail -1; python3 greet.py %s 2>&1 | grep -q IndexError'
printf "# no name with --shout: a traceback\n$crash\n" --shout --shout > "$FRD/.review/defect-1.sh"
printf 'echo "always, says %s"; exit 0\n' "$EMAIL" > "$FRD/.review/defect-2.sh"
ln -s /etc/hostname "$FRD/.review/link.sh"   # a link is not a script
printf 'echo never; exit 1\n' > "$FRD/.review/defect-3.sh"
printf 'sleep 60; exit 0\n' > "$FRD/.review/defect-4.sh"
printf "echo x > left-behind.txt\n$crash\n" --shout --shout > "$FRD/.review/defect-5.sh"
printf "# no name at all: the same crash, and the answer does not name this script\n$crash\n" "" "" > "$FRD/.review/extra.sh"
cat > "$FRD/.review/box.sh" <<EOF
# what a script can reach, and the crash, so that it counts
(echo x > "$VROOT/outside-box") 2>/dev/null
[ -e "$RV/greet.py" ] && echo "repository: seen" || echo "repository: hidden"
[ -e "$VAR/sessions" ] && echo "archive: seen" || echo "archive: hidden"
[ -e "$VROOT/home/marker" ] && echo "home: seen" || echo "home: hidden"
echo "variable: [\${SECRET_FROM_CALLER:-}]"
(echo x > .git/probe) 2>/dev/null && echo "git folder: written" || echo "git folder: read-only"
python3 -c 'import socket,sys; socket.create_connection(("127.0.0.1", int(sys.argv[1])), 3)' "${URL##*:}" 2>/dev/null; [ \$? = 0 ] && echo "network: reached" || echo "network: none"
d=\$(mktemp -d) && echo "temporary folder: ok"
python3 greet.py 2>&1 | grep -q IndexError
EOF
# Two more ways to change the clone that leave what every tracked file reads as: a new, empty folder, and a file
# swapped for a link to its twin (twin-a and twin-b hold the same in every commit). Each is a change.
printf "mkdir left-folder\n$crash\n" "" "" > "$FRD/.review/defect-7.sh"
printf 'rm twin-a && ln -s twin-b twin-a\n' > "$FRD/.review/defect-8.sh"
printf "$crash\n" "" "" >> "$FRD/.review/defect-8.sh"
# A script that plants a command in the clone's own git configuration, for git to run when the tool next
# looks at the clone (found by the review of pull request 1): nothing may come of it, boxed or not.
cat > "$FRD/.review/escape.sh" <<EOF
printf '#!/bin/sh\ntouch "$VROOT/escaped"\n' > .git/planted.sh 2>/dev/null; chmod +x .git/planted.sh 2>/dev/null
git config core.fsmonitor .git/planted.sh 2>/dev/null   # a path from the clone's root: the same in the box and out of it
python3 greet.py 2>&1 | grep -q IndexError
EOF
cat > "$FRD/answer.json" <<EOF
Done.
{"defects": [
 {"script": ".review/defect-1.sh", "file": "greet.py", "kind": "crash", "what": "No name gives a traceback. Ask $EMAIL.", "guarantee": null},
 {"script": ".review/defect-2.sh", "file": "greet.py", "kind": "other", "what": "always", "guarantee": null},
 {"script": ".review/defect-3.sh", "file": "greet.py", "kind": "other", "what": "never", "guarantee": null},
 {"script": ".review/defect-4.sh", "file": "greet.py", "kind": "other", "what": "slow", "guarantee": null},
 {"script": ".review/defect-5.sh", "file": "greet.py", "kind": "wrong result", "what": "leaves a file", "guarantee": null},
 {"script": ".review/defect-6.sh", "file": "greet.py", "kind": "stated guarantee broken", "what": "no script", "guarantee": "the README"}],
 "unverified": ["a guess"], "experiments": ["tried no name", "tried two names"]}
EOF
RLOG="$FAKELOG.review"
review() { (cd "$TMPROOT" && HOME="$VROOT/home" AGENT_TRANSCRIPTS="$VAR" CLAUDE_CODE_SESSION_ID=caller SECRET_FROM_CALLER=hunter2 FAKE_LATER="$VLATER" FAKE_REVIEW_DIR="$FRD" \
            AGENT_TRANSCRIPTS_SCRIPT_LIMIT=3 "$T" judge --review "$@" 2>&1); }
rcalls() { [ -f "$RLOG" ] && wc -l < "$RLOG" | tr -d ' ' || echo 0; }
rl() { py -c 'import json,sys; c=[json.loads(l) for l in open(sys.argv[1])]; print(eval(sys.argv[2], {"c": c, "json": json}))' "$RLOG" "$1"; }
VJ="$VAR/reviews/$V1/sonnet/review.json"
boxed=yes; bwrap --unshare-all --ro-bind / / true 2>/dev/null || boxed=no
# a bwrap that cannot start, first on PATH: a machine with no box
NOBOX="$TMPROOT/nobox"; mkdir -p "$NOBOX"; printf '#!/bin/sh\nexit 1\n' > "$NOBOX/bwrap"; chmod +x "$NOBOX/bwrap"

it "R6: with neither --session nor --limit no call is made, and it says which two options choose the sessions"
out="$(review "$VAR" --repo-dir "$RV")"; rc=$?
assert_eq "2 0" "$rc $(rcalls)"; has "$out" "--session ID or --limit N"
it "R7: where no box can be started for the scripts it refuses before any call, unless --local is given"
out="$(PATH="$NOBOX:$PATH" review "$VAR" --repo-dir "$RV" --session $V1)"; rc=$?
assert_eq "2 0" "$rc $(rcalls)"; has "$out" "--local"; has "$out" "with your own access"
it "R2: a session with no commit of its own, and one whose line began with it, are not reviewed and say which"
out="$(review "$VAR" --repo-dir "$RV" --session $V2 --session $V3 $([ $boxed = no ] && echo --local))"; rc=$?
assert_eq "0 0" "$rc $(rcalls)"
has "$out" "${V2:0:8} not reviewed: no commit recorded for the session"; has "$out" "${V3:0:8} not reviewed: its commits have no base"

if [ $boxed = yes ]; then
it "R6: before any call it prints the sessions, the calls (the sandbox check among them) and the most they can cost"
left() { ls -d "${TMPDIR:-/tmp}"/transcripts-review-* 2>/dev/null | wc -l | tr -d ' '; }; left_before="$(left)"
rm -f "$VROOT/outside-box"; out="$(review "$VAR" --repo-dir "$RV" --session $V1)"; rc=$?
assert_eq "0 2" "$rc $(rcalls)"
has "$out" "1 session to review with Claude Sonnet, 2 calls (1 to check the sandbox), at most \$1.55: ${V1:0:8}"
it "R7: the first call checks the sandbox: Haiku, in the sandbox, told to run the tool's own probe"
assert_eq "True haiku True" "$(rl 'str(c[0]["check"]) + " " + c[0]["argv"][c[0]["argv"].index("--model") + 1] + " " + str(json.loads(c[0]["settings"])["sandbox"]["enabled"])')"
it "R2: the reviewer: Sonnet with a shell and the three read tools, no setting source, a spending limit, the event stream"
has "$(rl '"|".join(c[1]["argv"])')" "-p|--model|sonnet|--permission-mode|acceptEdits|--allowedTools|Bash|Read|Grep|Glob|--setting-sources||--settings|"
has "$(rl '"|".join(c[1]["argv"])')" "|--max-budget-usd|1.5|--output-format|stream-json|--verbose"
it "R2: its folder is a clone with no remote, no ref and no commit after the session's last, outside the repository and the archive"
assert_eq "[] [] 2 $VL False" "$(rl '"[%s] [%s] %s %s %s" % (c[1]["remotes"], c[1]["refs"], c[1]["commits"], c[1]["head"], c[1]["later"])')"
assert_eq "False False False" "$(py -c 'import json,os,sys; c=[json.loads(l) for l in open(sys.argv[1])]; w=c[1]["cwd"]; print(w.startswith(sys.argv[2]), w.startswith(sys.argv[3]), os.path.exists(w))' "$RLOG" "$RV" "$VAR")"
it "R2: the brief is grade/briefs/review.md with the two commits, which is Appendix B of the record, and names no path of the repository"
assert_eq "$(sed "s/@BASE@/${VB:0:10}/g; s/@HEAD@/${VL:0:10}/g" "$here/../grade/briefs/review.md" 2>&1)" "$(rl 'c[1]["prompt"].rstrip("\n")')"
assert_eq "$(appendix "Appendix B" "Outcome")" "$(cat "$here/../grade/briefs/review.md" 2>&1)"
lacks "$(rl 'c[1]["prompt"]')" "$RV"
it "R2: its settings turn the sandbox on, with no leave to run a command outside it, and deny reading the repository, the archive and the settings themselves"
assert_eq "True False True True True" "$(py -c '
import json,sys
c=[json.loads(l) for l in open(sys.argv[1])]; s=json.loads(c[1]["settings"]); deny=s["permissions"]["deny"]; a=c[1]["argv"]
print(s["sandbox"]["enabled"], s["sandbox"].get("allowUnsandboxedCommands"), "Read(/%s/**)" % sys.argv[2] in deny, "Read(/%s/**)" % sys.argv[3] in deny, "Read(/%s)" % a[a.index("--settings")+1] in deny)' "$RLOG" "$RV" "$VAR")"
it "R2: it does not inherit the caller's archive, session or other variables"
assert_eq "None None" "$(rl 'str(c[1]["env"]["AGENT_TRANSCRIPTS"]) + " " + str(c[1]["env"]["CLAUDE_CODE_SESSION_ID"])')"
it "R3: a defect is shown only if its script exits 0 at the last commit and not at the base, and leaves the clone as it was"
st() { py -c 'import json,sys; d=json.load(open(sys.argv[1])); print(" | ".join("%s %s %s" % (x["script"], x["status"], "named" if x["named"] else "not named") for x in d["defects"]))' "$VJ"; }
assert_eq "defect-1.sh shown named | defect-2.sh shown at the base too named | defect-3.sh not shown at the last commit named | defect-4.sh timed out named | defect-5.sh changed the clone named | defect-6.sh named and missing named | box.sh shown not named | defect-7.sh changed the clone not named | defect-8.sh changed the clone not named | escape.sh shown not named | extra.sh shown not named" "$(st)"
assert_eq "reviewed 4 False 2 1 0.3 $VB $VL" "$(rj "$VJ" '" ".join(str(d[k]) for k in ("status", "shown", "looked_outside", "experiments", "unverified", "cost_usd", "base", "last"))')"
has "$out" "${V1:0:8} review: 4 defects shown (1 crash, 3 not named in the answer); not counted: 1 shown at the base too, 1 not shown at the last commit, 1 timed out, 3 changed the clone, 1 named and missing"
it "R3: a shown defect's id is made from its script, and what the reviewer said of it is kept, redacted"
assert_eq "$(sha256sum "$FRD/.review/defect-1.sh" | cut -c1-6) crash greet.py" "$(rj "$VJ" '" ".join(d["defects"][0][k] for k in ("id", "kind", "file"))')"
lacks "$(cat "$VJ" 2>/dev/null)" "$EMAIL"; has "$(cat "$VJ" 2>/dev/null)" "<redacted:email>"
it "R3: the scripts and what they printed at each commit are kept under DIR/reviews/<session>/"
assert_eq "$(cat "$FRD/.review/defect-1.sh")" "$(cat "$VAR/reviews/$V1/sonnet/scripts/defect-1.sh" 2>&1)"
has "$(cat "$VAR/reviews/$V1/sonnet/runs/defect-1.sh.last.out" 2>&1)" "IndexError"; has "$(cat "$VAR/reviews/$V1/sonnet/runs/defect-1.sh.base.out" 2>&1)" "Hello, --shout!"
it "R7: a script runs in a box: it cannot write outside its clone, see the repository, the archive or the home folder, read the caller's variables or reach the network"
b="$(cat "$VAR/reviews/$V1/sonnet/runs/box.sh.last.out" 2>&1)"
for x in "repository: hidden" "archive: hidden" "home: hidden" "variable: []" "network: none" "temporary folder: ok" "git folder: read-only"; do has "$b" "$x"; done
[ -e "$VROOT/outside-box" ] && bad "the script wrote outside its clone" || ok
it "R7: a command a script plants in its clone's git configuration is never run: the tool runs no git where a script has been"
[ -e "$VROOT/escaped" ] && bad "the planted command ran, outside the box" || ok
it "R3: what a script printed is kept redacted, and a link among the scripts is not taken for one"
o="$(cat "$VAR/reviews/$V1/sonnet/runs/defect-2.sh.last.out" 2>&1)"; lacks "$o" "$EMAIL"; has "$o" "always, says <redacted:email>"
lacks "$(st)" "link.sh"; [ -e "$VAR/reviews/$V1/sonnet/scripts/link.sh" ] && bad "the link was copied" || ok
it "nothing of the run is left in the temporary folder: the clones are gone"
assert_eq "$left_before" "$(left)"
it "a session that has a review for this model, brief and commit is not reviewed again; --again reviews; another model's is kept apart"
before="$(rcalls)"; out="$(review "$VAR" --repo-dir "$RV" --session $V1)"; assert_eq "0 $before" "$? $(rcalls)"; has "$out" "1 already reviewed"
out="$(review "$VAR" --repo-dir "$RV" --session $V1 --model opus)"; assert_eq "0 $((before + 2))" "$? $(rcalls)"
assert_eq "opus sonnet" "$(rj "$VAR/reviews/$V1/opus/review.json" 'd["model"]') $(rj "$VJ" 'd["model"]')"; has "$(rl '"|".join(c[-1]["argv"])')" "|--model|opus|"
out="$(review "$VAR" --repo-dir "$RV" --session $V1 --again)"; assert_eq "0 $((before + 4))" "$? $(rcalls)"
it "R3: a run whose commands name the repository is kept, marked as having looked outside, and its defects are not counted"
out="$(FAKE_REVIEW_CMD="cat $RV/answer.txt" review "$VAR" --repo-dir "$RV" --session $V1 --again)"; rc=$?
assert_eq "1 looked outside True 0" "$rc $(rj "$VJ" 'd["status"] + " " + str(d["looked_outside"]) + " " + str(d["shown"])')"; has "$out" "looked outside its clone"
it "R7: a sandbox that lets a write out, lets the repository be read, or a check that did not run: nothing is reviewed and it says which"
for how in writes reads norun; do
  before="$(rcalls)"; out="$(FAKE_SANDBOX=$how review "$VAR" --repo-dir "$RV" --session $V1 --again)"; rc=$?
  assert_eq "1 $((before + 1))" "$rc $(rcalls)"
  case $how in writes) has "$out" "a write outside the reviewer's folder went through" ;; reads) has "$out" "the repository could be read" ;; norun) has "$out" "the check did not run" ;; esac
done
it "an answer that is no JSON, a failed run and a reviewer past its time are each kept as what they are and reviewed again next time"
for how in noanswer error slow; do
  out="$(FAKE_REVIEW=$how AGENT_TRANSCRIPTS_REVIEW_LIMIT=2 review "$VAR" --repo-dir "$RV" --session $V1 --again)"; rc=$?
  want="no answer"; [ $how = error ] && want=error; [ $how = slow ] && want="timed out"
  assert_eq "1 $want 0" "$rc $(rj "$VJ" 'd["status"] + " " + str(d["shown"])')"
done
before="$(rcalls)"; out="$(review "$VAR" --repo-dir "$RV" --session $V1)"; assert_eq "0 $((before + 2)) reviewed" "$? $(rcalls) $(rj "$VJ" 'd["status"]')"
it "the reviewer must be the model asked for: an answer another model served is an error, and only sonnet or opus can be asked for"
out="$(FAKE_SERVED=haiku review "$VAR" --repo-dir "$RV" --session $V1 --again)"; rc=$?
assert_eq "1 error 0" "$rc $(rj "$VJ" 'd["status"] + " " + str(d["shown"])')"; has "$out" "served by claude-haiku-5-5, not sonnet"
out="$(review "$VAR" --repo-dir "$RV" --session $V1 --again --model haiku)"; assert_eq 2 "$?"; has "$out" "--model sonnet|opus"
it "a kept review is for the commit it was made at: when the session's last commit is another, it is reviewed again"
out="$(review "$VAR" --repo-dir "$RV" --session $V1 --again)"; before="$(rcalls)"
out="$(review "$VAR" --repo-dir "$RV" --session $V1)"; assert_eq "0 $before" "$? $(rcalls)"
python3 - "$VAR/sessions/$V1.json" "$VLATER" <<'PY'
import json, sys
e = json.load(open(sys.argv[1])); e["last_stop"]["commit"] = sys.argv[2]; json.dump(e, open(sys.argv[1], "w"))
PY
out="$(review "$VAR" --repo-dir "$RV" --session $V1)"; assert_eq "0 $((before + 2)) $VLATER" "$? $(rcalls) $(rj "$VJ" 'd["last"]')"
python3 - "$VAR/sessions/$V1.json" "$VL" <<'PY'
import json, sys
e = json.load(open(sys.argv[1])); e["last_stop"]["commit"] = sys.argv[2]; json.dump(e, open(sys.argv[1], "w"))
PY
else
  echo "  (no bwrap can start here: the boxed runs are not tested on this machine)"
fi
it "R7: with --local on a machine with no box the scripts run as the caller, and it says so"
rm -f "$VROOT/outside-box"; out="$(PATH="$NOBOX:$PATH" review "$VAR" --repo-dir "$RV" --session $V1 --again --local)"; rc=$?
assert_eq "0 reviewed 4" "$rc $(rj "$VJ" 'd["status"] + " " + str(d["shown"])')"; has "$out" "with your own access"
[ -e "$VROOT/escaped" ] && bad "the planted command ran, with no box: the tool ran git in the script's clone" || ok
[ -e "$VROOT/outside-box" ] && ok || bad "expected the unboxed script to have written outside its clone"
has "$(cat "$VAR/reviews/$V1/sonnet/runs/box.sh.last.out" 2>&1)" "variable: []"
it "a script that prints without end is stopped at its time with only the end of its output kept, not all of it held in memory"
printf 'while :; do printf "%%01000d\\n" 7; done\n' > "$TMPROOT/noisy.sh"; mkdir -p "$TMPROOT/noisy-clone"
assert_eq "None True True" "$(cd "$here/../grade" && python3 -B -c '
import sys, tracemalloc
sys.dont_write_bytecode = True
import review
tracemalloc.start()
code, out = review.run_script(sys.argv[1], sys.argv[2], [], False, 2)
print(code, len(out) <= review.OUTPUT_CAP, tracemalloc.get_traced_memory()[1] < 5_000_000)' "$TMPROOT/noisy.sh" "$TMPROOT/noisy-clone" 2>&1)"
it "what a script left is compared without reading more than the clean clone held: a new file, or one of another size, is not read, in whichever order the folder is listed"
want="False True True True True | read: the file as it was, no new file, no grown file, the file with another byte"
assert_eq "$want / $want | small" "$(cd "$here/../grade" && python3 -B -c '
import os, sys, tracemalloc
sys.dont_write_bytecode = True
import review
work, clean, x_at = sys.argv[1], sys.argv[1] + "/clean", "printf x | dd bs=1 conv=notrunc 2>/dev/null seek=%d of=%s"
os.makedirs(clean); os.system("cd %s && %s" % (clean, x_at % (1 << 25, "big"))); was = review.tree_state(clean)
read, entry, entries = [], review.entry, review.entries
def noting(path, like=None):
    got = entry(path, like)
    read.extend([os.path.basename(path)] if got[0] == "file" and got[2] else [])
    return got
review.entry = noting
def after(command):   # (whether the tool finds the clone changed after a script that runs the command, the files it read)
    open(work + "/left.sh", "w").write(command + "\n"); del read[:]
    return review.try_script(work + "/left.sh", clean, was, work, [], False, 60)[2], list(read)
def one(order):       # a file system lists a folder in an order of its own: the new file before the old one, or after it
    review.entries = lambda root: sorted(entries(root), reverse=order)
    same, new, grown, gone, byte = after("true"), after(x_at % (1 << 31, "new")), after(x_at % (1 << 31, "big")), after("rm big"), after(x_at % (8, "big"))
    return "%s %s %s %s %s | read: %s, %s, %s, %s" % (
        same[0], new[0], grown[0], gone[0], byte[0], "the file as it was" if same[1] == ["big"] else same[1],
        "no new file" if "new" not in new[1] else "the new file", "no grown file" if not grown[1] else "the grown file",
        "the file with another byte" if byte[1] == ["big"] else byte[1])
tracemalloc.start()
print(one(False), "/", one(True), "| small" if tracemalloc.get_traced_memory()[1] < 5_000_000 else "| too much held")' "$TMPROOT/left" 2>&1 | tail -1)"
it "more than ten sessions are not reviewed in one run"
out="$(review "$VAR" --repo-dir "$RV" --limit 11)"; assert_eq 2 "$?"; has "$out" "at most 10"

echo
echo "transcripts judge and report: $pass passed, $fail failed"
[ "$fail" -eq 0 ]
