"""review: the defects a reviewer that runs the code can show (record
docs/changes/2026-11-15-checkable-judges.md, R2, R3 and R7).

A measure, not a verdict. For a session's own commits, base..last, a fresh Claude session with a
shell, Read, Grep and Glob is given the brief in briefs/review.md, which demands a method, in a
scratch clone that holds the history up to the last commit and nothing else: no remote, no ref,
no later commit. It runs in Claude Code's sandbox, with reading the repository and the archive
denied; before the first review of a run one Haiku call checks that the sandbox holds.

The reviewer leaves each defect as a script, .review/<name>.sh. Nothing it says is taken on
trust. The tool copies the scripts out and runs each one itself, from the root of a clean clone,
at the last commit and at the base. A defect is shown only if its script exits 0 at the last
commit and not at the base, in time, and leaves the clone as it was. A script that passes
everywhere, or shows something the session inherited, is not a defect of the session.

The scripts are a model's shell commands, so they run in a box (bwrap): no network, the file
system read-only but for the clone and an empty /tmp, the clone's .git read-only too, the
repository, the archive and the home folder hidden, the environment cleared. Where no box can be
started the caller has to say --local, and they run with the caller's own access.

The tool runs no git in a folder a script has been in. A script can write its clone's git
configuration, and git runs commands that configuration names (core.fsmonitor on a status):
that would be the script's command, run by the tool, outside the box. So each script gets a copy
of the clean clone to run in, the copy is compared with the clean clone by reading its files,
and it is thrown away. What a script prints is read as it comes and only its end is kept.

A shown defect's id is the first six hex digits of the SHA-256 of its script, so that a person's
ruling names the defect and not its place in a list.
"""
import collections
import hashlib
import json
import os
import re
import secrets
import select
import shlex
import shutil
import signal
import subprocess
import time

import judge

MEASURE = "review/1"  # bump when what counts as shown changes; a changed brief is seen by its hash
MODELS = ("sonnet", "opus")
BUDGET = 1.5          # dollars one review may spend
CHECK_BUDGET = 0.05   # and the sandbox check
MAX_SESSIONS = 10     # reviews in one run
REVIEW_LIMIT = 1200   # seconds for a reviewer; AGENT_TRANSCRIPTS_REVIEW_LIMIT overrides
SCRIPT_LIMIT = 120    # seconds for one run of a script; AGENT_TRANSCRIPTS_SCRIPT_LIMIT overrides
MAX_SCRIPTS, MAX_SCRIPT_BYTES, OUTPUT_CAP = 20, 100_000, 20_000
TOOLS = ["Bash", "Read", "Grep", "Glob"]
KINDS = ("wrong result", "crash", "data lost or leaked", "stated guarantee broken", "test cannot fail", "other")
SHOWN = "shown"
REASONS = ["shown at the base too", "not shown at the last commit", "timed out", "changed the clone", "named and missing"]
BRIEF = open(os.path.join(os.path.dirname(os.path.realpath(__file__)), "briefs", "review.md"), encoding="utf-8").read()


def sha(data):
    return hashlib.sha256(data if isinstance(data, bytes) else data.encode()).hexdigest()


def seconds(name, default):
    v = os.environ.get(name, "")
    return int(v) if v.isdigit() and int(v) > 0 else default


def run_keeping_the_end(cmd, cwd, env, limit, keep):
    """As run, for a command whose output cannot be trusted to end: it is read as it comes and only its last
    keep bytes are held, so a script that prints for ever costs no more memory than one that prints nothing."""
    try:
        p = subprocess.Popen(cmd, cwd=cwd, env=env, stdin=subprocess.DEVNULL, stdout=subprocess.PIPE, stderr=subprocess.STDOUT,
                             start_new_session=True)
    except OSError as e:
        return 127, f"{cmd[0]} did not start ({e})"
    tail, held, late, deadline, fd = collections.deque(), 0, False, time.time() + limit, p.stdout.fileno()
    while True:
        left = deadline - time.time()
        if left <= 0 or not select.select([fd], [], [], left)[0]:
            late = True
            break
        chunk = os.read(fd, 65536)
        if not chunk:
            break
        tail.append(chunk)
        held += len(chunk)
        while held - len(tail[0]) >= keep:
            held -= len(tail.popleft())
    if not late:
        try:
            p.wait(timeout=max(0.1, deadline - time.time()))
        except subprocess.TimeoutExpired:  # it closed its output and went on
            late = True
    if late:
        try:
            os.killpg(p.pid, signal.SIGKILL)
        except OSError:
            pass
        p.wait()
    p.stdout.close()
    return (None if late else p.returncode), b"".join(tail)[-keep:].decode("utf-8", "replace")


