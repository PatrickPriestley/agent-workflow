#!/usr/bin/env bash
# Tests for store/schema.sql, run in a PostgreSQL this suite starts for itself (record
# docs/changes/2026-11-15-readable-store.md, R1 and R2). The stand-in the other suites use is a
# dictionary and runs no SQL, so the grants, the checks and the view are tested here and nowhere
# else. This is PostgreSQL, not Supabase: what the store's own interface answers is the probe's
# to show (store/probe).
#
# Where no PostgreSQL is installed the suite says so and exits 0, unless SCHEMA_TEST_REQUIRED=1
# (the Linux CI job sets it): then that is a failure.
set -u
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
pass=0; fail=0; CURRENT=""
it() { CURRENT="$1"; }
ok()  { pass=$((pass+1)); printf '  ok   %s\n' "$CURRENT"; }
bad() { fail=$((fail+1)); printf '  FAIL %s\n       %s\n' "$CURRENT" "$1"; }
assert_eq()  { [ "$1" = "$2" ] && ok || bad "expected [$1] got [$2]"; }
has() { printf '%s' "$1" | grep -qF -- "$2" && ok || bad "missing [$2] in: $(printf '%s' "$1" | head -c 300)"; }

bindir=""
for d in "$(pg_config --bindir 2>/dev/null)" /usr/lib/postgresql/*/bin /opt/homebrew/opt/postgresql*/bin /usr/local/opt/postgresql*/bin; do
  [ -n "$d" ] && [ -x "$d/initdb" ] && [ -x "$d/pg_ctl" ] && [ -x "$d/psql" ] && bindir="$d"
done
if [ -z "$bindir" ]; then
  echo "store schema: not run, no PostgreSQL is installed here (initdb, pg_ctl and psql)"
  [ "${SCHEMA_TEST_REQUIRED:-}" = 1 ] && { echo "store schema: SCHEMA_TEST_REQUIRED=1, so that is a failure" >&2; exit 1; }
  exit 0
fi

# A short path: a socket's path may be 107 bytes at most, and macOS's temporary folder is long.
PG="$(mktemp -d /tmp/pgs.XXXXXX)" || { echo "cannot make a temporary folder" >&2; exit 1; }
# PostgreSQL does not run as root. Where this suite does (a container), its server runs as another user.
as=""
if [ "$(id -u)" = 0 ]; then
  for u in postgres nobody; do id "$u" >/dev/null 2>&1 && { as="$u"; break; }; done
  [ -n "$as" ] || { echo "store schema: running as root with no other user to run PostgreSQL as" >&2; rm -rf "$PG"; exit 1; }
  chown "$as" "$PG"
fi
run() { if [ -n "$as" ]; then su -s /bin/sh "$as" -c "$(printf '%q ' "$@")"; else "$@"; fi; }
stop() { run "$bindir/pg_ctl" -D "$PG/data" -m immediate stop >/dev/null 2>&1; rm -rf "$PG"; }
trap stop EXIT
run "$bindir/initdb" -D "$PG/data" -A trust -U postgres -E UTF8 --locale=C >"$PG/initdb.log" 2>&1 \
  || { echo "store schema: initdb failed: $(tail -3 "$PG/initdb.log")" >&2; exit 1; }
# No statement may run for more than 20 seconds: a view that never ends fails its test and does not hang the suite.
run "$bindir/pg_ctl" -D "$PG/data" -l "$PG/server.log" -w -o "-c listen_addresses='' -k $PG -c statement_timeout=20000" start >"$PG/start.log" 2>&1 \
  || { echo "store schema: the server did not start: $(tail -3 "$PG/server.log" 2>/dev/null)" >&2; exit 1; }
# sql STATEMENTS...: run in one session, the last line of what it prints (an error included)
sql() { run "$bindir/psql" -h "$PG" -U postgres -d postgres -At -v ON_ERROR_STOP=1 "${@/#/-c}" 2>&1 | tail -1; }
sql_file() { cp "$1" "$PG/file.sql"; chmod 644 "$PG/file.sql"; run "$bindir/psql" -h "$PG" -U postgres -d postgres -q -v ON_ERROR_STOP=1 -f "$PG/file.sql" 2>&1 | grep -v '^psql:.*NOTICE' ; return "${PIPESTATUS[0]}"; }
# sql_all STATEMENT: everything it prints, on one line (an error's message is not its last line)
sql_all() { run "$bindir/psql" -h "$PG" -U postgres -d postgres -At -v ON_ERROR_STOP=1 -c "$1" 2>&1 | tr '\n' ' '; }
# as ROLE STATEMENT: the statement's answer as that role
as_role() { sql "set role $1" "$2"; }

