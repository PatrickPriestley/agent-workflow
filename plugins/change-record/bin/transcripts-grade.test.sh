#!/usr/bin/env bash
# Tests for transcripts grade (record docs/changes/2026-11-09-skill-transcripts.md, R8 and R9):
# the field graders on the two real dispatch sessions (grade/fixtures, redacted) and on made-up
# sessions, in both tool-result key orders, with flagged and unflagged failures and denials.
# Also the sheet a person labels from, the label files and transcripts accuracy (record
# docs/changes/2026-11-11-grading-trust.md, R1 to R3). Fixtures use made-up addresses and tokens only. Needs bash, git, gzip and python3.
set -u
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
T="$here/transcripts"; STANDIN="$here/../store/stand-in.py"; FIX="$here/../grade/fixtures"
# The real path, not a link to it: on macOS the temporary folder is /var/..., a link to /private/var/...,
# and git and python name the real one.
# a suite that cannot make its temporary folder must not go on: TMPROOT would be the folder it was started in
TMPROOT="$(mktemp -d)" && TMPROOT="$(cd "$TMPROOT" && pwd -P)" || { echo "cannot make a temporary folder" >&2; exit 1; }
PIDS=""
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
has()  { printf '%s' "$1" | grep -qF -- "$2" && ok || bad "missing [$2] in: $(printf '%s' "$1" | head -c 700)"; }
lacks() { printf '%s' "$1" | grep -qF -- "$2" && bad "unexpected [$2] in: $(printf '%s' "$1" | head -c 700)" || ok; }

unset CLAUDE_CODE_REMOTE CLAUDE_CODE_REMOTE_SESSION_ID CLAUDE_CODE_CONTAINER_ID AGENT_TRANSCRIPTS AGENT_TRANSCRIPTS_PARENT AGENT_TRANSCRIPTS_URL
export no_proxy="127.0.0.1,localhost" NO_PROXY="127.0.0.1,localhost"
export XDG_CONFIG_HOME="$TMPROOT/config"; mkdir -p "$XDG_CONFIG_HOME/agent-transcripts"
printf 'machine-G\n' > "$XDG_CONFIG_HOME/agent-transcripts/machine-id"
READKEY="read-key-made-up-0002"

# A repository like the dispatch sessions' one: commit A holds the approved tier 2 record with an
# empty Outcome, commit B the Outcome filled and the code changed, commit C a tier 1 record that
# is done, for the made-up sessions.
REPO="$TMPROOT/checkout"; mkdir -p "$REPO/docs/changes" "$REPO/tests" "$REPO/plugins/change-record/skills/change"
shout_record() { cat <<EOF
---
id: 2026-11-08-shout
tier: 2
status: approved
requester: A Requester
approvers: [A Requester, 2026-11-08]
---
# greet.py takes a --shout flag

## Goal
x

## Probed facts
- Verified against the real system: x

## Problem
x

## Requirements
- R1. x

## Options and concerns
- A. x

## Decisions
- x. Rejected: y.

## Tasks
1. x

## Checks
x

## Outcome
$1
EOF
}
mine_record() { cat <<EOF
---
id: $1
tier: 1
status: $2
requester: A Requester
---
# x

## Goal
x

## Probed facts
- Verified against the real system: x

## Decisions
- x. Rejected: y.

## Tasks
1. x

## Checks
x

## Outcome
$3
EOF
}
# at DAY git-args...: a git command whose commit is made on that day. The first commit is made long before
# any session here began and the others long after each ended, so the first is where a session started
# and the others are its own (record 2026-11-12-grader-faults).
at() { local d="$1"; shift; GIT_AUTHOR_DATE="${d}T00:00:00Z" GIT_COMMITTER_DATE="${d}T00:00:00Z" git "$@"; }
(
  cd "$REPO" && git init -q -b main && git config user.email t@example.com && git config user.name t
  git config core.hooksPath /dev/null
  printf -- '---\nname: change\n---\n# Change\n' > plugins/change-record/skills/change/SKILL.md
  printf 'def greet(n):\n    return n\n' > greet.py; printf 'import unittest\n' > tests/test_greet.py
  shout_record "" > docs/changes/2026-11-08-shout.md
  git add -A && at 2026-01-01 commit -qm "docs(change): 2026-11-08-shout" && git remote add origin https://github.com/Owner/Shout
  shout_record "Shipped the flag; output pasted." > docs/changes/2026-11-08-shout.md
  printf 'def greet(n):\n    return n.upper()\n' > greet.py
  at 2027-01-01 commit -qam "feat: shout"
  mine_record 2026-11-10-mine done "Shipped; output pasted." > docs/changes/2026-11-10-mine.md
  mine_record 2026-11-10-open open "" > docs/changes/2026-11-10-open.md
  # two open records whose task is ticked [x], one with an empty Outcome and one filled (record 2026-11-12-grader-fixes)
  mine_record 2026-11-10-ticked open "" | sed 's/^1\. x$/- [x] x/' > docs/changes/2026-11-10-ticked.md
  mine_record 2026-11-10-ticked-filled open "Shipped; output pasted." | sed 's/^1\. x$/- [x] x/' > docs/changes/2026-11-10-ticked-filled.md
  printf '# A record with no header\n\n## Outcome\nShipped.\n' > docs/changes/2026-11-10-bare.md
  # a long record, as the tier 2 records here are: 300 probed facts, then the sections a labeller is asked about
  mine_record 2026-11-10-long done "$(echo "Write to jane.roe@example.org about it."; for i in $(seq 2 120); do echo "outcome line $i"; done)" \
    | awk '{print} /^## Probed facts/{for(i=1;i<=300;i++) print "- fact " i}' > docs/changes/2026-11-10-long.md
  git add -A && at 2027-01-02 commit -qm "docs(change): mine"
)
A="$(git -C "$REPO" rev-parse HEAD~2)"; B="$(git -C "$REPO" rev-parse HEAD~1)"; C="$(git -C "$REPO" rev-parse HEAD)"

AR="$TMPROOT/archive"
# add FILE: archive a transcript; setstops SID FIRST LAST: the commits at its first and last stop.
add() { (cd "$TMPROOT" && AGENT_TRANSCRIPTS="$AR" "$T" archive --transcript "$1" < /dev/null 2>&1); }
setstops() { python3 - "$AR/sessions/$1.json" "$2" "$3" <<'PY'
import json, sys
p, first, last = sys.argv[1:]
e = json.load(open(p))
e["first_stop"] = {"branch": "x", "commit": first or None}
e["last_stop"] = {"branch": "x", "commit": last or None}
json.dump(e, open(p, "w"), indent=2)
PY
}
# v SID STEP: the verdict the scores file holds; ev SID STEP: its evidence, as JSON.
v()  { python3 -c 'import json,sys; r=[x for x in json.load(open(sys.argv[1])) if x["step"]==sys.argv[2]]; print(r[0]["verdict"] if r else "none")' "$AR/scores/$1.json" "$2" 2>/dev/null || echo "no-scores"; }
ev() { python3 -c 'import json,sys; r=[x for x in json.load(open(sys.argv[1])) if x["step"]==sys.argv[2]]; print(json.dumps(r[0]["evidence"]) if r else "none")' "$AR/scores/$1.json" "$2" 2>/dev/null || echo "no-scores"; }
grade() { (cd "$TMPROOT" && AGENT_TRANSCRIPTS="$AR" "$T" grade --repo-dir "$REPO" "$@" 2>&1); }

# A made-up session from a compact spec, one JSON event per line on stdin:
#   ["call", id, name, input]  ["result", id, text, is_error, "a"|"b"]  ["text", text]  ["prompt", text]
# Key order "a" is tool_use_id, type, content (as a passing result); "b" is type, content,
# is_error, tool_use_id (as a failing one); both are in the real transcripts.
GEN="$TMPROOT/gen.py"; cat > "$GEN" <<'PY'
import json, sys
path, sid, cwd = sys.argv[1:]
out, n = [], 0
for raw in sys.stdin:
    if not raw.strip():
        continue
    e = json.loads(raw)
    n += 1
    base = {"sessionId": sid, "timestamp": "2026-11-10T10:%02d:%02d.000Z" % divmod(n, 60), "cwd": cwd, "gitBranch": "x"}
    if e[0] == "call":
        base.update(type="assistant", message={"role": "assistant", "content": [{"type": "tool_use", "id": e[1], "name": e[2], "input": e[3]}]})
    elif e[0] == "result":
        if e[4] == "a":
            b = {"tool_use_id": e[1], "type": "tool_result", "content": e[2]}
        else:
            b = {"type": "tool_result", "content": e[2], "is_error": e[3], "tool_use_id": e[1]}
        base.update(type="user", message={"role": "user", "content": [b]})
    elif e[0] == "side":  # a subagent's call kept inline in the main transcript, as older versions did
        base.update(type="assistant", isSidechain=True, message={"role": "assistant", "content": [{"type": "tool_use", "id": e[1], "name": e[2], "input": e[3]}]})
    elif e[0] == "text":
        base.update(type="assistant", message={"role": "assistant", "content": [{"type": "text", "text": e[1]}]})
    else:
        base.update(type="user", message={"role": "user", "content": e[1]})
    out.append(json.dumps(base, separators=(",", ":")))