def run(cmd, cwd, env, stdin=None, limit=None, out=None):
    """(exit status, output) of cmd in a process group of its own; the status is None when it ran past limit."""
    target = open(out, "wb") if out else subprocess.PIPE
    try:
        p = subprocess.Popen(cmd, cwd=cwd, env=env, stdin=subprocess.PIPE, stdout=target, stderr=subprocess.STDOUT,
                             start_new_session=True)
    except OSError as e:
        return 127, f"{cmd[0]} did not start ({e})"
    finally:
        if out:
            target.close()
    try:
        got, _ = p.communicate((stdin or "").encode(), timeout=limit)
        return p.returncode, (got or b"").decode("utf-8", "replace")
    except subprocess.TimeoutExpired:
        try:
            os.killpg(p.pid, signal.SIGKILL)
        except OSError:
            pass
        got, _ = p.communicate()
        return None, (got or b"").decode("utf-8", "replace")


def git(cwd, *args):
    r = subprocess.run(["git", "-C", cwd] + list(args), capture_output=True, text=True, env=dict(os.environ, GIT_TERMINAL_PROMPT="0"))
    return r.returncode, r.stdout.strip()


def clone_at(repo, commit, dest):
    """A clone of repo at commit holding that commit's history and nothing else: no remote, no ref, nothing later."""
    steps = [["git", "clone", "-q", "--no-hardlinks", repo, dest], ["git", "-C", dest, "checkout", "-q", "--detach", commit],
             ["git", "-C", dest, "remote", "remove", "origin"]]
    for step in steps:
        r = subprocess.run(step, capture_output=True, text=True, env=dict(os.environ, GIT_TERMINAL_PROMPT="0"))
        if r.returncode != 0:
            raise RuntimeError(f"`{' '.join(step[:4])} ...` failed: {r.stderr.strip()[-200:]}")
    for ref in git(dest, "for-each-ref", "--format=%(refname)")[1].splitlines():
        git(dest, "update-ref", "-d", ref)
    for name in ("packed-refs", "FETCH_HEAD", "ORIG_HEAD"):
        try:
            os.remove(os.path.join(dest, ".git", name))
        except OSError:
            pass
    git(dest, "reflog", "expire", "--expire=now", "--all")
    git(dest, "gc", "-q", "--prune=now")
    if git(dest, "rev-parse", "HEAD")[1] != commit or git(dest, "for-each-ref")[1] or git(dest, "remote")[1]:
        raise RuntimeError("the scratch clone is not at the commit alone")


def write_settings(path, hidden):
    """The reviewer's settings: Claude Code's sandbox, with no leave to ask for a command to run outside it,
    and no reading of the hidden folders or of this file."""
    deny = [f"Read(/{h}/**)" for h in hidden] + [f"Read(/{path})"]
    box = {"enabled": True, "autoAllowBashIfSandboxed": True, "allowUnsandboxedCommands": False}
    with open(path, "w") as f:
        json.dump({"sandbox": box, "permissions": {"deny": deny}}, f)


def session_env():
    """The environment of a Claude session this tool starts: the caller's, without its archive, its session or its folder."""
    return {k: v for k, v in judge.clean_env().items() if k not in ("PWD", "OLDPWD", "CLAUDE_CODE_SESSION_ID")}


def check_sandbox(root, repo, settings):
    """None when the sandbox holds for a session started as the reviewer is; else what is wrong.
    The tool writes the probe and reads what it left: the session's own account of it is not used."""
    d, r = os.path.join(root, "check"), secrets.token_hex(4)
    os.makedirs(d)
    q = shlex.quote(repo)
    with open(os.path.join(d, "probe.sh"), "w") as f:
        f.write(f"echo ok > inside-{r}\n(echo x > ../outside-{r}) 2>/dev/null\n"
                f"(cat {q}/.git/HEAD {q}/.git > read-{r}) 2>/dev/null\necho ok > done-{r}\n")
    cmd = ["claude", "-p", "--model", "haiku", "--permission-mode", "acceptEdits", "--allowedTools", "Bash", "--setting-sources", "",
           "--settings", settings, "--max-budget-usd", str(CHECK_BUDGET), "--output-format", "json"]
    rc, out = run(cmd, d, session_env(), "Run exactly this one command with the Bash tool, then reply with the single word done: "
                  "bash probe.sh", limit=180)
    leaked = os.path.exists(os.path.join(root, f"outside-{r}"))
    if leaked:
        os.remove(os.path.join(root, f"outside-{r}"))
    if not (os.path.exists(os.path.join(d, f"inside-{r}")) and os.path.exists(os.path.join(d, f"done-{r}"))):
        return f"the check did not run (exit {rc}): {(out or '').strip()[-200:]}"
    if leaked:
        return ("a write outside the reviewer's folder went through, to " + root + ". The sandbox leaves its own temporary "
                "area writable: if that folder lies inside it, set TMPDIR to a folder that does not")
    read = os.path.join(d, f"read-{r}")
    if os.path.exists(read) and os.path.getsize(read) > 0:
        return "the repository could be read"
    return None


