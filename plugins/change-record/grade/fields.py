"""fields: the deterministic graders for one agent session against the change skill's steps.

Generalised from the eval graders (plugins/change-record/evals/*/graders): those name their
case's own code file and record, these work on any session (record
docs/changes/2026-11-09-skill-transcripts.md, R8 and R9, and its Decisions). The caller gives
the transcript's lines and, when it has them, the record as it stood at the session's first and
last commit; `grade()` returns one verdict per step: pass, fail or not_applicable, with evidence.

Rules every grader shares:

  * Only the session's own acts count: its tool calls, and text it wrote. A prompt or a tool
    result can quote anything.
  * A call counts as run only when its own result, matched by tool id, is there and is not a
    denial (a permission prompt refused or never answered, an interruption, a tool error),
    flagged or not. A flagged Bash result that is not a denial is a command that ran and failed;
    a flagged result of any other tool means it did nothing. A call with no result never ran.
  * A test run failed when its own result reports a failed test, from the flag or from the
    text alone (a run piped through `tail` exits 0).
  * Code is any file under the session's working tree except docs/, *.md and the like, test
    files and folders, and backups; a file outside the tree is not code.
"""
import json
import os
import re
import shlex

STEPS = ["tier-declared", "probe-before-record", "record-before-code", "red-first", "change-line",
         "record-check", "outcome-filled"]
RECORD_STEPS = {"probe-before-record", "record-before-code", "change-line", "record-check", "outcome-filled"}
PASS, FAIL, NA = "pass", "fail", "not_applicable"

RECORD = re.compile(r"^docs/changes/(?!README\.md$|TEMPLATE\.md$)[^/\s]+\.md$")
CHANGE_LINE = re.compile(r"^Change: (docs/changes/[^/\s]+\.md)[ \t]*$", re.M)
TIER0 = re.compile(r"\**Tier\**\s*:\s*\**\s*0(?!\d)")  # the eval grader declares-tier-0's pattern
DENIAL = re.compile(r"^\s*(?:<tool_use_error>)?\s*(?:This (?:Bash )?command (?:requires approval|contains multiple operations"
                    r"|changes directory)|Permission to use \S+ (?:with .*)?has been denied|The user doesn't want to"
                    r"|Claude requested permissions? to|\[Request interrupted|<tool_use_error>)", re.S)


class Unparsable(Exception):
    pass


# ---- reading a transcript ------------------------------------------------------------------

class Call:
    def __init__(self, n, cid, name, inp, cwd):
        self.n, self.id, self.name, self.input, self.cwd = n, cid, name, inp if isinstance(inp, dict) else {}, cwd
        self.result, self.is_error = None, None

    @property
    def status(self):
        """ran, failed (ran, exit code non-zero), or not_run (denied, refused or never answered)."""
        if self.result is None:
            return "not_run"
        if DENIAL.match(self.result):
            return "not_run"
        if self.is_error:
            return "failed" if self.name == "Bash" else "not_run"
        return "ran"

    @property
    def ran(self):
        return self.status != "not_run"


def text_of(content):
    if isinstance(content, str):
        return content
    if isinstance(content, list):
        return "\n".join(text_of(b.get("text") if isinstance(b, dict) and b.get("type") == "text" else
                                 b.get("content") if isinstance(b, dict) else b) for b in content)
    return "" if content is None else str(content)


