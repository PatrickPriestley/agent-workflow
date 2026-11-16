#!/usr/bin/env python3
"""A stand-in for the store's HTTPS interface (PostgREST on Supabase), for the tests only.

  stand-in.py PORTFILE LOGFILE READKEY [--hang SECONDS] [--refuse TABLE [--refuse-status N]]
              [--refuse-after N] [--refuse-session ID] [--loose TABLE]

It answers as the real project answered `store/probe` (record docs/changes/2026-11-09-skill-
transcripts.md, Probed facts): with any key but READKEY (or none, as through the cloud proxy)
an insert into chunks or sessions is 201, a duplicate primary key is 409 23505, and
ignore-duplicates, return=representation, select, update, delete and any access to scores or
judge_votes are
401 42501. With READKEY, GET reads rows with `col=eq.value` filters, `select`, `order`,
`limit` and `offset`. Every request is appended to LOGFILE as one JSON line: method, path,
apikey, prefer and body. POST /__admin/tamper with {"chunk_id": ...} changes a stored chunk's
data, to test that materialize checks it; POST /__admin/forget with {"table": ..., "match":
{column: value}} drops the rows that match, to test what finds a row missing. --refuse TABLE answers 503 (or --refuse-status N)
to every insert into TABLE, as a store that fails part way would; --refuse-after N accepts N
inserts into chunks and answers 503 to every later one, as a store that fails part way
through a session would; --refuse-session ID answers 400 to any insert of that session's
rows, as a store that will not take one session's data would.

`messages` and the view `transcript` (record docs/changes/2026-11-15-readable-store.md) answer
as PostgreSQL answered that record's probe: several rows in one request are stored together
or, if one is a duplicate, not at all; a text holding U+0000 or a lone surrogate is 400; the
hooks' key reads neither. The view is the table's rows here: this stand-in runs no SQL, and
the view's own rules are tested in store/schema.test.sh. --loose TABLE makes that table keep the
new rows of a request it answers 409 to, and take a text PostgreSQL would refuse, as a store that
is not what the plan needs would: the probe must fail against it.
It writes its port to PORTFILE once it listens.
"""
import json
import sys
import threading
import time
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from socketserver import TCPServer
from urllib.parse import parse_qsl, urlsplit

PORTFILE, LOGFILE, READKEY = sys.argv[1:4]
OPTS = dict(zip(sys.argv[4::2], sys.argv[5::2]))
HANG = float(OPTS.get("--hang", 0))
REFUSE = OPTS.get("--refuse")
REFUSE_AFTER = int(OPTS["--refuse-after"]) if "--refuse-after" in OPTS else None
REFUSE_SESSION = OPTS.get("--refuse-session")
REFUSE_STATUS = int(OPTS.get("--refuse-status", 503))
LOOSE = OPTS.get("--loose")
ACCEPTED = {"chunks": 0}
KEYS = {"chunks": ("session_id", "stream", "chunk_id"), "sessions": ("session_id", "row_id"),
        "scores": ("session_id", "step", "grader", "graded_at"),
        "judge_votes": ("session_id", "question", "judge", "vote", "judged_at"),
        "messages": ("session_id", "stream", "chunk_id", "shape", "line", "block")}
TABLES = {"chunks": [], "sessions": [], "scores": [], "judge_votes": [], "messages": []}
VIEWS = {"transcript": "messages"}
LOCK = threading.Lock()
DENIED = {"code": "42501", "details": None, "hint": None, "message": "permission denied"}


def unstorable(row):
    """Whether a row holds a text PostgreSQL will not take: U+0000, or half of a surrogate pair."""
    for v in row.values() if isinstance(row, dict) else []:
        if isinstance(v, str):
            try:
                v.encode("utf-8")
            except UnicodeEncodeError:
                return True
            if "\x00" in v:
                return True
    return False