open(path, "w").write("\n".join(out) + "\n")
PY
mk() { python3 "$GEN" "$1" "$2" "$REPO"; }
W="$TMPROOT/sessions"; mkdir -p "$W"
REC="docs/changes/2026-11-10-mine.md"
UT='python3 -m unittest discover -s tests -t . 2>&1 | tail -5'
RED='Ran 4 tests in 0.002s\n\nFAILED (failures=1)'
DENY='This command requires approval'

echo "R8: the two real dispatch sessions grade as the probes expect"
D1=95e399c5-a1ef-4de4-8612-001551b4f84d; D2=da1017af-e406-4505-ade7-a5b331fa0989
gzip -dc "$FIX/dispatch-1-95e399c5.jsonl.gz" > "$W/$D1.jsonl"; gzip -dc "$FIX/dispatch-2-da1017af.jsonl.gz" > "$W/$D2.jsonl"
add "$W/$D1.jsonl" > /dev/null; add "$W/$D2.jsonl" > /dev/null
setstops "$D1" "$A" "$A"; setstops "$D2" "$A" "$B"
out="$(grade --session "$D1" --session "$D2")"; rc=$?
it "grade exits 0 and writes a scores file per session"
assert_eq "0 yes yes" "$rc $([ -f "$AR/scores/$D1.json" ] && echo yes) $([ -f "$AR/scores/$D2.json" ] && echo yes)"
it "dispatch-2 passes red-first: the suite was run and seen failing before greet.py changed"
assert_eq pass "$(v $D2 red-first)"
it "dispatch-1 fails red-first: every test run before the code was denied"
assert_eq fail "$(v $D1 red-first)"
it "dispatch-1's six denied test runs before the code count as not run"
has "$(ev $D1 red-first)" '"denied_test_runs": 6'
it "dispatch-1: its runs before the code are zero, the denials notwithstanding"
has "$(ev $D1 red-first)" '"test_runs_before_code": 0'
it "both are tied to the record they edited and named"
assert_eq "docs/changes/2026-11-08-shout.md docs/changes/2026-11-08-shout.md" \
  "$(python3 -c 'import json,sys; print(" ".join(json.load(open(a))[0]["evidence"].get("record") or "none" for a in sys.argv[1:]))' "$AR/scores/$D1.json" "$AR/scores/$D2.json")"
it "the record was there when they started, so record-before-code and probe-before-record do not apply"
assert_eq "not_applicable not_applicable not_applicable not_applicable" \
  "$(v $D1 record-before-code) $(v $D1 probe-before-record) $(v $D2 record-before-code) $(v $D2 probe-before-record)"
it "the Change: line opens the PR description each wrote (a PR.md file, and the last message)"
assert_eq "pass pass" "$(v $D1 change-line) $(v $D2 change-line)"
it "tier is declared and the record passes record-check at the last commit"
assert_eq "pass pass pass pass" "$(v $D1 tier-declared) $(v $D2 tier-declared) $(v $D1 record-check) $(v $D2 record-check)"
it "outcome-filled does not apply to a record that is not done"
assert_eq "not_applicable not_applicable" "$(v $D1 outcome-filled) $(v $D2 outcome-filled)"
it "each row carries the session, step, skill, its blob, the grader, a verdict and a time"
row="$(python3 -c 'import json,sys; r=json.load(open(sys.argv[1])); print(len(r), sorted(r[0]))' "$AR/scores/$D2.json")"
assert_eq "7 ['evidence', 'graded_at', 'grader', 'session_id', 'skill', 'skill_blob', 'step', 'verdict']" "$row"
it "the summary names each session's verdicts"
has "$out" "da1017af red-first pass"
it "grade and sheet refuse a session that is a path, not one id, before anything is read or written (record 2026-11-17-session-is-one-id)"
touch "$TMPROOT/before-bad"; sleep 1
for bad in "$TMPROOT/elsewhere" "../../elsewhere" "a/b" "." ".." "$D1"$'\n'; do
  out="$(grade --session "$bad")"; assert_eq 2 "$?"; has "$out" "is not one session id"
  out="$("$T" sheet "$AR" --session "$bad" --repo-dir "$REPO" --labels "$TMPROOT/labels-bad" 2>&1)"; assert_eq 2 "$?"; has "$out" "is not one session id"
done
assert_eq "" "$(find "$AR" -newer "$TMPROOT/before-bad" -type f)"; assert_eq "no" "$([ -e "$TMPROOT/labels-bad" ] && echo yes || echo no)"

echo "R8: failures from the flag or from the text, in either key order; denials and missing results do not run"
mkcase() { mk "$W/$1.jsonl" "$1"; add "$W/$1.jsonl" > /dev/null; setstops "$1" "$A" "$C"; }
S=11111111-0000-0000-0000-00000000000
mkcase ${S}1 <<EOF
["call","w1","Write",{"file_path":"$REPO/$REC","content":"x"}]
["result","w1","File created successfully at: $REPO/$REC",false,"a"]
["call","t1","Write",{"file_path":"$REPO/tests/test_greet.py","content":"import unittest"}]
["result","t1","ok",false,"a"]
["call","t2","Write",{"file_path":"$REPO/tests/helpers.py","content":"X = 1"}]
["result","t2","ok",false,"a"]
["call","r1","Bash",{"command":"$UT"}]
["result","r1","$RED",false,"a"]
["call","c1","Edit",{"file_path":"$REPO/greet.py","old_string":"n","new_string":"n.upper()"}]
["result","c1","ok",false,"a"]
EOF
mkcase ${S}2 <<EOF
["call","w1","Write",{"file_path":"$REPO/$REC","content":"x"}]
["result","w1","File created successfully at: $REPO/$REC",false,"b"]
["call","r1","Bash",{"command":"node --test tests/"}]
["result","r1","Exit code 1\n# tests 3\n# pass 2\n# fail 1",true,"b"]
["call","c1","Bash",{"command":"sed -i 's/n/n.upper()/' greet.py"}]
["result","c1","",false,"b"]
EOF
mkcase ${S}3 <<EOF
["call","w1","Write",{"file_path":"$REPO/$REC","content":"x"}]
["result","w1","File created successfully",false,"a"]
["call","r1","Bash",{"command":"$UT"}]
["result","r1","Ran 3 tests in 0.001s\n\nOK",false,"a"]
["call","c1","Write",{"file_path":"$REPO/greet.py","content":"x"}]
["result","c1","ok",false,"a"]
["call","r2","Bash",{"command":"$UT"}]
["result","r2","$RED",false,"a"]
EOF
mkcase ${S}4 <<EOF
["call","w1","Write",{"file_path":"$REPO/$REC","content":"x"}]
["result","w1","File created successfully",false,"a"]
["call","r1","Bash",{"command":"python3 -m unittest discover -s tests -t ."}]
["result","r1","$DENY",true,"b"]
["call","p1","Bash",{"command":"python3 -c 'assert False'"}]
["result","p1","Exit code 1\nTraceback (most recent call last):\nAssertionError\nFAILED (failures=1)",true,"b"]
["call","r2","Bash",{"command":"pytest -q"}]
["call","c1","Write",{"file_path":"$REPO/greet.py","content":"x"}]
["result","c1","ok",false,"a"]
EOF
mkcase ${S}5 <<EOF
["call","w1","Write",{"file_path":"$REPO/$REC","content":"x"}]
["result","w1","File created successfully",false,"a"]
["call","r1","Bash",{"command":"$UT"}]
["result","r1","Exit code 1\nTraceback (most recent call last):\nSyntaxError: invalid syntax",true,"b"]
["call","c1","Write",{"file_path":"$REPO/greet.py","content":"x"}]
["result","c1","ok",false,"a"]
EOF
mkcase ${S}v <<EOF
["call","w1","Write",{"file_path":"$REPO/$REC","content":"x"}]
["result","w1","File created successfully",false,"a"]
["call","p1","Bash",{"command":"mkdir -p \$S/probe && cd \$S/probe && claude -p hi > out.json"}]
["result","p1","",false,"a"]
["call","p2","Bash",{"command":"echo x > \$TMPDIR/probe.py; echo y > \"\${OUT:-/tmp}/n.py\""}]
["result","p2","",false,"a"]
["call","r1","Bash",{"command":"$UT"}]
["result","r1","$RED",false,"a"]
["call","c1","Edit",{"file_path":"$REPO/greet.py","old_string":"n","new_string":"n.upper()"}]
["result","c1","ok",false,"a"]
EOF
mkcase ${S}w <<EOF
["call","w1","Write",{"file_path":"$REPO/$REC","content":"x"}]
["result","w1","File created successfully",false,"a"]
["call","p1","Bash",{"command":"cd \$S/probe && cd $REPO && echo 'X = 1' >> greet.py"}]
["result","p1","",false,"a"]
["call","r1","Bash",{"command":"$UT"}]
["result","r1","$RED",false,"a"]
EOF
out="$(grade)"
it "a failure the result flags, or one only in its text, counts; in key order a or b"
assert_eq "pass pass" "$(v ${S}1 red-first) $(v ${S}2 red-first)"
it "a write under an unexpanded variable, or after cd into one, is not a write in the tree"
assert_eq "pass" "$(v ${S}v red-first)"
it "a cd back to a known path after one into a variable makes its writes count again"
assert_eq "fail" "$(v ${S}w red-first)"
it "a green run before the code, and a failure only after it, is not red first"
assert_eq fail "$(v ${S}3 red-first)"
it "a denied run, a failure in another command, and a run with no result do not count"
assert_eq fail "$(v ${S}4 red-first)"
it "the denied run and the unanswered one are counted as not run"
has "$(ev ${S}4 red-first)" '"denied_test_runs": 2'
it "a run that never reached the tests (a SyntaxError) is not a failing test"
assert_eq fail "$(v ${S}5 red-first)"
it "a shell edit of greet.py is code (sed -i), and a Write under tests/ is not"
assert_eq "pass pass" "$(v ${S}2 record-before-code) $(v ${S}1 record-before-code)"

