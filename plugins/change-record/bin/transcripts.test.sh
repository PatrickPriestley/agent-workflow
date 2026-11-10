#!/usr/bin/env bash
# Tests for transcripts archive and import: a fake ~/.claude with a growing session transcript
# and a subagent transcript, a git repository the session ran in, and an archive in a scratch
# directory. Needs bash, git and python3.
set -u
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
T="$here/transcripts"
TMPROOT="$(mktemp -d)"; trap 'rm -rf "$TMPROOT"' EXIT
pass=0; fail=0; CURRENT=""
it() { CURRENT="$1"; }
ok()  { pass=$((pass+1)); printf '  ok   %s\n' "$CURRENT"; }
bad() { fail=$((fail+1)); printf '  FAIL %s\n       %s\n' "$CURRENT" "$1"; }
assert_eq()  { [ "$1" = "$2" ] && ok || bad "expected [$1] got [$2]"; }
has()  { printf '%s' "$1" | grep -qF -- "$2" && ok || bad "missing [$2] in: $(printf '%s' "$1" | head -c 700)"; }
lacks() { printf '%s' "$1" | grep -qF -- "$2" && bad "unexpected [$2] in: $(printf '%s' "$1" | head -c 700)" || ok; }
json() { python3 -c 'import json,sys; d=json.load(open(sys.argv[1])); print(eval(sys.argv[2], {"d": d}))' "$@" 2>&1; }

# Isolate the machine: no cloud variables, a config dir holding a known machine id.
unset CLAUDE_CODE_REMOTE CLAUDE_CODE_REMOTE_SESSION_ID CLAUDE_CODE_CONTAINER_ID AGENT_TRANSCRIPTS AGENT_TRANSCRIPTS_PARENT AGENT_TRANSCRIPTS_URL
export XDG_CONFIG_HOME="$TMPROOT/config"
mkdir -p "$XDG_CONFIG_HOME/agent-transcripts"; printf 'machine-0001\n' > "$XDG_CONFIG_HOME/agent-transcripts/machine-id"

# repo DIR URL: a git repository with origin URL, a plugin skill file, one commit on branch work.
repo() {
  mkdir -p "$1/plugins/change-record/skills/change"; (
    cd "$1" && git init -q -b work && git config user.email t@example.com && git config user.name t
    git config core.hooksPath /dev/null
    printf -- '---\nname: change\n---\n# Change\n' > plugins/change-record/skills/change/SKILL.md
    git add -A && git commit -qm "feat: base" && git remote add origin "$2" )
}
REPO="$TMPROOT/checkout"; repo "$REPO" "git@github.com:Owner/Repo.git"
COMMIT="$(git -C "$REPO" rev-parse HEAD)"
BLOB="$(git -C "$REPO" hash-object plugins/change-record/skills/change/SKILL.md)"
SID=11111111-2222-3333-4444-555555555555
HOMEC="$TMPROOT/claude"; PROJ="$HOMEC/projects/-checkout"; mkdir -p "$PROJ/$SID/subagents"
TR="$PROJ/$SID.jsonl"; SUB="$PROJ/$SID/subagents/agent-a0123456789abcdef.jsonl"

# line TS JSON-REST: one transcript line for session SID in REPO.
line() { printf '{"sessionId":"%s","timestamp":"%s","cwd":"%s","gitBranch":"work","version":"2.1.321","entrypoint":"cli",%s}\n' "$SID" "$1" "$REPO" "$2"; }
part1() {
  printf '{"type":"queue-operation","sessionId":"%s"}\n' "$SID"
  line 2026-11-01T10:00:00.000Z '"type":"user","message":{"role":"user","content":"Build task 1 of docs/changes/2026-11-01-other.md"}'
  line 2026-11-01T10:00:05.000Z '"type":"assistant","message":{"role":"assistant","content":[{"type":"tool_use","id":"t1","name":"Skill","input":{"skill":"change-record:change"}}]}'
}
part2() {
  line 2026-11-01T10:05:00.000Z '"type":"assistant","message":{"role":"assistant","content":[{"type":"tool_use","id":"t2","name":"Edit","input":{"file_path":"'"$REPO"'/docs/changes/2026-11-01-x.md","old_string":"a","new_string":"b"}}]}'
  line 2026-11-01T10:09:00.000Z '"type":"assistant","message":{"role":"assistant","content":[{"type":"text","text":"Change: docs/changes/2026-11-01-x.md\n\nDone."}]}'
}
hook() { printf '{"session_id":"%s","transcript_path":"%s","cwd":"%s","hook_event_name":"%s"}' "$SID" "$TR" "$REPO" "${1:-Stop}"; }
umask 022   # a common default, under which files would be readable by other users
AR="$TMPROOT/archive"
archive() { (cd "$REPO" && AGENT_TRANSCRIPTS="$AR" "$T" archive "$@" 2>&1); }
parts() { find "$AR/parts/$SID" -type f -name '*.jsonl' 2>/dev/null | sed "s|$AR/parts/$SID/||" | sort | tr '\n' ' '; }