class H(BaseHTTPRequestHandler):
    def log_message(self, *a):
        pass

    def answer(self, status, body=None):
        data = b"" if body is None else json.dumps(body).encode()
        self.send_response(status)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(data)))
        self.end_headers()
        self.wfile.write(data)

    def handle_any(self):
        if HANG:
            time.sleep(HANG)
        u = urlsplit(self.path)
        n = int(self.headers.get("Content-Length") or 0)
        raw = self.rfile.read(n) if n else b""
        key, prefer = self.headers.get("apikey"), self.headers.get("Prefer") or ""
        with LOCK:
            with open(LOGFILE, "a") as f:
                f.write(json.dumps({"method": self.command, "path": u.path, "query": u.query, "apikey": key,
                                    "prefer": prefer, "body": raw.decode("utf-8", "replace")}) + "\n")
        if u.path == "/__admin/tamper":
            cid = json.loads(raw)["chunk_id"]
            with LOCK:
                for r in TABLES["chunks"]:
                    if r["chunk_id"] == cid:
                        r["data"] = "H4sIAAAAAAAAA8tIzcnJBwCGphA2BQAAAA=="  # gzip of "hello"
            return self.answer(204)
        if u.path == "/__admin/forget":  # {"table": ..., "match": {column: value}}: the rows that match are gone
            want = json.loads(raw)
            with LOCK:
                TABLES[want["table"]][:] = [r for r in TABLES[want["table"]]
                                            if any(r.get(k) != v for k, v in want["match"].items())]
            return self.answer(204)
        table = u.path[len("/rest/v1/"):] if u.path.startswith("/rest/v1/") else None
        if table in VIEWS:  # a view is read, by the read key alone
            if key != READKEY:
                return self.answer(401, DENIED)
            if self.command != "GET":
                return self.answer(405, {"message": "the stand-in only reads a view"})
            table = VIEWS[table]
        if table not in TABLES:
            return self.answer(404, {"code": "PGRST205", "message": f"Could not find the table 'public.{table}'"})
        reader = key == READKEY
        if self.command == "POST" and table == REFUSE:
            return self.answer(REFUSE_STATUS, {"message": "the stand-in refuses this table"})
        if self.command == "POST" and table == "chunks" and REFUSE_AFTER is not None:
            with LOCK:
                ACCEPTED["chunks"] += 1
                over = ACCEPTED["chunks"] > REFUSE_AFTER
            if over:
                return self.answer(503, {"message": f"the stand-in refuses chunks after the first {REFUSE_AFTER}"})
        if self.command == "POST":
            if (not reader and (table in ("scores", "judge_votes") or "ignore-duplicates" in prefer
                                or "return=representation" in prefer)):
                return self.answer(401, DENIED)
            try:
                rows = json.loads(raw)
            except ValueError:
                return self.answer(400, {"code": "PGRST102", "message": "Empty or invalid json"})
            rows = rows if isinstance(rows, list) else [rows]
            if REFUSE_SESSION and any(r.get("session_id") == REFUSE_SESSION for r in rows):
                return self.answer(400, {"code": "23514", "message": "new row violates a check constraint (the stand-in refuses this session)"})
            if table == "messages" and table != LOOSE and any(unstorable(r) for r in rows):
                return self.answer(400, {"code": "22P05", "message": "unsupported Unicode escape sequence"})
            with LOCK:
                have = {tuple(r.get(c) for c in KEYS.get(table, ())) for r in TABLES[table]}
                dup = [r for r in rows if table in KEYS and tuple(r.get(c) for c in KEYS[table]) in have]
                if dup and table == LOOSE:
                    TABLES[table].extend(dict(r, created_at=time.time()) for r in rows if r not in dup)
                if dup:
                    return self.answer(409, {"code": "23505", "message": f"duplicate key value violates unique constraint \"{table}_pkey\""})
                TABLES[table].extend(dict(r, created_at=time.time()) for r in rows)
            return self.answer(201)
        if not reader:
            return self.answer(401, DENIED)
        if self.command != "GET":
            return self.answer(405, {"message": "the stand-in only reads"})
        q = parse_qsl(u.query)
        rows = list(TABLES[table])
        cols, order, limit, offset = None, None, None, 0
        for k, v in q:
            if k == "select":
                cols = None if v == "*" else v.split(",")
            elif k == "order":
                order = [c.split(".")[0] for c in v.split(",")]
            elif k == "limit":
                limit = int(v)
            elif k == "offset":
                offset = int(v)
            elif v.startswith("eq."):
                rows = [r for r in rows if str(r.get(k)) == v[3:]]
            elif v.startswith("in.("):
                want = v[4:-1].split(",")
                rows = [r for r in rows if str(r.get(k)) in want]
        if order:
            rows.sort(key=lambda r: tuple(str(r.get(c)) for c in order))
        rows = rows[offset:offset + limit if limit is not None else None]
        if cols:
            rows = [{c: r.get(c) for c in cols} for r in rows]
        return self.answer(200, rows)

    do_GET = do_POST = do_PATCH = do_DELETE = handle_any


class Server(ThreadingHTTPServer):
    def server_bind(self):
        # HTTPServer.server_bind also looks up the host's name (socket.getfqdn), which nothing
        # here uses and which took 35 seconds per stand-in on the macOS runner.
        TCPServer.server_bind(self)
        self.server_name, self.server_port = self.server_address[:2]


srv = Server(("127.0.0.1", 0), H)
with open(PORTFILE + ".tmp", "w") as f:
    f.write(str(srv.server_address[1]))
import os  # noqa: E402
os.replace(PORTFILE + ".tmp", PORTFILE)
srv.serve_forever()