def read(lines):
    """Calls and the session's own texts, in order; raises Unparsable on a line that is not JSON."""
    calls, texts, pending, n, first_cwd = [], [], {}, 0, None
    for i, raw in enumerate(lines, 1):
        if isinstance(raw, bytes):
            raw = raw.decode("utf-8", "replace")
        if not raw.strip():
            continue
        try:
            d = json.loads(raw)
        except ValueError:
            raise Unparsable(f"line {i} of the transcript is not JSON")
        if not isinstance(d, dict) or d.get("isSidechain") or d.get("type") not in ("assistant", "user"):
            continue
        first_cwd = first_cwd or d.get("cwd")
        content = (d.get("message") or {}).get("content")
        for b in content if isinstance(content, list) else []:
            if not isinstance(b, dict):
                continue
            n += 1
            if d["type"] == "assistant" and b.get("type") == "text":
                texts.append((n, b.get("text") or ""))
            elif d["type"] == "assistant" and b.get("type") == "tool_use":
                c = Call(n, b.get("id"), b.get("name"), b.get("input"), d.get("cwd"))
                calls.append(c)
                pending.setdefault(c.id, []).append(c)
            elif d["type"] == "user" and b.get("type") == "tool_result":
                waiting = pending.get(b.get("tool_use_id")) or []
                if waiting:
                    c = waiting.pop(0)
                    c.result, c.is_error = text_of(b.get("content")), bool(b.get("is_error"))
    return calls, texts, first_cwd


# ---- paths -------------------------------------------------------------------------------

def rel(path, base, root):
    """The path relative to the working tree, or None when it is outside it."""
    if not path or not root:
        return None
    path = os.path.expanduser(path)
    full = os.path.normpath(path if os.path.isabs(path) else os.path.join(base or root, path))
    root = os.path.normpath(root)
    if full == root or not full.startswith(root.rstrip("/") + "/"):
        return None
    return os.path.relpath(full, root)


TEST_DIRS = {"test", "tests", "__tests__", "spec", "specs", "fixtures", "testdata", "evals"}


def kind(r):
    """record, doc, test, other (not code) or code, for a path relative to the working tree."""
    if r is None:
        return "other"
    parts = r.split("/")
    base = parts[-1]
    if RECORD.match(r):
        return "record"
    if parts[0] in (".git",) or base.endswith((".bak", ".orig", "~", ".pyc")) or "__pycache__" in parts:
        return "other"
    if parts[0] == "docs" or re.search(r"\.(md|markdown|rst|txt|adoc)$", base, re.I):
        return "doc"
    if TEST_DIRS & set(parts[:-1]) or re.match(r"(?:test_.*|.*_test\.[^.]+|.*[.-](?:test|spec)\.[^.]+(?:\.[^.]+)?)$", base):
        return "test"
    return "code"


# ---- shell commands ----------------------------------------------------------------------

OPS = {";", "&&", "||", "|", "&", "(", ")", "|&", ";;"}
WRITE_REDIRECTS = {">", ">>", "&>", "&>>", ">|"}


def strip_heredocs(cmd):
    out, lines, i = [], cmd.split("\n"), 0
    while i < len(lines):
        ln = lines[i]
        out.append(ln)
        i += 1
        for _, d in re.findall(r"<<-?\s*(['\"]?)(\w+)\1", ln):
            while i < len(lines) and lines[i].strip() != d:
                i += 1
            i += 1
    return "\n".join(out)


def heredoc_bodies(cmd):
    return [m.group(3) for m in re.finditer(r"<<-?\s*(['\"]?)(\w+)\1[^\n]*\n(.*?)\n\s*\2\s*(?:\n|$)", cmd, re.S)]


def simple_commands(cmd):
    """[(argv, [(redirect op, target)])] for each simple command, heredoc bodies left out."""
    s = strip_heredocs(cmd).replace("\n", " ; ")
    try:
        lex = shlex.shlex(s, posix=True, punctuation_chars=True)
        lex.whitespace_split = True
        toks = list(lex)
    except ValueError:
        toks = s.split()
    cmds, argv, redir, i = [], [], [], 0
    while i < len(toks):
        t = toks[i]
        if t in OPS:
            if argv or redir:
                cmds.append((argv, redir))
            argv, redir = [], []
        elif re.fullmatch(r"\d*(?:>>?|&>>?|>\||<|<<-?|<<<|>&|<&)", t):
            op = t.lstrip("0123456789")
            target = toks[i + 1] if i + 1 < len(toks) else ""
            if op in WRITE_REDIRECTS and target not in OPS:
                redir.append((op, target))
            i += 1
        elif not argv and re.match(r"^[A-Za-z_][A-Za-z0-9_]*=", t):
            pass  # an environment assignment before the command
        else:
            argv.append(t)
        i += 1
    if argv or redir:
        cmds.append((argv, redir))
    # `2>/dev/null` lexes as `2` `>`: drop a bare fd number left as the last argument before it
    return [([a for a in av if not re.fullmatch(r"\d", a)] if rd else av, rd) for av, rd in cmds]


