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

# ---- The weekly probe report: two functions the publishable key may call ----
# A later scoring of the same probe: only it counts in the report.
v2="insert into public.probe_verdicts (probe_id, scorer_run, loop, verdict, evidence) values ('probe-45656703509', 45661678362, 'verify', 'missed', 'secret evidence text')"
assert_eq "INSERT 0 1" "$(as_role anon "$v2")"
other="insert into public.probe_runs (probe_id, scorer_run, pr, repository, kind, loud, file, first_line, last_line, planted_sha, caught, ran) values ('probe-45630016303', 45717183157, 68, 'PatrickPriestley/agent-workflow', 'off-by-one', true, 'bin/pr-size', 8, 12, repeat('b', 40), 1, 5)"
assert_eq "INSERT 0 1" "$(as_role anon "$other")"
assert_eq "INSERT 0 1" "$(as_role anon "insert into public.probe_verdicts (probe_id, scorer_run, loop, verdict, evidence) values ('probe-45630016303', 45717183157, 'verify', 'caught', 'x')")"
it "report: the hooks' key may call the loop totals, which count each probe's latest scoring only"
assert_eq "verify|2|1|1|0|0|0|0" "$(as_role anon "select string_agg(concat_ws('|', loop, probes, caught, missed, not_run, failed, no_data, judge), ';') from public.probe_report_loops()")"
it "report: and the recent probes, newest first, latest scoring each, with no evidence"
assert_eq "probe-45630016303|68|off-by-one|t|bin/pr-size|1|5;probe-45656703509|69|dropped-alternative|f|bin/commit-gate|4|6" \
  "$(as_role anon "select string_agg(concat_ws('|', probe_id, pr, kind, loud, file, caught, ran), ';' order by scored_at desc, probe_id) from public.probe_report_probes(12)")"
assert_eq "1" "$(as_role anon "select count(*) from public.probe_report_probes(1)")"
it "report: neither function returns evidence, and the key still cannot read the tables"
for f in probe_report_loops probe_report_probes; do
  assert_eq "f" "$(sql "select exists (select 1 from pg_proc p where p.proname = '$f' and array_to_string(p.proargnames, ',') like '%evidence%')")"
done
has "$(as_role anon "select count(*) from public.probe_verdicts")" "permission denied for table probe_verdicts"
has "$(as_role anon "select evidence from public.probe_verdicts")" "permission denied for table probe_verdicts"
it "report: a signed-in user, or any other role, may not call them"
for r in authenticated someone; do
  has "$(as_role $r "select count(*) from public.probe_report_loops()")" "permission denied for function probe_report_loops"
  has "$(as_role $r "select count(*) from public.probe_report_probes(12)")" "permission denied for function probe_report_probes"
done
it "report: they run as their owner with a fixed search path, so a caller's schema cannot stand in for public"
assert_eq "true true" "$(sql "select string_agg(p.prosecdef::text, ' ' order by p.proname) from pg_proc p where p.proname in ('probe_report_loops', 'probe_report_probes')")"
assert_eq "search_path=public, pg_temp;search_path=public, pg_temp" "$(sql "select string_agg(array_to_string(p.proconfig, ','), ';' order by p.proname) from pg_proc p where p.proname in ('probe_report_loops', 'probe_report_probes')")"
it "report: schema.sql runs again over the functions with nothing to say"
out="$(sql_file "$here/schema.sql")"; rc=$?; assert_eq "0 " "$rc $out"