echo "R8: record before code, probe before record, a code write that was denied"
mkcase ${S}6 <<EOF
["side","s0","Write",{"file_path":"$REPO/greet.py","content":"x"}]
["result","s0","ok",false,"a"]
["call","c0","Write",{"file_path":"$REPO/greet.py","content":"x"}]
["result","c0","Claude requested permissions to write to $REPO/greet.py, but you haven't granted it yet.",true,"b"]
["call","p1","Bash",{"command":"python3 -c 'import fileinput; print(fileinput.input)'"}]
["result","p1","<function input>",false,"a"]
["call","w1","Bash",{"command":"cat > $REC <<'EOF2'\n---\nid: x\nEOF2"}]
["result","w1","",false,"a"]
["call","c1","Bash",{"command":"echo 'X = 1' >> greet.py"}]
["result","c1","",false,"a"]
EOF
mkcase ${S}7 <<EOF
["call","w1","Write",{"file_path":"$REPO/$REC","content":"x"}]
["result","w1","File created successfully",false,"a"]
["call","p1","Bash",{"command":"python3 -c 'import fileinput'"}]
["result","p1","",false,"a"]
["call","c1","Bash",{"command":"cp /tmp/new_greet.py greet.py && python3 -m unittest"}]
["result","c1","Ran 1 test\n\nFAILED (failures=1)",false,"a"]
["call","w2","Edit",{"file_path":"$REPO/$REC","old_string":"a","new_string":"b"}]
["result","w2","ok",false,"a"]
EOF
mkcase ${S}8 <<EOF
["call","p1","Bash",{"command":"python3 -m pydoc fileinput | head"}]
["result","p1","$DENY",true,"b"]
["call","w1","Write",{"file_path":"$REPO/$REC","content":"x"}]
["result","w1","File created successfully",false,"a"]
EOF
out="$(grade)"
it "a denied code write, or a subagent's, is not this session's code; the record by heredoc comes first"
assert_eq pass "$(v ${S}6 record-before-code)"
it "a probe that ran before the record passes probe-before-record"
assert_eq pass "$(v ${S}6 probe-before-record)"
it "code by cp before the record's Edit, after its Write: the Write counts, record-before-code passes"
assert_eq pass "$(v ${S}7 record-before-code)"
it "a probe after the record fails probe-before-record"
assert_eq fail "$(v ${S}7 probe-before-record)"
it "a run in the same command as the code write is not a run before the code"
assert_eq fail "$(v ${S}7 red-first)"
it "a denied probe is no probe"
assert_eq fail "$(v ${S}8 probe-before-record)"
it "a session that wrote no code yet: red-first and record-before-code do not apply"
assert_eq "not_applicable not_applicable" "$(v ${S}8 red-first) $(v ${S}8 record-before-code)"
it "a session that opened no PR and wrote no description: change-line does not apply"
assert_eq not_applicable "$(v ${S}8 change-line)"
it "a record that is done with its Outcome filled passes outcome-filled; record-check passes at C"
assert_eq "pass pass" "$(v ${S}8 outcome-filled) $(v ${S}8 record-check)"

mkcase 44444444-0000-0000-0000-000000000001 <<EOF
["call","e1","Edit",{"file_path":"$REPO/$REC","old_string":"a","new_string":"b"}]
["result","e1","The file $REPO/$REC has been updated successfully.",false,"a"]
["call","c1","Write",{"file_path":"$REPO/greet.py","content":"x"}]
["result","c1","ok",false,"a"]
EOF
out="$(grade --session 44444444-0000-0000-0000-000000000001)"
it "a record the session edited first was there already, even when its first commit lacks it (uncommitted)"
assert_eq "not_applicable not_applicable" "$(v 44444444-0000-0000-0000-000000000001 record-before-code) $(v 44444444-0000-0000-0000-000000000001 probe-before-record)"

mkcase 44444444-0000-0000-0000-000000000002 <<EOF
["call","e1","Bash",{"command":"printf 'Shipped.\\n' >> docs/changes/2026-11-08-shout.md"}]
["result","e1","",false,"a"]
["call","c1","Write",{"file_path":"$REPO/greet.py","content":"x"}]
["result","c1","ok",false,"a"]
EOF
out="$(grade --session 44444444-0000-0000-0000-000000000002)"
it "a record in the session's first commit was there already, though the session only appended to it by shell"
assert_eq "not_applicable" "$(v 44444444-0000-0000-0000-000000000002 record-before-code)"

echo "R8: which record, and sessions with none"
mkcase ${S}9 <<EOF
["prompt","Change: docs/changes/2026-11-10-open.md\nWhat does greet.py do?"]
["call","q1","Read",{"file_path":"$REPO/greet.py"}]
["result","q1","def greet",false,"a"]
["text","It returns the name."]
EOF
mkcase 22222222-0000-0000-0000-000000000001 <<EOF
["call","w0","Write",{"file_path":"$REPO/docs/changes/2026-11-10-open.md","content":"x"}]
["result","w0","$DENY",true,"b"]
["call","w1","Write",{"file_path":"$REPO/$REC","content":"x"}]
["result","w1","File created successfully",false,"a"]
["call","g1","mcp__github__create_pull_request",{"title":"feat: x","body":"Change: $REC\n\nBody."}]
["result","g1","{\"number\": 7}",false,"a"]
EOF
mkcase 22222222-0000-0000-0000-000000000002 <<EOF
["call","w1","Write",{"file_path":"$REPO/$REC","content":"x"}]
["result","w1","File created successfully",false,"a"]
["call","g1","Bash",{"command":"gh pr create --title 'feat: x' --body \"\$(cat <<'EOF2'\n## Summary\n\nChange: $REC\nEOF2\n)\""}]
["result","g1","https://github.com/o/r/pull/8",false,"a"]
EOF
mkcase 22222222-0000-0000-0000-000000000003 <<EOF
["call","c1","Edit",{"file_path":"$REPO/greet.py","old_string":"n","new_string":"m"}]
["result","c1","ok",false,"a"]
["text","Fixed.\n\nTier: 1"]
EOF
mkcase 22222222-0000-0000-0000-000000000004 <<EOF
["call","c1","Edit",{"file_path":"$REPO/greet.py","old_string":"# teh","new_string":"# the"}]
["result","c1","ok",false,"a"]
["text","Typo fixed.\n\n**Tier: 0**"]
EOF
mkcase 22222222-0000-0000-0000-000000000005 <<EOF
["call","w1","Write",{"file_path":"$REPO/$REC","content":"x"}]
["result","w1","File created successfully",false,"a"]
["text","Change: docs/changes/2026-11-10-open.md"]
EOF
out="$(grade)"
it "a session with no record grades every record step as not applicable"
assert_eq "not_applicable not_applicable not_applicable not_applicable not_applicable" \
  "$(v ${S}9 probe-before-record) $(v ${S}9 record-before-code) $(v ${S}9 change-line) $(v ${S}9 record-check) $(v ${S}9 outcome-filled)"
it "and, with no code written, tier-declared and red-first do not apply either"
assert_eq "not_applicable not_applicable" "$(v ${S}9 tier-declared) $(v ${S}9 red-first)"
it "a Change: line in the prompt does not tie the session to that record"
has "$(ev ${S}9 record-check)" '"record": null'
it "a denied Write of another record does not tie the session to it"
has "$(ev 22222222-0000-0000-0000-000000000001 record-check)" "\"record\": \"$REC\""
it "a PR opened over MCP with the Change: line first passes change-line"
assert_eq pass "$(v 22222222-0000-0000-0000-000000000001 change-line)"
it "a PR opened by gh with the Change: line below a heading fails change-line"
assert_eq fail "$(v 22222222-0000-0000-0000-000000000002 change-line)"
it "code with no record and no Tier: 0 fails tier-declared, and red-first is graded"
assert_eq "fail fail not_applicable" "$(v 22222222-0000-0000-0000-000000000003 tier-declared) $(v 22222222-0000-0000-0000-000000000003 red-first) $(v 22222222-0000-0000-0000-000000000003 record-before-code)"
it "a tier 0 session declares it, and red-first does not apply to it"
assert_eq "pass not_applicable" "$(v 22222222-0000-0000-0000-000000000004 tier-declared) $(v 22222222-0000-0000-0000-000000000004 red-first)"
it "a session whose written and named records disagree is tied to neither"
has "$(ev 22222222-0000-0000-0000-000000000005 record-check)" '"record": null'

