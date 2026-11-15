"""labels: a person's verdicts for a session, the sheet they are made from, and the comparison
with the graders (record docs/changes/2026-11-11-grading-trust.md, R1 to R3 and its Decisions).

A label file, grade/labels/<sessionId>.txt, is plain lines:

    session: <sessionId>
    transcript: sha256:<64 hex> lines:<n>
    labelled-by: <name>, <date>
    <step>: <pass|fail|na> | <one-line reason>      one line for each of fields.STEPS

`transcript` is the hash of the transcript the label was made from: a label whose transcript
has since changed is stale and is not counted. A step with nothing before the `|` is not
labelled yet (a reason may be there already; a verdict never is until a person writes it). A
file with a missing step, a step twice, an unknown line or verdict, a verdict with no reason,
or verdicts with no name after labelled-by is rejected whole.

The sheet shows what the session did, call by call, and nothing a grader concluded from it:
no verdict, no reason, no count, not even which calls a grader picked. The pointers under each
step come from plain text matches (a path, the word "test"), wider than any grader's rule.
"""
import hashlib
import json
import os
import re
from datetime import datetime, timezone

import fields
import rubric

PASS, FAIL, NA = fields.PASS, fields.FAIL, fields.NA
VERDICTS = {"pass": PASS, "fail": FAIL, "na": NA, "n/a": NA, "not_applicable": NA}
SHOWN = {PASS: "pass", FAIL: "fail", NA: "not applicable"}
TRANSCRIPT = re.compile(r"^sha256:([0-9a-f]{64}) lines:(\d+)$")
KINDS = ("false_fail", "false_pass", "false_na")


# ---- the label file ----------------------------------------------------------------------

def transcript_hash(lines):
    """(sha256, line count) of a transcript's lines, each ended by a newline."""
    h = hashlib.sha256()
    for ln in lines:
        h.update(ln + b"\n")
    return h.hexdigest(), len(lines)


def stub(sid, sha, n):
    return (f"session: {sid}\ntranscript: sha256:{sha} lines:{n}\nlabelled-by:\n"
            "# One line per step: a verdict (pass, fail or na), then |, then a one-line reason.\n"
            + "".join(f"{s}:\n" for s in fields.STEPS))


def parse(text):
    """(label, problems). label: session, sha256, lines, by, steps {step: (verdict or None, reason)}."""
    seen, problems, steps = {}, [], {}
    for raw in text.splitlines():
        ln = raw.strip()
        if not ln or ln.startswith("#"):
            continue
        key, sep, value = ln.partition(":")
        key, value = key.strip(), value.strip()
        if not sep or key not in ("session", "transcript", "labelled-by") + tuple(fields.STEPS) + tuple(rubric.RETIRED):
            problems.append(f"unknown line {ln[:40]!r}")
        elif key in seen:
            problems.append(f"{key} is there twice")
        else:
            seen[key] = value
    m = TRANSCRIPT.match(seen.get("transcript") or "")
    if not seen.get("session"):
        problems.append("no session: line")
    if not m:
        problems.append("no transcript: sha256:<64 hex> lines:<n> line")
    for s in fields.STEPS:
        if s not in seen:
            problems.append(f"no line for {s}")
            continue
        word, bar, reason = seen[s].partition("|")
        word, reason = word.strip().lower(), reason.strip()
        if not word:
            steps[s] = (None, reason)
        elif word not in VERDICTS:
            problems.append(f"{s}: unknown verdict {word!r} (pass, fail or na)")
        elif not reason:
            problems.append(f"{s}: a verdict needs a one-line reason after |")
        else:
            steps[s] = (VERDICTS[word], reason)
    # A line for a rubric that was judged once and taken out (grade/rubric.py) may still be there. It is
    # checked as written and counted for nothing: no grader answers it any more.
    for q in rubric.RETIRED:
        word, bar, reason = (seen.get(q) or "").partition("|")
        word, reason = word.strip().lower(), reason.strip()
        if word and word not in rubric.LABELS[q] and word not in ("na", "n/a"):
            problems.append(f"{q}: unknown label {word!r} ({', '.join(rubric.LABELS[q])} or na)")
        elif word and not reason:
            problems.append(f"{q}: a label needs a one-line reason after |")
    if any(v for v, _ in steps.values()) and not seen.get("labelled-by"):
        problems.append("verdicts with no labelled-by: a person's name and the date")
    label = {"session": seen.get("session"), "sha256": m.group(1) if m else None, "lines": int(m.group(2)) if m else None,
             "by": seen.get("labelled-by") or None, "steps": steps}
    return label, problems


