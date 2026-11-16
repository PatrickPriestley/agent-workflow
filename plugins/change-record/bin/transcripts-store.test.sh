#!/usr/bin/env bash
# Tests for transcripts push and materialize against a stand-in for the store's HTTPS interface
# (store/stand-in.py, which answers as the real project answered store/probe). Fixtures use
# made-up addresses and tokens only. Needs bash, git and python3.
set -u
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
T="$here/transcripts"; STANDIN="$here/../store/stand-in.py"
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
export XDG_CONFIG_HOME="$TMPROOT/configA"
mkdir -p "$XDG_CONFIG_HOME/agent-transcripts" "$TMPROOT/configB/agent-transcripts"
printf 'machine-A\n' > "$XDG_CONFIG_HOME/agent-transcripts/machine-id"
printf 'machine-B\n' > "$TMPROOT/configB/agent-transcripts/machine-id"
READKEY="read-key-made-up-0001"

# standin NAME [--hang S]: start a stand-in; sets URL and LOG.
standin() {
  local pf="$TMPROOT/$1.port"; LOG="$TMPROOT/$1.log"; : > "$LOG"
  python3 "$STANDIN" "$pf" "$LOG" "$READKEY" "${@:2}" & PIDS="$PIDS $!"
  await_port "$pf"
  URL="http://127.0.0.1:$(cat "$pf")"
}
# A repository with the plugin skill, and a session in it.
REPO="$TMPROOT/checkout"; mkdir -p "$REPO/plugins/change-record/skills/change"; (
  cd "$REPO" && git init -q -b work && git config user.email t@example.com && git config user.name t
  git config core.hooksPath /dev/null
  printf -- '---\nname: change\n---\n# Change v1\n' > plugins/change-record/skills/change/SKILL.md
  git add -A && git commit -qm "feat: base" && git remote add origin https://github.com/Owner/Repo )
BLOB="$(git -C "$REPO" hash-object plugins/change-record/skills/change/SKILL.md)"
SID=aaaaaaaa-2222-3333-4444-555555555555
PROJ="$TMPROOT/claude/projects/-checkout"; mkdir -p "$PROJ/$SID/subagents"
TR="$PROJ/$SID.jsonl"; SUB="$PROJ/$SID/subagents/agent-a1.jsonl"
EMAIL="jane.doe@example.org"; GHTOK="ghp_ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789"
ANTTOK="sk-ant-api03-madeUpMadeUpMadeUp_0123456789-abcdefABCDEF"; AWSKEY="AKIAABCDEFGHIJKLMNOP"
BEARER="Bearer madeup.token-value_0123456789"; SBKEY="sb_secret_madeUp0123456789abcdefABCD"
line() { printf '{"sessionId":"%s","timestamp":"%s","cwd":"%s","gitBranch":"work","type":"%s","message":{"role":"%s","content":%s}}\n' "$SID" "$1" "$REPO" "$2" "$2" "$3"; }
part1() {
  line 2026-11-01T10:00:00.000Z user '"Mail '"$EMAIL"' about it.\nUse token '"$GHTOK"'"'
  line 2026-11-01T10:00:05.000Z assistant '[{"type":"tool_use","id":"t1","name":"Skill","input":{"skill":"change-record:change"}}]'
  line 2026-11-01T10:00:09.000Z user '[{"type":"tool_result","tool_use_id":"t1","content":"key='"$ANTTOK"' aws='"$AWSKEY"'\nAuthorization: '"$BEARER"'\napikey: '"$SBKEY"'\nmailto:'"$EMAIL"'"}]'
}
part2() {
  line 2026-11-01T10:05:00.000Z assistant '[{"type":"text","text":"Change: docs/changes/2026-11-01-x.md"}]'
  line 2026-11-01T10:09:00.000Z user '"plain line with nothing to hide"'
}
SECRETS=("$EMAIL" "$GHTOK" "$ANTTOK" "$AWSKEY" "madeup.token-value_0123456789" "$SBKEY")
AR="$TMPROOT/archive"
archive() { (cd "$REPO" && AGENT_TRANSCRIPTS="$AR" "$T" archive --transcript "$TR" < /dev/null 2>&1); }
push() { (cd "$REPO" && AGENT_TRANSCRIPTS="$AR" AGENT_TRANSCRIPTS_URL="$URL" "$T" push "$@" 2>&1); }
# sent: every chunk the stand-in was sent, decoded, as JSON lines {session, stream, generation, number, sender, text}.
sent() { python3 - "$LOG" <<'PY'
import base64, gzip, json, sys
for raw in open(sys.argv[1]):
    r = json.loads(raw)
    if r["method"] != "POST" or not r["path"].endswith("/chunks"):
        continue
    for c in (lambda b: b if isinstance(b, list) else [b])(json.loads(r["body"])):
        print(json.dumps({k: c.get(k) for k in ("session_id", "stream", "generation", "number", "sender", "chunk_id")}
                         | {"text": gzip.decompress(base64.b64decode(c["data"])).decode()}))
PY
}
methods() { python3 -c 'import json,sys; print(" ".join(sorted({json.loads(l)["method"] for l in open(sys.argv[1])})))' "$LOG"; }
count() { grep -c "\"path\": \"/rest/v1/$1\"" "$LOG" | tr -d ' '; }

echo "R4, R5: push sends new lines as redacted chunks, with inserts only"
standin s1
part1 > "$TR"; line 2026-11-01T10:01:00.000Z user '"sub '"$EMAIL"'"' > "$SUB"; archive > /dev/null
it "push sends each stream's archived lines as one chunk and one index row"
out="$(push)"; rc=$?
assert_eq 0 "$rc"
assert_eq "main subagents/agent-a1" "$(sent | python3 -c 'import json,sys; print(" ".join(sorted(json.loads(l)["stream"] for l in sys.stdin)))')"
assert_eq "1" "$(count sessions)"
it "it uses only POST: the hooks' key never reads, updates or deletes"
assert_eq "POST" "$(methods)"
it "no secret or address in the fixture reaches the store, in chunks or in any request"
for s in "${SECRETS[@]}"; do lacks "$(sent)" "$s"; lacks "$(cat "$LOG")" "$s"; done
has "$(sent)" "<redacted:email>"; has "$(sent)" "<redacted:github-token>"; has "$(sent)" "<redacted:anthropic-key>"
has "$(sent)" "<redacted:aws-key>"; has "$(sent)" "Bearer <redacted:token>"; has "$(sent)" "<redacted:supabase-key>"
it "every line sent is still JSON, and the local archive keeps the unredacted lines"
assert_eq "" "$(sent | python3 -c '
import json,sys
for l in sys.stdin:
    for x in json.loads(l)["text"].splitlines():
        try: json.loads(x)
        except ValueError: print("not JSON:", x[:80])')"
has "$(cat "$AR/parts/$SID/main/"g1-*.jsonl)" "$GHTOK"
it "the index entry records what was sent and the redaction version"
assert_eq "2 3 1" "$(python3 -c 'import json,sys; d=json.load(open(sys.argv[1])); s=d["sent"]["streams"]["main"]; print(d["redaction_version"], s["lines"], s["generation"])' "$AR/sessions/$SID.json" 2>&1)"
it "a push with nothing new sends nothing"
before="$(wc -l < "$LOG")"; out="$(push)"; rc=$?
assert_eq 0 "$rc"; assert_eq "$before" "$(wc -l < "$LOG")"
it "after growth, push sends only the new lines, as the next chunk, and a new index row version"
part2 >> "$TR"; archive > /dev/null; out="$(push)"
assert_eq "1 2 2" "$(sent | python3 -c '
import json,sys
r=[json.loads(l) for l in sys.stdin if json.loads(l)["stream"]=="main"]
print(r[-1]["generation"], r[-1]["number"], len(r[-1]["text"].splitlines()))')"
assert_eq "2" "$(count sessions)"
it "the sender is the machine id"
assert_eq "machine-A" "$(sent | python3 -c 'import json,sys; print(" ".join(sorted({json.loads(l)["sender"] for l in sys.stdin})))')"

echo "R4: a rewrite yields a new generation"
it "a transcript that no longer extends what was sent is sent whole as generation 2"
{ part1; line 2026-11-01T10:07:00.000Z user '"rewritten"'; } > "$TR"; archive > /dev/null; out="$(push)"
assert_eq "2 1 4" "$(sent | python3 -c '
import json,sys
r=[json.loads(l) for l in sys.stdin if json.loads(l)["stream"]=="main"]
print(r[-1]["generation"], r[-1]["number"], len(r[-1]["text"].splitlines()))')"
it "and the newest index row says so"
assert_eq "2" "$(python3 - "$LOG" <<'PY'
import json, sys
rows = [json.loads(json.loads(l)["body"]) for l in open(sys.argv[1]) if json.loads(l)["path"].endswith("/sessions")]
print(rows[-1]["entry"]["sent"]["streams"]["main"]["generation"])
PY
)"

echo "R4: two senders at once"
standin s2
SID2=bbbbbbbb-2222-3333-4444-555555555555; TRB="$PROJ/$SID2.jsonl"
part1 | sed "s/$SID/$SID2/" > "$TRB"
ARA="$TMPROOT/arA"; ARB="$TMPROOT/arB"
(cd "$REPO" && AGENT_TRANSCRIPTS="$ARA" "$T" archive --transcript "$TR" < /dev/null 2>/dev/null)
cp -r "$ARA" "$ARB"   # the same session archived the same way on two machines
(cd "$REPO" && XDG_CONFIG_HOME="$TMPROOT/configB" AGENT_TRANSCRIPTS="$ARB" "$T" archive --transcript "$TRB" < /dev/null 2>/dev/null)
it "two machines pushing at once both succeed"
(cd "$REPO" && AGENT_TRANSCRIPTS="$ARA" AGENT_TRANSCRIPTS_URL="$URL" "$T" push > "$TMPROOT/pa.out" 2>&1; echo $? > "$TMPROOT/pa.rc") &
pa=$!
(cd "$REPO" && XDG_CONFIG_HOME="$TMPROOT/configB" AGENT_TRANSCRIPTS="$ARB" AGENT_TRANSCRIPTS_URL="$URL" "$T" push > "$TMPROOT/pb.out" 2>&1; echo $? > "$TMPROOT/pb.rc") &
pb=$!; wait $pa $pb
assert_eq "0 0" "$(cat "$TMPROOT/pa.rc") $(cat "$TMPROOT/pb.rc")"
it "the store holds each chunk once: the second copy of a shared chunk is refused as a duplicate and counted as stored"
assert_eq "5" "$(count chunks)"   # A sends the shared session's 2 chunks, B those and its own
assert_eq "3" "$(python3 - "$URL" "$READKEY" <<'PY'
import json, sys, urllib.request
req = urllib.request.Request(sys.argv[1] + "/rest/v1/chunks?select=chunk_id", headers={"apikey": sys.argv[2]})
print(len(json.load(urllib.request.urlopen(req))))
PY
)"
it "each machine's archive records the shared session as sent"
for a in "$ARA" "$ARB"; do
  assert_eq "4" "$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["sent"]["streams"]["main"]["lines"])' "$a/sessions/$SID.json" 2>&1)"