echo "Rulings (record 2026-11-12-grader-fixes): what a probe is"
R=55555555-0000-0000-0000-0000000000
# probecase ID COMMAND RESULT: a session that ran one command and then wrote its record
probecase() { mkcase "$1" <<EOF
["call","p1","Bash",{"command":$2}]
["result","p1",$3,false,"a"]
["call","w1","Write",{"file_path":"$REPO/$REC","content":"x"}]
["result","w1","File created successfully",false,"a"]
EOF
}
probecase ${R}01 '"cat docs/changes/TEMPLATE.md | head -30; python3 --version"' '"Python 3.13.1"'
probecase ${R}02 '"git --version && node -V"' '"git version 2.43.0"'
probecase ${R}03 '"git checkout -q -b shout; python3 -m unittest discover -s tests -t . 2>&1 | tail -3"' '"Ran 1 test in 0.000s\n\nOK"'
probecase ${R}04 '"ls -la /srv/audit 2>&1 | head; echo \"AUDIT_LOG=$AUDIT_LOG\""' '"ls: cannot access /srv/audit: No such file or directory\nAUDIT_LOG="'
probecase ${R}05 '"printenv AUDIT_LOG"' '""'
probecase ${R}06 '"test -d /srv/audit && echo there"' '""'
probecase ${R}07 '"ls -la; cat greet.py; ls '"$REPO"'/tests; cat /srv/audit/log | head; env LC_ALL=C sort greet.py"' '"greet.py"'
probecase ${R}08 '"OUT=/srv/x; echo $OUT; echo \"exit $?\"; echo $HOME $PWD; export LOG_DIR=/srv/y && echo $LOG_DIR"' '"/srv/x"'
probecase ${R}09 '"ls /tmp/scratch ~/.claude/plugins/cache/change-record/skills/change/references /opt/plugins/change-record"' '"probing.md"'
probecase ${R}10 '"git worktree --help | head -20"' '"usage: git worktree add"'
probecase ${R}11 '"env"' '"AUDIT_LOG=/srv/audit/log"'
probecase ${R}12 '"echo \"AUDIT_LOG=$AUDIT_LOG\""' '"AUDIT_LOG="'
out="$(grade)"
it "--version alone is no probe, after an interpreter or any other command"
assert_eq "fail fail" "$(v ${R}01 probe-before-record) $(v ${R}02 probe-before-record)"
it "a run of the existing tests before the record is a probe"
assert_eq pass "$(v ${R}03 probe-before-record)"
it "a look at the environment is a probe: a path outside the working tree, a variable, printenv, test -d, env"
assert_eq "pass pass pass pass pass" "$(v ${R}04 probe-before-record) $(v ${R}05 probe-before-record) $(v ${R}06 probe-before-record) $(v ${R}11 probe-before-record) $(v ${R}12 probe-before-record)"
it "listing or reading files is no probe, in the working tree or out of it"
assert_eq fail "$(v ${R}07 probe-before-record)"
it "a variable the command set itself, the exit status and the shell's own variables are no look at the environment"
assert_eq fail "$(v ${R}08 probe-before-record)"
it "a temporary folder and a plugin's or skill's own folder are not the environment"
assert_eq fail "$(v ${R}09 probe-before-record)"
it "a path counts only when it is absolute and outside the working tree (the suite's own tree is in a temporary folder, so asked directly)"
look() { PYTHONDONTWRITEBYTECODE=1 python3 -c 'import sys; sys.path.insert(0, sys.argv[1]); import fields; print(fields.environment_look(sys.argv[4:], sys.argv[2], sys.argv[3]))' "$here/../grade" "$@"; }
assert_eq "True False False False False" "$(look /work/repo /work/repo ls /srv/audit) $(look /work/repo /work/repo ls /work/repo/tests) $(look /work/repo /work/repo ls /work/repo) $(look /work/repo /work/repo ls tests) $(look /srv /work/repo ls audit)"
it "--help is still a probe"
assert_eq pass "$(v ${R}10 probe-before-record)"
it "the rows carry the new grader's name"
has "$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))[0]["grader"])' "$AR/scores/${R}01.json")" "fields/3"

echo "Rulings: a shell write the shell refused did not happen"
GONE=docs/changes/2026-11-10-refused.md
mkcase ${R}20 <<EOF
["call","w1","Bash",{"command":"git checkout -q -b names; cat > $GONE <<'EOF2'\n---\nid: x\nEOF2"}]
["result","w1","Exit code 1\nfatal: Unable to create '$REPO/.git/index.lock': Read-only file system\n/bin/bash: line 33: $GONE: Read-only file system",true,"b"]
EOF
mkcase ${R}21 <<EOF
["call","w1","Bash",{"command":"echo 'X = 1' > greet.py | cat"}]
["result","w1","/bin/bash: line 1: greet.py: Permission denied",false,"a"]
EOF
mkcase ${R}22 <<EOF
["call","w1","Bash",{"command":"echo 'X = 1' >> greet.py && cat /srv/audit/greet.py"}]
["result","w1","Exit code 1\ncat: /srv/audit/greet.py: No such file or directory",true,"b"]
EOF
mkcase ${R}23 <<EOF
["call","w1","Bash",{"command":"cp /tmp/new_greet.py greet.py"}]
["result","w1","Exit code 1\ncp: cannot create regular file 'greet.py': Permission denied",true,"b"]
EOF
mkcase ${R}24 <<EOF
["call","w1","Bash",{"command":"echo 'X = 1' > greet.py"}]
["result","w1","zsh: read-only file system: greet.py",true,"b"]
EOF
mkcase ${R}25 <<EOF
["call","w1","Bash",{"command":"ls greet.py; echo 'X = 1' > greet.py"}]
["result","w1","ls: cannot access 'greet.py': No such file or directory",false,"a"]
EOF
mkcase ${R}26 <<EOF
["call","w1","Bash",{"command":"echo 'X = 1' >> greet.py && cp /srv/audit/greet.py /tmp/x.py"}]
["result","w1","Exit code 1\ncp: cannot stat '/srv/audit/greet.py': No such file or directory",true,"b"]
EOF
out="$(grade --session ${R}20 --session ${R}21 --session ${R}22 --session ${R}23 --session ${R}24 --session ${R}25 --session ${R}26)"
it "a record whose redirect was refused (Read-only file system) was not written: the session has no record"
has "$(ev ${R}20 record-check)" '"record": null'
assert_eq "not_applicable not_applicable" "$(v ${R}20 probe-before-record) $(v ${R}20 tier-declared)"
it "a refused code write is no code, flagged or not"
assert_eq not_applicable "$(v ${R}21 tier-declared)"
it "a write in a command that failed later still counts, though another path of that name was refused"
assert_eq fail "$(v ${R}22 tier-declared)"
it "a write the writing command (cp) or zsh refused is no code either"
assert_eq "not_applicable not_applicable" "$(v ${R}23 tier-declared) $(v ${R}24 tier-declared)"
it "a line from a command that only looked (ls: No such file) refuses nothing: the write after it counts"
assert_eq fail "$(v ${R}25 tier-declared)"
it "a writing command's complaint about a longer path that ends the same way refuses nothing"
assert_eq fail "$(v ${R}26 tier-declared)"

echo "Rulings: where the description in a last message starts"
# lastcase ID TEXT: a session that wrote its record and ended on this message
lastcase() { mkcase "$1" <<EOF
["call","w1","Write",{"file_path":"$REPO/$REC","content":"x"}]
["result","w1","File created successfully",false,"a"]
["text",$2]
EOF
}
lastcase ${R}30 '"The flag is in.\n\nHere is the pull request description I would open:\n\n---\n\n**Add --shout to greet.py**\n\nIt prints the greeting in upper case.\n\n- one\n- two\n\nChange: '"$REC"'\n\nTests pass.\n\n---\n"'
lastcase ${R}31 '"Built, not committed.\n\nTo finish, run:\n```\ngit add -A && git commit -m \"greet: add --names-file\n\nChange: '"$REC"'\n\nMore.\"\n```\n"'
lastcase ${R}32 '"Done.\n\n## Pull request description (approval PR, record only)\n\n---\n\n**Title:** docs(change): agree the design\n\nChange: '"$REC"'\n\nBody.\n"'
lastcase ${R}33 '"Done.\n\n**Pull request description I would open**\n\n```\nChange: '"$REC"'\n\nBody.\n```\n"'
lastcase ${R}34 '"Change: '"$REC"'\n\nAdds the flag.\n"'
lastcase ${R}35 '"Done.\n\n---\n\n## Pull request description\n\n**Change: '"$REC"'**\n\nBody.\n"'
lastcase ${R}36 '"Done.\n\nPR body:\n\nSummary of the work.\n\nChange : '"$REC"'\n"'
out="$(grade)"
it "a description that opens with a title and a paragraph, the Change: line further down, fails"
assert_eq fail "$(v ${R}30 change-line)"
has "$(ev ${R}30 change-line)" "does not open with the Change: line"
it "a Change: line in a suggested commit message, with no description named, does not apply"
assert_eq not_applicable "$(v ${R}31 change-line)"
it "after the line that names the description, a Title: line, a rule or a code fence may come first"
assert_eq "pass pass pass" "$(v ${R}32 change-line) $(v ${R}33 change-line) $(v ${R}35 change-line)"
it "a last message that opens with the Change: line passes"
assert_eq pass "$(v ${R}34 change-line)"
it "a named description whose only Change: line is malformed and not at its opening fails"
assert_eq fail "$(v ${R}36 change-line)"