echo "the store's schema in $("$bindir/psql" --version)"
# The roles Supabase has, and its habit of granting everything on a new table or view in public to all three, which
# is what schema.sql's revokes are there to undo (its own first lines say so).
sql "create role anon nologin" "create role authenticated nologin" "create role service_role nologin bypassrls" "create role someone nologin" \
    "alter default privileges in schema public grant all on tables to anon, authenticated, service_role" >/dev/null

it "R1: schema.sql runs, and runs again with nothing to say"
out="$(sql_file "$here/schema.sql")"; rc=$?; assert_eq "0 " "$rc $out"
out="$(sql_file "$here/schema.sql")"; rc=$?; assert_eq "0 " "$rc $out"

row="insert into public.messages (session_id, stream, chunk_id, shape, line, block, who, kind, text) values ('r1', 'main', repeat('a', 64), 1, 1, 0, 'user', 'text', 'hello')"
it "R1: the hooks' key (anon) may insert a row, once"
assert_eq "INSERT 0 1" "$(as_role anon "$row")"
has "$(as_role anon "$row")" "duplicate key value violates unique constraint"
it "R1: and nothing else: no select, update or delete of the table, and no select of the view"
has "$(as_role anon "select count(*) from public.messages")" "permission denied for table messages"
has "$(as_role anon "update public.messages set text = 'x'")" "permission denied for table messages"
has "$(as_role anon "delete from public.messages")" "permission denied for table messages"
has "$(as_role anon "select count(*) from public.transcript")" "permission denied"
it "R1: a signed-in user, and any other role, get nothing"
for r in authenticated someone; do
  has "$(as_role $r "$row")" "permission denied for table messages"
  has "$(as_role $r "select count(*) from public.messages")" "permission denied for table messages"
  has "$(as_role $r "select count(*) from public.transcript")" "permission denied"
done
it "R1: the read key (service_role) reads the table and the view"
assert_eq "1" "$(as_role service_role "select count(*) from public.messages")"
assert_eq "0" "$(as_role service_role "select count(*) from public.transcript")"
it "R1: running the file a third time leaves the row and the grants as they were"
sql_file "$here/schema.sql" >/dev/null
assert_eq "1" "$(sql "select count(*) from public.messages")"
has "$(as_role anon "select count(*) from public.messages")" "permission denied for table messages"
it "R1: row security is on for the table, and the view is granted to the read key alone"
assert_eq "t" "$(sql "select relrowsecurity from pg_class where relname = 'messages'")"
assert_eq "f f f t" "$(sql "select concat_ws(' ', has_table_privilege('anon', 'public.transcript', 'select'), has_table_privilege('authenticated', 'public.transcript', 'select'), has_table_privilege('someone', 'public.transcript', 'select'), has_table_privilege('service_role', 'public.transcript', 'select'))")"
it "R1: the view reads as the one who asks where the server can (PostgreSQL 15 and later)"
if [ "$(sql "select current_setting('server_version_num')::int >= 150000")" = t ]; then
  assert_eq "{security_invoker=true}" "$(sql "select reloptions from pg_class where relname = 'transcript'")"