def load(folder):
    """({sessionId: label}, [(file name, problem)]) for the *.txt files of a labels folder."""
    labels, problems = {}, []
    try:
        names = sorted(n for n in os.listdir(folder) if n.endswith(".txt"))
    except OSError:
        names = []
    for name in names:
        try:
            label, bad = parse(open(os.path.join(folder, name), encoding="utf-8", errors="replace").read())
        except OSError as e:
            label, bad = None, [str(e)]
        if not bad and label["session"] != name[:-4]:
            bad = [f"the file is named for another session than its session: line ({label['session']})"]
        if bad:
            problems += [(name, b) for b in bad]
        else:
            labels[label["session"]] = label
    return labels, problems


def labelled(label):
    return any(v for v, _ in label["steps"].values())


# ---- the comparison ----------------------------------------------------------------------

def when(s):
    try:
        t = datetime.fromisoformat(str(s).replace("Z", "+00:00"))
    except ValueError:
        return datetime.min.replace(tzinfo=timezone.utc)
    return t if t.tzinfo else t.replace(tzinfo=timezone.utc)


def latest_rows(rows):
    """{step: row}: the field graders' latest row per step, from one session's score rows."""
    best = {}
    for r in rows or []:
        s = r.get("step")
        if s in fields.STEPS and str(r.get("grader") or "").startswith("fields/"):
            if s not in best or when(r.get("graded_at")) >= when(best[s].get("graded_at")):
                best[s] = r
    return best


def compare(labels, here):
    """The graders against the labels.

    labels: {sessionId: label}. here: {sessionId: {"sha256", "lines", "rows"}} for each session
    with a transcript: its hash and line count now, and its score rows (None if never graded).
    Returns counts {step: {labelled, agree, false_fail, false_pass, false_na, both_na}} (both_na: the
    agreements where label and grader both say not applicable), disagreements
    [{step, kind, session, label, reason, grader, why}], not_counted [(session, step or None,
    why)] and sessions, the ids with at least one step counted.
    """
    counts = {s: dict(labelled=0, agree=0, false_fail=0, false_pass=0, false_na=0, both_na=0) for s in fields.STEPS}
    disagreements, not_counted, counted = [], [], []
    for sid in sorted(set(labels) | set(here)):
        label, now = labels.get(sid), here.get(sid)
        if label is None:
            not_counted.append((sid, None, "no label file"))
        elif now is None:
            not_counted.append((sid, None, "labelled, but its transcript is not here"))
        elif not labelled(label):
            not_counted.append((sid, None, "not labelled yet"))
        elif label["sha256"] != now["sha256"]:
            not_counted.append((sid, None, f"stale label, made from a transcript of {label['lines']} lines (sha256 "
                                f"{label['sha256'][:10]}); it now has {now['lines']} lines (sha256 {now['sha256'][:10]})"))
        elif not latest_rows(now.get("rows")):
            not_counted.append((sid, None, "labelled, but not graded; run transcripts grade"))
        else:
            rows, any_counted = latest_rows(now["rows"]), False
            for s in fields.STEPS:
                verdict, reason = label["steps"][s]
                row = rows.get(s)
                ev = (row or {}).get("evidence")
                ev = ev if isinstance(ev, dict) else {}  # a row is whatever a file or the store holds
                if verdict is None:
                    not_counted.append((sid, s, "not labelled yet"))
                elif row is None:
                    not_counted.append((sid, s, "no score row"))
                elif ev.get("error"):
                    not_counted.append((sid, s, f"the grader could not grade it ({ev['error']})"))
                else:
                    any_counted = True
                    counts[s]["labelled"] += 1
                    got = row.get("verdict")
                    kind = "agree" if got == verdict else "false_fail" if got == FAIL else "false_pass" if got == PASS else "false_na"
                    counts[s][kind] += 1
                    counts[s]["both_na"] += got == verdict == NA
                    if kind != "agree":
                        disagreements.append({"step": s, "kind": kind, "session": sid, "label": verdict, "reason": reason,
                                              "grader": got, "why": ev.get("why") or ""})
            if any_counted:
                counted.append(sid)
    disagreements.sort(key=lambda d: fields.STEPS.index(d["step"]))
    return {"counts": counts, "disagreements": disagreements, "not_counted": not_counted, "sessions": counted}


