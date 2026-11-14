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
assert_eq "same 30012" "$(python3 - "$T" <<'PY'
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
same = sum(tr.redact_emails(t) == plain.sub("<redacted:email>", t) for t in cases)
print("same" if same == len(cases) else "differ", same)
PY
)"
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

echo "passed=$pass failed=$fail"; [ "$fail" -eq 0 ]
