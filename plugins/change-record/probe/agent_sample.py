"""transcripts probe: a sample of what an agent's hook passes, holding structure and no content.

Run as a Codex or Cursor hook command, it reads the hook's JSON on stdin and writes
<out>/<agent>-<event>.json: the hook input's keys and value types, the shape of the path it
names, and the shape of the transcript file at that path. It is how the owner shows this
repository what the real agents pass (docs/changes/2026-11-11-codex-cursor-capture.md, C2)
without sending a prompt, an answer, a command, a path, an address or an id anywhere.

What a sample may hold, and nothing else:
  - key names, when they look like field names (KEY); any other key is written "<key>"
  - of a string that is itself JSON, which is content more often than not: its types, and a
    key name only where the name is the agent's and not the session's, which is the first
    level of a tool call's argument string (ARG_KEYS) and the words of an agent's own wrapper
    around a result (WRAPPER_KEYS). No value of it is kept, and a JSON string inside it is
    not opened.
  - the JSON type of every value, counted per key path ("string:2 null:1")
  - values of the fields that name a kind of thing (TYPE_KEYS, VERSION_KEYS, TOOL_KEYS, and
    "name" inside a tool call), when they look like an identifier or a version number
  - how often the fixed phrases in MARKERS occur, per key path
  - counts: lines, bytes, items of each kind, and the order the kinds came in
  - the transcript path with every part replaced by its class (~, <n>, <uuid>, <name>) but
    for the folder and file words in DIRS, WORDS and EXTS
  - the names, never the values, of environment variables starting CODEX_ or CURSOR_

It never fails or slows the session it is hooked into: every problem is one line on stderr and
exit 0, nothing goes to stdout, and it reads at most LIMIT bytes of the transcript.
"""
import json
import os
import re
import subprocess
import sys

VERSION = 1
AGENTS = ("codex", "cursor")
LIMIT = 20 * 1024 * 1024   # bytes of transcript read; AGENT_TRANSCRIPTS_PROBE_BYTES overrides
INPUT_LIMIT = 1024 * 1024  # bytes of hook input read
DEPTH = 12
MAX_VALUES = 30            # distinct kept values per key path
MAX_ORDER = 200            # runs of kinds kept in "order"

KEY = re.compile(r"^[A-Za-z_][A-Za-z0-9_-]{0,39}$")
IDENT = re.compile(r"^[A-Za-z][A-Za-z0-9_.:-]{0,63}$")
VERSION_VALUE = re.compile(r"^\d{1,4}(\.\d{1,6}){1,3}([-+.][A-Za-z0-9]{1,16}){0,3}$")
UUID = re.compile(r"[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}")
HEX_ID = re.compile(r"^(?=.*\d)[0-9a-fA-F-]{8,}$")
TIMESTAMP = re.compile(r"\d{4}-\d{2}-\d{2}T\d{2}[-:]\d{2}[-:]\d{2}(\.\d+)?Z?")

TYPE_KEYS = {"type", "role", "status", "kind", "subtype", "event", "hook_event_name", "originator", "source",
             "model", "permission_mode", "reason", "approval_policy"}
VERSION_KEYS = {"cli_version", "cursor_version", "version"}
TOOL_KEYS = {"tool_name", "toolName", "tool"}
TOOL_CALL_KEYS = {"arguments", "input", "call_id", "tool_input", "args", "parameters", "tool_use_id"}
# A tool call's arguments, when they come as a JSON string: its first-level keys are the tool's parameter names.
ARG_KEYS = {"arguments", "input", "tool_input", "args", "parameters"}
# The words an agent's own wrapper around a tool's result uses. Any other key inside a JSON string is "<key>".
WRAPPER_KEYS = {"output", "metadata", "exit_code", "duration_seconds", "stdout", "stderr", "content", "text", "error",
                "success", "is_error", "result"}
# Fixed phrases whose presence the record's assumptions rest on; counted, case ignored.
MARKERS = ("*** Begin Patch", "*** Update File:", "*** Add File:", "*** Delete File:", "*** Move to:",
           "rejected by user", "<user_query>", "Change: docs/changes/")
# Line starts counted in a transcript that is plain text (a guess at Cursor's; unverified).
TEXT_MARKERS = ("user:", "assistant:", "[Tool call]", "[Tool result]", "[Thinking]")
DIRS = {".codex", ".cursor", ".config", ".local", "sessions", "archived_sessions", "projects", "agent-transcripts",
        "transcripts", "Library", "Application Support", "Cursor", "User", "workspaceStorage", "globalStorage",
        "share", "state", "tmp", "var", "private", "folders"}