echo "R1: new lines, and subagent transcripts, are added to the archive at each stop"
part1 > "$TR"
it "the first stop archives the transcript's lines as part 1 and writes one index entry"
out="$(hook Stop | archive)"; rc=$?
assert_eq 0 "$rc"; assert_eq "main/g1-000001.jsonl " "$(parts)"
assert_eq "$(cat "$TR")" "$(cat "$AR/parts/$SID/main/g1-000001.jsonl" 2>&1)"
assert_eq "$SID.json" "$(ls "$AR/sessions" 2>&1)"
it "the second stop adds only the new lines, plus the subagent's, and keeps one index entry"
part2 >> "$TR"; line 2026-11-01T10:06:00.000Z '"type":"user","isSidechain":true,"message":{"role":"user","content":"sub"}' > "$SUB"
printf '{"partial":' >> "$TR"   # a line still being written is left for the next stop
out="$(hook SessionEnd | archive)"; rc=$?
assert_eq 0 "$rc"
assert_eq "main/g1-000001.jsonl main/g1-000002.jsonl subagents/agent-a0123456789abcdef/g1-000001.jsonl " "$(parts)"
assert_eq "$(part2)" "$(cat "$AR/parts/$SID/main/g1-000002.jsonl" 2>&1)"
assert_eq "$SID.json" "$(ls "$AR/sessions" 2>&1)"
assert_eq "5" "$(json "$AR/sessions/$SID.json" 'd["streams"]["main"]["lines"]')"
it "a stop with no new complete lines adds no part"
out="$(hook Stop | archive)"
assert_eq "main/g1-000001.jsonl main/g1-000002.jsonl subagents/agent-a0123456789abcdef/g1-000001.jsonl " "$(parts)"
it "--transcript PATH archives without hook JSON, and the parts join back into the transcript"
{ part1; part2; } > "$TR"   # the partial line is dropped
out="$(archive --transcript "$TR" < /dev/null)"; rc=$?
assert_eq 0 "$rc"; assert_eq "$(cat "$TR")" "$(cat "$AR/parts/$SID/main/"g1-*.jsonl)"
it "a transcript that is no longer an extension of what was archived starts generation 2"
cp -r "$AR" "$TMPROOT/archive-before-rewrite"
{ part1; line 2026-11-01T10:07:00.000Z '"type":"user","message":{"role":"user","content":"rewritten"}'; } > "$TMPROOT/rewritten.jsonl"
cp "$TR" "$TMPROOT/tr.keep"; cp "$TMPROOT/rewritten.jsonl" "$TR"
out="$(hook Stop | archive)"
has "$(parts)" "main/g2-000001.jsonl"; assert_eq "2" "$(json "$AR/sessions/$SID.json" 'd["streams"]["main"]["generation"]')"
assert_eq "$(cat "$TR")" "$(cat "$AR/parts/$SID/main/g2-000001.jsonl" 2>&1)"
rm -rf "$AR"; mv "$TMPROOT/archive-before-rewrite" "$AR"; cp "$TMPROOT/tr.keep" "$TR"
it "a transcript cut to less than one whole line, then grown again, is still archived as generation 2"
cp -r "$AR" "$TMPROOT/archive-before-cut"; cp "$TR" "$TMPROOT/tr.keep"
printf '{"partial":' > "$TR"; out="$(hook Stop | archive)"
cp "$TMPROOT/rewritten.jsonl" "$TR"; out="$(hook Stop | archive)"
lacks "$out" "nothing archived"; has "$(parts)" "main/g2-000001.jsonl"
assert_eq "$(cat "$TR")" "$(cat "$AR/parts/$SID/main/g2-000001.jsonl" 2>&1)"
rm -rf "$AR"; mv "$TMPROOT/archive-before-cut" "$AR"; cp "$TMPROOT/tr.keep" "$TR"
it "the archive's folders and files are open to their owner only, as Claude Code keeps the transcripts"
assert_eq "" "$(find "$AR" -perm /077 2>&1 | sed "s|$AR|AR|")"