# ---- The weekly report's agent health and skills sections ----
# Made-up rows, written as the owner: two Verify runs and one CI diagnosis run, a refused call, a tool
# error, a session that used a plugin's skill and one an old skill, and gradings of that skill.
h64() { printf "repeat('%s', 64)" "$1"; }
sess="insert into public.sessions (session_id, row_id, sender, version, entry, created_at) values
 ('gh-aw-verify-pr-claims-11-1', $(h64 1), 's', 1, '{\"source\": \"agent\", \"skills\": []}', now() - interval '2 days'),
 ('gh-aw-verify-pr-claims-12-1', $(h64 2), 's', 1, '{\"source\": \"agent\", \"skills\": []}', now() - interval '1 day'),
 ('gh-aw-ci-diagnosis-13-1',     $(h64 3), 's', 1, '{\"source\": \"agent\", \"skills\": []}', now() - interval '20 days'),
 ('rep-a', $(h64 4), 's', 1, '{\"source\": \"cloud\", \"skills\": [{\"name\": \"testplug:testskill\", \"how\": \"Skill\"}]}', now() - interval '1 day'),
 ('rep-a', $(h64 5), 's', 2, '{\"source\": \"cloud\", \"skills\": [{\"name\": \"testplug:testskill\", \"how\": \"Skill\"}, {\"name\": \"testplug:other\", \"how\": \"Skill\"}]}', now() - interval '1 day'),
 ('rep-b', $(h64 6), 's', 1, '{\"source\": \"local\", \"skills\": [{\"name\": \"testplug:testskill\", \"how\": \"read\"}]}', now() - interval '30 days')"
sess="$(printf '%s' "$sess" | tr '\n' ' ')"; assert_eq "INSERT 0 6" "$(sql "$sess")"
msg() {  # SESSION LINE WHO KIND TOOL CALL FAILED TEXT
  printf "('%s', 'main', %s, 1, %s, 0, '%s', '%s', %s, '%s', %s, '%s')" "$1" "$(h64 c)" "$2" "$3" "$4" "$5" "$6" "$7" "$8"
}
msgs="insert into public.messages (session_id, stream, chunk_id, shape, line, block, who, kind, tool, call_id, failed, text) values
 $(msg gh-aw-verify-pr-claims-11-1 1 assistant call "'Bash'" c1 false '{"command": "source <(grep x bin/commit-gate)\ntest_line y"}'),
 $(msg gh-aw-verify-pr-claims-11-1 2 tool result null c1 true 'Permission to use Bash has been denied because Claude Code is running in dont ask mode.'),
 $(msg gh-aw-verify-pr-claims-11-1 3 assistant call "'Bash'" c2 false '{"command": "bash bin/x.test.sh"}'),
 $(msg gh-aw-verify-pr-claims-11-1 4 tool result null c2 true 'Exit code 1: passed=3 failed=1'),
 $(msg gh-aw-verify-pr-claims-12-1 1 assistant call "'Bash'" c1 false '{"command": "source <(grep x bin/commit-gate)\nmore"}'),
 $(msg gh-aw-verify-pr-claims-12-1 2 tool result null c1 true 'Permission to use Bash has been denied because Claude Code is running in dont ask mode.'),
 $(msg gh-aw-verify-pr-claims-12-1 3 assistant call "'Read'" c3 false '{"file_path": "/x"}'),
 $(msg gh-aw-verify-pr-claims-12-1 4 tool result null c3 false 'contents'),
 $(msg gh-aw-ci-diagnosis-13-1 1 assistant call "'Bash'" c1 false '{"command": "bash bin/old.test.sh"}'),
 $(msg gh-aw-ci-diagnosis-13-1 2 tool result null c1 true 'Permission to use Bash has been denied.')"
msgs="$(printf '%s' "$msgs" | tr '\n' ' ')"; assert_eq "INSERT 0 10" "$(sql "$msgs")"
# The same call stored again (a later generation's chunk): it is still one call.
assert_eq "INSERT 0 1" "$(sql "insert into public.messages (session_id, stream, chunk_id, shape, line, block, who, kind, tool, call_id, failed, text) values ('gh-aw-verify-pr-claims-12-1', 'main', $(h64 d), 1, 1, 0, 'assistant', 'call', 'Read', 'c3', false, 'again')")"
grades="insert into public.scores (session_id, step, skill, grader, verdict, graded_at) values
 ('rep-a', 'red-first', 'testplug:testskill', 'fields/1', 'fail', now() - interval '3 days'),
 ('rep-a', 'red-first', 'testplug:testskill', 'fields/1', 'pass', now() - interval '2 days'),
 ('rep-b', 'red-first', 'testplug:testskill', 'fields/1', 'not_applicable', now() - interval '2 days'),
 ('rep-b', 'tier-declared', 'testplug:testskill', 'fields/1', 'fail', now() - interval '2 days'),
 ('rep-b', 'tier-declared', 'testplug:testskill', 'fields/2', 'pass', now() - interval '1 day'),
 ('rep-a', 'tier-declared', 'testplug:testskill', 'fields/2', 'pass', now() - interval '2 days'),
 ('rep-a', 'tier-declared', 'testplug:testskill', 'fields/3', 'fail', now() - interval '1 day')"
