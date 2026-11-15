#!/usr/bin/env bash
# Tests for transcripts archive and import: a fake ~/.claude with a growing session transcript
# and a subagent transcript, a git repository the session ran in, and an archive in a scratch
# directory. Needs bash, git and python3.
set -u
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
T="$here/transcripts"
# The real path, not a link to it: on macOS the temporary folder is /var/..., a link to /private/var/...,
# and git and python name the real one.
# a suite that cannot make its temporary folder must not go on: TMPROOT would be the folder it was started in
TMPROOT="$(mktemp -d)" && TMPROOT="$(cd "$TMPROOT" && pwd -P)" || { echo "cannot make a temporary folder" >&2; exit 1; }
trap 'rm -rf "$TMPROOT"' EXIT
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
assert_eq "" "$(find "$AR" \( -perm -040 -o -perm -020 -o -perm -010 -o -perm -004 -o -perm -002 -o -perm -001 \) 2>&1 | sed "s|$AR|AR|")"

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
it "reading the skill file with cat, head or sed in Bash counts as using the skill; naming it does not"
SIDB=bbbbbbbb-2222-3333-4444-555555555555; mkdir -p "$TMPROOT/skillread"; TRB="$TMPROOT/skillread/$SIDB.jsonl"
{ line 2026-11-01T12:00:00.000Z '"type":"assistant","message":{"role":"assistant","content":[{"type":"tool_use","id":"b1","name":"Bash","input":{"command":"git log --oneline -- plugins/change-record/skills/change/SKILL.md; echo skills/x/SKILL.md"}}]}'
} | sed "s/$SID/$SIDB/" > "$TRB"
archive --transcript "$TRB" > /dev/null
assert_eq "[]" "$(json "$AR/sessions/$SIDB.json" 'str(d["skills"])')"
{ line 2026-11-01T12:01:00.000Z '"type":"assistant","message":{"role":"assistant","content":[{"type":"tool_use","id":"b2","name":"Bash","input":{"command":"cd /tmp && sed -n 1,80p '"$REPO"'/plugins/change-record/skills/change/SKILL.md | head -5"}}]}'
} | sed "s/$SID/$SIDB/" >> "$TRB"
archive --transcript "$TRB" > /dev/null
assert_eq "change-record:change Bash plugins/change-record/skills/change/SKILL.md $BLOB" "$(json "$AR/sessions/$SIDB.json" '" ".join(str(d["skills"][0][k]) for k in ("name","how","file","blob")) if d["skills"] else "none"')"
SIDC=cccccccc-2222-3333-4444-555555555555; TRC="$TMPROOT/skillread/$SIDC.jsonl"
{ line 2026-11-01T12:02:00.000Z '"type":"assistant","message":{"role":"assistant","content":[{"type":"tool_use","id":"c1","name":"Bash","input":{"command":"cat plugins/change-record/skills/change/SKILL.md"}}]}'
} | sed "s/$SID/$SIDC/" > "$TRC"
archive --transcript "$TRC" > /dev/null
assert_eq "change-record:change Bash $BLOB" "$(json "$AR/sessions/$SIDC.json" '" ".join(str(d["skills"][0][k]) for k in ("name","how","blob")) if d["skills"] else "none"')"
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