done
it "both senders' index rows are kept, one per machine"
assert_eq "machine-A machine-B" "$(python3 - "$LOG" "$SID" <<'PY'
import json, sys
print(" ".join(sorted(json.loads(json.loads(l)["body"])["sender"] for l in open(sys.argv[1])
               if json.loads(l)["path"].endswith("/sessions") and sys.argv[2] in json.loads(l)["body"])))
PY
)"

echo "R2: an unreachable, refused or slow store never fails or slows a session"
it "push to an unreachable store reports it, keeps nothing as sent, and the next push sends it all"
SID3=cccccccc-2222-3333-4444-555555555555; TRC="$PROJ/$SID3.jsonl"; part1 | sed "s/$SID/$SID3/" > "$TRC"
ARC="$TMPROOT/arC"; (cd "$REPO" && AGENT_TRANSCRIPTS="$ARC" "$T" archive --transcript "$TRC" < /dev/null 2>/dev/null)
out="$(cd "$REPO" && AGENT_TRANSCRIPTS="$ARC" AGENT_TRANSCRIPTS_URL="http://127.0.0.1:9" "$T" push 2>&1)"; rc=$?
assert_eq 1 "$rc"; has "$out" "next stop"
assert_eq "{}" "$(python3 -c 'import json,sys; print(json.dumps(json.load(open(sys.argv[1]))["sent"]))' "$ARC/sessions/$SID3.json")"
standin s3
out="$(cd "$REPO" && AGENT_TRANSCRIPTS="$ARC" AGENT_TRANSCRIPTS_URL="$URL" "$T" push 2>&1)"; rc=$?
assert_eq 0 "$rc"; assert_eq "1" "$(count chunks)"
it "a store URL that is not https is refused before anything is sent"
out="$(cd "$REPO" && AGENT_TRANSCRIPTS="$ARC" AGENT_TRANSCRIPTS_URL="http://store.example.org" "$T" push 2>&1)"; rc=$?
assert_eq 2 "$rc"; has "$out" "not https"
it "a new redaction version sends every stream again, as the next generation"
python3 -c '
import json,sys; p=sys.argv[1]; d=json.load(open(p)); d["sent"]["redaction"]=0; open(p,"w").write(json.dumps(d))' "$ARC/sessions/$SID3.json"
out="$(cd "$REPO" && AGENT_TRANSCRIPTS="$ARC" AGENT_TRANSCRIPTS_URL="$URL" "$T" push 2>&1)"
assert_eq "2 2" "$(count chunks) $(python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["sent"]["streams"]["main"]["generation"])' "$ARC/sessions/$SID3.json")"
it "a push that stops between two streams after a new redaction version still sends both again (record 2026-11-12-push-resend-after-stop)"
SID7=dddddddd-2222-3333-4444-555555555555; TRR="$PROJ/$SID7.jsonl"; mkdir -p "$PROJ/$SID7/subagents"
part1 | sed "s/$SID/$SID7/" > "$TRR"; line 2026-11-01T10:01:00.000Z user '"sub line"' | sed "s/$SID/$SID7/" > "$PROJ/$SID7/subagents/agent-a1.jsonl"
ARR="$TMPROOT/arR"; pushR() { (cd "$REPO" && AGENT_TRANSCRIPTS="$ARR" AGENT_TRANSCRIPTS_URL="$URL" "$T" push 2>&1); }
gens() { python3 -c 'import json,sys; s=json.load(open(sys.argv[1]))["sent"]; print(s["redaction"], " ".join("%s=%d/%d" % (k, v["generation"], v["parts"]) for k, v in sorted(s["streams"].items())))' "$ARR/sessions/$SID7.json"; }
(cd "$REPO" && AGENT_TRANSCRIPTS="$ARR" "$T" archive --transcript "$TRR" < /dev/null 2>/dev/null)
standin sr1; out="$(pushR)"
assert_eq "2 main=1/1 subagents/agent-a1=1/1" "$(gens)"
python3 -c '
import json,sys; p=sys.argv[1]; d=json.load(open(p)); d["sent"]["redaction"]=0; open(p,"w").write(json.dumps(d))' "$ARR/sessions/$SID7.json"
standin sr2 --refuse-after 1; out="$(pushR)"; rc=$?
assert_eq 1 "$rc"; has "$out" "503"
it "after the stop, the entry says the stream that was not reached is still owed"
assert_eq "2 main=2/1 subagents/agent-a1=2/0" "$(gens)"
it "the next push sends the stream that was not reached, as the next generation, and the first one is not sent a third time"
standin sr3; out="$(pushR)"; rc=$?
assert_eq "0 2 main=2/1 subagents/agent-a1=2/1" "$rc $(gens)"
assert_eq "subagents/agent-a1 2" "$(sent | python3 -c 'import json,sys; print(" ".join("%s %d" % (c["stream"], c["generation"]) for c in map(json.loads, sys.stdin)))')"
it "and a push after that has nothing to send"
standin sr4; out="$(pushR)"
assert_eq "0 0" "$(count chunks) $(count sessions)"
it "a later index row the store refused is sent at the next push, with no chunk sent again"
SID6=abababab-2222-3333-4444-555555555555; TRF="$PROJ/$SID6.jsonl"; part1 | sed "s/$SID/$SID6/" > "$TRF"
ARF="$TMPROOT/arF"; pushF() { (cd "$REPO" && AGENT_TRANSCRIPTS="$ARF" AGENT_TRANSCRIPTS_URL="$URL" "$T" push 2>&1); }
(cd "$REPO" && AGENT_TRANSCRIPTS="$ARF" "$T" archive --transcript "$TRF" < /dev/null 2>/dev/null)
standin s7; out="$(pushF)"
part2 | sed "s/$SID/$SID6/" >> "$TRF"; (cd "$REPO" && AGENT_TRANSCRIPTS="$ARF" "$T" archive --transcript "$TRF" < /dev/null 2>/dev/null)
standin s8 --refuse sessions; out="$(pushF)"; rc=$?
assert_eq "1 1" "$rc $(count chunks)"
standin s9; out="$(pushF)"; rc=$?
assert_eq "0 0 1" "$rc $(count chunks) $(count sessions)"
it "an insert key file others can read is refused, and nothing is sent"
mkdir -p "$TMPROOT/configK/agent-transcripts"; printf 'insert-key-made-up\n' > "$TMPROOT/configK/agent-transcripts/insert-key"
chmod 644 "$TMPROOT/configK/agent-transcripts/insert-key"; cp "$XDG_CONFIG_HOME/agent-transcripts/machine-id" "$TMPROOT/configK/agent-transcripts/"
ARK="$TMPROOT/arK"; cp -r "$ARC" "$ARK"; python3 -c '
import json,sys; p=sys.argv[1]; d=json.load(open(p)); d["sent"]={}; open(p,"w").write(json.dumps(d))' "$ARK/sessions/$SID3.json"
before="$(wc -l < "$LOG")"
out="$(cd "$REPO" && XDG_CONFIG_HOME="$TMPROOT/configK" AGENT_TRANSCRIPTS="$ARK" AGENT_TRANSCRIPTS_URL="$URL" "$T" push 2>&1)"; rc=$?
assert_eq 1 "$rc"; has "$out" "chmod 600"; assert_eq "$before" "$(wc -l < "$LOG")"
it "a 0600 insert key file is sent as the apikey header"
chmod 600 "$TMPROOT/configK/agent-transcripts/insert-key"
out="$(cd "$REPO" && XDG_CONFIG_HOME="$TMPROOT/configK" AGENT_TRANSCRIPTS="$ARK" AGENT_TRANSCRIPTS_URL="$URL" "$T" push 2>&1)"
assert_eq "insert-key-made-up" "$(tail -1 "$LOG" | python3 -c 'import json,sys; print(json.load(sys.stdin)["apikey"])')"
it "the hook returns at once while a slow store is sent to in the background, within its time limit"
standin s4 --hang 3
SID4=dddddddd-2222-3333-4444-555555555555; TRD="$PROJ/$SID4.jsonl"; part1 | sed "s/$SID/$SID4/" > "$TRD"
ARD="$TMPROOT/arD"
start=$(date +%s)
out="$(printf '{"session_id":"%s","transcript_path":"%s","cwd":"%s"}' "$SID4" "$TRD" "$REPO" \
  | (cd "$REPO" && AGENT_TRANSCRIPTS="$ARD" AGENT_TRANSCRIPTS_URL="$URL" "$T" archive 2>&1))"; rc=$?
took=$(( $(date +%s) - start ))
assert_eq 0 "$rc"; [ "$took" -le 1 ] && ok || bad "the hook took ${took}s"
for _ in $(seq 100); do grep -q '"/rest/v1/sessions"' "$LOG" 2>/dev/null && break; sleep 0.1; done
for _ in $(seq 50); do [ "$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["sent"].get("version"))' "$ARD/sessions/$SID4.json")" = 1 ] && break; sleep 0.1; done
assert_eq "1" "$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["sent"].get("version"))' "$ARD/sessions/$SID4.json")"
it "a background push past its time limit stops, and its stderr goes to the archive's log"
SID5=eeeeeeee-2222-3333-4444-555555555555; TRE="$PROJ/$SID5.jsonl"; part1 | sed "s/$SID/$SID5/" > "$TRE"
standin s5 --hang 30
printf '{"session_id":"%s","transcript_path":"%s","cwd":"%s"}' "$SID5" "$TRE" "$REPO" \
  | (cd "$REPO" && AGENT_TRANSCRIPTS="$ARD" AGENT_TRANSCRIPTS_URL="$URL" AGENT_TRANSCRIPTS_PUSH_LIMIT=1 "$T" archive 2>&1)
for _ in $(seq 60); do grep -q "time limit" "$ARD/push.log" 2>/dev/null && break; sleep 0.1; done
has "$(cat "$ARD/push.log" 2>&1)" "time limit"
assert_eq "{}" "$(python3 -c 'import json,sys; print(json.dumps(json.load(open(sys.argv[1]))["sent"]))' "$ARD/sessions/$SID5.json")"
it "with AGENT_TRANSCRIPTS_URL unset the hook sends nothing and push says why"
out="$(cd "$REPO" && AGENT_TRANSCRIPTS="$ARD" "$T" push 2>&1)"; rc=$?
assert_eq 2 "$rc"; has "$out" "AGENT_TRANSCRIPTS_URL"