grades="$(printf '%s' "$grades" | tr '\n' ' ')"; assert_eq "INSERT 0 7" "$(sql "$grades")"
since="now() - interval '7 days'"
it "health: per agent, runs, calls, refused calls and other errors, since a time"
assert_eq "verify-pr-claims|2|4|2|1" "$(as_role anon "select string_agg(concat_ws('|', agent, runs, calls, refused, errors), ';' order by agent) from public.agent_health($since)")"
assert_eq "ci-diagnosis|1|1|1|0;verify-pr-claims|2|4|2|1" "$(as_role anon "select string_agg(concat_ws('|', agent, runs, calls, refused, errors), ';' order by agent) from public.agent_health(now() - interval '60 days')")"
it "health: the refused commands, by their first line, most tried first"
assert_eq 'verify-pr-claims|Bash|source <(grep x bin/commit-gate)|2' "$(as_role anon "select string_agg(concat_ws('|', agent, tool, command, times), ';') from public.agent_refused_commands($since, 10)")"
it "skills: per skill and plugin, sessions in the period and in all, from each session's latest row, by where it ran"
assert_eq "testplug:other|testplug|1|1|0|1|0|0;testplug:testskill|testplug|1|2|1|1|0|0" "$(as_role anon "select string_agg(concat_ws('|', skill, plugin, sessions, sessions_all, local, cloud, agent, dispatch), ';' order by skill) from public.skill_usage($since) where skill like 'testplug:%'")"
it "skills: one verdict per session and step, its latest grading by any grader version, and when last graded"
# fields/1, /2 and /3 are versions of one grader: a re-grading replaces the verdict, it is not a second vote.
assert_eq "testplug:testskill|red-first|2|1|0|1;testplug:testskill|tier-declared|2|1|1|0" "$(as_role anon "select string_agg(concat_ws('|', skill, step, sessions, pass, fail, not_applicable), ';' order by step) from public.skill_grades() where skill like 'testplug:%'")"
assert_eq "t" "$(as_role anon "select bool_and(last_graded > now() - interval '3 days') from public.skill_grades() where skill like 'testplug:%'")"
it "health and skills: a signed-in user, or any other role, may not call them; they run as their owner with a fixed path"
for f in "agent_health(now())" "agent_refused_commands(now(), 5)" "skill_usage(now())" "skill_grades()"; do
  for r in authenticated someone; do has "$(as_role $r "select count(*) from public.$f")" "permission denied for function ${f%%(*}"; done
done
assert_eq "search_path=public, pg_temp;search_path=public, pg_temp;search_path=public, pg_temp;search_path=public, pg_temp" "$(sql "select string_agg(array_to_string(p.proconfig, ','), ';' order by p.proname) from pg_proc p where p.proname in ('agent_health', 'agent_refused_commands', 'skill_usage', 'skill_grades')")"
assert_eq "true true true true" "$(sql "select string_agg(p.prosecdef::text, ' ' order by p.proname) from pg_proc p where p.proname in ('agent_health', 'agent_refused_commands', 'skill_usage', 'skill_grades')")"
it "health and skills: the key still cannot read the tables themselves"
for t in messages scores sessions; do has "$(as_role anon "select count(*) from public.$t")" "permission denied for table $t"; done
it "health and skills: schema.sql runs again over them with nothing to say"
out="$(sql_file "$here/schema.sql")"; rc=$?; assert_eq "0 " "$rc $out"