echo "probe (2026-11-11-codex-cursor-capture task 1): a sample of what an agent's hook passes, structure only"
MU="$here/../grade/fixtures/agents/made-up"
PH="$TMPROOT/zzowner-home"; PO="$TMPROOT/probe-out"
CXID=0199a1b2-c3d4-7e5f-8a9b-0c1d2e3f4a5b; CUID=7c9e6679-7425-40de-944b-e07fc1f90ae7
CXT="$PH/.codex/sessions/2026/11/11/rollout-2026-11-11T10-00-00-$CXID.jsonl"
CUT="$PH/.cursor/projects/SECRET-PROJECT/agent-transcripts/$CUID.jsonl"
mkdir -p "$(dirname "$CXT")" "$(dirname "$CUT")"; cp "$MU/codex-rollout.jsonl" "$CXT"; cp "$MU/cursor-transcript.jsonl" "$CUT"
# What each agent's stop hook passes, as the record's Probed facts describe it (assumed, not yet seen).
codex_hook() { printf '{"session_id":"%s","transcript_path":%s,"cwd":"%s","hook_event_name":"Stop","model":"gpt-5.1-codex","permission_mode":"default","turn_id":"turn_SECRETid0001","stop_hook_active":false,"last_assistant_message":"SECRET-ANSWER to pat.secret@example.com"}' "$CXID" "$1" "$REPO"; }
cursor_hook() { printf '{"conversation_id":"%s","generation_id":"8d0f7780-8536-51ef-a55c-f18fd2a01bf8","model":"claude-4.5-sonnet","hook_event_name":"stop","cursor_version":"2.1.321","workspace_roots":["%s"],"user_email":"pat.secret@example.com","transcript_path":%s,"status":"completed","loop_count":0}' "$CUID" "$REPO" "$1"; }
# probe OUTDIR ARGS...: run as a hook runs it, in the repository, hook JSON on stdin; stdout and stderr kept apart.
probe() { local o="$1"; shift; (cd "$REPO" && HOME="$PH" CODEX_PROBE_SETTING=SECRET-ENV CURSOR_TRACE_ID=SECRET-ENV "$T" probe "$@" --out "$o" 2>"$TMPROOT/probe.err"); }
same() { [ -f "$1" ] && [ -f "$2" ] && cmp -s "$1" "$2" && ok || bad "expected [the stored summary $(basename "$1")] got [$(head -c 1500 "$2" 2>/dev/null || true)]"; }
no_content() {   # nothing of the made-up session's content, paths, addresses or ids is in the sample
  local s; s="$(cat "$1" 2>/dev/null)"
  [ -n "$s" ] && ok || bad "expected [a sample at $1] got [none]"
  for x in SECRET zzowner "@" "$CXID" "$CUID" 8d0f7780 "$TMPROOT" "$REPO" toolu_ 3f2a9c1d a1b2c3d4e5f60718; do lacks "$s" "$x"; done
}

it "probe --agent codex writes the stored summary of the hook input and the rollout's shape, and prints nothing"
out="$(codex_hook "\"$CXT\"" | probe "$PO" --agent codex)"; rc=$?
assert_eq 0 "$rc"; assert_eq "" "$out"; same "$MU/codex-stop.expected.json" "$PO/codex-stop.json"
it "the Codex sample names item types, tool names and the markers the record's assumptions rest on"
s="$(cat "$PO/codex-stop.json" 2>/dev/null)"
for x in '"agent": "codex"' function_call_output custom_tool_call local_shell_call apply_patch '"shell"' '*** Update File:' 'rejected by user' session_meta creator_account_id last_assistant_message '0.58.0' 'gpt-5.1-codex' CODEX_PROBE_SETTING \
         '~/.codex/sessions/<n>/<n>/<n>/rollout-<timestamp>-<uuid>.jsonl' '"incomplete_last_line": true'; do has "$s" "$x"; done
it "the Codex sample holds no prompt, answer, command, path, address or id"
no_content "$PO/codex-stop.json"
it "a string that is itself JSON is content: its key names and values are not copied (record 2026-11-12-probe-no-content)"
JXT="$PH/.codex/sessions/2026/11/12/rollout-2026-11-12T10-00-00-$CXID.jsonl"; mkdir -p "$(dirname "$JXT")"
python3 - "$JXT" <<'PY'
import json, sys
def line(typ, payload): return json.dumps({"timestamp": "2026-11-12T10:00:00.000Z", "type": typ, "payload": payload})
prompt = json.dumps({"accountOwner": "Bob", "reason": "confidential", "password": "hunter2"})
package = json.dumps({"customerName": "Ada", "status": "churned", "dependencies": {"leftpad": "1.0.0"}, "kind": "enterprise"})
rows = [
    line("response_item", {"type": "message", "role": "user", "content": [{"type": "input_text", "text": prompt}]}),
    line("response_item", {"type": "function_call", "name": "shell", "call_id": "call_1",
                           "arguments": json.dumps({"command": ["cat", "package.json"], "env": {"deployTarget": "prod"}, "note": package,
                                                    "status": "refunded", "name": "AdaLovelace"})}),
    line("response_item", {"type": "function_call_output", "call_id": "call_1",
                           "output": json.dumps({"output": package, "metadata": {"exit_code": 0, "duration_seconds": 0.1}, "billingPlan": "gold"})}),
    line("response_item", {"type": "function_call_output", "call_id": "call_2", "output": json.dumps({"clientList": [{"fullName": "Ada", "status": "vip"}], "source": "crm"})}),
]
open(sys.argv[1], "w").write("\n".join(rows) + "\n")
PY
out="$(codex_hook "\"$JXT\"" | probe "$PO/json" --agent codex)"; rc=$?
assert_eq 0 "$rc"
s="$(cat "$PO/json/codex-stop.json" 2>/dev/null)"
for x in accountOwner confidential password hunter2 customerName churned dependencies leftpad enterprise deployTarget billingPlan clientList crm \
         refunded AdaLovelace fullName vip; do lacks "$s" "$x"; done