echo "R3: the index entry"
it "the entry for the fixture session matches the stored one"
cat > "$TMPROOT/expected.json" <<EOF
{
  "schema": 1,
  "session_id": "$SID",
  "source": "local",
  "machine": {"id": "machine-0001", "cloud_container": null, "cloud_session": null},
  "repository": "github.com/owner/repo",
  "first_stop": {"branch": "work", "commit": "$COMMIT"},
  "last_stop": {"branch": "work", "commit": "$COMMIT"},
  "first_timestamp": "2026-11-01T10:00:00.000Z",
  "last_timestamp": "2026-11-01T10:09:00.000Z",
  "skills": [{"name": "change-record:change", "how": "Skill", "file": "plugins/change-record/skills/change/SKILL.md", "blob": "$BLOB"}],
  "records": {"written": ["docs/changes/2026-11-01-x.md"], "change_line": ["docs/changes/2026-11-01-x.md"]},
  "record": "docs/changes/2026-11-01-x.md",
  "parent_session": null,
  "redaction_version": null,
  "sent": {}
}
EOF
diff="$(python3 - "$TMPROOT/expected.json" "$AR/sessions/$SID.json" <<'PY' 2>&1
import json, sys
want = json.load(open(sys.argv[1])); got = json.load(open(sys.argv[2]))
got.pop("streams", None)
for k in sorted(set(want) | set(got)):
    if want.get(k, "<absent>") != got.get(k, "<absent>"):
        print(f"{k}: want {want.get(k, '<absent>')!r} got {got.get(k, '<absent>')!r}")
PY
)"
assert_eq "" "$diff"
it "each stream in the entry says how many lines and bytes are archived and their sha256"
assert_eq "$(python3 -c 'import hashlib,sys; print(hashlib.sha256(open(sys.argv[1],"rb").read()).hexdigest())' "$TR")" \
  "$(json "$AR/sessions/$SID.json" 'd["streams"]["main"]["sha256"]')"