WORDS = {"rollout", "transcript", "session", "agent", "chat", "conversation", "composer"}
EXTS = (".jsonl.zst", ".jsonl", ".json", ".txt", ".md", ".log", ".zst", ".db", ".sqlite", ".vscdb")
ZSTD_MAGIC = b"\x28\xb5\x2f\xfd"
SQLITE_MAGIC = b"SQLite format 3\x00"


def say(msg):
    print("transcripts probe: " + msg, file=sys.stderr)


def safe_key(k):
    if isinstance(k, str) and KEY.match(k) and not re.search(r"\d{3,}", k) and not HEX_ID.match(k):
        return k
    return "<key>"


def identifier(v):
    return bool(isinstance(v, str) and IDENT.match(v) and not re.search(r"\d{6,}", v)
                and not UUID.search(v) and not HEX_ID.match(v))


def tool_call(obj):
    t = obj.get("type")
    return bool(TOOL_CALL_KEYS & set(obj)) or (isinstance(t, str) and ("call" in t or "tool" in t))


def kept_value(key, v, in_tool_call):
    """The value itself, for the few fields that name a kind of thing; else None."""
    if not isinstance(v, str):
        return None
    if key in VERSION_KEYS:
        return v if VERSION_VALUE.match(v) else None
    if key in TYPE_KEYS or key in TOOL_KEYS or (key == "name" and in_tool_call):
        return v if identifier(v) else None
    return None


def bump(d, k, n=1):
    d[k] = d.get(k, 0) + n


class Shape:
    """Key paths with the types seen at each, the kept values, and the marker counts."""

    def __init__(self):
        self.paths, self.values, self.markers = {}, {}, {}

    def add(self, v, path="", key=None, in_tool_call=False, depth=0, inside=None):
        """inside: None in the transcript's own JSON; within a string that is itself JSON, "args"
        at the first level of a tool call's argument string and "content" anywhere else."""
        here = path or "."
        types = self.paths.setdefault(here, {})
        if v is None:
            bump(types, "null")
        elif isinstance(v, bool):
            bump(types, "boolean")
        elif isinstance(v, (int, float)):
            bump(types, "number")
        elif isinstance(v, str):
            inner = self.json_in(v)
            if inner is not None:
                bump(types, "json-string")
                if inside is None and depth < DEPTH:  # one level: the agent's wrapper, not what is in it
                    self.add(inner, here + "|json", None, False, depth + 1, "args" if key in ARG_KEYS else "content")
                return
            bump(types, "string")
            kept = kept_value(key, v, in_tool_call) if inside is None else None
            if kept is not None:
                vals = self.values.setdefault(here, {})
                bump(vals, kept if kept in vals or len(vals) < MAX_VALUES else "<more>")
            low = v.lower()
            for m in MARKERS:
                n = low.count(m.lower())
                if n:
                    bump(self.markers.setdefault(here, {}), m, n)
        elif isinstance(v, list):
            bump(types, "array")
            if depth < DEPTH:
                for x in v:
                    self.add(x, here + "[]", key, in_tool_call, depth + 1, inside)
        elif isinstance(v, dict):
            bump(types, "object")
            if depth < DEPTH:
                tc = tool_call(v)
                for k, x in v.items():
                    sk = safe_key(k) if inside in (None, "args") or k in WRAPPER_KEYS else "<key>"
                    self.add(x, (path + "." if path else "") + sk, sk, tc, depth + 1, "content" if inside else None)

    @staticmethod
    def json_in(s):
        t = s.strip()
        if not (t[:1] in "{[" and t[-1:] in "}]"):
            return None
        try:
            v = json.loads(t)
        except ValueError:
            return None
        return v if isinstance(v, (dict, list)) else None

    def out(self):
        d = {"paths": {p: " ".join("%s:%d" % (t, n) for t, n in sorted(ts.items())) for p, ts in self.paths.items()}}
        if self.values:
            d["values"] = self.values
        if self.markers:
            d["markers"] = self.markers
        return d


def kind_of(item):
    """What kind of line this is: its type or role, then that of the object it wraps."""
    if not isinstance(item, dict):
        return "<" + type(item).__name__ + ">"
    def name(o):
        for k in ("type", "role"):
            if identifier(o.get(k)):
                return o[k]
        return None
    parts = [name(item) or "-"]
    for k in ("payload", "item", "message"):
        if isinstance(item.get(k), dict):
            inner = name(item[k])
            if inner:
                parts.append(inner)
            break
    return "/".join(parts)