it "what the agent itself wraps a result or a call in is still structure: the wrapper's known keys and a call's argument names"
for x in '"payload.output|json.metadata.exit_code": "number:1"' '"payload.output|json.output": "json-string:1"' '"payload.arguments|json.command[]": "string:2"' \
         '"payload.arguments|json.env": "object:1"' '"payload.arguments|json.env.<key>": "string:1"' '"payload.arguments|json.note": "json-string:1"' \
         '"payload.output|json.<key>"' '"payload.content[].text": "json-string:1"'; do has "$s" "$x"; done
it "a JSON string at the first level is opened with every key masked; one inside another JSON string is not opened"
has "$s" '"payload.content[].text|json.<key>": "string:3"'
lacks "$s" 'note|json'; lacks "$s" 'output|json.output|json'
it "probe --agent cursor writes the stored summary, whatever keys the transcript uses"
out="$(cursor_hook "\"$CUT\"" | probe "$PO" --agent cursor)"; rc=$?
assert_eq 0 "$rc"; assert_eq "" "$out"; same "$MU/cursor-stop.expected.json" "$PO/cursor-stop.json"
s="$(cat "$PO/cursor-stop.json" 2>/dev/null)"
for x in '"agent": "cursor"' tool_use tool_result StrReplace '"Shell"' user_email workspace_roots '2.1.321' is_error CURSOR_TRACE_ID '.<key>' 'rejected by user'; do has "$s" "$x"; done
it "the Cursor sample holds no content either: a key that is a path or an id, and a name outside a tool call, are not copied"
no_content "$PO/cursor-stop.json"; lacks "$s" "SECRET-PROJECT"
it "a transcript that is not JSON lines is summarised as text: counts and known markers only"
cp "$MU/cursor-transcript.txt" "$PH/.cursor/projects/SECRET-PROJECT/agent-transcripts/$CUID.txt"
out="$(cursor_hook "\"$PH/.cursor/projects/SECRET-PROJECT/agent-transcripts/$CUID.txt\"" | probe "$PO/text" --agent cursor)"; rc=$?
assert_eq 0 "$rc"; same "$MU/cursor-stop-text.expected.json" "$PO/text/cursor-stop.json"; no_content "$PO/text/cursor-stop.json"
has "$(cat "$PO/text/cursor-stop.json" 2>/dev/null)" '"format": "text"'
it "no transcript file given: exit 0, it says so, and the sample records that none was given"
out="$(cursor_hook null | probe "$PO/none" --agent cursor)"; rc=$?
assert_eq 0 "$rc"; has "$(cat "$TMPROOT/probe.err")" "no transcript file given"
assert_eq "False" "$(json "$PO/none/cursor-stop.json" 'd["transcript"]["given"]')"; no_content "$PO/none/cursor-stop.json"
it "a transcript file that does not exist: exit 0, it says so, and the sample records it"
out="$(codex_hook "\"$PH/.codex/sessions/SECRET-gone.jsonl\"" | probe "$PO/gone" --agent codex)"; rc=$?
assert_eq 0 "$rc"; has "$(cat "$TMPROOT/probe.err")" "does not exist"
assert_eq "True False" "$(json "$PO/gone/codex-stop.json" 'str(d["transcript"]["given"])+" "+str(d["transcript"]["exists"])')"; no_content "$PO/gone/codex-stop.json"
it "a compressed rollout is named as zstd and not read"
printf '\050\265\057\375SECRET-compressed' > "$PH/.codex/sessions/2026/11/11/rollout-2026-11-11T10-00-00-$CXID.jsonl.zst"
out="$(codex_hook "\"$PH/.codex/sessions/2026/11/11/rollout-2026-11-11T10-00-00-$CXID.jsonl.zst\"" | probe "$PO/zst" --agent codex)"; rc=$?
assert_eq 0 "$rc"; assert_eq "zstd" "$(json "$PO/zst/codex-stop.json" 'd["transcript"]["format"]')"
has "$(cat "$PO/zst/codex-stop.json" 2>/dev/null)" 'rollout-<timestamp>-<uuid>.jsonl.zst'; no_content "$PO/zst/codex-stop.json"
it "a transcript longer than the limit is read up to it and marked truncated, so the hook's time is bounded"
out="$(codex_hook "\"$CXT\"" | AGENT_TRANSCRIPTS_PROBE_BYTES=1500 probe "$PO/cut" --agent codex)"; rc=$?
assert_eq 0 "$rc"; assert_eq "True $(head -c 1500 "$CXT" | wc -l | tr -d " ")" "$(json "$PO/cut/codex-stop.json" 'str(d["transcript"]["truncated"])+" "+str(d["transcript"]["lines"])')"
assert_eq "False" "$(json "$PO/codex-stop.json" 'd["transcript"]["truncated"]')"
it "hook input that is missing or not a JSON object: exit 0, it says so, nothing is written"
out="$(printf '' | probe "$PO/empty" --agent codex)"; rc=$?
assert_eq 0 "$rc"; has "$(cat "$TMPROOT/probe.err")" "no hook input"; [ -e "$PO/empty" ] && bad "expected [no sample] got [$(ls "$PO/empty")]" || ok
out="$(printf '["SECRET"]' | probe "$PO/empty" --agent codex)"; rc=$?
assert_eq 0 "$rc"; has "$(cat "$TMPROOT/probe.err")" "no hook input"; lacks "$(cat "$TMPROOT/probe.err")" "SECRET"; [ -e "$PO/empty" ] && bad "expected [no sample] got [$(ls "$PO/empty")]" || ok
it "an agent it does not know, or none: exit 0, it says so, nothing is written"
out="$(codex_hook "\"$CXT\"" | probe "$PO/who" --agent opencode)"; rc=$?
assert_eq 0 "$rc"; has "$(cat "$TMPROOT/probe.err")" "--agent codex|cursor"; [ -e "$PO/who" ] && bad "expected [no sample] got [$(ls "$PO/who")]" || ok
out="$(codex_hook "\"$CXT\"" | probe "$PO/who")"; rc=$?
assert_eq 0 "$rc"; has "$(cat "$TMPROOT/probe.err")" "--agent codex|cursor"; [ -e "$PO/who" ] && bad "expected [no sample] got [$(ls "$PO/who")]" || ok
it "a folder it cannot write to: exit 0 and it says so"
printf 'x' > "$TMPROOT/a-file"
out="$(codex_hook "\"$CXT\"" | probe "$TMPROOT/a-file/sub" --agent codex)"; rc=$?
assert_eq 0 "$rc"; has "$(cat "$TMPROOT/probe.err")" "cannot write"
it "a sample that cannot take its place leaves no half-written file beside it (record 2026-11-15-probe-sample)"
mkdir -p "$PO/taken/codex-stop.json"   # the sample's own name is a folder: the last step of the write fails
out="$(codex_hook "\"$CXT\"" | probe "$PO/taken" --agent codex)"; rc=$?
assert_eq "0 codex-stop.json" "$rc $(ls "$PO/taken" | tr '\n' ' ' | sed 's/ $//')"; has "$(cat "$TMPROOT/probe.err")" "cannot write"
it "a value with a dot is kept only where every dot stands between digits: a model's version is, a host name or a dotted name is not"
out="$(printf '{"hook_event_name":"stop","model":"db.internal.corp.example.com","reason":"jane.doe.example.org","source":"gpt-5.2-codex","kind":"v2.1.321","status":"ok.","transcript_path":null}' | probe "$PO/dots" --agent cursor)"; rc=$?
s="$(cat "$PO/dots/cursor-stop.json" 2>/dev/null)"
assert_eq 0 "$rc"; for x in internal corp example jane doe '"ok."'; do lacks "$s" "$x"; done
has "$s" '"gpt-5.2-codex": 1'; has "$s" '"v2.1.321": 1'
it "a text transcript whose last line has no newline after it has that line counted, though another line reads as JSON"
printf 'user:\nhello\n42\nassistant: bye' > "$PH/.cursor/projects/SECRET-PROJECT/agent-transcripts/tail.txt"
out="$(cursor_hook "\"$PH/.cursor/projects/SECRET-PROJECT/agent-transcripts/tail.txt\"" | probe "$PO/tail" --agent cursor)"; rc=$?
assert_eq "0 4 1 1" "$rc $(json "$PO/tail/cursor-stop.json" 'str(d["transcript"]["lines"]) + " " + str(d["transcript"]["line_starts"].get("user:")) + " " + str(d["transcript"]["line_starts"].get("assistant:"))')"
it "an event name that is not a plain word does not choose the file's name"
out="$(printf '{"hook_event_name":"../../SECRET evil","transcript_path":null}' | probe "$PO/ev" --agent cursor)"; rc=$?
assert_eq 0 "$rc"; assert_eq "cursor-unknown.json" "$(ls "$PO/ev" 2>&1)"; no_content "$PO/ev/cursor-unknown.json"
it "a value that names a kind is copied only when it is a plain identifier or a version number, and a key that is an id is not"
out="$(printf '{"hook_event_name":"stop","status":"s1234567","kind":"run-c9e66790-7425-40de-944b-e07fc1f90ae7","reason":"deadbeef01","cursor_version":"9.9 words","model":"two words","a1b2c3d4e5f6a7b8":1,"transcript_path":null}' | probe "$PO/vals" --agent cursor)"; rc=$?
assert_eq 0 "$rc"; s="$(cat "$PO/vals/cursor-stop.json" 2>/dev/null)"; has "$s" '"status": "string:1"'; has "$s" '"<key>": "number:1"'
for x in s1234567 c9e66790 deadbeef01 "9.9" words a1b2c3d4e5f6a7b8; do lacks "$s" "$x"; done
it "input it cannot take in at all: exit 0, it gives up in one line, nothing is written"
out="$(head -c 200000 /dev/zero | tr '\0' '[' | probe "$PO/deep" --agent codex)"; rc=$?
assert_eq 0 "$rc"; assert_eq "" "$out"; has "$(cat "$TMPROOT/probe.err")" "gave up"; assert_eq "1" "$(wc -l < "$TMPROOT/probe.err" | tr -d ' ')"
[ -e "$PO/deep" ] && bad "expected [no sample] got [$(ls "$PO/deep")]" || ok
it "without --out the sample goes to grade/fixtures/agents beside the script, and says where"
mkdir -p "$TMPROOT/plugin"; cp -r "$here" "$TMPROOT/plugin/bin"; [ -d "$here/../probe" ] && cp -r "$here/../probe" "$TMPROOT/plugin/probe"
out="$(codex_hook "\"$CXT\"" | (cd "$REPO" && HOME="$PH" "$TMPROOT/plugin/bin/transcripts" probe --agent codex 2>&1))"; rc=$?
assert_eq 0 "$rc"; has "$out" "grade/fixtures/agents/codex-stop.json"
[ -f "$TMPROOT/plugin/grade/fixtures/agents/codex-stop.json" ] && ok || bad "expected [a sample under the plugin's grade/fixtures/agents] got [none]"
[ -e "$TMPROOT/plugin/probe/__pycache__" ] && bad "expected [no __pycache__ beside the plugin's code] got [one]" || ok