echo "R7: materialize rebuilds Claude Code's layout from the store"
standin s6
ARM="$TMPROOT/arM"; part1 > "$TR"; part2 >> "$TR"; line 2026-11-01T10:01:00.000Z user '"sub"' > "$SUB"
(cd "$REPO" && AGENT_TRANSCRIPTS="$ARM" "$T" archive --transcript "$TR" < /dev/null 2>/dev/null)
(cd "$REPO" && AGENT_TRANSCRIPTS="$ARM" AGENT_TRANSCRIPTS_URL="$URL" "$T" push > /dev/null 2>&1)
part2 | sed 's/10:0/10:1/' >> "$TR"
(cd "$REPO" && AGENT_TRANSCRIPTS="$ARM" "$T" archive --transcript "$TR" < /dev/null 2>/dev/null)
(cd "$REPO" && AGENT_TRANSCRIPTS="$ARM" AGENT_TRANSCRIPTS_URL="$URL" "$T" push > /dev/null 2>&1)
printf '%s\n' "$READKEY" > "$XDG_CONFIG_HOME/agent-transcripts/read-key"; chmod 600 "$XDG_CONFIG_HOME/agent-transcripts/read-key"
OUT="$TMPROOT/mat"
mat() { (cd "$REPO" && AGENT_TRANSCRIPTS_URL="$URL" "$T" materialize "$@" 2>&1); }
it "materialize writes each session's transcripts in Claude Code's layout"
out="$(mat "$OUT")"; rc=$?
assert_eq 0 "$rc"
assert_eq "projects/github-com-owner-repo/$SID.jsonl projects/github-com-owner-repo/$SID/subagents/agent-a1.jsonl sessions/$SID.json skills/change-record:change/SKILL.md" \
  "$(cd "$OUT" 2>/dev/null && find . -type f | sed 's|^\./||' | sort | tr '\n' ' ' | sed 's/ $//')"
it "the transcript is the redacted text of every line, in order"
assert_eq "$(python3 "$here/transcripts" redact < "$TR" 2>&1)" "$(cat "$OUT/projects/github-com-owner-repo/$SID.jsonl" 2>&1)"
lacks "$(cat "$OUT/projects/github-com-owner-repo/$SID.jsonl" 2>&1)" "$GHTOK"
it "each file's time is its last timestamp"
assert_eq "2026-11-01T10:19:00 2026-11-01T10:01:00" "$(python3 -c '
import os,sys,datetime
print(" ".join(datetime.datetime.fromtimestamp(os.path.getmtime(p), datetime.timezone.utc).strftime("%Y-%m-%dT%H:%M:%S") for p in sys.argv[1:]))' \
  "$OUT/projects/github-com-owner-repo/$SID.jsonl" "$OUT/projects/github-com-owner-repo/$SID/subagents/agent-a1.jsonl" 2>&1)"
it "the skills folder holds each skill under its plugin-qualified name, at the version the session used"
(cd "$REPO" && printf -- '---\nname: change\n---\n# Change v2\n' > plugins/change-record/skills/change/SKILL.md && git commit -qam "feat: v2")
rm -rf "$OUT"; out="$(mat "$OUT")"
assert_eq "$(git -C "$REPO" cat-file blob "$BLOB")" "$(cat "$OUT/skills/change-record:change/SKILL.md" 2>&1)"
it "the session's index entry is written beside them"
assert_eq "$SID 2" "$(python3 -c 'import json,sys; d=json.load(open(sys.argv[1])); print(d["session_id"], d["sent"]["version"])' "$OUT/sessions/$SID.json" 2>&1)"
it "materialize reads with the read key, and without one it is refused before any request"
mv "$XDG_CONFIG_HOME/agent-transcripts/read-key" "$TMPROOT/rk"; before="$(wc -l < "$LOG")"
out="$(mat "$TMPROOT/mat2")"; rc=$?
assert_eq 2 "$rc"; has "$out" "read-key"; assert_eq "$before" "$(wc -l < "$LOG")"
mv "$TMPROOT/rk" "$XDG_CONFIG_HOME/agent-transcripts/read-key"
it "a stored chunk whose bytes do not match its chain id is refused, and the session is not written"
cid="$(python3 - "$LOG" <<'PY'
import json, sys
print([json.loads(json.loads(l)["body"])["chunk_id"] for l in open(sys.argv[1])
       if json.loads(l)["method"] == "POST" and json.loads(l)["path"].endswith("/chunks")][0])
PY
)"
python3 -c 'import json,sys,urllib.request; urllib.request.urlopen(urllib.request.Request(sys.argv[1]+"/__admin/tamper", data=json.dumps({"chunk_id":sys.argv[2]}).encode(), method="POST"))' "$URL" "$cid"
out="$(mat "$TMPROOT/mat3")"; rc=$?
assert_eq 1 "$rc"; has "$out" "does not match"; [ -e "$TMPROOT/mat3/projects/github-com-owner-repo/$SID.jsonl" ] && bad "a tampered transcript was written" || ok
it "an index row whose stream or session id would write outside the folder is refused"
python3 - "$URL" <<'PY'
import base64, gzip, hashlib, json, sys, urllib.request
def post(t, row):
    urllib.request.urlopen(urllib.request.Request(sys.argv[1] + "/rest/v1/" + t, data=json.dumps(row).encode(), method="POST"))
for sid, stream in (("ffffffff-0000", "subagents/../../../../escape"), ("..", "main")):
    raw = b'{"x":1}\n'
    root = hashlib.sha256(f"{sid}/{stream}".encode()).hexdigest()
    cid = hashlib.sha256(f"{root}:{hashlib.sha256(raw).hexdigest()}".encode()).hexdigest()
    post("chunks", {"session_id": sid, "stream": stream, "chunk_id": cid, "start_id": root, "data": base64.b64encode(gzip.compress(raw)).decode()})
    post("sessions", {"session_id": sid, "row_id": cid, "sender": "x", "version": 1,
                      "entry": {"repository": "r", "sent": {"streams": {stream: {"tip": cid}}}}})
PY
out="$(mat "$TMPROOT/mat4/inner")"; rc=$?
assert_eq 1 "$rc"; has "$out" "not a transcript name"; has "$out" "not a plain name"
assert_eq "" "$(find "$TMPROOT/mat4" "$TMPROOT" -maxdepth 1 -name 'escape*' 2>/dev/null; find "$TMPROOT/mat4" -name 'escape*' 2>/dev/null)"
it "a stream or skill named with a leading dot segment is refused, not written one folder up"
python3 - "$URL" "$BLOB" <<'PY'
import base64, gzip, hashlib, json, sys, urllib.request
def post(t, row):
    urllib.request.urlopen(urllib.request.Request(sys.argv[1] + "/rest/v1/" + t, data=json.dumps(row).encode(), method="POST"))
for sid, stream, skills in (("ffffffff-0001", "subagents/../x", []), ("ffffffff-0002", "subagents/./x", []),
                            ("ffffffff-0003", "main", [{"name": "..", "blob": sys.argv[2]}, {"name": ".", "blob": sys.argv[2]},
                                                       {"name": "p:..", "blob": sys.argv[2]}])):
    raw = b'{"x":1}\n'
    root = hashlib.sha256(f"{sid}/{stream}".encode()).hexdigest()
    cid = hashlib.sha256(f"{root}:{hashlib.sha256(raw).hexdigest()}".encode()).hexdigest()
    post("chunks", {"session_id": sid, "stream": stream, "chunk_id": cid, "start_id": root, "data": base64.b64encode(gzip.compress(raw)).decode()})
    post("sessions", {"session_id": sid, "row_id": cid, "sender": "x", "version": 1,
                      "entry": {"repository": "r", "skills": skills, "sent": {"streams": {stream: {"tip": cid}}}}})
PY
out="$(mat "$TMPROOT/mat5")"
has "$out" "'subagents/../x' is not a transcript name"; has "$out" "'subagents/./x' is not a transcript name"
assert_eq "" "$(find "$TMPROOT/mat5" -name 'x.jsonl' 2>/dev/null)"
assert_eq "" "$(find "$TMPROOT/mat5" -maxdepth 2 -name SKILL.md 2>/dev/null)"
it "a folder inside a repository's working tree is refused"
out="$(mat "$REPO/mat")"; rc=$?
assert_eq 2 "$rc"; has "$out" "working tree"

