#!/usr/bin/env bash
# Tests for bin/agent-session-collect: it turns a gh-aw agent run's Claude output
# (agent-stdio.log, stream-json) into a transcript in Claude Code's own layout, which
# plugins/change-record/bin/transcripts then archives and pushes like any session.
# The fixture is a real headless run (a Bash call and a subagent), paths changed.
#   bash bin/agent-session-collect.test.sh
set -u
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"; root="$(cd "$here/.." && pwd)"
C=(python3 -I "$here/agent-session-collect")
fx="$here/testdata/agent-sessions/agent-stdio.log"
pass=0; fail=0; CURRENT=""
it() { CURRENT="$1"; }
ok()  { pass=$((pass+1)); printf '  ok   %s\n' "$CURRENT"; }
bad() { fail=$((fail+1)); printf '  FAIL %s\n       %s\n' "$CURRENT" "$1"; }
assert_eq() { [ "$1" = "$2" ] && ok || bad "expected [$1] got [$2]"; }
T="$(mktemp -d "${TMPDIR:-/tmp}/agent-session-collect.XXXXXX")"; [ -n "${KEEP:-}" ] || trap 'rm -rf "$T"' EXIT
# macOS's TMPDIR ends in a slash, so the path has "//"; the collector writes cwd normalized.
T="$(python3 -I -c 'import os, sys; print(os.path.abspath(sys.argv[1]))' "$T")"
mkdir -p "$T/repo" && git -C "$T/repo" init -q && git -C "$T/repo" remote add origin https://github.com/Owner/Repo.git
printf 'Check the claims.\n' > "$T/prompt.txt"
collect() {  # args... -> stdout in $T/out.txt, exit code in $rc
  "${C[@]}" "$@" >"$T/out.txt" 2>"$T/err.txt"; rc=$?
}
std=(--prompt "$T/prompt.txt" --workflow "Verify PR claims" --run-id 4242 --attempt 2 --cwd "$T/repo")
q() { python3 -I -c "$1" "${@:2}"; }  # python one-liner over files

it "a run's log becomes one transcript named for the workflow, run and attempt, printed on stdout"
collect "$fx" "${std[@]}" --out "$T/s"; assert_eq 0 "$rc"
main="$T/s/gh-aw-verify-pr-claims-4242-2.jsonl"
assert_eq "$main" "$(cat "$T/out.txt")"
[ -f "$main" ] && ok || bad "no $main"
it "only user and assistant lines are kept, and the run's result, last; system, stream events and plain text are not"
assert_eq "user assistant user assistant assistant user assistant result" "$(q 'import json,sys; print(" ".join(json.loads(l)["type"] for l in open(sys.argv[1])))' "$main" 2>/dev/null)"
grep -q 'skipped 1 line that is not JSON' "$T/err.txt" && ok || bad "$(cat "$T/err.txt")"
{ cat "$fx"; printf '%s\n' '{"type":"summary","message":{"role":"user","content":"a summary"},"uuid":"u-s","session_id":"x"}'; } > "$T/other.log"
collect "$T/other.log" "${std[@]}" --out "$T/o"
assert_eq "user assistant user assistant assistant user assistant result" "$(q 'import json,sys; print(" ".join(json.loads(l)["type"] for l in open(sys.argv[1])))' "$T/o/gh-aw-verify-pr-claims-4242-2.jsonl" 2>/dev/null)"
it "the prompt comes first, as the user's message, at the first line's time"
q 'import json,sys; d=json.loads(open(sys.argv[1]).readline()); assert d["message"]=={"role":"user","content":"Check the claims.\n"}, d; assert d["timestamp"]=="2026-11-25T12:39:00.974Z", d' "$main" && ok || bad "first line"
it "each line names the session, the checkout, gh-aw as entrypoint, and the line before it"
q '
import json,sys
ls=[json.loads(l) for l in open(sys.argv[1])]
prev=None
for d in ls:
    assert d["sessionId"]=="gh-aw-verify-pr-claims-4242-2" and d["cwd"]==sys.argv[2] and d["entrypoint"]=="gh-aw", d
    assert d["parentUuid"]==prev and d["isSidechain"] is False, d
    assert "parent_tool_use_id" not in d and "session_id" not in d, d
    prev=d["uuid"]
assert len({d["uuid"] for d in ls})==len(ls)
' "$main" "$T/repo" && ok || bad "fields"
it "a subagent's lines go to subagents/agent-<id>.jsonl, chained, as a sidechain"
sub="$(ls "$T/s/gh-aw-verify-pr-claims-4242-2/subagents/" 2>/dev/null)"
assert_eq "agent-toolu_01Px3oHxCRB1L5XsnhoSd4J5.jsonl" "$sub"
q '
import json,sys
ls=[json.loads(l) for l in open(sys.argv[1])]
assert [d["type"] for d in ls]==["user","assistant","user"], ls
prev=None
for d in ls:
    assert d["isSidechain"] is True and d["sessionId"]=="gh-aw-verify-pr-claims-4242-2" and d["parentUuid"]==prev, d
    prev=d["uuid"]
' "$T/s/gh-aw-verify-pr-claims-4242-2/subagents/$sub" && ok || bad "subagent lines"
it "the same log collected twice gives the same bytes, so the store sees duplicates, not new sessions"
collect "$fx" "${std[@]}" --out "$T/s2"; cmp -s "$main" "$T/s2/gh-aw-verify-pr-claims-4242-2.jsonl" && ok || bad "differs"