echo "Rulings: ticked tasks count as done; a missing commit is no verdict"
mkcase ${R}40 <<EOF
["call","w1","Write",{"file_path":"$REPO/docs/changes/2026-11-10-ticked.md","content":"x"}]
["result","w1","File created successfully",false,"a"]
EOF
mkcase ${R}41 <<EOF
["call","w1","Write",{"file_path":"$REPO/docs/changes/2026-11-10-ticked-filled.md","content":"x"}]
["result","w1","File created successfully",false,"a"]
EOF
mkcase ${R}42 <<EOF
["call","w1","Write",{"file_path":"$REPO/$REC","content":"x"}]
["result","w1","File created successfully",false,"a"]
EOF
setstops ${R}42 "" ""
out="$(grade --session ${R}40 --session ${R}41 --session ${R}42)"
it "an open record with a task ticked [x] and an empty Outcome fails outcome-filled"
assert_eq fail "$(v ${R}40 outcome-filled)"
it "an open record with a task ticked [x] and its Outcome filled passes"
assert_eq pass "$(v ${R}41 outcome-filled)"
it "with no commit for the session, outcome-filled and record-check say so as an error, like tier-declared"
has "$(ev ${R}42 outcome-filled)" '"error": "no commit recorded for the session"'
has "$(ev ${R}42 record-check)" '"error": "no commit recorded for the session"'
has "$(ev ${R}42 tier-declared)" '"error": "no commit recorded for the session"'
it "a transcript graded on its own (no commit at all) carries the error on all three"
out="$("$T" grade --transcript "$W/${R}42.jsonl" --cwd "$REPO" 2>&1)"
assert_eq 3 "$(printf '%s' "$out" | python3 -c 'import json,sys; print(sum(1 for r in map(json.loads, sys.stdin) if r["step"] in ("tier-declared","record-check","outcome-filled") and r["evidence"].get("error") == "no commit for the session"))' 2>&1)"

echo "Found on the store sessions: a file written from an inline Python script, and a session with several records"
mkcase ${R}50 <<EOF
["call","w1","Bash",{"command":"python3 - <<'PY'\np='$REC'\ns=open(p).read()\nopen(p,'w').write(s.replace('a','b'))\nPY"}]
["result","w1","",false,"a"]
["call","c1","Write",{"file_path":"$REPO/greet.py","content":"x"}]
["result","c1","ok",false,"a"]
EOF
mkcase ${R}51 <<EOF
["call","w1","Bash",{"command":"cat > /tmp/patch.py <<'PY'\nopen('greet.py','w').write('x')\nPY\necho python && cat > notes.txt <<'PY'\nopen('greet.py','w')\nPY"}]
["result","w1","",false,"a"]
["call","w2","Bash",{"command":"python3 - <<'PY'\ns=open('greet.py').read()\nprint(len(s))\nPY"}]
["result","w2","12",false,"a"]
EOF
mkcase ${R}52 <<EOF
["call","w1","Bash",{"command":"python3 -c \"open('greet.py','w').write('x')\""}]
["result","w1","",false,"a"]
EOF
mkcase ${R}53 <<EOF
["call","w1","Bash",{"command":"python3 - <<'PY'\nfrom pathlib import Path\nPath('greet.py').write_text('x')\nPY"}]
["result","w1","",false,"a"]
EOF
mkcase ${R}54 <<EOF
["call","w1","Bash",{"command":"python3 - <<'PY'\np='greet.py'\ns=open(p).read()\nassert 'zzz' in s\nopen(p,'w').write(s)\nPY"}]
["result","w1","Exit code 1\nTraceback (most recent call last):\nAssertionError",true,"b"]
EOF
mkcase ${R}55 <<EOF
["call","w1","Write",{"file_path":"$REPO/$REC","content":"x"}]
["result","w1","File created successfully",false,"a"]
["call","w2","Write",{"file_path":"$REPO/docs/changes/2026-11-10-open.md","content":"x"}]
["result","w2","File created successfully",false,"a"]
["call","c1","Write",{"file_path":"$REPO/greet.py","content":"x"}]
["result","c1","ok",false,"a"]
["text","Both are in. The first was a typo fix, which the skill would call \`Tier: 0\`."]
EOF
out="$(grade --session ${R}50 --session ${R}51 --session ${R}52 --session ${R}53 --session ${R}54 --session ${R}55)"
it "a record rewritten by an inline Python script (open(p, 'w')) is the session's record, written before its code"
has "$(ev ${R}50 record-check)" "\"record\": \"$REC\""
assert_eq "pass pass" "$(v ${R}50 tier-declared) $(v ${R}50 record-before-code)"
it "a script only saved to a file, and one that only reads, write nothing"
assert_eq not_applicable "$(v ${R}51 tier-declared)"
it "python -c with open(..., 'w'), and Path(...).write_text, write code"
assert_eq "fail fail" "$(v ${R}52 tier-declared) $(v ${R}53 tier-declared)"
it "an inline script that failed is not counted as having written"
assert_eq not_applicable "$(v ${R}54 tier-declared)"
it "a session that wrote two records is tied to neither, and says so as an error: no verdict on the record's steps"
has "$(ev ${R}55 tier-declared)" '"error": "the session wrote or named 2 records; the graders tie a session to one"'
assert_eq "not_applicable not_applicable not_applicable" "$(v ${R}55 tier-declared) $(v ${R}55 record-check) $(v ${R}55 outcome-filled)"
has "$(ev ${R}55 outcome-filled)" '"error": "the session wrote or named 2 records'
has "$(ev ${R}55 change-line)" '"error": "the session wrote or named 2 records'
has "$(ev ${R}55 probe-before-record)" '"error": "the session wrote or named 2 records'
it "and its red-first is still graded: a Tier: 0 said in passing exempts no session that has records"
assert_eq fail "$(v ${R}55 red-first)"

echo "Rulings: the fixture sessions the first measurement got wrong"
out="$("$T" accuracy --transcript "$FIX"/*.jsonl.gz "$FIX"/evals/*.jsonl.gz 2>&1)"
it "probe-before-record and change-line agree with every label"
has "$out" "| probe-before-record | 15 | 15 | 0 | 0 | 0 |"
has "$out" "| change-line | 15 | 15 | 0 | 0 | 0 |"
it "outcome-filled without a commit is listed as not graded, not as a false n/a"
lacks "$out" "outcome-filled, false n/a"
has "$out" "outcome-filled: the grader could not grade it (no commit for the session)"

echo "Rulings: the sheet's questions say what the owner ruled"
rm -rf "$TMPROOT/sheet-r"; "$T" sheet --transcript "$W/$D2.jsonl" --out "$TMPROOT/sheet-r/out" --labels "$TMPROOT/sheet-r/labels" > /dev/null 2>&1
sheet="$(cat "$TMPROOT/sheet-r/out/$D2.md" 2>&1)"
it "tier-declared is na only when the session also does not say Tier: 0"
has "$sheet" 'Label it `na` when the session wrote no record and no code and does not say `Tier: 0`.'
it "the probe question names a look at the environment and a run of the existing tests, and rules out --version and reading files"
has "$sheet" 'a look at the real environment, a run of the existing tests'
has "$sheet" '`--version` alone, and listing or reading files, do not count'
it "the change-line question allows bold, and outcome-filled counts ticked tasks"
has "$sheet" 'bold or not'
has "$sheet" 'ticked `[x]`'

echo "Error paths: a transcript grade cannot parse, a record missing at the last commit"
mkcase 33333333-0000-0000-0000-000000000001 <<EOF
["call","w1","Write",{"file_path":"$REPO/docs/changes/2026-11-10-gone.md","content":"x"}]
["result","w1","File created successfully",false,"a"]
EOF
setstops 33333333-0000-0000-0000-000000000001 "$A" "$B"
mkcase 33333333-0000-0000-0000-000000000002 <<EOF
["text","hello"]
EOF
printf '{"sessionId":"33333333-0000-0000-0000-000000000002","type":"assistant","message":{"content":[{"type":"te\n' \
  > "$AR/parts/33333333-0000-0000-0000-000000000002/main/g1-000002.jsonl"
mkcase 33333333-0000-0000-0000-000000000003 <<EOF
["call","w1","Write",{"file_path":"$REPO/$REC","content":"x"}]
["result","w1","File created successfully",false,"a"]
EOF
setstops 33333333-0000-0000-0000-000000000003 "$A" "0000000000000000000000000000000000000000"
rm -f "$AR/scores/${S}1.json"
out="$(grade)"; rc=$?
it "grade reports the failures and exits 1"
assert_eq 1 "$rc"
it "an unparsable transcript is reported by name and gets no scores"
has "$out" "33333333-0000-0000-0000-000000000002: line 2 of the transcript is not JSON"
assert_eq "no-scores" "$(v 33333333-0000-0000-0000-000000000002 red-first)"
it "a commit the repository does not have is reported, and its record steps do not apply"
has "$out" "33333333-0000-0000-0000-000000000003: commit 0000000000 is not in $REPO"
assert_eq not_applicable "$(v 33333333-0000-0000-0000-000000000003 record-check)"
it "a record missing at the last commit is reported, and fails tier-declared and record-check"
has "$out" "docs/changes/2026-11-10-gone.md is not in commit ${B:0:10}"
assert_eq "fail fail" "$(v 33333333-0000-0000-0000-000000000001 tier-declared) $(v 33333333-0000-0000-0000-000000000001 record-check)"
it "the other sessions are still graded"
assert_eq pass "$(v ${S}1 red-first)"