echo "store faults (record 2026-11-12-store-faults): one session that cannot be sent, the newest redaction, a long run of letters"
# two sessions in one archive; the first by name cannot be read
SIDX=10000000-2222-3333-4444-555555555555; SIDY=20000000-2222-3333-4444-555555555555
part1 | sed "s/$SID/$SIDX/" > "$PROJ/$SIDX.jsonl"; part1 | sed "s/$SID/$SIDY/" > "$PROJ/$SIDY.jsonl"
ARX="$TMPROOT/arX"; pushX() { (cd "$REPO" && AGENT_TRANSCRIPTS="$ARX" AGENT_TRANSCRIPTS_URL="$URL" "$T" push 2>&1); }
for x in $SIDX $SIDY; do (cd "$REPO" && AGENT_TRANSCRIPTS="$ARX" "$T" archive --transcript "$PROJ/$x.jsonl" < /dev/null 2>/dev/null); done
sentof() { python3 -c 'import json,sys; print(json.dumps(json.load(open(sys.argv[1]))["sent"].get("version")))' "$ARX/sessions/$1.json"; }
chunks_of() { grep "\"path\": \"/rest/v1/chunks\"" "$LOG" | grep -c "$1" | tr -d ' '; }
mv "$ARX/parts/$SIDX" "$TMPROOT/held-parts"
standin sx1; out="$(pushX)"; rc=$?
it "a session whose archived lines cannot be read does not keep the next one from being sent"
assert_eq "1 0 1" "$rc $(chunks_of $SIDX) $(chunks_of $SIDY)"
assert_eq "null 1" "$(sentof $SIDX) $(sentof $SIDY)"
it "the push says which session it could not send, and that the rest went"
has "$out" "${SIDX:0:8}"; has "$out" "1 session could not be sent"; has "$out" "pushed 1 new chunks"
it "the next push tries that session again and sends nothing twice"
out="$(pushX)"; rc=$?
assert_eq "1 0 1" "$rc $(chunks_of $SIDX) $(chunks_of $SIDY)"
mv "$TMPROOT/held-parts" "$ARX/parts/$SIDX"
it "a session the store refuses is the same: the others still go, and it is tried again once the store takes it"
ARZ="$TMPROOT/arZ"; pushZ() { (cd "$REPO" && AGENT_TRANSCRIPTS="$ARZ" AGENT_TRANSCRIPTS_URL="$URL" "$T" push 2>&1); }
for x in $SIDX $SIDY; do (cd "$REPO" && AGENT_TRANSCRIPTS="$ARZ" "$T" archive --transcript "$PROJ/$x.jsonl" < /dev/null 2>/dev/null); done
standin sx2 --refuse-session $SIDX; out="$(pushZ)"; rc=$?
assert_eq "1 1" "$rc $(python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["sent"].get("version"))' "$ARZ/sessions/$SIDY.json")"
has "$out" "${SIDX:0:8}"; has "$out" "400"
it "a session that was passed over is tried once in a push, not at each of its passes"
assert_eq 1 "$(chunks_of $SIDX)"
standin sx3; out="$(pushZ)"; rc=$?
assert_eq "0 1 0" "$rc $(chunks_of $SIDX) $(chunks_of $SIDY)"
it "a store that cannot be reached, or fails as a whole, still stops the push at once"
standin sx4 --refuse chunks; ARW="$TMPROOT/arW"
for x in $SIDX $SIDY; do (cd "$REPO" && AGENT_TRANSCRIPTS="$ARW" "$T" archive --transcript "$PROJ/$x.jsonl" < /dev/null 2>/dev/null); done
out="$(cd "$REPO" && AGENT_TRANSCRIPTS="$ARW" AGENT_TRANSCRIPTS_URL="$URL" "$T" push 2>&1)"; rc=$?
assert_eq "1 1" "$rc $(count chunks)"; has "$out" "push stopped"
it "a refusal that is about who asks or how often (401, 429) is the store's, not one session's: the push stops at once"
for st in 401 429; do
  standin "sx5-$st" --refuse chunks --refuse-status $st
  out="$(cd "$REPO" && AGENT_TRANSCRIPTS="$ARW" AGENT_TRANSCRIPTS_URL="$URL" "$T" push 2>&1)"; rc=$?
  assert_eq "1 1" "$rc $(count chunks)"; has "$out" "push stopped"
done

# the same session sent twice, the second time by a copy of the tool with the next redaction version, which
# takes a long word out: the second copy in the store is the shorter one
SIDN=30000000-2222-3333-4444-555555555555; WORD="SHORTENME$(python3 -c 'print("x" * 400)')"
line 2026-11-01T10:00:00.000Z user "\"Take $WORD out of this.\"" | sed "s/$SID/$SIDN/" > "$PROJ/$SIDN.jsonl"
ARN="$TMPROOT/arN"; (cd "$REPO" && AGENT_TRANSCRIPTS="$ARN" "$T" archive --transcript "$PROJ/$SIDN.jsonl" < /dev/null 2>/dev/null)
mkdir -p "$TMPROOT/v2/bin"; python3 - "$T" "$TMPROOT/v2/bin/transcripts" "$TMPROOT/v2/next" <<'PY'
import os, re, sys
s = open(sys.argv[1]).read()
now = int(re.search(r"\nREDACTION = (\d+)", s).group(1))
a = s.replace("\nREDACTION = %d" % now, "\nREDACTION = %d" % (now + 1), 1).replace("\nPATTERNS = [", "\nPATTERNS = [\n    (_R(r\"SHORTENMEx*\"), \"\"),", 1)
assert a.count("REDACTION = %d" % (now + 1)) == 1 and "SHORTENMEx*" in a
open(sys.argv[2], "w").write(a); os.chmod(sys.argv[2], 0o755)
open(sys.argv[3], "w").write(str(now + 1))
PY
standin sn1
(cd "$REPO" && AGENT_TRANSCRIPTS="$ARN" AGENT_TRANSCRIPTS_URL="$URL" "$T" push > /dev/null 2>&1)
(cd "$REPO" && AGENT_TRANSCRIPTS="$ARN" AGENT_TRANSCRIPTS_URL="$URL" "$TMPROOT/v2/bin/transcripts" push > /dev/null 2>&1)
it "after a new redaction that shortens the text, materialize returns the newer copy, not the longer one"
assert_eq "2 2" "$(count chunks) $(count sessions)"
out="$(mat "$TMPROOT/matN" --session $SIDN)"
got="$(cat "$TMPROOT/matN"/projects/*/"$SIDN.jsonl" 2>/dev/null)"
has "$got" "out of this"; lacks "$got" "SHORTENME"
assert_eq "$(cat "$TMPROOT/v2/next")" "$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["redaction_version"])' "$TMPROOT/matN/sessions/$SIDN.json")"

it "addresses are redacted exactly as the one pattern redacts them: 30,000 made-up strings and the hard cases"
# The program is a file, not a here-document inside "$( )": there bash 3.2 (macOS) expands the braces of the
# pattern's {2,} as it does a word's, and Python is given a pattern ending in 2 that finds no address at all
# (seen on the macOS runner, record 2026-11-15-suites-on-macos).
cat > "$TMPROOT/addresses.py" <<'ADDRESSES'
import importlib.machinery, importlib.util, random, re, sys
sys.dont_write_bytecode = True
loader = importlib.machinery.SourceFileLoader("tr", sys.argv[1])
tr = importlib.util.module_from_spec(importlib.util.spec_from_loader("tr", loader)); loader.exec_module(tr)
plain = re.compile(r"[A-Za-z0-9._%+-]+(?:@|%40)[A-Za-z0-9-]+(?:\.[A-Za-z0-9-]+)*\.[A-Za-z]{2,}")
random.seed(11)
parts = ["a", "b", "1", "4", "0", ".", "%", "+", "-", "_", "@", " ", "\n", "/", ":", "<", ">", "x", "%40", ".com", ".org",
         "jane.doe@example.org", "\u00e9", "@a.co", "%40b.io", "a%40", "40", ".c", "-.", "..", "@@", "%4"]
cases = ["".join(random.choice(parts) for _ in range(random.randint(1, 30))) for _ in range(30000)]
cases += ["jane.doe@example.org1@a.co", "a@b.orgc@d.com", "x%40y.io%40z.io", "a%40b@c.org", "@a.co", "a@", "a@b", "a@b.c", "%40%40%40a.io",
          "mailto:jane.doe@example.org,john%40example.com.", "a@b.co" * 50, ""]
wrong = [t for t in cases if tr.redact_emails(t) != plain.sub("<redacted:email>", t)]
print("same" if not wrong else "differ", len(cases) - len(wrong))
for t in wrong[:4]:  # which, when they differ: a difference seen on one machine only cannot be found without them
    print("input %r | redactor %r | pattern %r" % (t, tr.redact_emails(t), plain.sub("<redacted:email>", t)))
if wrong:  # and whether the pattern this program holds is the one written above
    print("python %s | the pattern as compiled: %r | it finds jane.doe@example.org: %s"
          % (sys.version.split()[0], plain.pattern, bool(plain.search("jane.doe@example.org"))))
ADDRESSES
assert_eq "same 30012" "$(python3 "$TMPROOT/addresses.py" "$T" 2>&1)"
it "redaction of a long run of letters, digits and dots takes well under a second, not a time that grows with its square"
python3 -c 'import json; print(json.dumps({"type": "user", "message": {"role": "user", "content": "0f" * 30000 + " and " + "a." * 30000 + " and " + "%40" * 20000}}))' > "$TMPROOT/long.jsonl"
assert_eq "done 1" "$(python3 - "$T" "$TMPROOT/long.jsonl" <<'PY'
import subprocess, sys
try:
    r = subprocess.run([sys.argv[1], "redact"], stdin=open(sys.argv[2], "rb"), capture_output=True, timeout=5)
    print("done", len(r.stdout.splitlines()))
except subprocess.TimeoutExpired:
    print("not done in 5 s")
PY
)"

echo "account ids (record 2026-11-14-redact-account-id): the ids of the owner's account do not leave the machine"
# made-up ids: ORG under the key and in text, ACC only inside a string that is itself JSON, as a command's output
ORG="0a1b2c3d-1111-2222-3333-444455556666"; ACC="5e6f7a8b-9999-8888-7777-666655554444"; MARK="<redacted:account-id>"
SIDA=40000000-2222-3333-4444-555555555555; mkdir -p "$PROJ/$SIDA/subagents"
TRA="$PROJ/$SIDA.jsonl"; SUBA="$PROJ/$SIDA/subagents/agent-b1.jsonl"
linea() { line "$@" | sed "s/$SID/$SIDA/"; }
# att SESSION TIME KEY VALUE: the line a harness writes about the account
att() { printf '{"sessionId":"%s","timestamp":"%s","cwd":"%s","gitBranch":"work","type":"attachment","attachment":{"type":"account","%s":"%s"}}\n' "$1" "$2" "$REPO" "$3" "$4"; }
{ linea 2026-11-02T10:00:00.000Z user '"start"'
  att "$SIDA" 2026-11-02T10:00:01.000Z organizationUuid "$ORG"
  att "$SIDA" 2026-11-02T10:00:02.000Z userID u1
  linea 2026-11-02T10:00:03.000Z user '"Connect at https://claude.ai/connect-github?org='"$ORG"' first"'
  linea 2026-11-02T10:00:04.000Z assistant '[{"type":"tool_use","id":"t1","name":"Bash","input":{"command":"ls /root/.claude/skills/synced/'"$ORG"'/x; cat ~/.claude.json"}}]'
  linea 2026-11-02T10:00:05.000Z user '[{"type":"tool_result","tool_use_id":"t1","content":"{\"oauthAccount\":{\"accountUuid\":\"'"$ACC"'\"}}\nseen '"$ACC"' and u1 again"}]'
} > "$TRA"
linea 2026-11-02T10:00:06.000Z user '"the subagent reads synced/'"$ORG"'/y"' > "$SUBA"
ARA="$TMPROOT/arA"
archivea() { (cd "$REPO" && AGENT_TRANSCRIPTS="$ARA" "$T" archive --transcript "$1" < /dev/null 2>&1); }
pusha() { (cd "$REPO" && AGENT_TRANSCRIPTS="$ARA" AGENT_TRANSCRIPTS_URL="$URL" "$T" push "$@" 2>&1); }
standin sa1; archivea "$TRA" > /dev/null; out="$(pusha)"; rc=$?
it "a session with the account's id under its key and in text is sent"
assert_eq "0 2" "$rc $(sent | wc -l | tr -d ' ')"
it "the id is in no chunk and no request: not under its key, not in a URL, not as a folder name"
lacks "$(sent)" "$ORG"; lacks "$(cat "$LOG")" "$ORG"
has "$(sent)" "\\\"organizationUuid\\\":\\\"$MARK\\\""; has "$(sent)" "org=$MARK first"; has "$(sent)" "synced/$MARK/x"
it "an id named only inside a string that is itself JSON is learned from it, and taken out there and after"
lacks "$(sent)" "$ACC"; has "$(sent)" "seen $MARK and"
it "a subagent's stream that has the id in text only is redacted with what the main stream taught"
has "$(sent)" "synced/$MARK/y"
it "a short value is masked at its key and not learned: the same letters elsewhere stay"
has "$(sent)" "\\\"userID\\\":\\\"$MARK\\\""; has "$(sent)" "and u1 again"
it "every line sent is still JSON"
assert_eq "ok" "$(sent | python3 -c 'import json,sys
for l in sys.stdin:
    for x in json.loads(l)["text"].splitlines(): json.loads(x)