def unwrap(argv):
    """The command under env, timeout, nice, sudo, time, uv run, poetry run, npx and the like."""
    while argv:
        b = os.path.basename(argv[0])
        if b in ("env", "nice", "nohup", "sudo", "time", "command", "exec"):
            argv = [a for a in argv[1:]]
            while argv and (argv[0].startswith("-") or "=" in argv[0]):
                argv = argv[1:]
        elif b == "timeout":
            argv = argv[1:]
            while argv and (argv[0].startswith("-") or re.fullmatch(r"[\d.]+[smhd]?", argv[0])):
                argv = argv[1:]
        elif b in ("uv", "poetry", "pdm", "pipenv", "hatch") and len(argv) > 1 and argv[1] == "run":
            argv = argv[2:]
        elif b in ("npx", "bunx", "pnpx"):
            argv = argv[1:]
        else:
            return argv
    return argv


def shell_writes(cmd, base):
    """[(path, base)] of the files a command writes: redirects, tee, cp, mv, install, sed -i."""
    out = []
    for argv, redir in simple_commands(cmd):
        argv = unwrap(argv)
        for _, t in redir:
            if not t.startswith("/dev/"):
                out.append((t, base))
        if not argv:
            continue
        b = os.path.basename(argv[0])
        args = [a for a in argv[1:] if not a.startswith("-")]
        if b == "cd" and args:
            base = os.path.normpath(os.path.join(base or "/", os.path.expanduser(args[0])))
        elif b == "tee":
            out += [(a, base) for a in args]
        elif b in ("cp", "mv", "install") or (b == "git" and argv[1:2] == ["mv"]):
            if b == "git":
                args = args[1:]
            if len(args) >= 2:
                dest = args[-1]
                if dest.endswith("/") or dest in (".", ".."):
                    out += [(os.path.join(dest, os.path.basename(s)), base) for s in args[:-1]]
                else:
                    out.append((dest, base))
        elif b in ("sed", "gsed") and any(a.startswith("-i") or a == "--in-place" or re.fullmatch(r"-[a-hj-zE]*i\S*", a)
                                           for a in argv[1:]):
            pos, skip, script_given = [], False, False
            for a in argv[1:]:
                if skip:
                    skip = False
                    continue
                if a in ("-e", "--expression", "-f", "--file"):
                    skip, script_given = True, True
                elif not a.startswith("-"):
                    pos.append(a)
            out += [(a, base) for a in (pos if script_given else pos[1:])]
    return out


INTERPRETERS = re.compile(r"^(?:python(?:\d(?:\.\d+)?)?|node|nodejs|deno|bun|ruby|perl|php)$")