echo "user-level capture: the owner's scope list (record 2026-11-15-user-level-capture, R1 to R4 and R6)"
# A config folder of its own, five repositories and a folder that is none, an archive, and a stand-in for the store.
SC="$TMPROOT/scope-config"; mkdir -p "$SC/agent-transcripts"; cp "$XDG_CONFIG_HOME/agent-transcripts/machine-id" "$SC/agent-transcripts/"
LIST="$SC/agent-transcripts/scope"; SAR="$TMPROOT/scope-archive"; SHOME="$TMPROOT/scope-claude"
RIN="$TMPROOT/s-wanted"; repo "$RIN" "git@github.com:Owner/Wanted.git"
ROUT="$TMPROOT/s-client"; repo "$ROUT" "https://github.com/Client/Private"
REX="$TMPROOT/s-secret"; repo "$REX" "https://github.com/Owner/Secret-Thing.git"
RNO="$TMPROOT/s-no-origin"; repo "$RNO" "https://github.com/Owner/Gone"; git -C "$RNO" remote remove origin
RLOC="$TMPROOT/s-local"; repo "$RLOC" "$RIN"
NOREPO="$TMPROOT/s-no-repo"; mkdir -p "$NOREPO"
export no_proxy="127.0.0.1,localhost" NO_PROXY="127.0.0.1,localhost"
SPORT="$TMPROOT/scope.port"; SLOG="$TMPROOT/scope-store.log"; : > "$SLOG"
python3 "$here/../store/stand-in.py" "$SPORT" "$SLOG" read-key-made-up & STANDIN_PID=$!
trap 'kill $STANDIN_PID 2>/dev/null; rm -rf "$TMPROOT"' EXIT
for _ in $(seq 600); do [ -s "$SPORT" ] && break; sleep 0.05; done
SURL="http://127.0.0.1:$(cat "$SPORT")"
# sess DIR ID [FIRST-DIR]: the transcript of session ID in DIR (begun in FIRST-DIR, when given); prints its path
sess() {
  local p="$SHOME/projects/-scoped/$2.jsonl"; mkdir -p "$SHOME/projects/-scoped"
  printf '{"sessionId":"%s","timestamp":"2026-11-02T10:00:00.000Z","cwd":"%s","gitBranch":"work","type":"user","message":{"role":"user","content":"hello"}}\n' "$2" "${3:-$1}" > "$p"
  printf '{"sessionId":"%s","timestamp":"2026-11-02T10:00:05.000Z","cwd":"%s","gitBranch":"work","type":"assistant","message":{"role":"assistant","content":[{"type":"text","text":"done"}]}}\n' "$2" "$1" >> "$p"
  printf '%s' "$p"
}
# sstop DIR ID [FIRST-DIR]: the Stop hook of session ID in DIR, with archive --scoped and the store's URL set
sstop() {
  printf '{"session_id":"%s","transcript_path":"%s","cwd":"%s","hook_event_name":"Stop"}' "$2" "$(sess "$@")" "$1" \
    | (cd "$1" && XDG_CONFIG_HOME="$SC" AGENT_TRANSCRIPTS="$SAR" AGENT_TRANSCRIPTS_URL="${STORE-$SURL}" "$T" archive --scoped 2>&1)
}
kept() { ls "$SAR/sessions" 2>/dev/null | sed 's/\.json$//' | tr '\n' ' '; }
# snap: every file of the archive with its content's hash; a started push leaves push.log there
snap() { [ -d "$SAR" ] && (cd "$SAR" && find . -type f | sort | while read -r f; do printf '%s %s\n' "$(git hash-object "$f")" "$f"; done); }
requests() { wc -l < "$SLOG" | tr -d ' '; }