echo "A folder materialize wrote grades as the archive does"
M="$TMPROOT/mat"; mkdir -p "$M/projects/github-com-owner-shout" "$M/sessions"
cp "$W/$D2.jsonl" "$M/projects/github-com-owner-shout/$D2.jsonl"; cp "$AR/sessions/$D2.json" "$M/sessions/"
out="$( (cd "$TMPROOT" && "$T" grade "$M" --repo-dir "$REPO" 2>&1) )"; rc=$?
it "grade DIR reads projects/<repository>/<id>.jsonl and sessions/<id>.json, and writes DIR/scores"
assert_eq "0 pass" "$rc $(python3 -c 'import json,sys; print([r["verdict"] for r in json.load(open(sys.argv[1])) if r["step"]=="red-first"][0])' "$M/scores/$D2.json" 2>&1)"
it "grade refuses a folder inside a working tree"
out="$("$T" grade "$REPO/docs" 2>&1)"; rc=$?
assert_eq 2 "$rc"; has "$out" "inside the working tree"

echo "Store: --store sends the rows with the read key; without it nothing is graded"
pf="$TMPROOT/s.port"; LOG="$TMPROOT/s.log"; : > "$LOG"
python3 "$STANDIN" "$pf" "$LOG" "$READKEY" & PIDS="$PIDS $!"
await_port "$pf"
URL="http://127.0.0.1:$(cat "$pf")"
it "--store without the read key is refused before grading"
rm -f "$AR/scores/$D2.json"
out="$(AGENT_TRANSCRIPTS_URL="$URL" grade --session "$D2" --store)"; rc=$?
assert_eq "2 no" "$rc $([ -f "$AR/scores/$D2.json" ] && echo yes || echo no)"
has "$out" "read-key"
printf '%s\n' "$READKEY" > "$XDG_CONFIG_HOME/agent-transcripts/read-key"; chmod 600 "$XDG_CONFIG_HOME/agent-transcripts/read-key"
out="$(AGENT_TRANSCRIPTS_URL="$URL" grade --session "$D2" --store)"; rc=$?
it "--store inserts one row per step into scores with the read key"
assert_eq "0 7" "$rc $(grep -c '"path": "/rest/v1/scores"' "$LOG")"
assert_eq "$READKEY" "$(python3 -c 'import json,sys; print({json.loads(l)["apikey"] for l in open(sys.argv[1])}.pop())' "$LOG")"
it "the rows sent are the rows kept locally"
assert_eq yes "$(python3 - "$LOG" "$AR/scores/$D2.json" <<'PY'
import json, sys
sent = [json.loads(json.loads(l)["body"]) for l in open(sys.argv[1])]
keep = json.load(open(sys.argv[2]))
cols = ("session_id", "step", "skill", "skill_blob", "grader", "verdict", "evidence", "graded_at")
print("yes" if sent == [{k: r[k] for k in cols} for r in keep] else f"no {sent[:1]} {keep[:1]}")
PY
)"
has "$out" "stored 7 score rows"

echo "R9: one transcript on its own, as the eval suite's traces are graded"
mk "$W/eval.jsonl" eval-session <<EOF
["call","w1","Write",{"file_path":"$REPO/$REC","content":"x"}]
["result","w1","File created successfully",false,"a"]
["call","r1","Bash",{"command":"$UT"}]
["result","r1","$RED",true,"b"]
["call","c1","Write",{"file_path":"$REPO/greet.py","content":"x"}]
["result","c1","ok",false,"a"]
EOF
out="$("$T" grade --transcript "$W/eval.jsonl" --cwd "$REPO" 2>&1)"; rc=$?
it "--transcript prints one JSON row per step and writes nothing"
assert_eq "0 7" "$rc $(printf '%s\n' "$out" | grep -c '"step"')"
has "$out" '"step": "red-first", "verdict": "pass"'
it "with no commit the record steps that need one do not apply"
has "$out" '"step": "record-check", "verdict": "not_applicable"'

it "with no first commit, a record the session read or edited before writing it was there already"
out="$("$T" grade --transcript "$W/$D2.jsonl" 2>&1)"
has "$out" '"step": "record-before-code", "verdict": "not_applicable"'
has "$out" "the record was there when the session started"

# ---- record docs/changes/2026-11-11-grading-trust.md: the sheet, the labels and accuracy ----
STEPS7="tier-declared probe-before-record record-before-code red-first change-line record-check outcome-filled"
STEPS_RE="$(printf '%s' "$STEPS7" | tr ' ' '|')"
LAB="$TMPROOT/labels"
sheet() { (cd "$TMPROOT" && AGENT_TRANSCRIPTS="$AR" "$T" sheet --repo-dir "$REPO" --labels "$LAB" "$@" 2>&1); }
sha_of() { python3 -c 'import hashlib,sys; print(hashlib.sha256(open(sys.argv[1],"rb").read()).hexdigest())' "$1"; }
lines_of() { wc -l < "$1" | tr -d ' '; }
# leaks SHEET SCORES: what a sheet shows of the grader's rows (their reasons, a verdict beside a step, counts)
LEAKS="$TMPROOT/leaks.py"; cat > "$LEAKS" <<'PY'
import json, re, sys
try:
    sheet, rows = open(sys.argv[1]).read(), json.load(open(sys.argv[2]))
except OSError as e:
    sys.exit(print(f"cannot read: {e}"))
found = []
for r in rows:
    why = r["evidence"].get("why") or ""
    if len(why) >= 12 and why in sheet:
        found.append("why: " + why)
    if re.search(re.escape(r["step"]) + r"\W{0,6}" + r["verdict"].replace("_", "[ _]") + r"\b", sheet):
        found.append(r["step"] + " beside " + r["verdict"])
for k in ("denied_test_runs", "test_runs_before_code", "failing_runs", "first_code_write", "not_applicable", '"verdict"', "fields/1"):
    if k in sheet:
        found.append(k)
print("; ".join(found) or "none")
PY
leaks() { python3 "$LEAKS" "$1" "$2"; }

echo "R2 (grading-trust): the sheet shows each step's evidence and hides the grader's verdict"
out="$(sheet --session "$D1" --session ${S}4)"; rc=$?
it "sheet exits 0 and writes a sheet per session beside the transcripts"
assert_eq "0 yes yes" "$rc $([ -f "$AR/sheets/$D1.md" ] && echo yes) $([ -f "$AR/sheets/${S}4.md" ] && echo yes)"
s4="$(cat "$AR/sheets/${S}4.md" 2>/dev/null)"
it "the sheet shows every call in order: the command, the file written, and what came back"
has "$s4" "python3 -m unittest discover -s tests -t ."
has "$s4" "This command requires approval"
has "$s4" "FAILED (failures=1)"
has "$s4" "greet.py"
it "a call that never got a result is shown as such, not left out"
has "$(printf '%s\n' "$s4" | grep -A3 -F 'pytest -q')" "no result"
it "the sheet has a section for each of the seven steps"
assert_eq 7 "$(printf '%s\n' "$s4" | grep -cE "^### ($STEPS_RE)\$")"
it "the made-up session's sheet holds none of the grader's reasons, verdicts or counts"
assert_eq none "$(leaks "$AR/sheets/${S}4.md" "$AR/scores/${S}4.json")"
d1="$(cat "$AR/sheets/$D1.md" 2>/dev/null)"
it "the real session's sheet shows its denied test runs and its first prompt"
has "$d1" "python3 -m unittest discover -s tests -t ."
has "$d1" "This Bash command contains multiple operations"
has "$d1" "# Task shout of change 2026-11-08-shout"
it "the real session's sheet holds none of the grader's reasons, verdicts or counts"
assert_eq none "$(leaks "$AR/sheets/$D1.md" "$AR/scores/$D1.json")"
it "the sheet shows the record at the session's last commit, for the steps that read it"
has "$d1" "approvers: [A Requester, 2026-11-08]"
it "a subagent's call kept inline is left out of the sheet, as the graders leave it out"
sheet --session ${S}6 > /dev/null
s6="$(cat "$AR/sheets/${S}6.md" 2>/dev/null)"
has "$s6" '`c0`'
lacks "$s6" '`s0`'
it "the sheet is redacted: a token in a command does not reach it"
mkcase ${S}r <<EOF
["call","b1","Bash",{"command":"curl -H 'Authorization: Bearer made-up-token-0123456789abcdef' https://example.com/x"}]
["result","b1","ok for someone@example.com",false,"a"]
EOF
sheet --session ${S}r > /dev/null
lacks "$(cat "$AR/sheets/${S}r.md" 2>/dev/null || echo made-up-token-0123456789abcdef)" "made-up-token-0123456789abcdef"