else ok; fi
it "R1: each check of the table refuses what it is there for"
# refused CHECK COLUMNS VALUES: the constraint an insert of those values trips
refused() { sql_all "insert into public.messages ($2) values ($3)" | sed -n 's/.*violates check constraint "\([a-z_]*\)".*/\1/p'; }
base="session_id, stream, chunk_id, shape, line, block, who, kind, text"
assert_eq "messages_session_id_check" "$(refused x "$base" "'a b', 'main', repeat('a', 64), 1, 1, 0, 'user', 'text', 'x'")"
assert_eq "messages_stream_check" "$(refused x "$base" "'r1', '', repeat('a', 64), 1, 1, 0, 'user', 'text', 'x'")"
assert_eq "messages_chunk_id_check" "$(refused x "$base" "'r1', 'main', 'abc', 1, 1, 0, 'user', 'text', 'x'")"
assert_eq "messages_shape_check" "$(refused x "$base" "'r1', 'main', repeat('a', 64), 0, 1, 0, 'user', 'text', 'x'")"
assert_eq "messages_line_check" "$(refused x "$base" "'r1', 'main', repeat('a', 64), 1, 0, 0, 'user', 'text', 'x'")"
assert_eq "messages_block_check" "$(refused x "$base" "'r1', 'main', repeat('a', 64), 1, 1, -1, 'user', 'text', 'x'")"
assert_eq "messages_who_check" "$(refused x "$base" "'r1', 'main', repeat('a', 64), 1, 1, 0, 'nobody', 'text', 'x'")"
assert_eq "messages_tool_check" "$(refused x "$base, tool" "'r1', 'main', repeat('a', 64), 1, 9, 0, 'user', 'text', 'x', repeat('t', 201)")"
assert_eq "messages_call_id_check" "$(refused x "$base, call_id" "'r1', 'main', repeat('a', 64), 1, 9, 0, 'user', 'text', 'x', repeat('c', 201)")"
it "R1: a row the table's checks refuse: a kind that is none of the three, a text with no end to it"
has "$(sql_all "insert into public.messages (session_id, stream, chunk_id, shape, line, block, who, kind, text) values ('r1', 'main', repeat('a', 64), 1, 2, 0, 'user', 'thought', 'x')")" 'violates check constraint "messages_kind_check"'
has "$(sql_all "insert into public.messages (session_id, stream, chunk_id, shape, line, block, who, kind, text) values ('r1', 'main', repeat('a', 64), 1, 3, 0, 'user', 'text', repeat('x', 3000001))" | cut -c1-200)" 'violates check constraint "messages_text_check"'

# Made-up sessions, one for each thing R2 says of the view. A chunk here is its id, its start and its
# number; its bytes are never read. Each message's text says where it should come in its session.
python3 - > "$PG/rows.sql" <<'PY'
import hashlib, json

out = []
def h(s):
    return hashlib.sha256(s.encode()).hexdigest()
def root(sid, stream="main"):
    return h(f"{sid}/{stream}")
def chunk(sid, cid, start, number, stream="main"):
    out.append("insert into public.chunks (session_id, stream, chunk_id, start_id, sender, generation, number, lines, bytes, redaction, data) "
               f"values ('{sid}', '{stream}', '{cid}', '{start}', 'test', 1, {number}, 1, 1, 2, '');")
def msg(sid, cid, line, block, text, shape=1, stream="main"):
    out.append("insert into public.messages (session_id, stream, chunk_id, shape, line, block, who, kind, text) "
               f"values ('{sid}', '{stream}', '{cid}', {shape}, {line}, {block}, 'user', 'text', '{text}');")
def index(sid, entry, row_id=None, version=1):
    doc = json.dumps(entry).replace("'", "''")
    out.append(f"insert into public.sessions (session_id, row_id, sender, version, entry) values ('{sid}', '{row_id or h(sid + doc)}', 'test', {version}, '{doc}');")
def entry(tips, redaction=2, when="2026-11-15T10:00:00Z"):
    e = {"last_timestamp": when, "sent": {"streams": {s: {"tip": t, "bytes": 10} for s, t in tips.items()}}}
    if redaction is not None:
        e["redaction_version"] = redaction
    return e
def chain(sid, n=2, stream="main", texts=None, numbers=None):
    """n chunks from the root; returns the tip."""
    start = root(sid, stream)
    for i in range(n):
        cid = h(f"{sid}/{stream}/{i}")
        chunk(sid, cid, start, (numbers or range(1, n + 1))[i], stream)
        msg(sid, cid, 1, 0, (texts or [f"{sid}-{k}" for k in range(1, 2 * n + 1)])[2 * i], stream=stream)
        msg(sid, cid, 2, 0, (texts or [f"{sid}-{k}" for k in range(1, 2 * n + 1)])[2 * i + 1], stream=stream)
        start = cid
    return start