def table(res, n_here, n_labels):
    """The comparison as Markdown."""
    n = len(res["sessions"])
    out = ["# Grader accuracy", "",
           f"The field graders' latest row for each session and step, against a person's label. {n} session{'s are' if n != 1 else ' is'} "
           f"counted, of {n_here} with a transcript here and {n_labels} label files. A false fail is a fail the label does not "
           "share, a false pass a pass the label does not share, and a false n/a a not applicable where the label says pass or fail.",
           "", "| Step | Labelled | Agree | False fail | False pass | False n/a |", "|---|---|---|---|---|---|"]
    for s in fields.STEPS:
        c = res["counts"][s]
        out.append(f"| {s} | {c['labelled']} | {c['agree']} | {c['false_fail']} | {c['false_pass']} | {c['false_na']} |")
    out += ["", "## Disagreements", ""]
    for d in res["disagreements"]:
        out.append(f"- {d['step']}, {d['kind'].replace('_', ' ').replace(' na', ' n/a')}, {d['session']}: the label says "
                   f"{SHOWN[d['label']]} ({d['reason']}); the grader says {SHOWN.get(d['grader'], d['grader'])} ({d['why']})")
    if not res["disagreements"]:
        out.append("None.")
    out += ["", "## Not counted", ""]
    for sid, step, why in res["not_counted"]:
        out.append(f"- {sid}{', ' + step if step else ''}: {why}")
    if not res["not_counted"]:
        out.append("Nothing.")
    return "\n".join(out) + "\n"


# ---- the sheet ---------------------------------------------------------------------------

QUESTIONS = [  # (step, the question, when it does not apply, which pointers help)
    ("tier-declared", "Did the session declare a tier? Yes if its record's frontmatter holds tier 0, 1 or 2, or, with no "
     "record, if its own text or pull request description says `Tier: 0`.",
     "the session wrote no record and no code and does not say `Tier: 0`", ("tier", "records")),
    ("probe-before-record", "Before it first wrote its record, did the session try out what the change depends on: "
     "inline code, a module, a scratch script, `--help`, a request to another system, a look at the real environment, "
     "a run of the existing tests? `--version` alone, and listing or reading files, do not count.",
     "there is no record, the session did not write it, or it was there before the session started", ("records", "shell")),
    ("record-before-code", "Was the record first written before the first code? Code is any file in the working tree "
     "outside docs/, documentation, tests, fixtures and backups.",
     "there is no record, the session did not write it, it was there before the session started, or no code was written",
     ("writes", "shell")),
    ("red-first", "Before the first code was written, did a test run actually run and report a failed test? A run that "
     "was denied, refused or never answered did not run; a run that stopped on a syntax or import error is no failed test.",
     "no code was written, or the change is tier 0", ("tests", "writes")),
    ("change-line", "Does the pull request description the session opened or wrote (else the description in its last "
     "message) open with `Change: <the record's path>`, alone on its line, bold or not? In a last message the "
     "description starts at the line that names it, and a `Title:` line may come before the `Change:` line.",
     "there is no record, or nothing the session opened or wrote is a pull request description", ("pr", "last")),
    ("record-check", "Does the record, as it stood at the session's last commit, hold what `record-check` asks of its "
     "tier: the frontmatter fields and every section?",
     "there is no record, or the record at the last commit is not shown below", ("records",)),
    ("outcome-filled", "If the record is done, or the session marked a task done (`done: true` in the frontmatter, or "
     "an item ticked `[x]` under Tasks), does its Outcome hold anything?",
     "there is no record, it cannot be read, or it is not done and no task was marked done", ("records",)),
]
QUIET = ("Read", "Glob", "Grep", "LS", "TodoWrite", "TodoRead", "ToolSearch", "TaskCreate", "TaskUpdate", "TaskList")
RECORD_PATH = re.compile(r"docs/changes/(?!README\.md|TEMPLATE\.md)[^/\s\"'`)]+\.md")


def clip(text, head, tail=0, width=220):
    """The first and last lines of a text, long lines cut, with what was left out counted."""
    lines = [ln.rstrip() for ln in str(text).strip("\n").split("\n")]
    lines = [ln if len(ln) <= width else ln[:width] + " [...]" for ln in lines]
    if len(lines) > head + tail + 1:
        lines = lines[:head] + [f"[... {len(lines) - head - tail} more lines]"] + (lines[-tail:] if tail else [])
    return lines


def block(lines):
    return ["    " + ln for ln in lines] if lines else ["    (empty)"]