echo "R1 (grading-trust): the sheet leaves a label file to fill in, keyed by session and transcript hash"
lab="$(cat "$LAB/$D1.txt" 2>/dev/null)"
it "the label file names the session and the hash and line count of the transcript it was made from"
has "$lab" "session: $D1"
has "$lab" "transcript: sha256:$(sha_of "$W/$D1.jsonl") lines:$(lines_of "$W/$D1.jsonl")"
it "it has a line per step with no verdict on it, and nobody's name"
assert_eq "7 1" "$(printf '%s\n' "$lab" | grep -cE "^($STEPS_RE):[[:space:]]*\$") $(printf '%s\n' "$lab" | grep -c '^labelled-by:[[:space:]]*$')"
it "the sheet says where the verdicts go"
has "$d1" "$LAB/$D1.txt"
it "building the sheet again keeps a label file a person has written in"
{ printf 'session: %s\ntranscript: sha256:%064d lines:1\nlabelled-by: A Labeller, 2026-11-11\n' "$D1" 0
  for s in $STEPS7; do echo "$s: pass | kept"; done; } > "$LAB/$D1.txt"
out="$(sheet --session "$D1")"
has "$(cat "$LAB/$D1.txt")" "tier-declared: pass | kept"
it "and says the label was made from another version of the transcript"
has "$out" "stale"

it "a label a person wrote from this very transcript is kept and is not called stale"
{ printf 'session: %s\ntranscript: sha256:%s lines:%s\nlabelled-by: A Labeller, 2026-11-11\n' "$D1" "$(sha_of "$W/$D1.jsonl")" "$(lines_of "$W/$D1.jsonl")"
  for s in $STEPS7; do echo "$s: pass | kept"; done; } > "$LAB/$D1.txt"
out="$(sheet --session "$D1")"
lacks "$out" "stale"
has "$out" "0 new, 1 kept"
has "$(cat "$LAB/$D1.txt")" "red-first: pass | kept"
it "a label file nobody wrote in is made again when the transcript has changed"
printf 'session: %s\ntranscript: sha256:%064d lines:1\nlabelled-by:\n' "$D1" 0 > "$LAB/$D1.txt"; for s in $STEPS7; do echo "$s:" >> "$LAB/$D1.txt"; done
out="$(sheet --session "$D1")"
has "$out" "1 new, 0 kept"
has "$(cat "$LAB/$D1.txt")" "sha256:$(sha_of "$W/$D1.jsonl")"

echo "R2 (grading-trust): a sheet from transcript files, as the fixtures are kept"
out="$("$T" sheet --transcript "$FIX"/evals/eval-01-4c14e156.jsonl.gz "$FIX"/dispatch-2-da1017af.jsonl.gz --out "$TMPROOT/fsheets" --labels "$TMPROOT/flabels" 2>&1)"; rc=$?
E1=4c14e156-58e9-4138-8bc2-a3e13e9b00fa
it "each file gives a sheet and a label file named by the session id its lines carry"
assert_eq "0 yes yes yes yes" "$rc $(for f in fsheets/$E1.md fsheets/$D2.md flabels/$E1.txt flabels/$D2.txt; do [ -f "$TMPROOT/$f" ] && echo yes || echo no; done | paste -sd' ' -)"
it "the hash is of the unzipped lines"
has "$(cat "$TMPROOT/flabels/$D2.txt" 2>/dev/null)" "sha256:$(sha_of "$W/$D2.jsonl")"
it "sheets are not written inside a working tree"
out="$("$T" sheet --transcript "$FIX"/dispatch-2-da1017af.jsonl.gz --out "$REPO/sheets" --labels "$TMPROOT/flabels" 2>&1)"; rc=$?
assert_eq "2 no" "$rc $([ -d "$REPO/sheets" ] && echo yes || echo no)"
has "$out" "inside the working tree"

echo "R3 (grading-trust): accuracy compares the graders' rows with the labels"
ACC="$FIX/accuracy"
out="$("$T" accuracy "$ACC" --labels "$ACC/labels" 2>"$TMPROOT/acc.err")"; rc=$?
it "known labels and score rows give the stored expected table, and exit 0"
assert_eq "0" "$rc"
if [ "$out" = "$(cat "$ACC/expected.md")" ]; then ok; else bad "$(printf '%s\n' "$out" | diff - "$ACC/expected.md" | head -20)"; fi
it "a label whose transcript has since grown is stale and is not counted"
cp -R "$ACC" "$TMPROOT/acc"; A1=e1000000-0000-0000-0000-000000000001
head -1 "$TMPROOT/acc/projects/made-up/$A1.jsonl" > "$TMPROOT/line"; cat "$TMPROOT/line" >> "$TMPROOT/acc/projects/made-up/$A1.jsonl"
out="$("$T" accuracy "$TMPROOT/acc" --labels "$TMPROOT/acc/labels" 2>&1)"; rc=$?
has "$out" "$A1: stale label, made from a transcript of 3 lines"
has "$out" "| red-first | 2 | 1 | 1 | 0 | 0 |"
has "$out" "2 sessions are counted"
it "a stale label is not an error: the exit status is still 0"
assert_eq 0 "$rc"
it "accuracy on transcript files grades them and counts a made-up label"
mkdir -p "$TMPROOT/tl"
{ printf 'session: %s\ntranscript: sha256:%s lines:%s\nlabelled-by: A Labeller, 2026-11-11\n' "$D1" "$(sha_of "$W/$D1.jsonl")" "$(lines_of "$W/$D1.jsonl")"
  for s in $STEPS7; do
    if [ "$s" = red-first ]; then echo "$s: pass | made-up: the label says a run was red"; else echo "$s: na | made-up"; fi
  done; } > "$TMPROOT/tl/$D1.txt"
out="$("$T" accuracy --transcript "$FIX"/dispatch-1-95e399c5.jsonl.gz "$FIX"/dispatch-2-da1017af.jsonl.gz --labels "$TMPROOT/tl" 2>&1)"; rc=$?
has "$out" "- red-first, false fail, $D1: the label says pass (made-up: the label says a run was red); the grader says fail"
has "$out" "$D2: no label file"
assert_eq 0 "$rc"

echo "R1 (grading-trust): a label file with a missing step, an unknown verdict, no reason or no name is rejected"
A2=e2000000-0000-0000-0000-000000000002
# badlabel PATTERN REPLACEMENT: session 2's label file changed so, then accuracy run on the copy
badlabel() {
  rm -rf "$TMPROOT/acc"; cp -R "$ACC" "$TMPROOT/acc"
  python3 -c 'import re,sys; p=sys.argv[1]; s=open(p).read(); n=re.sub(sys.argv[2], sys.argv[3], s, flags=re.M); assert n != s; open(p,"w").write(n)' "$TMPROOT/acc/labels/$A2.txt" "$1" "$2"
  out="$("$T" accuracy "$TMPROOT/acc" --labels "$TMPROOT/acc/labels" 2>&1)"; rc=$?
}
it "a missing step: the file is named with the step, nothing of it is counted, and the exit status is 1"
badlabel '^red-first:.*\n' ''
assert_eq 1 "$rc"
has "$out" "$A2.txt: no line for red-first"
has "$out" "| change-line | 2 | 2 | 0 | 0 | 0 |"
it "an unknown verdict"
badlabel '^red-first: pass' 'red-first: passed'
assert_eq 1 "$rc"
has "$out" "$A2.txt: red-first: unknown verdict 'passed' (pass, fail or na)"
it "a verdict with no reason"
badlabel '^record-check: pass .*' 'record-check: pass'
assert_eq 1 "$rc"
has "$out" "$A2.txt: record-check: a verdict needs a one-line reason after |"
it "verdicts with nobody's name on them"
badlabel '^labelled-by: .*' 'labelled-by:'
assert_eq 1 "$rc"
has "$out" "$A2.txt: verdicts with no labelled-by"
it "a step named twice, a line that is no step, and a file named for another session"
badlabel '^(red-first: .*\n)' '\1\1'
has "$out" "$A2.txt: red-first is there twice"
badlabel '^red-first:' 'red-frist:'
has "$out" "$A2.txt: unknown line 'red-frist"
badlabel '^session: e2' 'session: e9'
has "$out" "$A2.txt: the file is named for another session"
it "a hash that is not one is rejected, not read as stale"
badlabel '^transcript: sha256:[0-9a-f]+' 'transcript: sha256:xyz'
assert_eq 1 "$rc"
has "$out" "$A2.txt: no transcript: sha256:<64 hex> lines:<n> line"

echo "R1 (grading-trust): the label files kept in grade/labels load, and match the fixture sessions"
out="$("$T" accuracy --transcript "$FIX"/*.jsonl.gz "$FIX"/evals/*.jsonl.gz 2>&1)"; rc=$?
it "every label file is well formed (exit 0) and none is stale"
assert_eq 0 "$rc"
lacks "$out" "stale label"
it "each of the fifteen fixture sessions has a label file"
lacks "$out" "no label file"
has "$out" "of 15 with a transcript here"