assert_eq "1" "$(json "$AR/sessions/$SID.json" 'd["streams"]["subagents/agent-a0123456789abcdef"]["lines"]')"
it "a commit after the first stop moves last_stop and keeps first_stop"
(cd "$REPO" && git commit -q --allow-empty -m "feat: more")
line 2026-11-01T10:10:00.000Z '"type":"user","message":{"role":"user","content":"more"}' >> "$TR"
hook Stop | archive > /dev/null
assert_eq "$COMMIT $(git -C "$REPO" rev-parse HEAD)" "$(json "$AR/sessions/$SID.json" 'd["first_stop"]["commit"]+" "+d["last_stop"]["commit"]')"
assert_eq "2026-11-01T10:10:00.000Z" "$(json "$AR/sessions/$SID.json" 'd["last_timestamp"]')"
it "a session that writes one record but names another on its Change: line is tied to neither"
SID2=22222222-2222-3333-4444-555555555555; TR2="$PROJ/$SID2.jsonl"
{ line 2026-11-01T11:00:00.000Z '"type":"assistant","message":{"role":"assistant","content":[{"type":"tool_use","id":"w","name":"Write","input":{"file_path":"docs/changes/2026-11-01-a.md","content":"x"}}]}'
  line 2026-11-01T11:01:00.000Z '"type":"assistant","message":{"role":"assistant","content":[{"type":"text","text":"Change: docs/changes/2026-11-01-b.md"}]}'
  line 2026-11-01T11:02:00.000Z '"type":"user","message":{"role":"user","content":[{"type":"tool_result","tool_use_id":"r","content":"Change: docs/changes/2026-11-01-c.md"}]}'
  line 2026-11-01T11:03:00.000Z '"type":"user","message":{"role":"user","content":[{"type":"text","text":"End with this line:\n\nChange: docs/changes/2026-11-01-d.md"}]}'
} | sed "s/$SID/$SID2/" > "$TR2"
archive --transcript "$TR2" > /dev/null
assert_eq "None ['docs/changes/2026-11-01-b.md']" "$(json "$AR/sessions/$SID2.json" 'str(d["record"])+" "+str(d["records"]["change_line"])')"
it "a dispatch child records its parent and source; its own id as parent is ignored"
SID3=33333333-2222-3333-4444-555555555555; TR3="$PROJ/$SID3.jsonl"; part1 | sed "s/$SID/$SID3/" > "$TR3"
(cd "$REPO" && AGENT_TRANSCRIPTS="$AR" AGENT_TRANSCRIPTS_PARENT=parent-9 "$T" archive --transcript "$TR3" < /dev/null)
assert_eq "dispatch parent-9" "$(json "$AR/sessions/$SID3.json" 'd["source"]+" "+d["parent_session"]')"
(cd "$REPO" && AGENT_TRANSCRIPTS="$AR" "$T" archive --transcript "$TR3" < /dev/null)
assert_eq "dispatch parent-9" "$(json "$AR/sessions/$SID3.json" 'd["source"]+" "+d["parent_session"]')"
SID4=44444444-2222-3333-4444-555555555555; TR4="$PROJ/$SID4.jsonl"; part1 | sed "s/$SID/$SID4/" > "$TR4"
(cd "$REPO" && AGENT_TRANSCRIPTS="$AR" AGENT_TRANSCRIPTS_PARENT=$SID4 "$T" archive --transcript "$TR4" < /dev/null)
assert_eq "local None" "$(json "$AR/sessions/$SID4.json" 'd["source"]+" "+str(d["parent_session"])')"
it "a cloud session records the container and cloud session, not a machine id"
SID5=55555555-2222-3333-4444-555555555555; TR5="$PROJ/$SID5.jsonl"; part1 | sed "s/$SID/$SID5/" > "$TR5"
(cd "$REPO" && AGENT_TRANSCRIPTS="$AR" CLAUDE_CODE_REMOTE=true CLAUDE_CODE_CONTAINER_ID=container_x CLAUDE_CODE_REMOTE_SESSION_ID=cse_y "$T" archive --transcript "$TR5" < /dev/null)
assert_eq "cloud {'id': None, 'cloud_container': 'container_x', 'cloud_session': 'cse_y'}" "$(json "$AR/sessions/$SID5.json" 'd["source"]+" "+str(d["machine"])')"
it "remote URLs of the same repository normalise to one name"
for u in https://github.com/Owner/Repo https://user:tok@github.com/owner/repo.git/ ssh://git@github.com/Owner/Repo.git http://local_proxy@127.0.0.1:41245/git/Owner/Repo; do
  git -C "$REPO" remote set-url origin "$u"; rm -f "$AR/sessions/$SID5.json"
  (cd "$REPO" && AGENT_TRANSCRIPTS="$AR" "$T" archive --transcript "$TR5" < /dev/null)
  assert_eq "github.com/owner/repo" "$(json "$AR/sessions/$SID5.json" 'd["repository"]')"
done
git -C "$REPO" remote set-url origin "git@github.com:Owner/Repo.git"
it "a machine without a machine id gets a random one, written once"
rm -rf "$TMPROOT/config2"; SID6=66666666-2222-3333-4444-555555555555; TR6="$PROJ/$SID6.jsonl"; part1 | sed "s/$SID/$SID6/" > "$TR6"
(cd "$REPO" && XDG_CONFIG_HOME="$TMPROOT/config2" AGENT_TRANSCRIPTS="$AR" "$T" archive --transcript "$TR6" < /dev/null)
mid="$(cat "$TMPROOT/config2/agent-transcripts/machine-id" 2>&1)"
assert_eq "$mid" "$(json "$AR/sessions/$SID6.json" 'd["machine"]["id"]')"
(cd "$REPO" && XDG_CONFIG_HOME="$TMPROOT/config2" AGENT_TRANSCRIPTS="$AR" "$T" archive --transcript "$TR6" < /dev/null)
assert_eq "$mid" "$(cat "$TMPROOT/config2/agent-transcripts/machine-id")"
[ "${#mid}" -ge 16 ] && ok || bad "machine id [$mid] is shorter than 16 characters"