it "R1: a session in a repository a line of the list matches is archived, the pattern written with the capitals GitHub shows"
printf '# the repositories whose sessions are kept\n\ngithub.com/Owner/*   # all of mine\n!github.com/Owner/Secret-*\n' > "$LIST"
out="$(STORE="" sstop "$RIN" s-in-1)"; rc=$?
assert_eq "0 [] s-in-1 " "$rc [$out] $(kept)"
assert_eq "github.com/owner/wanted" "$(json "$SAR/sessions/s-in-1.json" 'd["repository"]')"
it "R1: a line with no wildcard is the whole repository: its owner alone, or its name without the host, matches nothing"
printf 'github.com/Owner\nOwner/Wanted\nwanted\n' > "$LIST"
out="$(STORE="" sstop "$RIN" s-partial)"; assert_eq "0 [] s-in-1 " "$? [$out] $(kept)"
printf 'GitHub.com/Owner/Wanted\n' > "$LIST"
out="$(STORE="" sstop "$RIN" s-in-2)"; assert_eq "0 [] s-in-1 s-in-2 " "$? [$out] $(kept)"
it "R1: archive --scoped --transcript PATH takes the repository from the transcript, in either order of the two options"
out="$(cd "$NOREPO" && XDG_CONFIG_HOME="$SC" AGENT_TRANSCRIPTS="$SAR" "$T" archive --scoped --transcript "$(sess "$RIN" s-in-3)" 2>&1 < /dev/null)"
assert_eq "0 [] s-in-1 s-in-2 s-in-3 " "$? [$out] $(kept)"
out="$(cd "$NOREPO" && XDG_CONFIG_HOME="$SC" AGENT_TRANSCRIPTS="$SAR" "$T" archive --transcript "$(sess "$ROUT" s-out-t)" --scoped 2>&1 < /dev/null)"
assert_eq "0 [] s-in-1 s-in-2 s-in-3 " "$? [$out] $(kept)"