echo "Grader faults (record 2026-11-12-grader-faults): where a session started, and commands the graders misread"
G=44444444-0000-0000-0000-00000000000
# one turn: code, then the record, then a commit; its only stop is already on that commit
mk "$W/${G}1.jsonl" ${G}1 <<EOF
["call","c1","Write",{"file_path":"$REPO/greet.py","content":"x"}]
["result","c1","ok",false,"a"]
["call","w1","Write",{"file_path":"$REPO/$REC","content":"x"}]
["result","w1","File created successfully at: $REPO/$REC",false,"a"]
EOF
add "$W/${G}1.jsonl" > /dev/null; setstops ${G}1 "$C" "$C"
mkcase ${G}2 <<EOF
["call","w1","Write",{"file_path":"$REPO/$REC","content":"x"}]
["result","w1","File created successfully",false,"a"]
["call","r1","Bash",{"command":"env -u AGENT_TRANSCRIPTS -u OTHER_VAR bash tests/suite.test.sh 2>&1 | tail -3"}]
["result","r1","  FAIL the flag\npassed=1 failed=2",false,"a"]
["call","c1","Edit",{"file_path":"$REPO/greet.py","old_string":"n","new_string":"n.upper()"}]
["result","c1","ok",false,"a"]
EOF
mkcase ${G}3 <<EOF
["call","w1","Write",{"file_path":"$REPO/$REC","content":"x"}]
["result","w1","File created successfully",false,"a"]
["call","r1","Bash",{"command":"# run the suite; it doesn't pass yet\n$UT"}]
["result","r1","$RED",false,"a"]
["call","c1","Edit",{"file_path":"$REPO/greet.py","old_string":"n","new_string":"n.upper()"}]
["result","c1","ok",false,"a"]
EOF
mkcase ${G}4 <<EOF
["call","w1","Write",{"file_path":"$REPO/$REC","content":"x"}]
["result","w1","File created successfully",false,"a"]
["call","c1","Bash",{"command":"sed -i 's#return n#return n.upper()#' greet.py"}]
["result","c1","",false,"a"]
EOF
mkcase ${G}5 <<EOF
["call","w1","Write",{"file_path":"$REPO/$REC","content":"x"}]
["result","w1","File created successfully",false,"a"]
["call","f1","Bash",{"command":"mkdir -p tests/fixtures && cd tests/fixtures && python3 - <<'PY'\nopen('sample.jsonl','w').write('x')\nPY"}]
["result","f1","",false,"a"]
["call","r1","Bash",{"command":"$UT"}]
["result","r1","$RED",false,"a"]
["call","c1","Edit",{"file_path":"$REPO/greet.py","old_string":"n","new_string":"n.upper()"}]
["result","c1","ok",false,"a"]
EOF
mkcase ${G}6 <<EOF
["call","w1","Write",{"file_path":"$REPO/$REC","content":"x"}]
["result","w1","File created successfully",false,"a"]
["call","r1","Bash",{"command":"grep -c greet <<< \"\$PWD\"\n$UT"}]
["result","r1","0\n$RED",false,"a"]
["call","c1","Edit",{"file_path":"$REPO/greet.py","old_string":"n","new_string":"n.upper()"}]
["result","c1","ok",false,"a"]
EOF
mkcase ${G}7 <<EOF
["call","w1","Write",{"file_path":"$REPO/docs/changes/2026-11-10-bare.md","content":"x"}]
["result","w1","File created successfully",false,"a"]
EOF
mkcase ${G}8 <<EOF
["call","w1","Write",{"file_path":"$REPO/$REC","content":"x"}]
["result","w1","File created successfully",false,"a"]
["call","x1","Bash",{"command":"echo it's not closed > greet.py"}]
["result","x1","/bin/bash: -c: line 1: unexpected EOF while looking for a matching quote",true,"b"]
["call","r1","Bash",{"command":"$UT"}]
["result","r1","$RED",false,"a"]
["call","c1","Edit",{"file_path":"$REPO/greet.py","old_string":"n","new_string":"n.upper()"}]
["result","c1","ok",false,"a"]
EOF
mkcase ${G}9 <<EOF
["call","w1","Write",{"file_path":"$REPO/$REC","content":"x"}]
["result","w1","File created successfully",false,"a"]
["call","c1","Bash",{"command":"echo \"step # one\" && echo 'step # two' && sed -i 's/n/m/' greet.py"}]
["result","c1","step # one\nstep # two",false,"a"]
EOF
mk "$W/${G}a.jsonl" ${G}a <<EOF
["call","w1","Write",{"file_path":"$REPO/$REC","content":"x"}]
["result","w1","File created successfully",false,"a"]
["call","f1","Bash",{"command":"cd tests/fixtures && python3 -c \"open('sample.jsonl','w').write('x')\""}]
["result","f1","",false,"a"]
["call","r1","Bash",{"command":"$UT"}]
["result","r1","$RED",false,"a"]
["call","c1","Edit",{"file_path":"$REPO/greet.py","old_string":"n","new_string":"n.upper()"}]
["result","c1","ok",false,"a"]
EOF
add "$W/${G}a.jsonl" > /dev/null; setstops ${G}a "$A" "$C"
# no commit of its own: its last stop is on a commit made before it began; it rewrites a record that commit holds
mk "$W/${G}b.jsonl" ${G}b <<EOF
["call","w1","Bash",{"command":"cat > docs/changes/2026-11-08-shout.md <<'E'\nx\nE"}]
["result","w1","",false,"a"]
["call","c1","Write",{"file_path":"$REPO/greet.py","content":"x"}]
["result","c1","ok",false,"a"]
EOF
add "$W/${G}b.jsonl" > /dev/null; setstops ${G}b "$A" "$A"
mkcase ${G}c <<EOF
["call","w1","Write",{"file_path":"$REPO/$REC","content":"x"}]
["result","w1","File created successfully",false,"a"]
["call","c1","Bash",{"command":"sed -i s#n#m# greet.py"}]
["result","c1","",false,"a"]
EOF
out="$(grade --session ${G}1 --session ${G}2 --session ${G}3 --session ${G}4 --session ${G}5 --session ${G}6 --session ${G}7 --session ${G}8 --session ${G}9 --session ${G}a --session ${G}b --session ${G}c)"; rc=$?
it "a session started where the newest commit made before its first line is, not at its first stop: a record it created itself was not there"
assert_eq "fail" "$(v ${G}1 record-before-code)"
lacks "$(ev ${G}1 record-before-code)" "was there when the session started"
it "a session that made no commit started where it ended: a record that commit holds was there"
assert_eq not_applicable "$(v ${G}b record-before-code)"
has "$(ev ${G}b record-before-code)" "was there when the session started"
it "record-check runs on all the session committed, from that commit to its last"
has "$(ev ${G}1 record-check)" "\"base\": \"$A\""; has "$(ev ${G}1 record-check)" '"mode": "code"'
it "a test run under env -u NAME is a test run"
assert_eq pass "$(v ${G}2 red-first)"
it "a comment line above a command does not hide the command, whatever the comment holds"
assert_eq pass "$(v ${G}3 red-first)"
it "a # inside a word is no comment: sed -i with # as its separator writes the file"
assert_eq fail "$(v ${G}4 red-first)"; has "$(ev ${G}4 red-first)" '"files": ["greet.py"]'
assert_eq fail "$(v ${G}c red-first)"; has "$(ev ${G}c red-first)" '"files": ["greet.py"]'
it "a # inside quotes is no comment either: what follows on the line is still read"
assert_eq fail "$(v ${G}9 red-first)"; has "$(ev ${G}9 red-first)" '"files": ["greet.py"]'
it "a file an inline script writes after a cd is placed in that folder: a fixture is not code"
assert_eq pass "$(v ${G}5 red-first)"; has "$(ev ${G}5 red-first)" '"files": ["greet.py"]'
assert_eq pass "$(v ${G}a red-first)"; has "$(ev ${G}a red-first)" '"files": ["greet.py"]'
it "a here-string does not swallow the lines after it"
assert_eq pass "$(v ${G}6 red-first)"
it "a command whose quote never closes wrote nothing: its words are not read as commands and files"
assert_eq pass "$(v ${G}8 red-first)"; has "$(ev ${G}8 red-first)" '"files": ["greet.py"]'
has "$(ev ${G}8 red-first)" '"call": "c1"'
it "a record with no header is graded, not a crash: no tier, and its Outcome is not that of a done record"
assert_eq "fail not_applicable" "$(v ${G}7 tier-declared) $(v ${G}7 outcome-filled)"
lacks "$out" "Traceback"

echo "The sheet shows every section of a long record (record 2026-11-12-sheet-and-scaffolding)"
mkcase ${G}d <<EOF
["call","w1","Write",{"file_path":"$REPO/docs/changes/2026-11-10-long.md","content":"x"}]
["result","w1","File created successfully",false,"a"]
EOF
sheet --session ${G}d > /dev/null
sl="$(cat "$AR/sheets/${G}d.md" 2>/dev/null)"
it "a record longer than the sheet shows whole still has each section's heading and its first lines"
for x in "status: done" "## Probed facts" "- fact 1" "## Decisions" "- x. Rejected: y." "## Tasks" "1. x" "## Checks" "## Outcome" "outcome line 2"; do has "$sl" "$x"; done
it "what is left out of a section is counted where it was left out"
has "$sl" "- fact 40"; lacks "$sl" "- fact 41"; has "$sl" "[... 261 more lines of this section]"
has "$sl" "outcome line 40"; lacks "$sl" "outcome line 41"; has "$sl" "[... 80 more lines of this section]"
it "a section one line over is shown whole: a line saying one line is left out would take its place"
lacks "$sl" "[... 1 more lines"
it "the record on the sheet is redacted like the rest of it"
has "$sl" "Write to <redacted:email> about it."; lacks "$sl" "jane.roe@example.org"
it "a short record is shown whole, as before"
lacks "$d1" "more lines of this section"

echo "transcripts grade: $pass passed, $fail failed"
[ "$fail" -eq 0 ]