# in order, though the sender numbered its chunks backwards and a line holds two blocks
tip = chain("good", numbers=[2, 1]); msg("good", tip, 2, 1, "good-5"); index("good", entry({"main": tip}))
# a line's blocks come before the next line's: the second block of line 1 before the first of line 2
tip = chain("lines", 1); msg("lines", tip, 1, 1, "lines-1b"); index("lines", entry({"main": tip}))
# two index rows that tie in everything: the first by row_id is the one
a, b = chain("tie", 1, texts=["tie-first", "tie-first-2"]), h("tie/other")
chunk("tie", b, root("tie"), 1); msg("tie", b, 1, 0, "tie-second")
index("tie", entry({"main": a}), row_id="1" * 64); index("tie", entry({"main": b}), row_id="2" * 64)
# the ranking, a key at a time: the newer redaction though it is the earlier row; then the later; then the larger; then the higher version
def pair(sid, first, second):
    """Two index rows for one session, each with a chunk of its own; the text says which should be shown."""
    for name, (red, when, size, version) in (("shown", first), ("hidden", second)):
        cid = h(f"{sid}/{name}"); chunk(sid, cid, root(sid), 1); msg(sid, cid, 1, 0, f"{sid}-{name}")
        e = entry({"main": cid}, redaction=red, when=when); e["sent"]["streams"]["main"]["bytes"] = size
        index(sid, e, row_id=("f" if name == "shown" else "0") * 64, version=version)  # a tie would go to the hidden row
pair("redact", (2, "2026-11-01T00:00:00Z", 10, 1), (1, "2026-11-15T00:00:00Z", 99, 9))
pair("late", (2, "2026-11-15T00:00:00Z", 10, 1), (2, "2026-11-01T00:00:00Z", 99, 9))
pair("large", (2, "2026-11-15T00:00:00Z", 99, 1), (2, "2026-11-15T00:00:00Z", 10, 9))
pair("version", (2, "2026-11-15T00:00:00Z", 10, 9), (2, "2026-11-15T00:00:00Z", 10, 1))
# a stream with no chunk yet: its tip is its root
tip = chain("empty"); index("empty", entry({"main": tip, "subagents/agent-a": root("empty", "subagents/agent-a")}))
# what materialize refuses: an id that begins with a dot, a stream that is no transcript's, a chunk missing, a chain in a ring
tip = chain(".x"); index(".x", entry({"main": tip}))
tip = chain("dots"); index("dots", entry({"main": tip, "../x": root("dots", "../x")}))
gone = h("missing/gone"); cid = h("missing/1"); chunk("missing", cid, gone, 2); msg("missing", cid, 1, 0, "missing-1"); index("missing", entry({"main": cid}))
r1, r2 = h("ring/1"), h("ring/2"); chunk("ring", r1, r2, 1); chunk("ring", r2, r1, 2); msg("ring", r1, 1, 0, "ring-1"); index("ring", entry({"main": r1}))
# an index row that cannot be read, beside a good one, three ways; the bad row is the later and the larger
for sid, bad in (("bad1", {"redaction_version": "two", "last_timestamp": "9999", "sent": {"streams": [1, 2]}}),
                 ("bad2", {"redaction_version": 999, "last_timestamp": "9999", "sent": {"streams": []}})):
    tip = chain(sid); index(sid, entry({"main": tip})); index(sid, bad, version=99)
tip = chain("bad3"); wrong = h("bad3/wrong"); chunk("bad3", wrong, root("bad3"), 9); msg("bad3", wrong, 1, 0, "bad3-wrong")
index("bad3", entry({"main": tip}, redaction=None)); index("bad3", dict(entry({"main": wrong}, redaction="two", when="9999")), version=99)
# a session whose only index row cannot be read
tip = chain("only"); index("only", entry({"main": tip}, redaction="two"))
# rows of another shape beside a session's own
tip = chain("shape", 1); msg("shape", tip, 1, 0, "shape-planted", shape=999); msg("shape", tip, 3, 0, "shape-planted-2", shape=2); index("shape", entry({"main": tip}))
# the rows of messages go in last and backwards, so that no order of insertion can pass for the order of the view
print("\n".join([s for s in out if "public.messages" not in s] + [s for s in reversed(out) if "public.messages" in s]))
PY
it "the made-up rows load"
out="$(sql_file "$PG/rows.sql")"; rc=$?; assert_eq "0 " "$rc $out"
# shown SESSION [STREAM]: the texts the view shows for it, in order, with their numbers
shown() { sql "select coalesce(string_agg(n || ':' || text, ' ' order by n), 'nothing') from public.transcript where session_id = '$1' and stream = '${2:-main}'"; }