# From here the archive holds three sessions in scope that no push has sent, and every stop has the store's URL.
before="$(snap)"
# outside ID DIR [FIRST-DIR]: the stop archives nothing, says nothing, exits 0 and leaves the archive as it was
outside() {
  local id="$1"; shift
  out="$(sstop "$1" "$id" "${@:2}")"; rc=$?
  assert_eq "0 []" "$rc [$out]"
  [ "$(snap)" = "$before" ] && ok || bad "the archive changed: $(snap | diff <(printf '%s\n' "$before") - | head -5)"
}
it "R2: with no scope list, nothing is archived, nothing is printed and no push starts"
rm -f "$LIST"; outside s-none "$RIN"
it "R2: with a list of comments and blank lines only"
printf '# nothing yet\n\n   \n' > "$LIST"; outside s-empty "$RIN"
it "R2: in a repository no line matches"
printf 'github.com/Owner/*\n' > "$LIST"; outside s-client "$ROUT"
it "R2: in a repository a line excludes, whether the exclusion comes after the match or before it"
printf 'github.com/Owner/*\n!github.com/owner/secret-*\n' > "$LIST"; outside s-secret-1 "$REX"
printf '!github.com/owner/secret-*\n*\n' > "$LIST"; outside s-secret-2 "$REX"
it "R2: outside any repository, though the list says *"
printf '*\n' > "$LIST"; outside s-no-repo "$NOREPO"
it "R2: in a repository with no origin, though the list says *"
outside s-no-origin "$RNO"
it "R2: in a repository whose origin is a local path, though the list says * and names the path"
printf '*\n%s\n' "$RIN" >> "$LIST"; outside s-local "$RLOC"
it "a session begun in a repository out of scope is not archived from one in scope, nor one that ends up out of scope"
printf 'github.com/Owner/*\n' > "$LIST"
outside s-moved-in "$RIN" "$ROUT"; outside s-moved-out "$ROUT" "$RIN"
it "R2: the store got no request from any of those stops"
sleep 0.5; assert_eq 0 "$(requests)"
it "a scope list that cannot be read archives nothing and starts no push, and says so"
rm -f "$LIST"; mkdir "$LIST"; out="$(sstop "$RIN" s-unreadable)"; rc=$?; rmdir "$LIST"
assert_eq "0 True" "$rc $([ "$(snap)" = "$before" ] && echo True)"; has "$out" "$LIST"
it "the control: a stop in scope, with the same store, is archived and what the archive held is sent"
printf 'github.com/Owner/*\n' > "$LIST"
out="$(sstop "$RIN" s-in-4)"; rc=$?
for _ in $(seq 100); do [ "$(grep -c '"/rest/v1/sessions"' "$SLOG")" -ge 4 ] && break; sleep 0.1; done
assert_eq "0 [] 4" "$rc [$out] $(grep -c '"/rest/v1/sessions"' "$SLOG")"
assert_eq "s-in-1 s-in-2 s-in-3 s-in-4 " "$(kept)"
it "R3: without --scoped the hook archives whatever session it is given, as before"
out="$(printf '{"session_id":"s-any","transcript_path":"%s","cwd":"%s"}' "$(sess "$ROUT" s-any)" "$ROUT" | (cd "$ROUT" && XDG_CONFIG_HOME="$SC" AGENT_TRANSCRIPTS="$TMPROOT/scope-archive-2" "$T" archive 2>&1))"
assert_eq "0 [] s-any.json" "$? [$out] $(ls "$TMPROOT/scope-archive-2/sessions" 2>&1)"