echo "R2: opt-in, and never blocks a session"
it "with AGENT_TRANSCRIPTS unset the hook does nothing and exits 0"
out="$(hook Stop | (cd "$REPO" && "$T" archive 2>&1))"; rc=$?
assert_eq 0 "$rc"; assert_eq "" "$out"
it "an unwritable archive exits 0 with a message, and the next stop archives everything"
printf 'x' > "$TMPROOT/afile"; BAD="$TMPROOT/afile/archive"
out="$(hook Stop | (cd "$REPO" && AGENT_TRANSCRIPTS="$BAD" "$T" archive 2>&1))"; rc=$?
assert_eq 0 "$rc"; has "$out" "transcripts:"; has "$out" "next stop"
AR2="$TMPROOT/archive2"
out="$(hook Stop | (cd "$REPO" && AGENT_TRANSCRIPTS="$AR2" "$T" archive 2>&1))"; rc=$?
assert_eq 0 "$rc"; assert_eq "$(cat "$TR")" "$(cat "$AR2/parts/$SID/main/"g1-*.jsonl 2>&1)"
it "bad hook JSON exits 0 with a message"
out="$(printf 'not json' | (cd "$REPO" && AGENT_TRANSCRIPTS="$AR" "$T" archive 2>&1))"; rc=$?
assert_eq 0 "$rc"; has "$out" "transcripts:"
it "a transcript_path that does not exist exits 0 with a message"
out="$(printf '{"session_id":"x","transcript_path":"%s/nope.jsonl","cwd":"%s"}' "$TMPROOT" "$REPO" | (cd "$REPO" && AGENT_TRANSCRIPTS="$AR" "$T" archive 2>&1))"; rc=$?
assert_eq 0 "$rc"; has "$out" "nope.jsonl"
it "an archive inside a repository's working tree is refused, and nothing is written there"
out="$(hook Stop | (cd "$REPO" && AGENT_TRANSCRIPTS="$REPO/transcripts" "$T" archive 2>&1))"; rc=$?
assert_eq 0 "$rc"; has "$out" "working tree"; [ -e "$REPO/transcripts" ] && bad "$REPO/transcripts was created" || ok
it "a held lock exits 0 at once and leaves the lines for the next stop"
AR3="$TMPROOT/archive3"; mkdir -p "$AR3/locks/$SID"
out="$(hook Stop | (cd "$REPO" && AGENT_TRANSCRIPTS="$AR3" "$T" archive 2>&1))"; rc=$?
assert_eq 0 "$rc"; has "$out" "next stop"; [ -e "$AR3/sessions/$SID.json" ] && bad "archived while locked" || ok

it "a lock left by a run that died over a minute ago is taken over"
python3 -c 'import os,sys; os.utime(sys.argv[1], (0, 0))' "$AR3/locks/$SID"
out="$(hook Stop | (cd "$REPO" && AGENT_TRANSCRIPTS="$AR3" "$T" archive 2>&1))"; rc=$?
assert_eq 0 "$rc"; [ -e "$AR3/sessions/$SID.json" ] && ok || bad "not archived after a stale lock: $out"
it "a session id that is not a plain name is refused, and nothing is written outside the archive"
printf '{"sessionId":"../escape","cwd":"%s"}\n' "$REPO" > "$TMPROOT/esc.jsonl"
out="$(cd "$REPO" && AGENT_TRANSCRIPTS="$AR3" "$T" archive --transcript "$TMPROOT/esc.jsonl" 2>&1 < /dev/null)"; rc=$?
assert_eq 0 "$rc"; has "$out" "not a plain name"; [ -e "$AR3/escape.json" ] || [ -e "$AR3/parts/escape" ] && bad "wrote outside" || ok