def is_test_command(argv):
    argv = unwrap(argv)
    if not argv:
        return False
    b, rest = os.path.basename(argv[0]), argv[1:]
    if INTERPRETERS.match(b):
        if b.startswith("python") and "-m" in rest:
            i = rest.index("-m")
            return i + 1 < len(rest) and rest[i + 1] in ("unittest", "pytest", "nose2", "tox", "nox")
        if b in ("node", "nodejs", "deno", "bun") and rest[:1] == ["test"] or "--test" in rest:
            return True
        return any(kind(a) == "test" and not a.startswith("-") for a in rest[:1])
    if b in ("pytest", "py.test", "jest", "vitest", "mocha", "ava", "tap", "rspec", "tox", "nox", "ctest", "phpunit", "bats"):
        return True
    if b in ("npm", "yarn", "pnpm", "bun") and rest and (rest[0] in ("test", "t") or (rest[0] == "run" and rest[1:2] and
                                                                                     rest[1].startswith("test"))):
        return True
    if b in ("go", "cargo", "dotnet", "mvn", "gradle", "./gradlew", "mix", "swift", "zig") and "test" in rest[:2]:
        return True
    if b in ("make", "gmake") and any(a in ("test", "check", "tests") for a in rest):
        return True
    if b in ("bash", "sh", "zsh") and rest:
        script = next((a for a in rest if not a.startswith("-")), "")
        return bool(re.search(r"(?:^|/)(?:test[^/]*|[^/]*[.-]test)\.(?:sh|bash)$", script))
    return bool(re.search(r"(?:^|/)(?:test[^/]*|[^/]*[.-]test)\.(?:sh|bash)$", argv[0]))


TEST_FAILED = re.compile(
    r"FAILED \(|AssertionError|^(?:FAIL|ERROR): \w|\b[1-9]\d* (?:failed|failing)\b|^# fail [1-9]|^not ok \d"
    r"|^--- FAIL|^FAIL\s|test result: FAILED|\b[1-9]\d* failures?\b|^\s*FAIL\b|Tests?:\s+[1-9]\d* failed", re.M)


def probe_command(argv, base, root):
    """A command that tries something out: an interpreter on inline code, stdin, a module or a
    script outside the working tree's code, pydoc, --help or --version, or a request to another
    system. Running a test suite, or the repository's own program, is not a probe."""
    argv = unwrap(argv)
    if not argv or is_test_command(argv):
        return False
    b, rest = os.path.basename(argv[0]), argv[1:]
    if b in ("pydoc", "pydoc3", "curl", "wget", "http", "https", "claude") or (b == "gh" and rest[:1] == ["api"]):
        return True
    if any(a in ("--help", "-h", "--version", "-V") for a in rest[:2]):
        return True
    if INTERPRETERS.match(b):
        opts = [a for a in rest if a.startswith("-")]
        if any(o in ("-c", "-e", "-p", "-", "--eval", "--print", "-m") or re.fullmatch(r"-[A-Za-z]*[cep]", o) for o in opts):
            return True
        script = next((a for a in rest if not a.startswith("-")), None)
        if script is None:
            return True  # reads its program from stdin
        return kind(rel(script, base, root)) != "code"
    return False


# ---- the session's acts -------------------------------------------------------------------

FILE_TOOLS = ("Write", "Edit", "MultiEdit", "NotebookEdit")


def writes(call, root):
    """The paths, relative to the working tree, a call wrote (only if it ran)."""
    if not call.ran:
        return []
    inp, base = call.input, call.cwd or root
    if call.name in FILE_TOOLS:
        return [rel(inp.get("file_path") or inp.get("notebook_path") or "", base, root)]
    if call.name == "Bash":
        return [rel(p, b, root) for p, b in shell_writes(str(inp.get("command") or ""), base)]
    if call.name.startswith("mcp__") and call.name.endswith(("create_or_update_file", "push_files")):
        paths = [inp.get("path")] + [f.get("path") for f in inp.get("files") or [] if isinstance(f, dict)]
        return [p.lstrip("/") for p in paths if isinstance(p, str) and p]
    return []