# ---- Repository-aware: a second repository's rows, and the repo filter ----
two="insert into public.probe_runs (probe_id, scorer_run, pr, repository, kind, loud, file, first_line, last_line, planted_sha, caught, ran) values ('probe-90', 91, 12, 'PatrickPriestley/meal-plan', 'off-by-one', false, 'apps/api/src/weeks.ts', 3, 4, repeat('c', 40), 0, 1)"
assert_eq "INSERT 0 1" "$(as_role anon "$two")"
assert_eq "INSERT 0 1" "$(as_role anon "insert into public.probe_verdicts (probe_id, scorer_run, loop, verdict, evidence) values ('probe-90', 91, 'verify', 'missed', 'x')")"
mp="insert into public.sessions (session_id, row_id, sender, version, entry, created_at) values
 ('gh-aw-verify-pr-claims-21-1', $(h64 7), 's', 1, '{\"source\": \"agent\", \"repository\": \"github.com/patrickpriestley/meal-plan\", \"skills\": []}', now() - interval '1 day'),
 ('rep-m', $(h64 8), 's', 1, '{\"source\": \"local\", \"repository\": \"github.com/PatrickPriestley/meal-plan\", \"skills\": [{\"name\": \"testplug:testskill\"}]}', now() - interval '1 day')"
mp="$(printf '%s' "$mp" | tr '\n' ' ')"; assert_eq "INSERT 0 2" "$(sql "$mp")"
assert_eq "INSERT 0 2" "$(sql "insert into public.messages (session_id, stream, chunk_id, shape, line, block, who, kind, tool, call_id, failed, text) values ('gh-aw-verify-pr-claims-21-1', 'main', $(h64 e), 1, 1, 0, 'assistant', 'call', 'Bash', 'm1', false, '{\"command\": \"pnpm test\"}'), ('gh-aw-verify-pr-claims-21-1', 'main', $(h64 e), 1, 2, 0, 'tool', 'result', null, 'm1', true, 'Permission to use Bash has been denied.')")"
assert_eq "INSERT 0 1" "$(sql "insert into public.scores (session_id, step, skill, grader, verdict, graded_at) values ('rep-m', 'red-first', 'testplug:testskill', 'fields/3', 'fail', now() - interval '1 day')")"
it "repo: owner/name in any form and case is one key"
assert_eq "a/b|a/b|a/b|a/b|" "$(sql "select concat_ws('|', public.repo_key('github.com/A/B'), public.repo_key('A/B'), public.repo_key('https://github.com/a/B'), public.repo_key('GitHub.com/a/b'), coalesce(public.repo_key(''), ''))")"
it "repo: with no repo, every repository, each row tagged with its own"
assert_eq "patrickpriestley/agent-workflow|verify;patrickpriestley/meal-plan|verify" "$(as_role anon "select string_agg(concat_ws('|', repository, loop), ';' order by repository, loop) from public.probe_report_loops() where loop = 'verify'")"
it "repo: with a repo, only it, whatever its case"
assert_eq "patrickpriestley/meal-plan|verify|1|0|1" "$(as_role anon "select string_agg(concat_ws('|', repository, loop, probes, caught, missed), ';') from public.probe_report_loops('PatrickPriestley/Meal-Plan')")"
assert_eq "0" "$(as_role anon "select count(*) from public.probe_report_loops('patrickpriestley/agent-workflow') where repository <> 'patrickpriestley/agent-workflow'")"
assert_eq "patrickpriestley/meal-plan|probe-90|12" "$(as_role anon "select string_agg(concat_ws('|', repository, probe_id, pr), ';') from public.probe_report_probes(12, 'patrickpriestley/meal-plan')")"
assert_eq "patrickpriestley/meal-plan|verify-pr-claims|1|1|1|0" "$(as_role anon "select string_agg(concat_ws('|', repository, agent, runs, calls, refused, errors), ';') from public.agent_health(now() - interval '7 days', 'github.com/patrickpriestley/meal-plan')")"
assert_eq "patrickpriestley/meal-plan|verify-pr-claims|pnpm test|1" "$(as_role anon "select string_agg(concat_ws('|', repository, agent, command, times), ';') from public.agent_refused_commands(now() - interval '7 days', 10, 'patrickpriestley/meal-plan')")"
assert_eq "patrickpriestley/meal-plan|testplug:testskill|1|1|1|0" "$(as_role anon "select string_agg(concat_ws('|', repository, skill, sessions, sessions_all, local, cloud), ';') from public.skill_usage(now() - interval '7 days', 'patrickpriestley/meal-plan')")"
assert_eq "patrickpriestley/meal-plan|testplug:testskill|red-first|1|0|1" "$(as_role anon "select string_agg(concat_ws('|', repository, skill, step, sessions, pass, fail), ';') from public.skill_grades('patrickpriestley/meal-plan')")"
it "repo: the same agent in two repositories is two rows, not one"
assert_eq "2" "$(as_role anon "select count(*) from public.agent_health(now() - interval '7 days') where agent = 'verify-pr-claims'")"
assert_eq "patrickpriestley/meal-plan|1|1|1|0" "$(as_role anon "select concat_ws('|', repository, runs, calls, refused, errors) from public.agent_health(now() - interval '7 days') where agent = 'verify-pr-claims' and repository = 'patrickpriestley/meal-plan'")"
it "repo: a repository with nothing gives nothing, and repo_key is not the key's to call"
assert_eq "0" "$(as_role anon "select count(*) from public.probe_report_loops('nobody/nothing')")"
has "$(as_role anon "select public.repo_key('a/b')")" "permission denied for function repo_key"
it "repo: schema.sql runs again, dropping and making the functions, with nothing to say, and their grants hold"
out="$(sql_file "$here/schema.sql")"; rc=$?; assert_eq "0 " "$rc $out"
assert_eq "patrickpriestley/meal-plan|verify|1|0|1" "$(as_role anon "select string_agg(concat_ws('|', repository, loop, probes, caught, missed), ';') from public.probe_report_loops('patrickpriestley/meal-plan')")"
has "$(as_role authenticated "select count(*) from public.skill_grades()")" "permission denied for function skill_grades"