def box_available():
    try:
        return subprocess.run(["bwrap", "--unshare-all", "--ro-bind", "/", "/", "true"], capture_output=True, timeout=20).returncode == 0
    except (OSError, subprocess.SubprocessError):
        return False


def run_script(script, clone, hidden, boxed, limit):
    """(exit status or None when it ran past limit, what it printed) of one script from the root of clone."""
    path = os.environ.get("PATH", "/usr/local/bin:/usr/bin:/bin")
    if boxed:
        hide = [a for h in hidden if h not in ("/", "/tmp") for a in ("--tmpfs", h)]
        dot_git = os.path.join(clone, ".git")
        cmd = (["bwrap", "--unshare-all", "--die-with-parent", "--ro-bind", "/", "/", "--dev", "/dev", "--proc", "/proc", "--tmpfs", "/tmp"]
               + hide + ["--bind", clone, "/tmp/work"] + (["--ro-bind", dot_git, "/tmp/work/.git"] if os.path.exists(dot_git) else [])
               + ["--ro-bind", script, "/tmp/defect.sh", "--chdir", "/tmp/work", "--clearenv",
                         "--setenv", "PATH", path, "--setenv", "HOME", "/tmp", "--setenv", "TMPDIR", "/tmp", "--setenv", "LANG", "C.UTF-8",
                         "--setenv", "PYTHONDONTWRITEBYTECODE", "1", "bash", "/tmp/defect.sh"])
        return run_keeping_the_end(cmd, clone, {"PATH": path}, limit, OUTPUT_CAP)
    scratch = clone + ".tmp"
    os.makedirs(scratch, exist_ok=True)
    try:
        return run_keeping_the_end(["bash", script], clone, {"PATH": path, "HOME": scratch, "TMPDIR": scratch, "LANG": "C.UTF-8",
                                                           "PYTHONDONTWRITEBYTECODE": "1"}, limit, OUTPUT_CAP)
    finally:
        shutil.rmtree(scratch, ignore_errors=True)


def entry(p, like=None):
    """What one entry of a folder is: a link with where it points, a folder, a file with its size and the hash
    of its content. Given like, what it was in the clean clone, a file is read only if it was a file of this
    size there, and then a piece at a time: a script can leave a file of any size."""
    try:
        if os.path.islink(p):
            return ("link", os.readlink(p))
        if os.path.isdir(p):
            return ("folder",)
        if not os.path.isfile(p):
            return ("neither a file nor a folder",)
        size, h = os.path.getsize(p), hashlib.sha256()
        if like is not None and like[:2] != ("file", size):
            return ("file", size, None)
        with open(p, "rb") as f:
            for piece in iter(lambda: f.read(1 << 20), b""):
                h.update(piece)
        return ("file", size, h.hexdigest())
    except OSError:
        return ("unreadable",)


def entries(root):
    """Each entry of a folder outside .git, as (its path from root, its path). No git, and no link followed."""
    for where, dirs, files in os.walk(root):
        if where == root and ".git" in dirs:
            dirs.remove(".git")
        for name in dirs + files:
            yield os.path.relpath(os.path.join(where, name), root), os.path.join(where, name)


def tree_state(root):
    return {rel: entry(p) for rel, p in entries(root)}


def tree_changed(root, was):
    """Whether a folder a script has run in is no longer as was, the clean clone's tree_state. It stops at the
    first entry that differs, so it reads no more than the clean clone held."""
    seen = 0
    for rel, p in entries(root):
        if rel not in was or entry(p, was[rel]) != was[rel]:
            return True
        seen += 1
    return seen != len(was)