print("ok")' 2>&1)"
it "a later run sends a later part that has the id in text and no key: it learns from the first part"
linea 2026-11-02T10:09:00.000Z user '"again '"$ORG"' later"' >> "$TRA"; archivea "$TRA" > /dev/null
standin sa2; out="$(pusha)"
has "$(sent)" "again $MARK later"; lacks "$(sent)" "$ORG"; lacks "$(cat "$LOG")" "$ORG"
it "the key in a subagent's stream teaches the main stream, which is redacted first"
SIDB=50000000-2222-3333-4444-555555555555; mkdir -p "$PROJ/$SIDB/subagents"; ORGB="9f8e7d6c-aaaa-bbbb-cccc-ddddeeeeffff"
linea 2026-11-02T11:00:00.000Z user '"main names '"$ORGB"' only in text"' | sed "s/$SIDA/$SIDB/" > "$PROJ/$SIDB.jsonl"
att "$SIDB" 2026-11-02T11:00:01.000Z organizationUuid "$ORGB" > "$PROJ/$SIDB/subagents/agent-c1.jsonl"
ARB="$TMPROOT/arB"; (cd "$REPO" && AGENT_TRANSCRIPTS="$ARB" "$T" archive --transcript "$PROJ/$SIDB.jsonl" < /dev/null > /dev/null 2>&1)
standin sb1; (cd "$REPO" && AGENT_TRANSCRIPTS="$ARB" AGENT_TRANSCRIPTS_URL="$URL" "$T" push > /dev/null 2>&1)
has "$(sent)" "main names $MARK only"; lacks "$(sent)" "$ORGB"; lacks "$(cat "$LOG")" "$ORGB"
it "redact reads all its input first: text before the key's line, and a line that is not JSON, lose the id too"
got="$( { linea 2026-11-02T12:00:00.000Z user '"early '"$ORG"' use"'; att "$SIDA" 2026-11-02T12:00:01.000Z organizationUuid "$ORG"; printf 'not json org=%s here\n' "$ORG"; } | "$T" redact 2>&1)"
lacks "$got" "$ORG"; has "$got" "early $MARK use"; has "$got" "not json org=$MARK here"
assert_eq 3 "$(printf '%s\n' "$got" | wc -l | tr -d ' ')"
it "a line with no id keeps its exact bytes"
assert_eq "$(linea 2026-11-02T12:00:00.000Z user '"nothing here"' | cksum)" "$( { linea 2026-11-02T12:00:00.000Z user '"nothing here"'; att "$SIDA" 2026-11-02T12:00:01.000Z organizationUuid "$ORG"; } | "$T" redact | head -1 | cksum)"
it "an id that begins another is taken out whole: the longer one first, no tail left"
got="$( { att "$SIDA" 2026-11-02T12:00:00.000Z userID abcdefgh1234; att "$SIDA" 2026-11-02T12:00:01.000Z accountUuid abcdefgh1234-5678-wxyz; linea 2026-11-02T12:00:02.000Z user '"both abcdefgh1234-5678-wxyz and abcdefgh1234."'; } | "$T" redact 2>&1)"
has "$got" "both $MARK and $MARK.\""; lacks "$got" "5678"
it "under an account key only a string is replaced: a null stays, and an object is redacted like any other"
got="$(printf '{"userID":null,"accountUuid":{"note":"mail %s","organizationUuid":"%s"}}\n' "$EMAIL" "$ORG" | "$T" redact 2>&1)"
assert_eq "{\"userID\":null,\"accountUuid\":{\"note\":\"mail <redacted:email>\",\"organizationUuid\":\"$MARK\"}}" "$got"
it "a part that names a new id, as a session resumed under another account would, teaches the redactor before that part is sent"
ORGC="77777777-1234-1234-1234-121212121212"
{ att "$SIDA" 2026-11-02T10:20:00.000Z organizationUuid "$ORGC"; linea 2026-11-02T10:20:01.000Z user '"now under '"$ORGC"' here"'; } >> "$TRA"; archivea "$TRA" > /dev/null
standin sa3; out="$(pusha)"
has "$(sent)" "now under $MARK here"; lacks "$(sent)" "$ORGC"; lacks "$(cat "$LOG")" "$ORGC"
it "a sheet made from the archive's own lines shows the placeholder too"
mkdir -p "$TMPROOT/labelsA2"; out="$(cd "$REPO" && "$T" sheet "$ARA" --labels "$TMPROOT/labelsA2" 2>&1)"
sheet="$(cat "$ARA/sheets/$SIDA.md" 2>/dev/null)"
lacks "$sheet" "$ORG"; has "$sheet" "synced/$MARK/x"
it "the other spelling of the key, as a tool's result has it, is known too"
ACCS="31313131-4444-4444-4444-565656565656"
got="$( { linea 2026-11-02T12:00:00.000Z user '"listed {\"creator\":{\"account_uuid\":\"'"$ACCS"'\",\"organization_uuid\":\"'"$ORGB"'\"}} then '"$ACCS"' and '"$ORGB"'"'; } | "$T" redact 2>&1)"
lacks "$got" "$ACCS"; lacks "$got" "$ORGB"; has "$got" "then $MARK and $MARK\""
it "an id joined to a known one in a folder name, with no key of its own anywhere, is learned from the name"
ACCJ="42424242-5555-5555-5555-676767676767"
got="$( { att "$SIDA" 2026-11-02T12:00:00.000Z organizationUuid "$ORG"; linea 2026-11-02T12:00:01.000Z user '"ls skills/synced/'"${ORG}_$ACCJ"'/x"'; linea 2026-11-02T12:00:02.000Z user '"alone '"$ACCJ"' too"'; } | "$T" redact 2>&1)"
lacks "$got" "$ACCJ"; has "$got" "synced/${MARK}_$MARK/x"; has "$got" "alone $MARK too"
it "a later part sent by a later run with only the joined name loses both ids"
linea 2026-11-02T10:30:00.000Z user '"cat synced/'"${ORG}_$ACCJ"'/SKILL.md, then '"$ACCJ"'"' >> "$TRA"; archivea "$TRA" > /dev/null
standin sa4; out="$(pusha)"
has "$(sent)" "synced/${MARK}_$MARK/SKILL.md, then $MARK"; lacks "$(sent)" "$ACCJ"; lacks "$(sent)" "$ORG"
it "a UUID that merely follows an underscore, with no known id before it, stays, though an id is known"
got="$( { att "$SIDA" 2026-11-02T12:00:00.000Z organizationUuid "$ORG"; linea 2026-11-02T12:00:01.000Z user '"run_'"$ACCJ"' kept"'; } | "$T" redact 2>&1)"
has "$got" "run_$ACCJ kept"
it "a sheet made from a local transcript shows the placeholder where a command named the id"
mkdir -p "$TMPROOT/sheetsA" "$TMPROOT/labelsA"; out="$(cd "$REPO" && "$T" sheet --transcript "$TRA" --out "$TMPROOT/sheetsA" --labels "$TMPROOT/labelsA" 2>&1)"
sheet="$(cat "$TMPROOT/sheetsA"/*.md 2>/dev/null)"
lacks "$sheet" "$ORG"; has "$sheet" "synced/$MARK/x"
it "no archived fixture holds an account id: each has the placeholder under the key"
assert_eq "15 0" "$(python3 - "$here/../grade/fixtures" <<'PY'
import glob, gzip, re, sys
files = sorted(glob.glob(sys.argv[1] + "/**/*.jsonl.gz", recursive=True)); bad = 0
for f in files:
    vals = set(re.findall(r'\\*"(?:organizationUuid|accountUuid|userID)\\*"\s*:\s*\\*"([^"\\]*)', gzip.open(f, "rt", errors="replace").read()))
    bad += vals != {"<redacted:account-id>"}
print(len(files), bad)
PY
)"