# scope DIR [ARG]: transcripts scope, run in DIR
scope() { (cd "$1" && XDG_CONFIG_HOME="$SC" AGENT_TRANSCRIPTS="$SAR" "$T" scope "${@:2}" 2>&1); }
it "R4: scope says the repository is in scope and by which line, then the archive's size, and exits 0"
printf '# mine\n!github.com/owner/secret-*\nGitHub.com/Owner/*\n' > "$LIST"
out="$(scope "$RIN")"; rc=$?
assert_eq 0 "$rc"; has "$out" "github.com/owner/wanted is in scope: line 3 of $LIST, GitHub.com/Owner/*"
has "$out" "the archive $SAR holds 4 sessions, 0.0 MB"
it "R4: scope DIR is the repository at DIR, from anywhere"
out="$(scope "$NOREPO" "$RIN")"; assert_eq 0 "$?"; has "$out" "github.com/owner/wanted is in scope"
it "R4: out of scope it exits 1 and says which of the seven reasons it is"
out="$(scope "$REX")"; assert_eq 1 "$?"; has "$out" "not in scope: line 2 of $LIST excludes github.com/owner/secret-thing, !github.com/owner/secret-*"
has "$out" "the archive $SAR holds 4 sessions"
out="$(scope "$ROUT")"; assert_eq 1 "$?"; has "$out" "not in scope: no line of $LIST matches github.com/client/private"
out="$(scope "$NOREPO")"; assert_eq 1 "$?"; has "$out" "not in scope: $NOREPO is in no git repository"
out="$(scope "$RNO")"; assert_eq 1 "$?"; has "$out" "not in scope: the repository at $RNO has no origin"
out="$(scope "$RLOC")"; assert_eq 1 "$?"; has "$out" "not in scope: the origin of the repository at $RLOC is a local path"
printf '# nothing yet\n' > "$LIST"
out="$(scope "$RIN")"; assert_eq 1 "$?"; has "$out" "not in scope: the scope list $LIST names no repository"
rm -f "$LIST"
out="$(scope "$RIN")"; assert_eq 1 "$?"; has "$out" "not in scope: there is no scope list at $LIST"
it "R4: the archive's size is the bytes of its parts, in MB"
printf 'github.com/Owner/*\n' > "$LIST"; head -c 1500000 /dev/zero > "$SAR/parts/s-in-1/main/g1-000009.jsonl"; head -c 800000 /dev/zero > "$SAR/push.log"
has "$(scope "$RIN")" "the archive $SAR holds 4 sessions, 1.5 MB of transcripts, not redacted"; rm -f "$LIST"
it "R4: with AGENT_TRANSCRIPTS unset it says that nothing is archived on this machine"
out="$(cd "$RIN" && XDG_CONFIG_HOME="$SC" "$T" scope 2>&1)"; assert_eq 1 "$?"; has "$out" "AGENT_TRANSCRIPTS is not set"
it "R4: a folder that is not there, or a second argument, is a usage error"
scope "$RIN" "$TMPROOT/no-such-folder" > /dev/null; a=$?; scope "$RIN" "$RIN" "$ROUT" > /dev/null; b=$?
assert_eq "2 2" "$a $b"