def events(lines):
    """The session in order: ("user"|"injected"|"says", n, text) and ("call", n, call), sidechains left out."""
    out, pending, n = [], {}, 0
    for i, raw in enumerate(lines, 1):
        if isinstance(raw, bytes):
            raw = raw.decode("utf-8", "replace")
        if not raw.strip():
            continue
        try:
            d = json.loads(raw)
        except ValueError:
            raise fields.Unparsable(f"line {i} of the transcript is not JSON")
        if not isinstance(d, dict) or d.get("isSidechain") or d.get("type") not in ("assistant", "user"):
            continue
        content = (d.get("message") or {}).get("content")
        who = "says" if d["type"] == "assistant" else "injected" if d.get("isMeta") else "user"
        if isinstance(content, str):
            content = [{"type": "text", "text": content}]
        for b in content if isinstance(content, list) else []:
            if not isinstance(b, dict):
                continue
            if b.get("type") == "text" and (b.get("text") or "").strip():
                n += 1
                out.append((who, n, b["text"]))
            elif d["type"] == "assistant" and b.get("type") == "tool_use":
                n += 1
                c = {"id": b.get("id"), "name": str(b.get("name")), "input": b.get("input") if isinstance(b.get("input"), dict) else {},
                     "result": None, "is_error": False}
                out.append(("call", n, c))
                pending.setdefault(c["id"], []).append(c)
            elif d["type"] == "user" and b.get("type") == "tool_result":
                waiting = pending.get(b.get("tool_use_id")) or []
                if waiting:
                    c = waiting.pop(0)
                    c["result"], c["is_error"] = fields.text_of(b.get("content")), bool(b.get("is_error"))
    return out


def show_call(n, c, red):
    name, inp = c["name"], c["input"]
    path = str(inp.get("file_path") or inp.get("notebook_path") or "")
    long = 150 if RECORD_PATH.search(path) or re.search(r"(?i)(?:^|/)(?:pr|pull)[^/]*\.(?:md|txt)$", path) else 0
    out = [f"**[{n}] {name}** `{c['id']}`" + (f" {red(path)}" if path else ""), ""]
    if name == "Bash":
        body, keep = clip(red(str(inp.get("command") or "")), 14, 2), (3, 6)
    elif name == "Write":
        body, keep = clip(red(str(inp.get("content") or "")), long or 8), (2, 0)
    elif name in ("Edit", "MultiEdit"):
        edits = inp.get("edits") if isinstance(inp.get("edits"), list) else [inp]
        body, keep = [], (2, 0)
        for e in [e for e in edits if isinstance(e, dict)][:6]:
            body += ["- " + ln for ln in clip(red(str(e.get("old_string") or "")), long or 5)]
            body += ["+ " + ln for ln in clip(red(str(e.get("new_string") or "")), long or 8)]
    else:
        body, keep = clip(red(json.dumps(inp, ensure_ascii=False)), 3, 0, 300), ((1, 0) if name in QUIET else (3, 3))
    out += block(body) + [""]
    if c["result"] is None:
        out.append("It has no result: the call was never answered.")
    else:
        if c["is_error"] and name in QUIET:
            keep = (3, 0)
        out.append("Result, flagged as an error:" if c["is_error"] else "Result:")
        out += [""] + block(clip(red(c["result"]), *keep))
    return out + [""]


def record_shown(text, each=40):
    """A record as the sheet shows it: what is before its first section whole, then each section's
    heading and first lines, so that a long record still shows every section the questions ask about."""
    parts = re.split(r"(?m)^(?=## )", str(text).strip("\n"))
    out = clip(parts[0], 10 ** 6)
    for part in parts[1:]:
        lines = clip(part, 10 ** 6)
        more = len(lines) - 1 - each
        out += lines if more <= 1 else lines[:1 + each] + [f"[... {more} more lines of this section]", ""]
    return out


def own_commits(commits):
    """The line of a sheet that says where the session's own commits are, for a labeller who wants to read them."""
    if not commits:
        return "No commit of this session's is known: what it wrote is in the calls below."
    base, last = commits
    log = "git log --first-parent --no-merges"
    if base:
        return f"The session's own commits, in the repository: `{log} {base[:10]}..{last[:10]}`."
    return f"The session's own commits, in the repository: `{log} {last[:10]}` (the history begins with this session)."