echo "readable-store R3: store/probe checks the messages table with the hooks' key (record 2026-11-15-readable-store)"
PROBE="$here/../store/probe"
for c in P Q; do mkdir -p "$TMPROOT/config$c/agent-transcripts"; printf 'insert-key-made-up\n' > "$TMPROOT/config$c/agent-transcripts/insert-key"; done
printf '%s\n' "$READKEY" > "$TMPROOT/configP/agent-transcripts/read-key"; chmod 600 "$TMPROOT"/config[PQ]/agent-transcripts/*-key
standin probe
out="$(XDG_CONFIG_HOME="$TMPROOT/configP" AGENT_TRANSCRIPTS_URL="$URL" python3 "$PROBE" 2>&1)"; rc=$?
it "with both keys every check of the probe passes against the stand-in"
assert_eq 0 "$rc"; has "$out" " passed, 0 failed"
it "the checks of the new table are among them, each by name"
for c in "two rows in one request: stored" "the same request again: refused as a duplicate" "one new row and one stored row: refused as a duplicate" \
         "select messages: refused" "update a message: refused" "delete a message: refused" "select the transcript view: refused" \
         "one row in a request of at least 3,100,000 bytes: stored" "a text holding U+0000: refused" "a text holding a lone surrogate: refused" \
         "read key: the new row of the refused request is not there"; do has "$out" "ok   $c: HTTP"; done
it "the rows went as the probe says: the first request holds two, and one request is at least 3,100,000 bytes"
assert_eq "True True" "$(python3 - "$LOG" <<'PY2'
import json, sys
posts = [json.loads(l) for l in open(sys.argv[1])]
posts = [p["body"] for p in posts if p["method"] == "POST" and p["path"] == "/rest/v1/messages"]
print(isinstance(json.loads(posts[0]), list) and len(json.loads(posts[0])) == 2, max(len(b.encode()) for b in posts) >= 3100000)
PY2
)"
it "without the read key the probe says the read-back was not made, and exits 1"
out="$(XDG_CONFIG_HOME="$TMPROOT/configQ" AGENT_TRANSCRIPTS_URL="$URL" python3 "$PROBE" 2>&1)"; rc=$?
assert_eq 1 "$rc"; has "$out" "not made: no read key here"; lacks "$out" "FAIL"
it "against a store that keeps the new row of a refused request and takes a text PostgreSQL would not, the probe fails on each and exits 1"
standin loose --loose messages
out="$(XDG_CONFIG_HOME="$TMPROOT/configP" AGENT_TRANSCRIPTS_URL="$URL" python3 "$PROBE" 2>&1)"; rc=$?
assert_eq 1 "$rc"; has "$out" "FAIL read key: the new row of the refused request is not there: HTTP 200 but"
has "$out" "FAIL a text holding U+0000: refused: HTTP 201"; has "$out" "FAIL a text holding a lone surrogate: refused: HTTP 201"; has "$out" " 3 failed"
standin probe2
it "the stand-in answers for the new table as PostgreSQL answered the probe of the record: a duplicate among several rows stores none of them"
row() { printf '{"session_id":"standin-m","stream":"main","chunk_id":"%064d","shape":1,"line":%s,"block":0,"who":"user","kind":"text","text":"%s"}' 0 "$1" "$2"; }
post() { curl -s -o /dev/null -w '%{http_code}' -X POST -H 'Content-Type: application/json' -H "apikey: ${2:-insert-key-made-up}" --data-binary "$1" "$URL/rest/v1/messages"; }
get() { curl -s -H "apikey: $READKEY" "$URL/rest/v1/$1"; }
assert_eq "201 409 409" "$(post "[$(row 1 a),$(row 2 b)]") $(post "[$(row 1 a),$(row 2 b)]") $(post "[$(row 3 c),$(row 1 a)]")"
assert_eq "[1, 2]" "$(get 'messages?session_id=eq.standin-m&select=line&order=line' | python3 -c 'import json,sys; print([r["line"] for r in json.load(sys.stdin)])')"
it "and it refuses a text PostgreSQL cannot hold, and any reading with the hooks' key, of the table or of the view"
assert_eq "400 400 401 401" "$(post "$(row 4 'a\u0000b')") $(post "$(row 5 'a\ud800b')") $(curl -s -o /dev/null -w '%{http_code}' -H 'apikey: insert-key-made-up' "$URL/rest/v1/messages?select=line") $(curl -s -o /dev/null -w '%{http_code}' -H 'apikey: insert-key-made-up' "$URL/rest/v1/transcript?select=n")"
it "each with the code the real store gave the probe: 22P05 for U+0000, PGRST102 for half of a pair"
code() { curl -s -X POST -H 'Content-Type: application/json' -H 'apikey: insert-key-made-up' --data-binary "$1" "$URL/rest/v1/messages" | python3 -c 'import json,sys; print(json.load(sys.stdin)["code"])'; }
assert_eq "22P05 PGRST102" "$(code "$(row 6 'a\u0000b')") $(code "$(row 7 'a\ud800b')")"
assert_eq "2" "$(get 'transcript?session_id=eq.standin-m&select=line' | python3 -c 'import json,sys; print(len(json.load(sys.stdin)))')"

echo "readable-store R4: the rows of a chunk are read from its redacted lines by one rule (record 2026-11-15-readable-store)"
FIX="$here/../store/fixtures"
cat > "$TMPROOT/tool.py" <<'PY'
"""The tool's own functions, for a test: run CODE with `tr` bound to bin/transcripts loaded as a module."""
import importlib.machinery, importlib.util, json, sys  # noqa: E401,F401
sys.dont_write_bytecode = True
loader = importlib.machinery.SourceFileLoader("transcripts_tool", sys.argv[1])
tr = importlib.util.module_from_spec(importlib.util.spec_from_loader("transcripts_tool", loader))
loader.exec_module(tr)
exec(sys.argv[2])
PY
tool() { python3 "$TMPROOT/tool.py" "$T" "$@" 2>&1 | tail -4; }
it "the fixture named for the tool's shape gives its rows, compared whole"
assert_eq "1" "$(tool 'print(tr.SHAPE)')"
"$T" redact < "$FIX/shape-1.jsonl" > "$TMPROOT/shape-1.redacted" 2>/dev/null
assert_eq "16 rows, the same" "$(tool '
want = [json.loads(l) for l in open(sys.argv[3])]
got = tr.message_rows(open(sys.argv[4], "rb").read())
bad = [(w, g) for w, g in zip(want, got) if w != g]
print(f"{len(got)} rows, the same" if got == want else f"{len(got)} rows; the first that differs: {bad[:1]}")' "$FIX/shape-1.rows.jsonl" "$TMPROOT/shape-1.redacted")"
it "an address in a text is stored redacted: the rows are read after redaction"
rows="$(tool 'print(json.dumps(tr.message_rows(open(sys.argv[3], "rb").read())))' "$TMPROOT/shape-1.redacted")"
has "$rows" "Mail <redacted:email> about the plan."; lacks "$rows" "jane.doe@example.org"
it "a text whose form in a request would be over 3,000,000 bytes is cut to the longest beginning that is not, and its last line says how many characters are left in the chunk"
big() { tool '
n, ch = int(sys.argv[3]), sys.argv[4]
text = ch * n
row = tr.message_rows(json.dumps({"type": "user", "message": {"content": text}}).encode() + b"\n")[0]
got = row["text"]
if got == text:
    print("whole", len(json.dumps(got)))
else:
    head, _, note = got.rpartition("\n")
    left = n - len(head)
    longer = text[:len(head) + 1] + "\n" + note.replace(str(left), str(left - 1))
    print("cut", text.startswith(head), str(left) in note, len(json.dumps(got)) <= 3000000, len(json.dumps(longer)) > 3000000, len(head) > 0)' "$@"; }
assert_eq "cut True True True True True" "$(big 1600000 '"')"
it "the limit is in the bytes of the request and not in characters: 600,000 characters of 6 bytes each are cut, and 2,999,998 of one byte are not"
assert_eq "cut True True True True True" "$(big 600000 'é')"
assert_eq "whole 3000000" "$(big 2999998 a)"
assert_eq "cut True True True True True" "$(big 2999999 a)"
it "R5: a chunk's rows are cut into requests in order, each body at most 1,000,000 bytes, and a row that is more goes alone"
assert_eq "2 1 1 2 in order, none over" "$(tool '
rows = [{"line": i, "text": "x" * n} for i, n in enumerate([400000, 400000, 400000, 1200000, 10, 10], 1)]
reqs = tr.row_requests(rows)
size = lambda r: len(json.dumps(r, separators=(",", ":")).encode())
print(" ".join(str(len(r)) for r in reqs), "in order," if [x for r in reqs for x in r] == rows else "out of order,",
      "none over" if all(size(r) <= 1000000 or len(r) == 1 for r in reqs) else "one over")')"
assert_eq "1 2: 1000000 bytes and then the rest" "$(tool '
row = lambda n: {"t": "x" * n}
size = lambda r: len(json.dumps(r, separators=(",", ":")).encode())
a = row(1000000 - size([row(0)]))
reqs = tr.row_requests([a, row(1), row(2)])
print(" ".join(str(len(r)) for r in reqs) + ":", size(reqs[0]), "bytes and then the rest")')"
assert_eq "0" "$(tool 'print(len(tr.row_requests([])))')"
it "R5: two rows whose request is exactly 1,000,000 bytes go together, one byte more and they part, and a first row that is over gives no empty request"
assert_eq "2 | 1 1 | 1 1" "$(tool '
row = lambda n: {"t": "x" * n}
size = lambda r: len(json.dumps(r, separators=(",", ":")).encode())
fill = 1000000 - size([row(0), row(0)])
shape = lambda rows: " ".join(str(len(r)) for r in tr.row_requests(rows))
print(shape([row(fill - 5), row(5)]), "|", shape([row(fill - 5), row(6)]), "|", shape([row(1200000), row(1)]))')"
it "R4: a time is kept only when it names a moment: the form, a real date, and an offset a clock can have"
assert_eq "True True True True False False False False False False False" "$(tool '
ok = ["2026-11-15T10:00:00Z", "2026-11-15T10:00:00.5-08:00", "2026-11-15T23:59:59+15:59", "0001-01-01T00:00:00Z"]
no = ["2026-11-15T10:00:00", "2026-11-15 10:00:00Z", "2026-02-30T10:00:00Z", "2026-11-15T24:00:00Z", "2026-11-15T10:00:00+16:00",
      "2026-11-15T10:00:00+01:60", "0000-01-01T00:00:00Z"]
print(" ".join(str(tr.instant(s) is not None) for s in ok + no))')"
it "R6: two times are one moment whatever the offset or the fraction they are written with; an hour apart, or half a second, they are not"
assert_eq "True True False False True False" "$(tool '
print(tr.same_field("at", "2026-11-15T10:00:00.250Z", "2026-11-15T11:00:00.25+01:00"), tr.same_field("at", "2026-11-15T10:00:00.123456789Z", "2026-11-15T10:00:00.123457+00:00"),
      tr.same_field("at", "2026-11-15T10:00:00Z", "2026-11-15T10:00:00+01:00"), tr.same_field("at", None, "2026-11-15T10:00:00Z"), tr.same_field("at", None, None),
      tr.same_field("at", "2026-11-15T10:00:00.250Z", "2026-11-15T10:00:00.750Z"))')"
it "R6: a microsecond apart is still one moment, since the table rounds a longer fraction its own way, and two apart is not"
assert_eq "True False" "$(tool 'print(tr.same_field("at", "2026-11-15T10:00:00.123456Z", "2026-11-15T10:00:00.123457Z"), tr.same_field("at", "2026-11-15T10:00:00.123456Z", "2026-11-15T10:00:00.123458Z"))')"
it "R4: a line nested deeper than the reader goes gives no row and stops nothing: the next line's row is there"
assert_eq "2 the line after" "$(tool '
deep = b"[" * 200000 + b"]" * 200000
rows = tr.message_rows(deep + b"\n" + json.dumps({"type": "user", "message": {"content": "the line after"}}).encode() + b"\n")
print(" ".join(str(r["line"]) + " " + r["text"] for r in rows))')"

echo "readable-store R5: transcripts messages fills the table from what the store holds"
# filled NAME [stand-in options]: a new stand-in holding one session's chunks and no rows: main in two chunks,
# one subagent's stream, and one stream whose only line gives no row.
SUBN="$PROJ/$SID/subagents/agent-n0.jsonl"
filled() {
  standin "$@"; local ar="$TMPROOT/ar-$1"
  part1 > "$TR"; line 2026-11-01T10:01:00.000Z user '"sub '"$EMAIL"'"' > "$SUB"; line 2026-11-01T10:02:00.000Z system '"nothing to read"' > "$SUBN"
  (cd "$REPO" && AGENT_TRANSCRIPTS="$ar" "$T" archive --transcript "$TR" < /dev/null > /dev/null 2>&1
   AGENT_TRANSCRIPTS="$ar" AGENT_TRANSCRIPTS_URL="$URL" "$T" push > /dev/null 2>&1)
  part2 >> "$TR"
  (cd "$REPO" && AGENT_TRANSCRIPTS="$ar" "$T" archive --transcript "$TR" < /dev/null > /dev/null 2>&1
   AGENT_TRANSCRIPTS="$ar" AGENT_TRANSCRIPTS_URL="$URL" "$T" push > /dev/null 2>&1)
}
messages() { (cd "$REPO" && AGENT_TRANSCRIPTS_URL="$URL" "$T" messages "$@" 2>&1); }
get() { curl -s -H "apikey: $READKEY" "$URL/rest/v1/$1"; }
# stored: the rows the stand-in holds, a line each: stream, the chunk's place by its id, line, block, who, kind, text
stored() { get 'messages?select=*' | python3 -c '
import json, sys
for r in sorted(json.load(sys.stdin), key=lambda r: (r["stream"], r["chunk_id"], r["line"], r["block"])):
    print(r["stream"], r["line"], r["block"], r["who"], r["kind"], r["shape"], json.dumps(r["text"])[:60])'; }
posts() { python3 -c '
import json, sys
for l in open(sys.argv[1]):
    r = json.loads(l)
    if r["method"] == "POST" and r["path"] == "/rest/v1/messages":
        print(len(json.loads(r["body"])) if isinstance(json.loads(r["body"]), list) else "one", len(r["body"].encode()))' "$LOG"; }
# chunk_of STREAM N: the id of the stream's Nth chunk as the stand-in was sent it
chunk_of() { sent | python3 -c '
import json, sys
print([c["chunk_id"] for c in map(json.loads, sys.stdin) if c["stream"] == sys.argv[1]][int(sys.argv[2]) - 1])' "$1" "$2"; }
filled m1
it "without the read key it refuses before any request"
mv "$XDG_CONFIG_HOME/agent-transcripts/read-key" "$TMPROOT/rk"; before="$(wc -l < "$LOG")"
out="$(messages)"; rc=$?
assert_eq 2 "$rc"; has "$out" "read-key"; assert_eq "$before" "$(wc -l < "$LOG")"
mv "$TMPROOT/rk" "$XDG_CONFIG_HOME/agent-transcripts/read-key"
it "a store with chunks and no rows is filled: it says the chunks read, the rows inserted and the chunks that needed none"
out="$(messages)"; rc=$?
assert_eq 0 "$rc"; has "$out" "read 4 chunks of 1 session"; has "$out" "inserted 6 rows"; has "$out" "1 chunk needed none"
it "the rows are each line's texts, calls and results, in the chunk they were read from, under the tool's shape"
assert_eq "main 1 0 assistant text 1 main 1 0 user text 1 main 2 0 assistant call 1 main 2 0 user text 1 main 3 0 tool result 1 subagents/agent-a1 1 0 user text 1" \
  "$(stored | cut -d' ' -f1-6 | sort | tr '\n' ' ' | sed 's/ $//')"
it "what is stored is the redacted text: no secret or address of the fixture is in any row or request"
rows="$(get 'messages?select=*')"
for s in "${SECRETS[@]}"; do lacks "$rows" "$s"; lacks "$(cat "$LOG")" "$s"; done
has "$rows" "Mail <redacted:email> about it."; has "$rows" "Bearer <redacted:token>"
it "each chunk's rows went in one request, a list, and a chunk with no row sent none"
assert_eq "1 2 3" "$(posts | cut -d' ' -f1 | sort | tr '\n' ' ' | sed 's/ $//')"
it "a second run inserts nothing: every chunk needs none, the one whose lines give no row among them both times"
before="$(posts | wc -l | tr -d ' ')"; out="$(messages)"; rc=$?
assert_eq 0 "$rc"; has "$out" "inserted 0 rows"; has "$out" "4 chunks needed none"; assert_eq "$before" "$(posts | wc -l | tr -d ' ')"
it "an unknown argument is a usage error, and nothing is asked of the store"
before="$(wc -l < "$LOG")"; out="$(messages --all)"; rc=$?
assert_eq 2 "$rc"; has "$out" "usage: transcripts messages"; assert_eq "$before" "$(wc -l < "$LOG")"

filled m2
c1="$(chunk_of main 1)"
# plant CHUNK LINE TEXT [SHAPE] [AT, as JSON] [WHO]: a row of main put there by another hand, with the hooks' key
plant() { curl -s -o /dev/null -w '%{http_code}' -X POST -H 'Content-Type: application/json' -H 'apikey: insert-key-made-up' --data-binary \
  "[{\"session_id\":\"$SID\",\"stream\":\"main\",\"chunk_id\":\"$1\",\"shape\":${4:-1},\"line\":$2,\"block\":0,\"at\":${5:-null},\"who\":\"${6:-user}\",\"kind\":\"text\",\"tool\":null,\"call_id\":null,\"failed\":false,\"side\":false,\"text\":\"$3\"}]" "$URL/rest/v1/messages"; }
it "a chunk with one row already there gets the others, one at a time, and the row that was there is left as it was"
assert_eq 201 "$(plant "$c1" 2 "planted by another hand")"
out="$(messages)"; rc=$?
assert_eq 0 "$rc"; has "$out" "inserted 5 rows"
assert_eq "1 1 1 1 2" "$(posts | cut -d' ' -f1 | sort | tr '\n' ' ' | sed 's/ $//')"
has "$(stored)" 'main 2 0 user text 1 "planted by another hand"'
assert_eq "6" "$(stored | wc -l | tr -d ' ')"
it "a row under another shape does not count as there"
filled m3; c1="$(chunk_of main 1)"
assert_eq 201 "$(plant "$c1" 2 "another shape's row" 2)"
out="$(messages)"
has "$out" "inserted 6 rows"; assert_eq "7" "$(stored | wc -l | tr -d ' ')"
it "a chunk whose bytes do not match its id is named and left out, the others are filled, and the exit status is 1"
filled m4; c1="$(chunk_of main 1)"
python3 -c 'import json,sys,urllib.request; urllib.request.urlopen(urllib.request.Request(sys.argv[1]+"/__admin/tamper", data=json.dumps({"chunk_id":sys.argv[2]}).encode(), method="POST"))' "$URL" "$c1"
out="$(messages)"; rc=$?
assert_eq 1 "$rc"; has "$out" "chunk ${c1:0:12} does not match its chain id"; has "$out" "1 chunk left out"; has "$out" "inserted 3 rows"
has "$out" ", 1 chunk needed none"
assert_eq "3" "$(stored | wc -l | tr -d ' ')"
it "a chunk the store will not take rows for is named with the store's answer, and the exit status is 1"
filled m5 --refuse messages
out="$(messages)"; rc=$?
assert_eq 1 "$rc"; has "$out" "chunk $(chunk_of main 1 | cut -c1-12) could not be filled: messages insert answered 503"
has "$out" "3 chunks could not be filled"; has "$out" "inserted 0 rows"
it "rows that went in one at a time before the store refused the next are counted: the summary says what is there"
filled m12 --refuse-line 3; c1="$(chunk_of main 1)"
plant "$c1" 1 "there already" > /dev/null
out="$(messages)"; rc=$?
assert_eq 1 "$rc"; has "$out" "chunk ${c1:0:12} could not be filled: messages insert answered 503"
has "$out" "inserted 4 rows"; has "$out" "1 chunk could not be filled"; assert_eq "5" "$(stored | wc -l | tr -d ' ')"
it "with --session only that session's chunks are read"
filled m6
SIDM=60000000-2222-3333-4444-555555555555
line 2026-11-03T10:00:00.000Z user '"another session"' | sed "s/$SID/$SIDM/" > "$PROJ/$SIDM.jsonl"
(cd "$REPO" && AGENT_TRANSCRIPTS="$TMPROOT/ar-m6b" "$T" archive --transcript "$PROJ/$SIDM.jsonl" < /dev/null > /dev/null 2>&1
 AGENT_TRANSCRIPTS="$TMPROOT/ar-m6b" AGENT_TRANSCRIPTS_URL="$URL" "$T" push > /dev/null 2>&1)
out="$(messages --session "$SIDM")"; rc=$?
assert_eq 0 "$rc"; has "$out" "read 1 chunk of 1 session"; has "$out" "inserted 1 row"
assert_eq "1" "$(stored | wc -l | tr -d ' ')"
out="$(messages)"
has "$out" "read 5 chunks of 2 sessions"; has "$out" "inserted 6 rows"; has "$out" "2 chunks needed none"
it "a chunk whose rows are over 1,000,000 bytes goes in several requests, each a list and none over, and all its rows are there"
standin m7
SIDL=70000000-2222-3333-4444-555555555555
for i in $(seq 30); do line "2026-11-04T10:00:$(printf %02d "$i").000Z" user "\"$(printf 'row %02d ' "$i")$(head -c 50000 /dev/zero | tr '\0' x)\""; done | sed "s/$SID/$SIDL/" > "$PROJ/$SIDL.jsonl"
(cd "$REPO" && AGENT_TRANSCRIPTS="$TMPROOT/ar-m7" "$T" archive --transcript "$PROJ/$SIDL.jsonl" < /dev/null > /dev/null 2>&1
 AGENT_TRANSCRIPTS="$TMPROOT/ar-m7" AGENT_TRANSCRIPTS_URL="$URL" "$T" push > /dev/null 2>&1)
out="$(messages)"; rc=$?
assert_eq 0 "$rc"; has "$out" "inserted 30 rows"
assert_eq "19 11 True" "$(posts | python3 -c '
import sys
p = [l.split() for l in sys.stdin]
print(" ".join(x[0] for x in p), all(int(x[1]) <= 1000000 for x in p))')"
assert_eq "30" "$(stored | wc -l | tr -d ' ')"

it "a chunk whose data cannot be opened at all is left out like one that does not match, and the others are filled"
filled m8
for d in '@@@' 'aGVsbG8='; do curl -s -o /dev/null -X POST -H 'Content-Type: application/json' -H 'apikey: insert-key-made-up' --data-binary \
  "{\"session_id\":\"$SID\",\"stream\":\"main\",\"chunk_id\":\"$(printf '%s' "$d" | shasum -a 256 | cut -c1-64)\",\"start_id\":\"x\",\"data\":\"$d\"}" "$URL/rest/v1/chunks"; done
out="$(messages)"; rc=$?
assert_eq 1 "$rc"; has "$out" "2 chunks left out"; has "$out" "inserted 6 rows"; lacks "$out" "Traceback"
it "a row written by another hand between the reading and the insert: the request is refused whole, and its rows then go one at a time"
filled m9; c1="$(chunk_of main 1)"
curl -s -o /dev/null -X POST --data-binary "{\"rows\":[{\"session_id\":\"$SID\",\"stream\":\"main\",\"chunk_id\":\"$c1\",\"shape\":1,\"line\":2,\"block\":0,\"who\":\"user\",\"kind\":\"text\",\"text\":\"written meanwhile\"}]}" "$URL/__admin/after-read"
out="$(messages)"; rc=$?
assert_eq 0 "$rc"; has "$out" "inserted 5 rows"; assert_eq "6" "$(stored | wc -l | tr -d ' ')"
assert_eq "1 1 1 1 2 3" "$(posts | cut -d' ' -f1 | sort | tr '\n' ' ' | sed 's/ $//')"
it "where the store has no such table yet it says to run schema.sql, sends nothing, and exits 1"
filled m10 --without messages
: > "$LOG"; out="$(messages)"; rc=$?
assert_eq 1 "$rc"; has "$out" "run plugins/change-record/store/schema.sql"; assert_eq "GET" "$(methods)"; assert_eq "1" "$(wc -l < "$LOG" | tr -d ' ')"
out="$(messages --check)"; rc=$?
assert_eq 1 "$rc"; has "$out" "run plugins/change-record/store/schema.sql"
it "with no store named, or one that cannot be reached, it says so: exit 2 and exit 1"
out="$(cd "$REPO" && "$T" messages 2>&1)"; rc=$?
assert_eq 2 "$rc"; has "$out" "AGENT_TRANSCRIPTS_URL"
out="$(cd "$REPO" && AGENT_TRANSCRIPTS_URL="http://127.0.0.1:1" "$T" messages 2>&1)"; rc=$?
assert_eq 1 "$rc"; has "$out" "cannot reach"; lacks "$out" "Traceback"

it "the rows store/probe leaves behind are passed over and said: its chunk is no transcript's, and it fails neither the fill nor the check"
filled m11
XDG_CONFIG_HOME="$TMPROOT/configP" AGENT_TRANSCRIPTS_URL="$URL" python3 "$here/../store/probe" > /dev/null 2>&1
out="$(messages)"; rc=$?
assert_eq 0 "$rc"; has "$out" "read 4 chunks of 1 session"; has "$out" "inserted 6 rows"; has "$out" "1 chunk of store/probe's passed over"
out="$(messages --check)"; rc=$?
assert_eq 0 "$rc"; has "$out" "4 chunks, 6 rows, each as its chunk gives it, 1 chunk of store/probe's passed over"
it "only the probe's own chunk is passed over: another chunk in a session named like the probe's is read, and left out if it is not what its id says"
curl -s -o /dev/null -X POST -H 'Content-Type: application/json' -H 'apikey: insert-key-made-up' --data-binary \
  "{\"session_id\":\"probe-0000\",\"stream\":\"main\",\"chunk_id\":\"$(printf x | shasum -a 256 | cut -c1-64)\",\"start_id\":\"$(printf y | shasum -a 256 | cut -c1-64)\",\"sender\":\"probe\",\"data\":\"first\"}" "$URL/rest/v1/chunks"
curl -s -o /dev/null -X POST -H 'Content-Type: application/json' -H 'apikey: insert-key-made-up' --data-binary \
  "{\"session_id\":\"probe-0001\",\"stream\":\"main\",\"chunk_id\":\"$(printf z | shasum -a 256 | cut -c1-64)\",\"start_id\":\"$(printf %064d 0)\",\"sender\":\"machine-A\",\"data\":\"first\"}" "$URL/rest/v1/chunks"
curl -s -o /dev/null -X POST -H 'Content-Type: application/json' -H 'apikey: insert-key-made-up' --data-binary \
  "{\"session_id\":\"not-the-probe\",\"stream\":\"main\",\"chunk_id\":\"$(printf w | shasum -a 256 | cut -c1-64)\",\"start_id\":\"$(printf %064d 0)\",\"sender\":\"probe\",\"data\":\"first\"}" "$URL/rest/v1/chunks"
out="$(messages)"; rc=$?
assert_eq 1 "$rc"; has "$out" "3 chunks left out"; has "$out" "1 chunk of store/probe's passed over"

echo "readable-store R6: transcripts messages --check compares the table with the chunks and changes nothing"
filled k1; messages > /dev/null
it "a filled store is clean, and the check sends nothing but reads"
: > "$LOG"; out="$(messages --check)"; rc=$?
assert_eq 0 "$rc"; has "$out" "4 chunks, 6 rows, each as its chunk gives it"; assert_eq "GET" "$(methods)"
it "a row planted before the fill under a key the chunk does not give, and one planted under a key it does with another text, are each reported"
filled k2; c1="$(chunk_of main 1)"; c2="$(chunk_of main 2)"
plant "$c1" 9 "no line 9 in this chunk" > /dev/null; plant "$c2" 1 "another text" 1 '"2026-11-01T10:05:00.000Z"' assistant > /dev/null
messages > /dev/null
: > "$LOG"; out="$(messages --check)"; rc=$?
assert_eq 1 "$rc"
has "$out" "not the chunk's: $SID main chunk ${c1:0:12} line 9 block 0"
has "$out" "differs (text): $SID main chunk ${c2:0:12} line 1 block 0"
has "$out" "1 row that is not its chunk's"; has "$out" "1 row that differs"; lacks "$out" "missing"
assert_eq "GET" "$(methods)"
it "a row that differs in a field and not in its text is reported with the field's name"
filled k3; c1="$(chunk_of main 1)"; c2="$(chunk_of main 2)"
plant "$c1" 1 'Mail <redacted:email> about it.\nUse token <redacted:github-token>' 1 '"2026-11-01T10:00:01.000Z"' context > /dev/null
it "and the same moment written another way is no difference"
plant "$c2" 2 'plain line with nothing to hide' 1 '"2026-11-01T11:09:00+01:00"' > /dev/null
messages > /dev/null; out="$(messages --check)"; rc=$?
assert_eq 1 "$rc"; has "$out" "differs (at, who): $SID main chunk ${c1:0:12} line 1 block 0"
has "$out" "1 row that differs"; lacks "$out" "chunk ${c2:0:12}"
it "a row left out is reported as missing, the check does not put it there, and the command then does, alone"
filled k4; c2="$(chunk_of main 2)"; messages > /dev/null
curl -s -o /dev/null -X POST --data-binary "{\"table\":\"messages\",\"match\":{\"chunk_id\":\"$c2\",\"line\":2}}" "$URL/__admin/forget"
assert_eq "5" "$(stored | wc -l | tr -d ' ')"
out="$(messages --check)"; rc=$?
assert_eq 1 "$rc"; has "$out" "missing: $SID main chunk ${c2:0:12} line 2 block 0"; has "$out" "1 row missing"
assert_eq "5" "$(stored | wc -l | tr -d ' ')"
: > "$LOG"; out="$(messages)"; rc=$?
assert_eq 0 "$rc"; has "$out" "inserted 1 row"; assert_eq "1" "$(posts | cut -d' ' -f1 | tr '\n' ' ' | sed 's/ $//')"
out="$(messages --check)"; rc=$?; assert_eq 0 "$rc"
it "a chunk whose bytes do not match its id is named by the check too, and the exit status is 1"
python3 -c 'import json,sys,urllib.request; urllib.request.urlopen(urllib.request.Request(sys.argv[1]+"/__admin/tamper", data=json.dumps({"chunk_id":sys.argv[2]}).encode(), method="POST"))' "$URL" "$c2"
out="$(messages --check)"; rc=$?
assert_eq 1 "$rc"; has "$out" "chunk ${c2:0:12} does not match its chain id"; has "$out" "1 chunk left out"
lacks "$out" "not the chunk's"; has "$out" "messages --check: 4 chunks, 4 rows, each as its chunk gives it, 1 chunk left out"
it "a row whose chunk the store does not hold is reported too, by its chunk and with how many, whatever its shape"
filled k6; messages > /dev/null
ghost="$(printf ghost | shasum -a 256 | cut -c1-64)"
plant "$ghost" 1 "a row with no chunk behind it" > /dev/null; plant "$ghost" 2 "and another" > /dev/null; plant "$ghost" 3 "of another shape" 7 > /dev/null
: > "$LOG"; out="$(messages --check)"; rc=$?
assert_eq 1 "$rc"; has "$out" "no such chunk: $SID main chunk ${ghost:0:12}: 3 rows"
has "$out" "messages --check: 4 chunks; 3 rows whose chunk the store does not hold"; assert_eq "GET" "$(methods)"
out="$(messages)"; rc=$?   # the fill has nothing to say of them: it cannot take a row out
assert_eq 0 "$rc"; lacks "$out" "no such chunk"
it "with --session only that session's rows are looked at, and a store with rows and no chunk at all is not clean"
out="$(messages --check --session "no-such-session")"; rc=$?
assert_eq 0 "$rc"; lacks "$out" "no such chunk"
standin k7; plant "$ghost" 1 "nothing behind it" > /dev/null
out="$(messages --check)"; rc=$?
assert_eq 1 "$rc"; has "$out" "no such chunk: $SID main chunk ${ghost:0:12}: 1 row"; has "$out" "0 chunks; 1 row whose chunk the store does not hold"
it "the rows store/probe leaves are under its own chunk, which the store holds: they are not reported"
XDG_CONFIG_HOME="$TMPROOT/configP" AGENT_TRANSCRIPTS_URL="$URL" python3 "$here/../store/probe" > /dev/null 2>&1
out="$(messages --check)"
has "$out" "0 chunks; 1 row whose chunk the store does not hold, 1 chunk of store/probe's passed over"; assert_eq 1 "$(printf '%s\n' "$out" | grep -c 'no such chunk')"
it "without the read key the check refuses too"
mv "$XDG_CONFIG_HOME/agent-transcripts/read-key" "$TMPROOT/rk"
out="$(messages --check)"; rc=$?
assert_eq 2 "$rc"; has "$out" "read-key"
mv "$TMPROOT/rk" "$XDG_CONFIG_HOME/agent-transcripts/read-key"

echo "passed=$pass failed=$fail"; [ "$fail" -eq 0 ]