echo "user-level capture: import --scoped (R6)"
printf 'github.com/Owner/*\n!github.com/owner/secret-*\n' > "$LIST"
SAR2="$TMPROOT/scope-archive-3"; rm -rf "$SHOME"
sess "$RIN" i-wanted > /dev/null; sess "$ROUT" i-client > /dev/null; sess "$REX" i-secret > /dev/null
sess "$NOREPO" i-no-repo > /dev/null; sess "$RLOC" i-local > /dev/null
simp() { (cd "$NOREPO" && XDG_CONFIG_HOME="$SC" AGENT_TRANSCRIPTS="$SAR2" "$T" import --claude-home "$SHOME" "$@" 2>&1); }
it "it registers the sessions whose repository is in scope and no other, from a folder that is no repository"
out="$(simp --scoped)"; rc=$?
assert_eq "0 i-wanted.json" "$rc $(ls "$SAR2/sessions" 2>&1 | tr '\n' ' ' | sed 's/ $//')"
has "$out" "imported 1"; has "$out" "skipped 4"
it "with no scope list it registers nothing"
rm -f "$LIST"; rm -rf "$SAR2"; out="$(simp --scoped)"; rc=$?
assert_eq "0 " "$rc $(ls "$SAR2/sessions" 2>/dev/null)"; has "$out" "imported 0"; has "$out" "skipped 5"
it "--scoped with --repo or --evals is a usage error: the list alone says what is taken"
simp --scoped --repo https://github.com/Client/Private > /dev/null; a=$?; simp --evals --scoped > /dev/null; b=$?
assert_eq "2 2 " "$a $b $(ls "$SAR2/sessions" 2>/dev/null)"

echo "user-level capture: the hook the plugin ships (R5)"
HOOKS="$here/../hooks/hooks.json"
it "Stop and SessionEnd, and no other event, each run one command with a limit of 10 seconds"
assert_eq "SessionEnd Stop" "$(python3 -c 'import json,sys; print(" ".join(sorted(json.load(open(sys.argv[1]))["hooks"])))' "$HOOKS" 2>&1)"
for ev in Stop SessionEnd; do
  assert_eq "1 1 command 10" "$(python3 -c '
import json,sys
g=json.load(open(sys.argv[1]))["hooks"][sys.argv[2]]; h=g[0]["hooks"]
print(len(g), len(h), h[0]["type"], h[0]["timeout"])' "$HOOKS" "$ev" 2>&1)"
done
it "the command is the plugin's own transcripts archive --scoped, never failing the session"
for ev in Stop SessionEnd; do
  pcmd="$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["hooks"][sys.argv[2]][0]["hooks"][0]["command"])' "$HOOKS" "$ev" 2>&1)"
  assert_eq '"${CLAUDE_PLUGIN_ROOT}/bin/transcripts" archive --scoped || true' "$pcmd"
done
# phook DIR ID: the plugin's hook command, run as Claude Code runs it for a stop of session ID in DIR
phook() {
  printf '{"session_id":"%s","transcript_path":"%s","cwd":"%s","hook_event_name":"Stop"}' "$2" "$(sess "$1" "$2")" "$1" \
    | (cd "$1" && CLAUDE_PLUGIN_ROOT="$(cd "$here/.." && pwd)" XDG_CONFIG_HOME="$SC" AGENT_TRANSCRIPTS="$HAR" sh -c "$pcmd" 2>&1)
}
HAR="$TMPROOT/hook-archive"; printf 'github.com/Owner/*\n' > "$LIST"
it "run as Claude Code runs it, it archives a session in a repository on the list"
out="$(phook "$RIN" h-wanted)"; assert_eq "0 [] h-wanted.json" "$? [$out] $(ls "$HAR/sessions" 2>&1)"
it "and none in a repository off it"
out="$(phook "$ROUT" h-client)"; assert_eq "0 [] h-wanted.json" "$? [$out] $(ls "$HAR/sessions" 2>&1)"
it "a plugin folder with no transcripts tool in it does not fail the session"
out="$(printf '{}' | (cd "$RIN" && CLAUDE_PLUGIN_ROOT="$TMPROOT/no-such-plugin" sh -c "$pcmd" 2>/dev/null))"; assert_eq "0 []" "$? [$out]"

echo "passed=$pass failed=$fail"; [ "$fail" -eq 0 ]