def try_script(script, clean, was, work, hidden, boxed, limit):
    """Run one script in a copy of the clean clone: (exit status or None, what it printed, whether it changed the
    copy). The copy is thrown away, and no git is run in it: see the module's note."""
    trial = os.path.join(work, "trial")
    shutil.copytree(clean, trial, symlinks=True)
    try:
        code, printed = run_script(script, trial, hidden, boxed, limit)
        return code, printed, tree_changed(trial, was)
    finally:
        shutil.rmtree(trial, ignore_errors=True)


def verdict(last, base):
    """Each is (exit status or None, whether the clone was changed)."""
    if last[0] is None or base[0] is None:
        return "timed out"
    if last[1] or base[1]:
        return "changed the clone"
    if last[0] != 0:
        return "not shown at the last commit"
    if base[0] == 0:
        return "shown at the base too"
    return SHOWN


def read_stream(path, model, repo):
    """What a reviewer's event stream holds: (status, the answer or None, facts about the run)."""
    result, commands = None, []
    try:
        lines = open(path, encoding="utf-8", errors="replace").read().splitlines()
    except OSError:
        lines = []
    for raw in lines:
        try:
            e = json.loads(raw)
        except ValueError:
            continue
        if not isinstance(e, dict):
            continue
        if e.get("type") == "assistant":
            for b in (e.get("message") or {}).get("content") or []:
                if isinstance(b, dict) and b.get("type") == "tool_use":
                    commands.append(json.dumps(b.get("input")))
        elif e.get("type") == "result":
            result = e
    facts = {"commands": len(commands), "looked_outside": any(repo in c for c in commands), "cost_usd": None, "served_model": None,
             "turns": None}
    if result is None:
        return "no answer", None, facts
    served = ",".join(sorted(result.get("modelUsage") or {})) or None
    facts.update(cost_usd=result.get("total_cost_usd") if isinstance(result.get("total_cost_usd"), (int, float)) else None,
                 served_model=served, turns=result.get("num_turns"))
    if result.get("is_error"):
        return "error", None, facts
    if not served or not any(model in m for m in served.split(",")):
        return "error", None, dict(facts, detail=f"served by {served or 'no model'}, not {model}")
    m = re.search(r"\{.*\}", result.get("result") if isinstance(result.get("result"), str) else "", re.S)
    try:
        answer = json.loads(m.group(0)) if m else None
    except ValueError:
        answer = None
    if not isinstance(answer, dict) or not isinstance(answer.get("defects"), list):
        return "no answer", None, facts
    return "answer", answer, facts


def collect(clone, dest):
    """Copy the reviewer's scripts out of its clone; {name: path}, plain files only."""
    found = {}
    src = os.path.join(clone, ".review")
    for name in sorted(os.listdir(src)) if os.path.isdir(src) else []:
        p = os.path.join(src, name)
        if (name.endswith(".sh") and os.path.isfile(p) and not os.path.islink(p) and os.path.getsize(p) <= MAX_SCRIPT_BYTES
                and len(found) < MAX_SCRIPTS):
            os.makedirs(dest, exist_ok=True)
            found[name] = shutil.copyfile(p, os.path.join(dest, name))
    return found