it "R2: a session's rows come in the order of the chain, numbered from 1, whatever numbers the sender gave its chunks"
assert_eq "1:good-1 2:good-2 3:good-3 4:good-4 5:good-5" "$(shown good)"
it "R2: within a chunk the rows go by line and then by block"
assert_eq "1:lines-1 2:lines-1b 3:lines-2" "$(shown lines)"
it "R2: two index rows that tie are settled as materialize settles them: the first by row_id"
assert_eq "1:tie-first 2:tie-first-2" "$(shown tie)"
it "R2: the index row is chosen as materialize chooses it: by redaction version, then the later, then the larger, then the higher version"
assert_eq "1:redact-shown 1:late-shown 1:large-shown 1:version-shown" "$(shown redact) $(shown late) $(shown large) $(shown version)"
it "R2: a stream with no chunk has no row and hides nothing"
assert_eq "1:empty-1 2:empty-2 3:empty-3 4:empty-4 | nothing" "$(shown empty) | $(shown empty subagents/agent-a)"
it "R2: no row of a session whose id begins with a dot"
assert_eq "nothing" "$(shown .x)"
it "R2: no row of a session one of whose streams is no transcript's"
assert_eq "nothing" "$(shown dots)"
it "R2: no row of a session whose chain does not reach its root"
assert_eq "nothing" "$(shown missing)"
it "R2: no row of a session whose chain comes back on itself, and the server spends under a second on it"
assert_eq "nothing" "$(shown ring)"
ms="$(run "$bindir/psql" -h "$PG" -U postgres -d postgres -At -c '\timing on' -c "select count(*) from public.transcript where session_id = 'ring'" 2>&1 | sed -n 's/^Time: \([0-9]*\).*/\1/p')"
[ -n "$ms" ] && [ "$ms" -lt 1000 ] && ok || bad "the query took [$ms] ms"
it "R2: an index row that cannot be read ranks below the good one, however late or large: a text for a version and a list for streams"
assert_eq "1:bad1-1 2:bad1-2 3:bad1-3 4:bad1-4" "$(shown bad1)"
it "R2: the same with a high number for a version and a list for streams"
assert_eq "1:bad2-1 2:bad2-2 3:bad2-3 4:bad2-4" "$(shown bad2)"
it "R2: the same with a text for a version and streams of its own, beside a good row that has no version"
assert_eq "1:bad3-1 2:bad3-2 3:bad3-3 4:bad3-4" "$(shown bad3)"
it "R2: a session whose only index row cannot be read shows nothing, and stops nothing"
assert_eq "nothing" "$(shown only)"
it "R2: rows of another shape are not shown"
assert_eq "1:shape-1 2:shape-2" "$(shown shape)"
it "R2: the sessions shown are the ones that should be, and no other"
assert_eq "bad1 bad2 bad3 empty good large late lines redact shape tie version" "$(sql "select string_agg(distinct session_id, ' ' order by session_id) from public.transcript")"
it "R2: the shape the view reads is the tool's"
tool="$(sed -n 's/^SHAPE = \([0-9][0-9]*\).*/\1/p' "$here/../bin/transcripts")"; view="$(sed -n 's/^where m\.shape = \([0-9][0-9]*\);.*/\1/p' "$here/schema.sql")"
assert_eq "${tool:-no SHAPE in the tool}" "${view:-no shape in the view}"
it "R1: the read key sees the view as the suite's owner does"
assert_eq "32 32" "$(sql "select count(*) from public.transcript") $(as_role service_role "select count(*) from public.transcript")"

it "R4: the rows the tool reads from its fixture go into the real table, as the store's interface puts rows in"
python3 - "$here/fixtures/shape-1.rows.jsonl" > "$PG/fixture.sql" <<'PY'
import hashlib, json, sys
rows = [dict(json.loads(l), session_id="fixture", stream="main", chunk_id="f" * 64) for l in open(sys.argv[1])]
cols = ", ".join(rows[0])
print(f"insert into public.messages ({cols}) select {cols} from json_populate_recordset(null::public.messages, $fixture${json.dumps(rows)}$fixture$::json);")
root = hashlib.sha256(b"fixture/main").hexdigest()
print("insert into public.chunks (session_id, stream, chunk_id, start_id, sender, generation, number, lines, bytes, redaction, data) "
      f"values ('fixture', 'main', '{'f' * 64}', '{root}', 'test', 1, 1, 21, 1, 2, '');")