def sheet(lines, sid, label_path, records=None, redact=None, commits=None):
    """The sheet for one session, as Markdown.

    records: [(path, text or None, note)] for each record the session's calls or Change: lines
    name, as it stood at the session's last commit, or why it cannot be shown; None when the
    caller has no commits. redact: applied to every text taken from the transcript. commits:
    (base or None, last) of the session's own commits, or None when it has none to name.
    """
    red = redact or (lambda t: t)
    evs = events(lines)
    sha, n_lines = transcript_hash(lines)
    calls = [(n, c) for kind, n, c in evs if kind == "call"]
    says = [(n, t) for kind, n, t in evs if kind == "says"]
    text_of_call = {n: json.dumps(c["input"], ensure_ascii=False) for n, c in calls}

    def nums(found):
        return ", ".join(f"[{n}]" for n in found) or "none"

    pointers = {
        "writes": "Calls of the file tools: " + (", ".join(
            f"[{n}] {c['name']} {red(str(c['input'].get('file_path') or c['input'].get('notebook_path') or ''))}"
            for n, c in calls if c["name"] in fields.FILE_TOOLS) or "none") + ". A shell command can write a file too.",
        "shell": "Shell commands: " + nums(n for n, c in calls if c["name"] == "Bash") + ".",
        "records": "Calls that name a file under docs/changes/: " + nums(n for n, c in calls if RECORD_PATH.search(text_of_call[n])) + ".",
        "tests": "Shell commands with \"test\", \"spec\" or \"check\" in them: "
                 + nums(n for n, c in calls if c["name"] == "Bash" and re.search(r"(?i)test|spec|check", text_of_call[n])) + ".",
        "pr": "Calls that mention a pull request: "
              + nums(n for n, c in calls if re.search(r"(?i)\bgh\s+pr\b|pull_request|pull request|(?:^|[/\"\s])pr[-_.a-z]*\.(?:md|txt)", text_of_call[n])) + ".",
        "tier": "The session's own texts with \"tier\" in them: " + nums(n for n, t in says if re.search(r"(?i)\btier\b", t)) + ".",
        "last": "Its last message: " + (f"[{says[-1][0]}]" if says else "none") + ".",
    }
    out = [f"# Label sheet: {sid}", "",
           f"Write your verdicts in `{label_path}`: after each step, `pass`, `fail` or `na`, then ` | ` and a one-line reason; "
           "and your name and the date after `labelled-by:`. This sheet shows what the session did and nothing a grader "
           "concluded from it. Judge each step from the calls below. A call did something only if its own result shows it "
           "ran: one that was denied, refused, interrupted or never answered did nothing.", "",
           f"Transcript: {n_lines} lines, sha256 {sha[:10]}. Lines of subagents kept inline are left out, as the graders leave them out.", "",
           own_commits(commits), "",
           "## The steps", ""]
    for step, question, na, ptrs in QUESTIONS:
        out += [f"### {step}", "", question, "", f"Label it `na` when {na}.", ""] + [pointers[p] for p in ptrs] + [""]
    out += ["## The record at the session's last commit", ""]
    if records is None:
        out += ["Not shown: no commit is known for this transcript. The record's text is in the calls that wrote it, below.", ""]
    elif not records:
        out += ["The session's calls and Change: lines name no file under docs/changes/.", ""]
    for path, text, note in records or []:
        out += [f"`{path}`" + (f": {note}" if text is None else ""), ""]
        if text is not None:
            out += block(record_shown(red(text))) + [""]
    out += ["## The session, in order", ""]
    last = says[-1][0] if says else None
    first_user = True
    for kind, n, x in evs:
        if kind == "call":
            out += show_call(n, x, red)
        else:
            who = {"user": "The user", "injected": "Injected context", "says": "The session"}[kind]
            keep = 60 if (kind == "user" and first_user) or n == last else 4 if kind == "injected" else 12
            first_user = first_user and kind != "user"
            out += [f"**[{n}] {who}:**", ""] + block(clip(red(x), keep, 0, 600)) + [""]
    return "\n".join(out).rstrip("\n") + "\n"


def named_records(lines):
    """Every docs/changes/ path the session's calls or its own Change: lines name, in order."""
    found = []
    for kind, _, x in events(lines):
        if kind == "call":
            hay = json.dumps(x["input"], ensure_ascii=False)
        elif kind == "says":
            hay = "\n".join(ln for ln in x.splitlines() if re.match(r"^\W*Change\W*:", ln.strip()))
        else:
            continue
        for m in RECORD_PATH.finditer(hay):
            if m.group(0) not in found:
                found.append(m.group(0))
    return found