# ---- session_effort: cost, effort and verbosity per agent or source ----
ef="insert into public.sessions (session_id, row_id, sender, version, entry, created_at) values
 ('gh-aw-ci-diagnosis-70-1', $(h64 a), 's', 1, '{\"source\": \"agent\", \"repository\": \"github.com/patrickpriestley/effort\", \"streams\": {\"main\": {\"effort\": {\"calls\": 3, \"input\": 6, \"output\": 29, \"cache_read\": 100, \"cache_write\": 50, \"tool_calls\": 2, \"text_chars\": 40, \"posted_chars\": 300, \"cost_usd\": 0.25, \"turns\": 3, \"last\": {\"id\": \"m\"}}}, \"subagents/agent-x\": {\"effort\": {\"calls\": 1, \"output\": 17, \"tool_calls\": 1}}}}', now() - interval '1 day'),
 ('gh-aw-ci-diagnosis-71-1', $(h64 a), 's', 1, '{\"source\": \"agent\", \"repository\": \"github.com/patrickpriestley/effort\", \"streams\": {\"main\": {\"effort\": {\"calls\": 2, \"output\": 11, \"cost_usd\": 0.5, \"tool_calls\": \"many\"}}}}', now() - interval '2 days'),
 ('gh-aw-ci-diagnosis-72-1', $(h64 a), 's', 1, '{\"source\": \"agent\", \"repository\": \"github.com/patrickpriestley/effort\", \"streams\": {\"main\": {\"generation\": 1}}}', now() - interval '3 days'),
 ('eff-local-1', $(h64 a), 's', 1, '{\"source\": \"local\", \"repository\": \"github.com/patrickpriestley/effort\", \"streams\": {\"main\": {\"effort\": {\"calls\": 5, \"output\": 100, \"text_chars\": 900}}}}', now() - interval '1 day'),
 ('eff-local-1', $(h64 b), 's', 2, '{\"source\": \"local\", \"repository\": \"github.com/patrickpriestley/effort\", \"streams\": {\"main\": {\"effort\": {\"calls\": 7, \"output\": 140, \"text_chars\": 1000}}}}', now() - interval '1 day'),
 ('gh-aw-ci-diagnosis-60-1', $(h64 a), 's', 1, '{\"source\": \"agent\", \"repository\": \"github.com/patrickpriestley/effort\", \"streams\": {\"main\": {\"effort\": {\"calls\": 90, \"cost_usd\": 9}}}}', now() - interval '40 days')"