def pr_bodies(calls, root):
    """[(call number, body)] of the pull request descriptions the session opened or wrote, in order."""
    out, files = [], {}
    for c in calls:
        if not c.ran:
            continue
        inp = c.input
        if c.name in ("Write",) and isinstance(inp.get("content"), str):
            files[os.path.normpath(os.path.join(c.cwd or root or "/", inp.get("file_path") or ""))] = inp["content"]
            if re.match(r"(?i)^(?:pr|pull[-_ ]?request)(?:[-_.](?:body|description|desc|text))?\.(?:md|txt)$",
                        os.path.basename(inp.get("file_path") or "")):
                out.append((c.n, inp["content"]))
        elif c.name.startswith("mcp__") and re.search(r"(?:create|update)_pull_request$", c.name) and isinstance(inp.get("body"), str):
            out.append((c.n, inp["body"]))
        elif c.name == "Bash":
            cmd = str(inp.get("command") or "")
            if not re.search(r"\bgh\s+pr\s+(?:create|edit)\b", cmd):
                continue
            body = None
            m = re.search(r"--body-file[ =](\S+)", cmd)
            if m:
                body = files.get(os.path.normpath(os.path.join(c.cwd or root or "/", m.group(1).strip("'\""))))
            elif heredoc_bodies(cmd) and re.search(r"(?:--body|-b)[ =]+\"?\$\(", cmd):
                body = heredoc_bodies(cmd)[0]
            else:
                for argv, _ in simple_commands(cmd):
                    for i, a in enumerate(argv[:-1]):
                        if a in ("--body", "-b"):
                            body = argv[i + 1]
                    for a in argv:
                        if a.startswith("--body="):
                            body = a[len("--body="):]
            if body is not None:
                out.append((c.n, body))
    return out


def choose_record(written, named):
    both = [x for x in written if x in named]
    if len(both) == 1:
        return both[0]
    if both or (written and named):
        return None
    one = written or named
    return one[0] if len(one) == 1 else None


# ---- the record --------------------------------------------------------------------------

def frontmatter(text):
    if not text or not text.startswith("---\n"):
        return {}, []
    end = text.find("\n---", 4)
    fm = text[4:end] if end > 0 else ""
    fields = {}
    for ln in fm.splitlines():
        m = re.match(r"^([A-Za-z_]+):\s*(.*?)\s*(?:#.*)?$", ln)
        if m:
            fields[m.group(1)] = m.group(2)
    done = len(re.findall(r"^\s+done:\s*true\s*$", fm, re.M))
    return fields, done


def outcome_lines(text):
    m = re.search(r"^## Outcome[ \t]*\n(.*?)(?=^## |\Z)", text or "", re.M | re.S)
    body = re.sub(r"<!--.*?-->", "", m.group(1), flags=re.S) if m else ""
    return [ln for ln in body.splitlines() if ln.strip() and not ln.startswith("Filled at the end:")]


# ---- grading -----------------------------------------------------------------------------