echo "R6: import registers existing sessions once, for repositories in scope"
OTHER="$TMPROOT/other"; repo "$OTHER" "https://github.com/someone/else"
mkdir -p "$HOMEC/projects/-other" "$HOMEC/projects/-tmp-claude-eval-x"
printf '{"sessionId":"77777777-0000-0000-0000-000000000000","timestamp":"2026-11-02T00:00:00Z","cwd":"%s","type":"user"}\n' "$OTHER" > "$HOMEC/projects/-other/77777777-0000-0000-0000-000000000000.jsonl"
printf '{"sessionId":"88888888-0000-0000-0000-000000000000","timestamp":"2026-11-02T00:00:00Z","cwd":"/tmp/claude-eval-x/home/cwd/","type":"user"}\n' > "$HOMEC/projects/-tmp-claude-eval-x/88888888-0000-0000-0000-000000000000.jsonl"
EV="$TMPROOT/claude-eval-y/cwd"; repo "$EV" "https://github.com/Owner/Repo"   # an eval run in a checkout of this repository
printf '{"sessionId":"99999999-0000-0000-0000-000000000000","timestamp":"2026-11-02T00:00:00Z","cwd":"%s","type":"user"}\n' "$EV" > "$HOMEC/projects/-tmp-claude-eval-x/99999999-0000-0000-0000-000000000000.jsonl"
AR4="$TMPROOT/archive4"
imp() { (cd "$REPO" && AGENT_TRANSCRIPTS="$AR4" "$T" import --claude-home "$HOMEC" "$@" 2>&1); }
it "import archives the sessions of this repository and skips the others, eval runs in its checkouts included"
out="$(imp)"; rc=$?
assert_eq 0 "$rc"; has "$out" "imported 6"; has "$out" "skipped 3"
assert_eq "$(cat "$TR")" "$(cat "$AR4/parts/$SID/main/"g1-*.jsonl 2>&1)"
[ -e "$AR4/sessions/77777777-0000-0000-0000-000000000000.json" ] && bad "another repository's session was imported" || ok
assert_eq "1" "$(find "$AR4/parts/$SID/subagents" -name '*.jsonl' 2>/dev/null | wc -l | tr -d ' ')"
it "a second import finds nothing new"
before="$(cd "$AR4" 2>/dev/null && find . -type f | sort)"
out="$(imp)"; rc=$?
assert_eq 0 "$rc"; has "$out" "imported 0"; has "$out" "unchanged 6"
assert_eq "$before" "$(cd "$AR4" && find . -type f | sort)"
it "--repo names another repository in scope, and --evals takes eval sessions"
out="$(imp --repo https://github.com/someone/else --evals)"
has "$out" "imported 3"
assert_eq "eval" "$(json "$AR4/sessions/88888888-0000-0000-0000-000000000000.json" 'd["source"]')"
it "import with AGENT_TRANSCRIPTS unset is an error, since nothing would be kept"
out="$(cd "$REPO" && "$T" import --claude-home "$HOMEC" 2>&1)"; rc=$?
assert_eq 2 "$rc"; has "$out" "AGENT_TRANSCRIPTS"

echo "the hook in this repository's .claude/settings.json"
SETTINGS="$here/../../../.claude/settings.json"
it "Stop and SessionEnd run transcripts archive, never failing the session"
for ev in Stop SessionEnd; do
  cmd="$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["hooks"][sys.argv[2]][0]["hooks"][0]["command"])' "$SETTINGS" "$ev" 2>&1)"
  has "$cmd" "plugins/change-record/bin/transcripts archive"; has "$cmd" "|| true"
done
it "the hook command, run as Claude Code runs it, archives into AGENT_TRANSCRIPTS"
root="$(cd "$here/../../.." && pwd)"; AR5="$TMPROOT/archive5"
out="$(hook Stop | (cd "$REPO" && CLAUDE_PROJECT_DIR="$root" AGENT_TRANSCRIPTS="$AR5" sh -c "$cmd" 2>&1))"; rc=$?
assert_eq 0 "$rc"; [ -e "$AR5/sessions/$SID.json" ] && ok || bad "no index entry in $AR5: $out"

echo "passed=$pass failed=$fail"; [ "$fail" -eq 0 ]