it "effort: the sessions go in"
ef="$(printf '%s' "$ef" | tr '\n' ' ')"; assert_eq "INSERT 0 6" "$(sql "$ef")"
q_eff="select string_agg(concat_ws('|', repository, who, sessions, measured, calls, input_tokens, output_tokens, cache_read_tokens, cache_write_tokens, tool_calls, text_chars, posted_chars, cost_usd, costed), ';' order by who) from public.session_effort(now() - interval '7 days', 'PatrickPriestley/Effort')"
it "effort: per agent its sessions since, those with counts, and sums over every stream, subagents included"
assert_eq "patrickpriestley/effort|ci-diagnosis|3|2|6|6|57|100|50|3|40|300|0.75|2;patrickpriestley/effort|local|1|1|7|0|140|0|0|0|1000|0|0" "$(as_role anon "$q_eff")"
it "effort: a session's latest index row counts; a count that is not a number, and a session before since, do not"
assert_eq "1" "$(as_role anon "select count(*) from public.session_effort(now() - interval '7 days', 'patrickpriestley/effort') where who = 'local' and calls = 7")"
assert_eq "4" "$(as_role anon "select sessions from public.session_effort(now() - interval '60 days', 'patrickpriestley/effort') where who = 'ci-diagnosis'")"
it "effort: a gh-aw run's tokens are the totals its result reported, where it has them"
rt="insert into public.sessions (session_id, row_id, sender, version, entry, created_at) values ('gh-aw-property-scout-80-1', $(h64 a), 's', 1, '{\"source\": \"agent\", \"repository\": \"github.com/patrickpriestley/effort\", \"streams\": {\"main\": {\"effort\": {\"calls\": 2, \"input\": 4, \"output\": 9, \"cache_read\": 10, \"cache_write\": 5, \"run_input\": 6, \"run_output\": 700, \"run_cache_read\": 30}}, \"subagents/agent-y\": {\"effort\": {\"calls\": 1, \"output\": 3, \"cache_write\": 2}}}}', now() - interval '1 day')"
assert_eq "INSERT 0 1" "$(sql "$rt")"
assert_eq "property-scout|3|6|700|30|7" "$(as_role anon "select concat_ws('|', who, calls, input_tokens, output_tokens, cache_read_tokens, cache_write_tokens) from public.session_effort(now() - interval '7 days', 'patrickpriestley/effort') where who = 'property-scout'")"
it "effort: other repositories are not counted, and the key may call it but not read the sessions"
assert_eq "0" "$(as_role anon "select count(*) from public.session_effort(now() - interval '7 days', 'nobody/nothing')")"
has "$(as_role anon "select count(*) from public.sessions")" "permission denied"
has "$(as_role authenticated "select count(*) from public.session_effort(now())")" "permission denied for function session_effort"
it "effort: schema.sql runs again with it, and it still answers"
out="$(sql_file "$here/schema.sql")"; rc=$?; assert_eq "0 " "$rc $out"
assert_eq "patrickpriestley/effort|ci-diagnosis|3|2|6|6|57|100|50|3|40|300|0.75|2;patrickpriestley/effort|local|1|1|7|0|140|0|0|0|1000|0|0;patrickpriestley/effort|property-scout|1|1|3|6|700|30|7|0|0|0|0" "$(as_role anon "$q_eff")"

echo
echo "store schema: passed=$pass failed=$fail"
[ "$fail" -eq 0 ]