def grade(lines, root=None, record_at_first=None, record_at_last=None, record_check=None):
    """Verdicts for one session.

    lines: the transcript's lines. root: the session's working tree (default: the first cwd).
    record_at_first(path) / record_at_last(path): the record's text at the session's first and
    last commit, or None if it is not there, or raise LookupError(reason) when that cannot be
    known (no commit, or a commit the repository lacks). record_check(path): (verdict, evidence)
    from running record-check on the session's commits, or raise LookupError(reason).
    Returns (record, [(step, verdict, evidence)]).
    """
    calls, texts, first_cwd = read(lines)
    root = os.path.normpath(root or first_cwd or "/")
    wrote = [(c, [w for w in writes(c, root) if w]) for c in calls]

    # which record: one the session wrote (a write that ran) or named on a Change: line of its own
    written, named = [], []
    for c, ws in wrote:
        for w in ws:
            if kind(w) == "record" and w not in written:
                written.append(w)
    for _, t in texts:
        for m in CHANGE_LINE.finditer(t):
            if m.group(1) not in named:
                named.append(m.group(1))
    for _, body in pr_bodies(calls, root):
        for m in CHANGE_LINE.finditer(body):
            if m.group(1) not in named:
                named.append(m.group(1))
    record = choose_record(written, named)
    base_ev = {"record": record, "records_written": written, "records_named": named}

    code_calls = [c for c, ws in wrote if any(kind(w) == "code" for w in ws)]
    first_code = code_calls[0].n if code_calls else None
    code_ev = {"first_code_write": None if not code_calls else
               {"call": code_calls[0].id, "files": [w for w in writes(code_calls[0], root) if kind(w) == "code"]}}
    tier0 = any(TIER0.search(t) for _, t in texts) or any(TIER0.search(b) for _, b in pr_bodies(calls, root))

    out = {}

    def put(step, verdict, why, **ev):
        out[step] = (verdict, dict(base_ev, why=why, **ev))

    # the record's text at the first and last commit, when there is one
    last_text = last_err = first_text = None
    first_known = False
    if record:
        try:
            last_text = record_at_last(record) if record_at_last else None
            if record_at_last is None:
                last_err = "no commit for the session"
        except LookupError as e:
            last_err = str(e)
        try:
            if record_at_first:
                first_text = record_at_first(record)
                first_known = True
        except LookupError:
            pass

    # tier-declared
    if record:
        if last_err:
            put("tier-declared", NA, f"the record cannot be read: {last_err}", error=last_err)
        elif last_text is None:
            put("tier-declared", FAIL, f"{record} is not in the session's last commit")
        else:
            tier = frontmatter(last_text)[0].get("tier")
            put("tier-declared", PASS if tier in ("0", "1", "2") else FAIL, f"tier {tier or 'missing'}", tier=tier)
    elif tier0:
        put("tier-declared", PASS, "no record, and the session declares Tier: 0", tier="0")
    elif first_code is not None:
        put("tier-declared", FAIL, "code written with no record and no Tier: 0", **code_ev)
    else:
        put("tier-declared", NA, "no record and no code written")

    # did the record exist before the session? yes if its first commit holds it, or if the
    # session's first act on it shows it there (a Read or Edit that ran, a Write that updated):
    # a record can sit uncommitted in the working tree
    existed = False
    if record:
        existed = first_known and first_text is not None
        for c in calls:
            p = rel(c.input.get("file_path") or "", c.cwd or root, root) if c.name in ("Read",) + FILE_TOOLS else None
            if p == record and c.ran:
                existed = existed or c.name in ("Read", "Edit", "MultiEdit") or "has been updated" in (c.result or "")
                break
            if record in writes(c, root):
                break
    record_writes = [c for c, ws in wrote if record and record in ws]
    first_record = record_writes[0].n if record_writes else None

    # probe-before-record and record-before-code: only for a record this session wrote first
    if not record:
        for s in ("probe-before-record", "record-before-code"):
            put(s, NA, "no record")
    elif not record_writes:
        for s in ("probe-before-record", "record-before-code"):
            put(s, NA, "the session did not write the record")
    elif existed:
        for s in ("probe-before-record", "record-before-code"):
            put(s, NA, "the record was there when the session started")
    else:
        probes = [c for c in calls if c.n < first_record and c.ran and (
            (c.name == "Bash" and any(probe_command(av, c.cwd or root, root) for av, _ in simple_commands(str(c.input.get("command") or ""))))
            or c.name in ("WebFetch", "WebSearch") or c.name.startswith("mcp__"))]
        put("probe-before-record", PASS if probes else FAIL,
            f"{len(probes)} probes ran before the record was first written" if probes else "no probe ran before the record was first written",
            probes=[c.id for c in probes][:10], first_record_write=record_writes[0].id)
        if first_code is None:
            put("record-before-code", NA, "no code written", first_record_write=record_writes[0].id)
        else:
            put("record-before-code", PASS if first_record < first_code else FAIL,
                "the record was written before the first code" if first_record < first_code else "code was written before the record",
                first_record_write=record_writes[0].id, **code_ev)

    # red-first: a test run that ran, and failed, before the first code write
    rec_tier = frontmatter(last_text)[0].get("tier") if last_text else None
    if first_code is None:
        put("red-first", NA, "no code written")
    elif (not record and tier0) or rec_tier == "0":
        put("red-first", NA, "tier 0: no test needed")
    else:
        tests = [c for c in calls if c.n < first_code and c.name == "Bash"
                 and any(is_test_command(av) for av, _ in simple_commands(str(c.input.get("command") or "")))]
        ran = [c for c in tests if c.ran]
        red = [c for c in ran if TEST_FAILED.search(c.result or "")]
        put("red-first", PASS if red else FAIL,
            f"a test run failed before the code ({red[0].id})" if red else
            "no test run that ran failed before the code" if ran else "no test ran before the code",
            test_runs_before_code=len(ran), denied_test_runs=len(tests) - len(ran),
            failing_runs=[c.id for c in red][:10], **code_ev)

    # change-line: the PR description's first line names the record
    if not record:
        put("change-line", NA, "no record")
    else:
        bodies = pr_bodies(calls, root)
        want = re.compile(r"^[*_`]*Change[*_`]*:\s*[*_`]*" + re.escape(record) + r"[*_`]*\s*$")
        if bodies:
            body = bodies[-1][1]
            first = next((ln for ln in body.splitlines() if ln.strip()), "")
            put("change-line", PASS if want.match(first.strip()) else FAIL,
                "the PR description opens with the Change: line" if want.match(first.strip()) else
                f"the PR description opens with {first.strip()[:80]!r}", source="pull request")
        else:
            last = texts[-1][1] if texts else ""
            lines_c = [ln.strip() for ln in last.splitlines() if re.match(r"^\W*Change\W*:", ln.strip())]
            if lines_c:
                good = any(want.match(ln) for ln in lines_c)
                put("change-line", PASS if good else FAIL,
                    "the description in the last message has the Change: line on its own" if good else
                    f"the last message's Change: line is {lines_c[0][:80]!r}", source="last message")
            else:
                put("change-line", NA, "the session opened no pull request and wrote no description")

    # record-check, at the session's commits
    if not record:
        put("record-check", NA, "no record")
    elif record_check is None:
        put("record-check", NA, "no commit for the session")
    else:
        try:
            verdict, ev = record_check(record)
            put("record-check", verdict, ev.pop("why", ""), **ev)
        except LookupError as e:
            put("record-check", NA, f"cannot run record-check: {e}", error=str(e))

    # outcome-filled, when the record is done or the session marked a task done
    if not record:
        put("outcome-filled", NA, "no record")
    elif last_err or last_text is None:
        put("outcome-filled", NA, f"the record cannot be read: {last_err or 'not in the last commit'}")
    else:
        fields, done_last = frontmatter(last_text)
        done_first = frontmatter(first_text)[1] if first_text else 0
        done = fields.get("status") == "done" or done_last > done_first
        if not done:
            put("outcome-filled", NA, f"the record is {fields.get('status') or 'without a status'} and no task was marked done")
        else:
            n = len(outcome_lines(last_text))
            put("outcome-filled", PASS if n else FAIL, f"Outcome has {n} lines" if n else "the record is done and its Outcome is empty",
                outcome_lines=n)

    return record, [(s,) + out[s] for s in STEPS]


def code_written(lines, root=None):
    """Whether the session wrote code, by the same rules as the graders (for the judge, C3)."""
    calls, _, first_cwd = read(lines)
    root = os.path.normpath(root or first_cwd or "/")
    return any(kind(w) == "code" for c in calls for w in writes(c, root) if w)


def commands_run(lines):
    """The first line of each shell command that ran, in order (for the judge's Outcome question)."""
    calls, _, _ = read(lines)
    return [str(c.input.get("command") or "").strip().splitlines()[0][:200] for c in calls
            if c.name == "Bash" and c.ran and str(c.input.get("command") or "").strip()]