entry = json.dumps({"redaction_version": 2, "sent": {"streams": {"main": {"tip": "f" * 64, "bytes": 1}}}})
print(f"insert into public.sessions (session_id, row_id, sender, version, entry) values ('fixture', '{'e' * 64}', 'test', 1, '{entry}');")
PY
out="$(sql_file "$PG/fixture.sql")"; rc=$?; assert_eq "0 " "$rc $out"
assert_eq "16" "$(sql "select count(*) from public.messages where session_id = 'fixture'")"
it "R4, R6: read back as the interface gives rows, each is the row that went in by the tool's own comparison, the time of a line among them"
run "$bindir/psql" -h "$PG" -U postgres -d postgres -At -c "select json_agg(row_to_json(m) order by line, block) from (select shape, line, block, at, who, kind, tool, call_id, failed, side, text from public.messages where session_id = 'fixture') m" > "$PG/back.json" 2>&1
assert_eq "16 rows, none differs; a time comes back as 2026-11-15T10:00:00.25+00:00 for 2026-11-15T10:00:00.250Z" "$(python3 - "$here/../bin/transcripts" "$here/fixtures/shape-1.rows.jsonl" "$PG/back.json" 2>&1 <<'PY'
import importlib.machinery, importlib.util, json, sys
sys.dont_write_bytecode = True
loader = importlib.machinery.SourceFileLoader("transcripts_tool", sys.argv[1])
tr = importlib.util.module_from_spec(importlib.util.spec_from_loader("transcripts_tool", loader))
loader.exec_module(tr)
want, back = [json.loads(l) for l in open(sys.argv[2])], json.load(open(sys.argv[3]))
differ = [(w["line"], w["block"], f) for w, b in zip(want, back) for f in tr.ROW_FIELDS + ("shape", "line", "block")
          if not tr.same_field(f, w[f], b[f])]
print(f"{len(back)} rows, {differ or 'none differs'}; a time comes back as {back[0]['at']} for {want[0]['at']}")
PY
)"
it "R4: and the view shows them in the fixture's order, with each row's kind, tool and text"
run "$bindir/psql" -h "$PG" -U postgres -d postgres -At -c "select json_agg(json_build_array(kind, tool, text) order by n) from public.transcript where session_id = 'fixture'" > "$PG/view.json" 2>&1
assert_eq "16 rows in the fixture's order" "$(python3 -c '
import json, sys
want = [[r["kind"], r["tool"], r["text"]] for r in map(json.loads, open(sys.argv[1]))]
got = json.load(open(sys.argv[2]))
print(len(got), "rows in the fixture" + chr(39) + "s order" if got == want else "rows that differ")' "$here/fixtures/shape-1.rows.jsonl" "$PG/view.json" 2>&1)"
it "R8: the README's query for one session, run as it is printed with a session's id put in, gives that session's rows in order"
# readme_query N: the Nth SQL block of the README's part on reading the store's text
readme_query() { python3 - "$here/../README.md" "$1" <<'PY'
import re, sys
text = open(sys.argv[1]).read()
part = text[text.index("**The store's text, for reading**"):]
blocks = re.findall(r"```sql\n(.*?)```", part[:part.index("\n**Grading.**")], re.S)
print(blocks[int(sys.argv[2]) - 1])
PY
}
readme_query 1 > "$PG/q1.sql" 2>&1; readme_query 2 > "$PG/q2.sql" 2>&1
assert_eq "1|user|text|good-1 2|user|text|good-2 3|user|text|good-3 4|user|text|good-4 5|user|text|good-5" \
  "$(sed "s/<session id>/good/" "$PG/q1.sql" > "$PG/file.sql"; chmod 644 "$PG/file.sql"; run "$bindir/psql" -h "$PG" -U postgres -d postgres -At -c 'set role service_role' -f "$PG/file.sql" 2>&1 | grep -v '^SET$' | cut -d'|' -f1,3,4,6 | tr '\n' ' ' | sed 's/ $//')"
it "R8: the README's query that searches every session finds a text whatever its case, and says where it is"
assert_eq "tie|main|1|user|text|tie-first tie|main|2|user|text|tie-first-2" \
  "$(sed "s/<words>/TIE-FIRST/" "$PG/q2.sql" > "$PG/file.sql"; chmod 644 "$PG/file.sql"; run "$bindir/psql" -h "$PG" -U postgres -d postgres -At -c 'set role service_role' -f "$PG/file.sql" 2>&1 | grep -v '^SET$' | tr '\n' ' ' | sed 's/ $//')"
it "R8: and each query names its placeholder once, so that nothing else in it is left to fill in"
assert_eq "1 1" "$(grep -c '<session id>' "$PG/q1.sql") $(grep -c '<words>' "$PG/q2.sql")"