def path_shape(path, home, cwd):
    """The path with every part replaced by its class, but for known folder and file words."""
    p = os.path.normpath(path)
    lead = ""
    for name, base in (("<cwd>", cwd), ("~", home)):
        if base and (p == base or p.startswith(base.rstrip("/") + "/")):
            lead, p = name, p[len(base.rstrip("/")):]
            break
    segs = [s for s in p.split("/") if s]
    if not segs:
        return lead or "/"

    def folder(s):
        if s in DIRS:
            return s
        if s.isdigit():
            return "<n>"
        return "<uuid>" if UUID.fullmatch(s) else "<name>"

    base = segs[-1]
    ext = next((e for e in EXTS if base.endswith(e)), None)
    if ext:
        stem = base[:-len(ext)]
    elif "." in base.strip("."):
        stem, ext = base.rsplit(".", 1)[0], ".<ext>"
    else:
        stem, ext = base, ""
    stem = UUID.sub("\x00uuid\x00", TIMESTAMP.sub("\x00timestamp\x00", stem))
    out = []
    for i, chunk in enumerate(stem.split("\x00")):
        if i % 2:
            out.append("<" + chunk + ">")
            continue
        for tok in re.split(r"([-_.])", chunk):
            if tok in ("", "-", "_", "."):
                out.append(tok)
            elif tok.isdigit():
                out.append("<n>")
            else:
                out.append(tok if tok in WORDS else "<name>")
    return lead + "/" + "/".join([folder(s) for s in segs[:-1]] + ["".join(out) + ext])


def read_limit():
    try:
        return max(1, int(os.environ.get("AGENT_TRANSCRIPTS_PROBE_BYTES", "")))
    except ValueError:
        return LIMIT


def transcript_shape(path):
    """What the file at path is made of: format, counts, and for JSON its kinds and shapes."""
    limit = read_limit()
    with open(path, "rb") as f:
        data = f.read(limit + 1)
    size = os.path.getsize(path)
    t = {"bytes": size, "truncated": len(data) > limit}
    data = data[:limit]
    if data.startswith(ZSTD_MAGIC):
        return dict(t, format="zstd", truncated=False)
    if data.startswith(SQLITE_MAGIC):
        return dict(t, format="sqlite", truncated=False)
    if not data.strip():
        return dict(t, format="empty")
    if b"\x00" in data:
        return dict(t, format="binary")
    text = data.decode("utf-8", "replace")
    lines = text.split("\n")
    last = lines.pop()   # what follows the last newline: nothing, or a line still being written
    items, not_json = [], 0
    for ln in lines:
        if ln.strip():
            try:
                items.append(json.loads(ln))
            except ValueError:
                not_json += 1
    incomplete = False
    if last.strip() and not t["truncated"]:
        try:
            items.append(json.loads(last))
            lines.append(last)
        except ValueError:
            incomplete = True
            if not items:   # no newline at the end of a file that is not JSON lines
                not_json += 1
                lines.append(last)
    whole = None
    if not_json and not t["truncated"]:
        try:
            whole = json.loads(text)
        except ValueError:
            pass
    if whole is not None:
        t["format"] = "json"
        t["top"] = "array" if isinstance(whole, list) else type(whole).__name__ if not isinstance(whole, dict) else "object"
        items, not_json = (whole if isinstance(whole, list) else [whole]), 0
    elif len(items) > not_json:
        t.update(format="jsonl", lines=len([ln for ln in lines if ln.strip()]), not_json=not_json,
                 incomplete_last_line=incomplete)
    else:
        marks = {}
        low = text.lower()
        for m in MARKERS:
            if low.count(m.lower()):
                marks[m] = low.count(m.lower())
        starts = {}
        for ln in lines:
            for m in TEXT_MARKERS:
                if ln.strip().lower().startswith(m.lower()):
                    bump(starts, m)
        return dict(t, format="text", lines=len(lines), blank_lines=len([ln for ln in lines if not ln.strip()]),
                    json_lines=len(items), markers=marks, line_starts=starts)
    kinds, order, more = {}, [], False
    for it in items:
        k = kind_of(it)
        if k not in kinds:
            kinds[k] = {"count": 0, "shape": Shape()}
        kinds[k]["count"] += 1
        kinds[k]["shape"].add(it)
        if order and order[-1][0] == k:
            order[-1][1] += 1
        elif len(order) < MAX_ORDER:
            order.append([k, 1])
        else:
            more = True
    t["kinds"] = {k: dict(v["shape"].out(), count=v["count"]) for k, v in kinds.items()}
    t["order"] = ["%s x%d" % (k, n) for k, n in order] + (["<more>"] if more else [])
    return t