def review_session(root, repo, base, last, model, settings, hidden, boxed, out, redact):
    """One session's review, written under out (stream.jsonl, scripts/, runs/); returns the document for review.json."""
    for old in ("scripts", "runs"):
        shutil.rmtree(os.path.join(out, old), ignore_errors=True)
    os.makedirs(out, exist_ok=True)
    work = os.path.join(root, "s" + secrets.token_hex(4))
    clean, mine, at_base = os.path.join(work, "last"), os.path.join(work, "review"), os.path.join(work, "base")
    doc = {"measure": MEASURE, "model": model, "brief_sha256": sha(BRIEF), "base": base, "last": last, "boxed": boxed, "shown": 0,
           "defects": [], "unverified": 0, "experiments": 0, "looked_outside": False}
    try:
        clone_at(repo, last, clean)
        shutil.copytree(clean, mine, symlinks=True)
        started = time.time()
        cmd = ["claude", "-p", "--model", model, "--permission-mode", "acceptEdits", "--allowedTools"] + TOOLS + [
            "--setting-sources", "", "--settings", settings, "--max-budget-usd", str(BUDGET), "--output-format", "stream-json", "--verbose"]
        stream = os.path.join(out, "stream.jsonl")
        rc, _ = run(cmd, mine, session_env(), BRIEF.replace("@BASE@", base[:10]).replace("@HEAD@", last[:10]),
                    limit=seconds("AGENT_TRANSCRIPTS_REVIEW_LIMIT", REVIEW_LIMIT), out=stream)
        status, answer, facts = read_stream(stream, model, repo)
        doc.update(facts, seconds=round(time.time() - started))
        if rc is None:
            return dict(doc, status="timed out")
        if status != "answer":
            return dict(doc, status=status)
        scripts = collect(mine, os.path.join(out, "scripts"))
        for step in (["git", "clone", "-q", "--no-hardlinks", clean, at_base], ["git", "-C", at_base, "checkout", "-q", "--detach", base]):
            if subprocess.run(step, capture_output=True).returncode != 0:
                raise RuntimeError(f"no clone at the base commit {base[:10]}")
        os.makedirs(os.path.join(out, "runs"), exist_ok=True)
        text = lambda v: redact(v) if isinstance(v, str) else None  # noqa: E731
        named = {}
        for d in answer["defects"]:
            if isinstance(d, dict) and isinstance(d.get("script"), str):
                named.setdefault(os.path.basename(d["script"]), d)
        limit = seconds("AGENT_TRANSCRIPTS_SCRIPT_LIMIT", SCRIPT_LIMIT)
        was = {"last": tree_state(clean), "base": tree_state(at_base)}
        for name in list(named) + [n for n in scripts if n not in named]:
            said = named.get(name) or {}
            row = {"id": None, "script": name, "named": name in named, "kind": said.get("kind") if said.get("kind") in KINDS else "other",
                   "file": text(said.get("file")), "what": text(said.get("what")), "guarantee": text(said.get("guarantee"))}
            if name not in scripts:
                doc["defects"].append(dict(row, status="named and missing"))
                continue
            row["id"] = sha(open(scripts[name], "rb").read())[:6]
            seen = {}
            for at, clone in (("last", clean), ("base", at_base)):
                code, printed, dirty = try_script(scripts[name], clone, was[at], work, hidden, boxed, limit)
                seen[at] = (code, dirty)
                with open(os.path.join(out, "runs", f"{name}.{at}.out"), "w") as f:
                    f.write(redact(printed[-OUTPUT_CAP:]))
                row[at] = {"exit": code, "changed_the_clone": seen[at][1]}
            doc["defects"].append(dict(row, status=verdict(seen["last"], seen["base"])))
        doc.update(unverified=len(answer.get("unverified") or []) if isinstance(answer.get("unverified"), list) else 0,
                   experiments=len(answer.get("experiments") or []) if isinstance(answer.get("experiments"), list) else 0)
        if doc["looked_outside"]:
            return dict(doc, status="looked outside")
        return dict(doc, status="reviewed", shown=sum(1 for d in doc["defects"] if d["status"] == SHOWN))
    except (RuntimeError, OSError) as e:
        return dict(doc, status="error", detail=str(e))
    finally:
        shutil.rmtree(work, ignore_errors=True)


def summary(doc):
    """One line on a review, for the terminal."""
    if doc["status"] == "looked outside":
        return "not counted: the reviewer looked outside its clone (one of its commands names the repository)"
    if doc["status"] != "reviewed":
        return f"not counted ({doc['status']})" + (f": {doc['detail']}" if doc.get("detail") else "")
    shown = [d for d in doc["defects"] if d["status"] == SHOWN]
    kinds = [f"{sum(1 for d in shown if d['named'] and d['kind'] == k)} {k}" for k in KINDS if any(d["named"] and d["kind"] == k for d in shown)]
    if any(not d["named"] for d in shown):
        kinds.append(f"{sum(1 for d in shown if not d['named'])} not named in the answer")
    rest = [f"{sum(1 for d in doc['defects'] if d['status'] == r)} {r}" for r in REASONS if any(d["status"] == r for d in doc["defects"])]
    return (f"{len(shown)} defect{'s' if len(shown) != 1 else ''} shown" + (f" ({', '.join(kinds)})" if kinds else "")
            + (f"; not counted: {', '.join(rest)}" if rest else ""))


def reviewed(doc, model, last):
    """Whether a kept review is for this model, this brief and this commit, and finished."""
    return (isinstance(doc, dict) and doc.get("status") == "reviewed" and doc.get("measure") == MEASURE and doc.get("model") == model
            and doc.get("brief_sha256") == sha(BRIEF) and doc.get("last") == last)