# ---- The probe loop's ledger (docs/plans/2026-11-24-probe-loop.md, Store) ----
run1="insert into public.probe_runs (probe_id, scorer_run, pr, repository, kind, loud, file, first_line, last_line, planted_sha, caught, ran) values ('probe-45656703509', 45661678361, 69, 'PatrickPriestley/agent-workflow', 'dropped-alternative', false, 'bin/commit-gate', 20, 22, repeat('a', 40), 4, 6)"
v1="insert into public.probe_verdicts (probe_id, scorer_run, loop, verdict, evidence) values ('probe-45656703509', 45661678361, 'verify', 'caught', 'differs 1, mentions Cursor')"
it "probes: the hooks' key (anon) may insert a probe and its verdicts, each once"
assert_eq "INSERT 0 1" "$(as_role anon "$run1")"
has "$(as_role anon "$run1")" "duplicate key value violates unique constraint"
assert_eq "INSERT 0 1" "$(as_role anon "$v1")"
has "$(as_role anon "$v1")" "duplicate key value violates unique constraint"
it "probes: the same probe scored by a later scorer run is new rows, not an update"
assert_eq "INSERT 0 1" "$(as_role anon "$(printf '%s' "$run1" | sed 's/45661678361/45661678362/')")"
it "probes: and the hooks' key can do nothing else with them"
for t in probe_runs probe_verdicts; do
  has "$(as_role anon "select count(*) from public.$t")" "permission denied for table $t"
  has "$(as_role anon "update public.$t set probe_id = 'x'")" "permission denied for table $t"
  has "$(as_role anon "delete from public.$t")" "permission denied for table $t"
  has "$(as_role authenticated "select count(*) from public.$t")" "permission denied for table $t"
done
assert_eq "2 1" "$(as_role service_role "select (select count(*) from public.probe_runs) || ' ' || (select count(*) from public.probe_verdicts)")"
it "probes: a verdict needs its probe, a loop and a verdict the scorer knows"
has "$(as_role anon "$(printf '%s' "$v1" | sed 's/45661678361/1/')")" 'Key is not present in table "probe_runs"'
has "$(as_role anon "$(printf '%s' "$v1" | sed "s/'verify'/'linter'/")")" "violates check constraint"
has "$(as_role anon "$(printf '%s' "$v1" | sed "s/'caught'/'maybe'/; s/'verify'/'ocr'/")")" "violates check constraint"
assert_eq "INSERT 0 1" "$(as_role anon "$(printf '%s' "$v1" | sed "s/'caught'/'failed'/; s/'verify'/'property-scout'/")")"
it "probes: each check refuses its own fault, one fault per row, named"
# One field wrong at a time (checks come before the key, so the scorer run can stay); the
# answer names the constraint that refused it.
bad_run() {  # SED-EXPRESSION CONSTRAINT
  has "$(as_role anon "$(printf '%s' "$run1" | sed "$1")")" "violates check constraint \"$2\""
}
bad_run "s/'probe-45656703509'/'x'/" probe_runs_probe_id_check
bad_run "s/45661678361/0/" probe_runs_scorer_run_check
bad_run "s/, 69, /, 0, /" probe_runs_pr_check
bad_run "s|'PatrickPriestley/agent-workflow'|'no slash'|" probe_runs_repository_check
bad_run "s/'dropped-alternative'/''/" probe_runs_kind_check
bad_run "s|'bin/commit-gate'|''|" probe_runs_file_check
bad_run "s/20, 22/0, 22/" probe_runs_first_line_check
bad_run "s/20, 22/22, 20/" probe_runs_check
bad_run "s/repeat('a', 40)/'abc'/" probe_runs_planted_sha_check
bad_run "s/4, 6)/-1, 6)/" probe_runs_caught_check
bad_run "s/4, 6)/7, 6)/" probe_runs_check1
has "$(as_role anon "$(printf '%s' "$v1" | sed "s/'differs 1, mentions Cursor'/repeat('e', 2001)/")")" 'violates check constraint "probe_verdicts_evidence_check"'
assert_eq "INSERT 0 1" "$(as_role anon "$(printf '%s' "$v1" | sed "s/'differs 1, mentions Cursor'/repeat('e', 2000)/; s/'verify'/'mutation'/")")"

echo
echo "store schema: passed=$pass failed=$fail"
[ "$fail" -eq 0 ]