def same_dir(a, b):
    try:
        return os.path.realpath(a) == os.path.realpath(b)
    except (OSError, ValueError):
        return False


def environment(hook):
    here = os.getcwd()
    where = "elsewhere"
    if isinstance(hook.get("cwd"), str) and same_dir(here, hook["cwd"]):
        where = "cwd"
    elif isinstance(hook.get("workspace_roots"), list) and any(
            isinstance(r, str) and same_dir(here, r) for r in hook["workspace_roots"]):
        where = "workspace_roots"
    try:
        r = subprocess.run(["git", "rev-parse", "--is-inside-work-tree"], capture_output=True, text=True, timeout=5)
        in_git = r.returncode == 0 and r.stdout.strip() == "true"
    except (OSError, subprocess.SubprocessError):
        in_git = False
    names = sorted(k for k in os.environ if re.match(r"^(CODEX|CURSOR)_[A-Z0-9_]{1,60}$", k))
    return {"process_cwd": where, "in_git_work_tree": in_git, "variables": names}


def sample(agent, hook):
    s = Shape()
    s.add(hook)
    ev = hook.get("hook_event_name")
    event = ev.lower() if isinstance(ev, str) and re.match(r"^[A-Za-z]{1,40}$", ev) else "unknown"
    doc = {"probe": VERSION, "agent": agent, "event": event, "hook_input": s.out(), "environment": environment(hook)}
    path = hook.get("transcript_path")
    if not isinstance(path, str) or not path:
        say("no transcript file given (transcript_path is " + ("null" if path is None else "not a path") + ")")
        doc["transcript"] = {"given": False}
        return doc
    path = os.path.expanduser(path)
    home = os.path.expanduser("~")
    cwd = hook.get("cwd") if isinstance(hook.get("cwd"), str) else None
    ids = [hook[k] for k in ("session_id", "conversation_id") if isinstance(hook.get(k), str) and hook[k]]
    t = {"given": True, "path_shape": path_shape(path, home if home != "~" else None, cwd),
         "name_holds_session_id": any(i in os.path.basename(path) for i in ids), "exists": os.path.isfile(path)}
    if not t["exists"]:
        say("the transcript file the hook names does not exist")
    else:
        try:
            t.update(transcript_shape(path))
        except OSError as e:
            say("cannot read the transcript file: " + (e.strerror or "error"))
            t["read_error"] = True
    doc["transcript"] = t
    return doc


def default_out():
    return os.path.normpath(os.path.join(os.path.dirname(os.path.realpath(__file__)), "..", "grade", "fixtures", "agents"))


def run(args):
    agent, out, i = None, None, 0
    while i < len(args):
        if args[i] in ("--agent", "--out") and i + 1 < len(args):
            if args[i] == "--agent":
                agent = args[i + 1]
            else:
                out = args[i + 1]
            i += 2
        else:
            say("usage: transcripts probe --agent codex|cursor [--out DIR]")
            return
    if agent not in AGENTS:
        say("usage: transcripts probe --agent codex|cursor [--out DIR]")
        return
    try:
        hook = json.loads(sys.stdin.buffer.read(INPUT_LIMIT).decode("utf-8", "replace"))
    except ValueError:
        hook = None
    if not isinstance(hook, dict):
        say("no hook input on stdin (a JSON object was expected); nothing written")
        return
    doc = sample(agent, hook)
    out = out or default_out()
    dest = os.path.join(out, "%s-%s.json" % (agent, doc["event"]))
    try:
        os.makedirs(out, exist_ok=True)
        tmp = dest + ".tmp%d" % os.getpid()
        with open(tmp, "w") as f:
            f.write(json.dumps(doc, indent=2, sort_keys=True) + "\n")
        os.replace(tmp, dest)
    except OSError as e:
        say("cannot write the sample to " + out + ": " + (e.strerror or "error"))
        return
    say("wrote " + dest)


def main(args):
    try:
        run(args)
    except Exception as e:  # a hook: never fail the session, and never echo what was read
        say("gave up: " + type(e).__name__)
    return 0