it "a log with no user or assistant line is refused: nothing to collect"
grep -v '"type":"\(user\|assistant\)"' "$fx" > "$T/empty.log"
collect "$T/empty.log" "${std[@]}" --out "$T/e"; assert_eq 1 "$rc"
grep -q 'nothing to collect' "$T/err.txt" && ok || bad "$(cat "$T/err.txt")"
grep -q Traceback "$T/err.txt" && bad "crashed: $(tail -1 "$T/err.txt")" || ok
[ ! -e "$T/e" ] && ok || bad "wrote $T/e"
it "a missing prompt file, or a bad run id, attempt or option, is a usage error"
collect "$fx" --prompt "$T/none.txt" --workflow W --run-id 1 --attempt 1 --cwd "$T/repo" --out "$T/u1"; assert_eq 2 "$rc"
collect "$fx" --prompt "$T/prompt.txt" --workflow W --run-id 1x --attempt 1 --cwd "$T/repo" --out "$T/u2"; assert_eq 2 "$rc"
collect "$fx" --prompt "$T/prompt.txt" --workflow W --run-id 1 --attempt 0 --cwd "$T/repo" --out "$T/u3"; assert_eq 2 "$rc"
collect "$fx" "${std[@]}"; assert_eq 2 "$rc"
it "a workflow name is reduced to a plain slug; a subagent id from the log cannot leave its folder"
sed 's/toolu_01Px3oHxCRB1L5XsnhoSd4J5/..\/..\/..\/x/g' "$fx" > "$T/evil.log"
collect "$T/evil.log" --prompt "$T/prompt.txt" --workflow '../CI fix; rm' --run-id 7 --attempt 1 --cwd "$T/repo" --out "$T/v"
assert_eq "0 $T/v/gh-aw-ci-fix-rm-7-1.jsonl" "$rc $(cat "$T/out.txt")"
assert_eq "agent-x.jsonl" "$(ls "$T/v/gh-aw-ci-fix-rm-7-1/subagents/" 2>/dev/null)"
assert_eq "" "$(find "$T" -maxdepth 1 -name 'x*' -o -maxdepth 1 -name 'agent-x*')"

it "the transcript archives as an agent session of the checkout's repository, with its subagent"
export AGENT_TRANSCRIPTS="$T/archive" XDG_CONFIG_HOME="$T/config"; unset AGENT_TRANSCRIPTS_URL CLAUDE_CODE_REMOTE
"$root/plugins/change-record/bin/transcripts" archive --transcript "$main" 2>"$T/arch.err"
e="$T/archive/sessions/gh-aw-verify-pr-claims-4242-2.json"
q '
import json,sys; e=json.load(open(sys.argv[1]))
assert e["source"]=="agent" and e["repository"]=="github.com/owner/repo", (e["source"], e["repository"])
assert sorted(e["streams"])==["main","subagents/agent-toolu_01Px3oHxCRB1L5XsnhoSd4J5"], sorted(e["streams"])
assert e["first_timestamp"]=="2026-11-25T12:39:00.974Z" and e["last_timestamp"]=="2026-11-25T12:39:05.917Z", e
' "$e" && ok || bad "entry: $(cat "$T/arch.err") $(head -c 600 "$e" 2>/dev/null)"
it "the result line keeps only what the run cost, and its tokens over the whole run, subagents included"
assert_eq '{"type":"result","subtype":"success","is_error":false,"total_cost_usd":0.00584974,"num_turns":3,"duration_ms":7359}' "$(tail -1 "$main" | q 'import json,sys; d=json.loads(sys.stdin.read()); print(json.dumps({k: d[k] for k in ("type","subtype","is_error","total_cost_usd","num_turns","duration_ms")}, separators=(",",":")))')"
assert_eq '{"input":10,"output":689,"cache_read":82069,"cache_write":29675}' "$(tail -1 "$main" | q 'import json,sys; print(json.dumps(json.loads(sys.stdin.read()).get("run_usage"), separators=(",",":")))')"
# the run's final text (its "result" field) is not kept; the line is chained like the others
assert_eq "sessionId uuid" "$(tail -1 "$main" | q 'import json,sys; d=json.loads(sys.stdin.read()); print(" ".join(k for k in ("result","sessionId","uuid") if k in d) or "none")')"
it "the archive counts the run's effort per stream: one call per message, its tokens, tool calls, text, and the cost it reported"
q '
import json,sys; s=json.load(open(sys.argv[1]))["streams"]
m, sub = s["main"]["effort"], s["subagents/agent-toolu_01Px3oHxCRB1L5XsnhoSd4J5"]["effort"]
got = {k: m[k] for k in ("calls","input","output","cache_read","cache_write","tool_calls","posted_chars","cost_usd","turns","duration_ms")}
want = {"calls": 3, "input": 6, "output": 29, "cache_read": 66272, "cache_write": 12989, "tool_calls": 2, "posted_chars": 0,
        "cost_usd": 0.00584974, "turns": 3, "duration_ms": 7359}
assert (m["run_input"], m["run_output"], m["run_cache_read"], m["run_cache_write"]) == (10, 689, 82069, 29675), m
assert got == want, got
assert m["text_chars"] > 0, m
assert (sub["calls"], sub["output"], sub["tool_calls"]) == (1, 17, 1) and "cost_usd" not in sub, sub
' "$e" && ok || bad "effort: $(q 'import json,sys; print(json.dumps({k: v.get("effort") for k, v in json.load(open(sys.argv[1]))["streams"].items()}))' "$e" 2>&1 | head -c 600)"
it "the redaction reads it, keeping the agent's tool call"
"$root/plugins/change-record/bin/transcripts" redact < "$main" | grep -q 'cat a.txt' && ok || bad "redact lost the tool call"

it "this test runs in CI"
grep -qF 'bash bin/agent-session-collect.test.sh' "$root/.github/workflows/test.yml" && ok || bad "not in test.yml"

echo; echo "passed=$pass failed=$fail"
[ "$fail" -eq 0 ]
