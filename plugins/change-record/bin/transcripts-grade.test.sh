#!/usr/bin/env bash
# Tests for transcripts grade (record docs/changes/2026-11-09-skill-transcripts.md, R8 and R9):
# the field graders on the two real dispatch sessions (grade/fixtures, redacted) and on made-up
# sessions, in both tool-result key orders, with flagged and unflagged failures and denials.
# Fixtures use made-up addresses and tokens only. Needs bash, git, gzip and python3.
set -u
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
T="$here/transcripts"; STANDIN="$here/../store/stand-in.py"; FIX="$here/../grade/fixtures"
TMPROOT="$(mktemp -d)"; PIDS=""
trap 'for p in $PIDS; do kill $p 2>/dev/null; done; rm -rf "$TMPROOT"' EXIT
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
(
  cd "$REPO" && git init -q -b main && git config user.email t@example.com && git config user.name t
  git config core.hooksPath /dev/null
  printf -- '---\nname: change\n---\n# Change\n' > plugins/change-record/skills/change/SKILL.md
  printf 'def greet(n):\n    return n\n' > greet.py; printf 'import unittest\n' > tests/test_greet.py
  shout_record "" > docs/changes/2026-11-08-shout.md
  git add -A && git commit -qm "docs(change): 2026-11-08-shout" && git remote add origin https://github.com/Owner/Shout
  shout_record "Shipped the flag; output pasted." > docs/changes/2026-11-08-shout.md
  printf 'def greet(n):\n    return n.upper()\n' > greet.py
  git commit -qam "feat: shout"
  mine_record 2026-11-10-mine done "Shipped; output pasted." > docs/changes/2026-11-10-mine.md
  mine_record 2026-11-10-open open "" > docs/changes/2026-11-10-open.md
  git add -A && git commit -qm "docs(change): mine"
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
for _ in $(seq 100); do [ -s "$pf" ] && break; sleep 0.05; done
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

echo "transcripts grade: $pass passed, $fail failed"
[ "$fail" -eq 0 ]
